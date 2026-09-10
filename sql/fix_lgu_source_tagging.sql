-- ============================================================================
-- MIGRATION: Fix LGU Source Tagging & Dashboard Classification
-- Target Tables: external.events_consolidated
-- Target Functions: external.sync_academic_lgu_to_events_consolidated
-- Target Views: "Analytics".descriptive_live_event_feed
-- ============================================================================

-- 1. Ensure source_type column exists on external.events_consolidated
ALTER TABLE external.events_consolidated 
ADD COLUMN IF NOT EXISTS source_type text;

-- 2. Backfill existing source_type in external.events_consolidated
UPDATE external.events_consolidated
SET source_type = 'lgu'
WHERE source_id LIKE 'external_lgu_%'
   OR source_name ~* '(government|city|pio|municipality|lgu|metropolitan|mmda|cainta)';

UPDATE external.events_consolidated
SET source_type = 'academic'
WHERE source_type IS NULL 
  AND (source_id LIKE 'external_acad_%' OR id LIKE 'CAL-%' OR source_table = 'processed_calendar_tables');

UPDATE external.events_consolidated
SET source_type = 'mobile-app'
WHERE source_type IS NULL
  AND (source_table = 'incidents' OR source_name = 'Ground Control System');

-- Default any remaining untyped rows to academic
UPDATE external.events_consolidated
SET source_type = 'academic'
WHERE source_type IS NULL;

