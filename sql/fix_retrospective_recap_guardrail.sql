-- =============================================================================
-- LRT-2 DSS | fix_retrospective_recap_guardrail.sql
-- =============================================================================
-- Purpose:
--   1. Purge retroactive past-event recap records that leaked into
--      external.events_consolidated when Facebook photo/recap posts
--      referenced past event dates (within the 14-day scraper window).
--   2. Remove duplicate student-council disruption entries where the
--      parent university page already provides the canonical announcement.
--   3. Upgrade external.sync_academic_lgu_to_events_consolidated() with a
--      retrospective post-event recap guardrail so that future photo recaps
--      do not generate spurious active disruption shocks in events_consolidated.
--
-- Anomalies fixed:
--   A. external_lgu_0251 — QC Government "Manila International Book Fair 2026
--      Event" photo recap posted Sept 14 but event_date extracted as 2026-09-09
--      (5 days in the past). Leaked 5 station rows into events_consolidated.
--   B. external_acad_0251 — San Beda Student Council pep rally photo recap
--      posted Sept 12 but event_date extracted as 2026-09-01 (11 days in
--      the past). Leaked 4 station rows into events_consolidated.
--   C. external_acad_0257 — FEU Central Student Organization duplicate of
--      external_acad_0256 (Far Eastern University Manila official page) for the
--      same campus, same date range (Sept 14-16), same ONLINE_CLASS_SHIFT code.
--      12 duplicate station rows removed from events_consolidated.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- PART 1: Purge retroactive past-event recap records
-- ---------------------------------------------------------------------------

-- 1A. Manila International Book Fair 2026 — posted as photo recap on Sept 14,
--     event_date = 2026-09-09 (5 days before post date). Not a forward-looking
--     disruption notice; purely a ceremonial recap. MIBF is also at SMX
--     Pasay, outside LRT-2 corridor.
DELETE FROM external.events_consolidated
WHERE source_id = 'external_lgu_0251'
  AND source_table = 'academic_lgu_events';

-- Mark the source record so future re-runs don't try to re-consolidate it.
UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'Retrospective photo recap: posted 2026-09-14 referencing past event_date 2026-09-09. MIBF venue (SMX Pasay) is outside LRT-2 corridor. Deactivated by fix_retrospective_recap_guardrail.sql.'
WHERE id = 'external_lgu_0251';

-- 1B. SBU Rizal Pep Rally for NCAA Season 102 — posted as photo recap on
--     Sept 12, event_date = 2026-09-01 (11 days before post date).
DELETE FROM external.events_consolidated
WHERE source_id = 'external_acad_0251'
  AND source_table = 'academic_lgu_events';

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'Retrospective photo recap: posted 2026-09-12 referencing past event_date 2026-09-01. Post-event celebratory album, not a forward disruption notice. Deactivated by fix_retrospective_recap_guardrail.sql.'
WHERE id = 'external_acad_0251';

-- ---------------------------------------------------------------------------
-- PART 2: Remove duplicate student council strike entries
-- ---------------------------------------------------------------------------
-- FEU Central Student Organization (external_acad_0257) and Far Eastern
-- University Manila (external_acad_0256) both posted ONLINE_CLASS_SHIFT
-- advisories for the same campus for Sept 14-16, 2026.
-- Retain the official administration page (external_acad_0256).
-- Remove the student org duplicate (external_acad_0257).
DELETE FROM external.events_consolidated
WHERE source_id = 'external_acad_0257'
  AND source_table = 'academic_lgu_events';

UPDATE external.academic_lgu_events
SET cancellation_reason = 'Duplicate of external_acad_0256 (Far Eastern University Manila official). Same campus, same date range 2026-09-14 to 2026-09-16, same ONLINE_CLASS_SHIFT code. Removed from events_consolidated to prevent double-counting by fix_retrospective_recap_guardrail.sql.'
WHERE id = 'external_acad_0257';

-- ---------------------------------------------------------------------------
-- PART 3: Upgrade sync trigger with retrospective recap guardrail
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION external.sync_academic_lgu_to_events_consolidated()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $func$
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
    v_start_date date;
    v_end_date date;
    v_curr_date date;
    v_date_match text[];
    -- Retrospective recap detection
    v_is_retrospective boolean := FALSE;
    v_days_in_past integer;
    v_combined_text text;
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM external.events_consolidated WHERE source_id = OLD.id AND source_table = 'academic_lgu_events';
        RETURN OLD;
    END IF;

    -- Resolve affected stations
    v_stations := external.get_affected_stations(NEW.station, NEW.post_text, NEW.image_text, NEW.source_name);

    -- -------------------------------------------------------------------------
    -- RETROSPECTIVE PHOTO RECAP GUARDRAIL
    --
    -- Rule: If event_code = 'MAJOR_ARENA_EVENT' AND the extracted event_date
    -- is more than 1 day before the post_date (the FB post was made AFTER
    -- the event already concluded), treat this as a retrospective photo album
    -- or celebratory recap — not a forward-looking disruption notice.
    --
    -- Additionally detect retrospective phrasing in post text.
    -- -------------------------------------------------------------------------
    v_combined_text := LOWER(COALESCE(NEW.post_text, '') || ' ' || COALESCE(NEW.image_text, ''));

    IF NEW.event_code = 'MAJOR_ARENA_EVENT'
       AND NEW.event_date IS NOT NULL
       AND NEW.event_date ~ '^\d{4}-\d{2}-\d{2}$'
       AND NEW.post_date IS NOT NULL THEN
        v_days_in_past := (NEW.post_date::date - NEW.event_date::date);
        IF v_days_in_past > 1 THEN
            v_is_retrospective := TRUE;
        END IF;
    END IF;

    -- Retrospective phrasing detection (Filipino + English recap language)
    IF NOT v_is_retrospective
       AND NEW.event_code = 'MAJOR_ARENA_EVENT'
       AND NEW.event_date IS NOT NULL
       AND NEW.event_date ~ '^\d{4}-\d{2}-\d{2}$'
       AND NEW.event_date::date < COALESCE(NEW.post_date::date, CURRENT_DATE) THEN
        IF v_combined_text ~* '(naging\s+matagumpay|came\s+together|held\s+(last|on)\s+(september|august|july|june|monday|tuesday|wednesday|thursday|friday|saturday|sunday)|photo\s+(highlight|album|recap|documentation)|look\s+back|event\s+recap|successfully\s+held|isang\s+matagumpay|naganap\s+noong|nagdaos\s+ng|naganap\s+kahapon|naging\s+makulay|nagtapos\s+na\s+ang|natapos\s+na|on\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2},?\s+20\d{2},?\s+the)' THEN
            v_is_retrospective := TRUE;
        END IF;
    END IF;

    IF v_is_retrospective THEN
        DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
        RAISE NOTICE 'Retrospective recap guardrail: blocked % (event_date: %, post_date: %, days_in_past: %)',
            NEW.id, NEW.event_date, NEW.post_date::date, v_days_in_past;
        RETURN NEW;
    END IF;

    -- -------------------------------------------------------------------------
    -- Resolve explicit source_type ('lgu' vs 'academic')
    -- -------------------------------------------------------------------------
    v_source_type := CASE
        WHEN NEW.source_name ~* '(university|college|school|institute|sanggunian|student council|varsitarian|konseho|tamaraw|bedan|ateneo|ust|feu|pup|uerm|tip|wcc|st\.?\s*paul|stella maris)' THEN 'academic'
        WHEN NEW.category = 'lgu'
             OR NEW.id LIKE 'external_lgu_%'
             OR NEW.source_name ~* '(government|pio|public information|municipality|\blgu\b|metropolitan|mmda|cainta|lungsod ng|pamahalaang lungsod)' THEN 'lgu'
        ELSE 'academic'
    END;

    -- Check if this is a cancellation or rescheduling
    IF NEW.is_cancellation = TRUE THEN
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

        IF NEW.event_date IS NOT NULL AND NEW.event_date ~ '^\d{4}-\d{2}-\d{2}$' THEN
            v_event_date := NEW.event_date::date;
            IF v_event_date > NEW.post_date::date
               AND (NEW.event_code = 'MAJOR_ARENA_EVENT' OR NEW.cancellation_target_code = 'MAJOR_ARENA_EVENT' OR LOWER(COALESCE(NEW.event_name, '')) ~* '(reschedul|move(d|s)\s+to|postpon)')
               AND NEW.event_code != 'RESUMPTION_CLASSES'
               AND LOWER(COALESCE(NEW.event_name, '')) !~* 'resumption' THEN
                v_is_reschedule := TRUE;
            END IF;
        END IF;

        IF NOT v_is_reschedule THEN
            DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
            RETURN NEW;
        END IF;
    END IF;

    -- Classify event
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

    SELECT fw.friction_weight INTO v_weight
    FROM external.friction_weight fw
    WHERE fw.friction_domain = v_result.friction_domain
      AND fw.trigger_category = v_result.trigger_category
    LIMIT 1;
    v_weight := COALESCE(v_weight, 0.65);

    DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';

    v_cat_code := CASE v_result.event_category
        WHEN 'class_suspension' THEN 'CS'
        WHEN 'holiday' THEN 'HD'
        WHEN 'school_break' THEN 'SB'
        WHEN 'transport_strike' THEN 'TS'
        WHEN 'major_event' THEN 'ME'
        WHEN 'exam_week' THEN 'EX'
        ELSE 'RC'
    END;

    IF NEW.event_date IS NOT NULL AND NEW.event_date ~ '^\d{4}-\d{2}-\d{2}\s*(?:to|–|-)\s*\d{4}-\d{2}-\d{2}$' THEN
        v_date_match := regexp_matches(NEW.event_date, '^(\d{4}-\d{2}-\d{2})\s*(?:to|–|-)\s*(\d{4}-\d{2}-\d{2})$');
        v_start_date := v_date_match[1]::date;
        v_end_date := v_date_match[2]::date;
        IF v_end_date > v_start_date + INTERVAL '14 days' THEN
            v_end_date := v_start_date + INTERVAL '14 days';
        END IF;
    ELSIF v_event_date IS NOT NULL THEN
        v_start_date := v_event_date;
        v_end_date := v_event_date;
    ELSIF NEW.event_date IS NOT NULL AND NEW.event_date ~ '^\d{4}-\d{2}-\d{2}$' THEN
        v_start_date := NEW.event_date::date;
        v_end_date := NEW.event_date::date;
    ELSE
        v_start_date := external.extract_event_date_from_text(NEW.post_text, NEW.image_text, NEW.post_date);
        v_end_date := v_start_date;
    END IF;

    v_curr_date := v_start_date;
    WHILE v_curr_date <= v_end_date LOOP
        FOREACH v_station IN ARRAY v_stations LOOP
            v_scrape_id := 'SCR-' || v_cat_code || '-' || TO_CHAR(v_curr_date, 'MMDD') || '-' || NEW.id || '-' || REPLACE(LOWER(v_station), ' ', '_');

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
                v_curr_date,
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
        v_curr_date := v_curr_date + INTERVAL '1 day';
    END LOOP;

    RETURN NEW;
END;
$func$;

COMMIT;