-- 3. Upgrade external.sync_academic_lgu_to_events_consolidated()
--    Explicitly passes source_type ('lgu' vs 'academic') into events_consolidated.
CREATE OR REPLACE FUNCTION external.sync_academic_lgu_to_events_consolidated()
RETURNS trigger AS $$
DECLARE
    v_result RECORD;
    v_weight numeric;
    v_event_date date;
    v_scrape_id text;
    v_cat_code text;
    v_stations text[];
    v_station text;
    v_is_reschedule boolean := FALSE;
    v_source_type text;
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM external.events_consolidated WHERE source_id = OLD.id AND source_table = 'academic_lgu_events';
        RETURN OLD;
    END IF;

    -- Resolve affected stations
    v_stations := external.get_affected_stations(NEW.station, NEW.post_text, NEW.image_text, NEW.source_name);

    -- Resolve explicit source_type ('lgu' vs 'academic')
    v_source_type := CASE 
        WHEN NEW.category = 'lgu' 
             OR NEW.id LIKE 'external_lgu_%' 
             OR NEW.source_name ~* '(government|city|pio|municipality|lgu|metropolitan|mmda|cainta)' THEN 'lgu'
        ELSE 'academic'
    END;

    -- Check if this is a cancellation or rescheduling
    IF NEW.is_cancellation = TRUE THEN
        -- 1. Deactivate/delete prior matching events on the station for the announcement date
        IF NEW.cancellation_target_code = 'MAJOR_ARENA_EVENT' 
           OR LOWER(COALESCE(NEW.event_name, '')) ~* '(uaap|kickoff|kick\s*off|exhibition|game|match|concert)' THEN
            DELETE FROM external.events_consolidated
            WHERE station = ANY(v_stations)
              AND event_date = NEW.post_date::date
              AND event_category = 'major_event'
              AND source_id != NEW.id;

            UPDATE external.academic_lgu_events
            SET is_cancelled = TRUE,
                cancellation_reason = 'Cancelled/rescheduled by ' || NEW.id || ' (' || COALESCE(NEW.event_name, '') || ')'
            WHERE station = ANY(v_stations)
              AND (event_date::text LIKE (TO_CHAR(NEW.post_date::date, 'YYYY-MM-DD') || '%'))
              AND (event_code = 'MAJOR_ARENA_EVENT' OR event_name ILIKE '%UAAP%' OR event_name ILIKE '%Party%' OR event_name ILIKE '%Kickoff%')
              AND id != NEW.id;
        END IF;

        -- Check if it was rescheduled to a new date
        IF NEW.event_date IS NOT NULL AND NEW.event_date ~ '^\d{4}-\d{2}-\d{2}$' THEN
            v_event_date := NEW.event_date::date;
            IF v_event_date > NEW.post_date::date THEN
                v_is_reschedule := TRUE;
            END IF;
        END IF;

        -- If it is a pure cancellation without a new date, do not insert any active disruption!
        IF NOT v_is_reschedule THEN
            DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
            RETURN NEW;
        END IF;
    END IF;

    -- Classify event using robust SELECT ... INTO
    IF NEW.event_code = 'MAJOR_ARENA_EVENT' THEN
        SELECT 
            COALESCE(NULLIF(TRIM(NEW.event_name), ''), 'Major Arena / Sports Event')::text AS event_name,
            'major_event'::text AS event_category,
            'academic'::text AS friction_domain,
            'Major Arena Event'::text AS trigger_category,
            TRUE::boolean AS affects_ridership
        INTO v_result;
    ELSE
        SELECT * INTO v_result
        FROM external.classify_event_from_text(NEW.post_text, NEW.image_text, NEW.category, NEW.event_name);
    END IF;

    IF v_result.affects_ridership = FALSE OR v_result.affects_ridership IS NULL THEN
        DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
        RETURN NEW;
    END IF;

    -- Lookup friction weight
    SELECT fw.friction_weight INTO v_weight
    FROM external.friction_weight fw
    WHERE fw.friction_domain = v_result.friction_domain 
      AND fw.trigger_category = v_result.trigger_category
    LIMIT 1;
    v_weight := COALESCE(v_weight, 0.65);

    -- Determine event date: prioritize parsed NEW.event_date if valid
    IF v_event_date IS NULL THEN
        IF NEW.event_date IS NOT NULL AND NEW.event_date ~ '^\d{4}-\d{2}-\d{2}$' THEN
            v_event_date := NEW.event_date::date;
        ELSE
            v_event_date := external.extract_event_date_from_text(NEW.post_text, NEW.image_text, NEW.post_date);
        END IF;
    END IF;

    v_cat_code := CASE v_result.event_category
        WHEN 'class_suspension' THEN 'CS'
        WHEN 'holiday' THEN 'HD'
        WHEN 'school_break' THEN 'SB'
        WHEN 'transport_strike' THEN 'TS'
        WHEN 'major_event' THEN 'ME'
        WHEN 'exam_week' THEN 'EX'
        ELSE 'RC'
    END;

    -- Clear any existing rows for this source_id first
    DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';

    -- Loop and insert for each affected station on the target event_date
    FOREACH v_station IN ARRAY v_stations LOOP
        v_scrape_id := 'SCR-' || v_cat_code || '-' || TO_CHAR(v_event_date, 'MMDD') || '-' || NEW.id || '-' || REPLACE(LOWER(v_station), ' ', '_');

        INSERT INTO external.events_consolidated (
            id, station, event_date, source_table, source_id, source_name,
            event_name, event_category, friction_domain, trigger_category,
            source_url, description,
            normalized_score, friction_weight_ref, announcement_time, updated_at,
            source_type
        )
        VALUES (
            v_scrape_id,
            external.normalize_station_name(v_station),
            v_event_date,
            'academic_lgu_events',
            NEW.id,
            NEW.source_name,
            v_result.event_name,
            v_result.event_category,
            v_result.friction_domain,
            v_result.trigger_category,
            NEW.source_url,
            NEW.post_text,
            CASE
                WHEN v_result.event_category IN ('class_suspension', 'holiday', 'school_break') THEN 1.0
                WHEN v_result.event_category = 'transport_strike' THEN 0.9
                ELSE v_weight
            END,
            CASE
                WHEN v_result.event_category = 'transport_strike' THEN 0.9
                ELSE v_weight
            END,
            NEW.post_date,
            now(),
            v_source_type
        )
        ON CONFLICT (id) DO UPDATE SET
            station = EXCLUDED.station,
            event_date = EXCLUDED.event_date,
            source_name = EXCLUDED.source_name,
            event_name = EXCLUDED.event_name,
            event_category = EXCLUDED.event_category,
            friction_domain = EXCLUDED.friction_domain,
            trigger_category = EXCLUDED.trigger_category,
            source_url = EXCLUDED.source_url,
            description = EXCLUDED.description,
            normalized_score = EXCLUDED.normalized_score,
            friction_weight_ref = EXCLUDED.friction_weight_ref,
            announcement_time = EXCLUDED.announcement_time,
            updated_at = now(),
            source_type = EXCLUDED.source_type;
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. Recreate Analytics.descriptive_live_event_feed view with accurate LGU source_type
CREATE OR REPLACE VIEW "Analytics"."descriptive_live_event_feed" AS
 SELECT weather_current.id AS trigger_id,
    'weather'::text AS source_type,
    'Open-Meteo Weather Service'::text AS source,
    (((((((('Station: '::text || weather_current.station) || ' - Temp: '::text) || weather_current.temperature) || '°C, Rain: '::text) || weather_current.rainfall_mm) || 'mm ('::text) || COALESCE(NULLIF(weather_current.computed_rainfall_level, 'None'::text), 'Normal'::text)) || ')'::text) AS message,
        CASE
            WHEN weather_current.rainfall_mm >= 30.0 
              OR weather_current.computed_rainfall_level = 'Red' 
              OR weather_current.wind_speed >= 62.0 
              THEN 'critical'::text
            WHEN weather_current.rainfall_mm >= 7.5 
              OR weather_current.computed_rainfall_level IN ('Orange', 'Yellow') 
              OR weather_current.wind_speed >= 39.0 
              THEN 'warning'::text
            ELSE 'low'::text
        END AS urgency,
    weather_current.station AS station_name,
    'https://open-meteo.com'::text AS source_url,
    'Station live weather metrics via Open-Meteo API'::text AS description
   FROM external.weather_current
  WHERE (((weather_current.observed_at AT TIME ZONE 'Asia/Manila'::text))::date = ((CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila'::text))::date)
UNION ALL
 SELECT min(ec.id) AS trigger_id,
        CASE
            WHEN ec.source_type = 'lgu'
                 OR ec.source_id LIKE 'external_lgu_%'
                 OR ec.event_category = 'lgu'::text
                 OR ec.friction_domain = 'lgu'::text
                 OR ec.source_name ~* '(government|city|pio|municipality|lgu|metropolitan|mmda|cainta)' THEN 'lgu'::text
            WHEN ec.source_type = 'mobile-app'
                 OR ec.source_table = 'incidents'
                 OR ec.source_name = 'Ground Control System' THEN 'mobile-app'
            ELSE 'academic'::text
        END AS source_type,
    string_agg(DISTINCT ec.source_name, ' / '::text) AS source,
    ((('Station: '::text || string_agg(DISTINCT ec.station, ', '::text)) || ' - '::text) || COALESCE(ec.event_name, 'Event Notice'::text)) AS message,
    max(COALESCE(ec.announcement_time, ec.updated_at)) AS "time",
        CASE
            -- Tier 1 (CRITICAL, Red): Normalized Score >= 0.80 or explicit physical disruptions
            WHEN ((lower(COALESCE(ec.event_name, ''::text)) ~* '(suspension|walang pasok|red alert|tigil pasada|strike|monsoon|typhoon)') 
                  OR (max(ec.normalized_score) >= 0.80)) THEN 'critical'::text
            -- Tier 2 (WARNING, Amber): Normalized Score between 0.45 and 0.79 or large crowd surges
            WHEN ((max(ec.normalized_score) >= 0.45) 
                  OR (lower(COALESCE(ec.event_name, ''::text)) ~* '(arena|concert|heavy rain|flood|commencement|graduation|rally)')) THEN 'warning'::text
            -- Tier 3 (INFORMATIONAL, Sky-Blue): Routine calendar milestones, exams, orientations, registrations
            ELSE 'low'::text
        END AS urgency,
    string_agg(DISTINCT ec.station, ', '::text) AS station_name,
    max(ec.source_url) AS source_url,
    max(ec.description) AS description
   FROM external.events_consolidated ec
  WHERE (ec.event_date = ((CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila'::text))::date)
  GROUP BY ec.event_date, 
           CASE
               WHEN ec.source_type = 'lgu'
                    OR ec.source_id LIKE 'external_lgu_%'
                    OR ec.event_category = 'lgu'::text
                    OR ec.friction_domain = 'lgu'::text
                    OR ec.source_name ~* '(government|city|pio|municipality|lgu|metropolitan|mmda|cainta)' THEN 'lgu'::text
               WHEN ec.source_type = 'mobile-app'
                    OR ec.source_table = 'incidents'
                    OR ec.source_name = 'Ground Control System' THEN 'mobile-app'
               ELSE 'academic'::text
           END,
           ec.event_category, 
           ec.friction_domain, 
           ec.event_name;

GRANT SELECT ON "Analytics"."descriptive_live_event_feed" TO anon, authenticated, service_role;
