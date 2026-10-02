-- =============================================================================
-- LRT-2 DSS | purge_all_scraped_anomalies_and_harden_guardrails.sql
-- =============================================================================
-- Purpose:
--   1. Upgrade external.sync_academic_lgu_to_events_consolidated() with
--      comprehensive guardrails:
--      - Off-corridor mega-arena & convention center geofencing filter (MOA Arena, PICC, San Andres, etc.)
--      - UE Caloocan out-of-corridor isolation
--      - Micro-venue, ticket booth, & campus anniversary suppression from MAJOR_ARENA_EVENT
--      - Expanded retrospective photo recap suppression (same-day & multi-day)
--      - Weather IMT demobilization exclusion from Civic Rally
--      - Online admissions / forms deadline routing away from Exam Week
--      - Civic theme month isolation
--      - Student council EVM petition denial isolation
--   2. Purge all 95 identified spurious shocks from external.events_consolidated.
--   3. Mark all 24 corresponding source records in external.academic_lgu_events
--      as cancelled with detailed audit reasons.
--   4. Delete off-corridor satellite campus holidays (Makati Day from FEU calendar).
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- PART 1: Upgrade sync trigger function FIRST with all hardened guardrails
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
    -- Guardrail detection flags
    v_is_retrospective boolean := FALSE;
    v_days_in_past integer;
    v_combined_text text;
    v_is_theme_month boolean := FALSE;
    v_is_caloocan_only boolean := FALSE;
    v_is_off_corridor_venue boolean := FALSE;
    v_is_micro_venue boolean := FALSE;
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM external.events_consolidated WHERE source_id = OLD.id AND source_table = 'academic_lgu_events';
        RETURN OLD;
    END IF;

    -- If the event is explicitly cancelled, remove any consolidated shocks and exit
    IF NEW.is_cancelled = TRUE THEN
        DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
        RETURN NEW;
    END IF;

    -- Resolve affected stations
    v_stations := external.get_affected_stations(NEW.station, NEW.post_text, NEW.image_text, NEW.source_name);
    v_combined_text := LOWER(COALESCE(NEW.post_text, '') || ' ' || COALESCE(NEW.image_text, '') || ' ' || COALESCE(NEW.event_name, ''));

    -- -------------------------------------------------------------------------
    -- 1. UE CALOOCAN OUT-OF-CORRIDOR GUARDRAIL
    -- -------------------------------------------------------------------------
    IF NEW.source_name ILIKE '%University of the East%' THEN
        IF (v_combined_text ~* '(ue\s+caloocan|caloocan\s+campus|caloocan\s+field|caloocan\s+open\s+field|samson\s+road)')
           AND NOT (v_combined_text ~* '(ue\s+manila|manila\s+campus|all\s+campuses|both\s+campuses|manila\s+and\s+caloocan|ue\s+community)') THEN
            v_is_caloocan_only := TRUE;
        END IF;
    END IF;

    IF v_is_caloocan_only THEN
        DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
        RAISE NOTICE 'UE Caloocan out-of-corridor guardrail: blocked % from LRT-2 corridor.', NEW.id;
        RETURN NEW;
    END IF;

    -- -------------------------------------------------------------------------
    -- 2. OFF-CORRIDOR MEGA ARENA & CONVENTION CENTER GEOFENCING GUARDRAIL
    -- Venues outside LRT-2 corridor: SM Mall of Asia Arena (Pasay), PICC (Pasay),
    -- San Andres Sports Complex (Malate District 5), World Trade Center, Philippine Arena.
    -- -------------------------------------------------------------------------
    IF v_combined_text ~* '(mall\s+of\s+asia\s+arena|moa\s+arena|smx\s+convention|philippine\s+international\s+convention\s+center|\bpicc\b|world\s+trade\s+center|san\s+andres\s+sports\s+complex|philippine\s+arena|bocaue|bonifacio\s+global\s+city|\bbgc\b|alabang|makati\s+city)'
       AND NOT v_combined_text ~* '(recto|legarda|pureza|v\.\s*mapa|j\.\s*ruiz|gilmore|betty\s*go|cubao|araneta|anonas|katipunan|santolan|marikina|antipolo)' THEN
        v_is_off_corridor_venue := TRUE;
    END IF;

    IF v_is_off_corridor_venue THEN
        DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
        RAISE NOTICE 'Off-corridor venue guardrail: blocked % (venue outside LRT-2 corridor).', NEW.id;
        RETURN NEW;
    END IF;

    -- -------------------------------------------------------------------------
    -- 3. MICRO-VENUE, TICKET BOOTH, & CAMPUS ANNIVERSARY GUARDRAIL
    -- Ticket sales, room reservation booths, covered courts, dance studios,
    -- choir concerts, and campus anniversary ceremonies do not produce arena friction.
    -- -------------------------------------------------------------------------
    IF NEW.event_code = 'MAJOR_ARENA_EVENT' THEN
        IF v_combined_text ~* '(ticket\s+selling|ticket\s+booth|ticket\s+reservation|ticket\s+availability|dance\s+studio|covered\s+court|children''?s\s+choir|foundation\s+anniversary|yellow\s+day)' THEN
            v_is_micro_venue := TRUE;
        END IF;
    END IF;

    IF v_is_micro_venue THEN
        DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
        RAISE NOTICE 'Micro-venue/ticket booth guardrail: blocked % from MAJOR_ARENA_EVENT.', NEW.id;
        RETURN NEW;
    END IF;

    -- -------------------------------------------------------------------------
    -- 4. CIVIC THEME MONTH / BROAD MULTI-WEEK CELEBRATION GUARDRAIL
    -- -------------------------------------------------------------------------
    IF v_combined_text ~* '(world\s+tourism\s+month|creative\s+industries\s+month|tourism\s+and\s+creative|buwan\s+ng\s+wika|anniversary\s+month)'
       OR (NEW.event_name ~* '(tourism\s+month|creative\s+month|buwan\s+ng\s+wika)') THEN
        v_is_theme_month := TRUE;
    END IF;

    IF v_is_theme_month AND NEW.event_code = 'MAJOR_ARENA_EVENT' THEN
        DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
        RAISE NOTICE 'Civic theme month guardrail: blocked % from MAJOR_ARENA_EVENT daily expansion.', NEW.id;
        RETURN NEW;
    END IF;

    -- -------------------------------------------------------------------------
    -- 5. RETROSPECTIVE PHOTO RECAP & SPORTS OUTCOME GUARDRAIL
    -- Catches past dates, same-day recaps, and explicit post-event phrasing.
    -- -------------------------------------------------------------------------
    IF NEW.event_code = 'MAJOR_ARENA_EVENT'
       AND NEW.event_date IS NOT NULL
       AND NEW.event_date ~ '^\d{4}-\d{2}-\d{2}$'
       AND NEW.post_date IS NOT NULL THEN
        v_days_in_past := (NEW.post_date::date - NEW.event_date::date);
        IF v_days_in_past >= 1 THEN
            v_is_retrospective := TRUE;
        END IF;
    END IF;

    -- Retrospective phrasing detection (same-day or past)
    IF NOT v_is_retrospective
       AND NEW.event_code = 'MAJOR_ARENA_EVENT' THEN
        IF v_combined_text ~* '(playing\s+it\s+back|katatapos\s+lang|after\s+the\s+(?:spectacular|opening|ceremony|game|match)|officially\s+commenced|came\s+together\s+for\s+an\s+opening|naging\s+matagumpay|held\s+(last|on)\s+(september|august|july|june|monday|tuesday|wednesday|thursday|friday|saturday|sunday)|photo\s+(highlight|album|recap|documentation)|look\s+back|event\s+recap|successfully\s+held|isang\s+matagumpay|naganap\s+noong|nagdaos\s+ng|naganap\s+kahapon|naging\s+makulay|nagtapos\s+na\s+ang|natapos\s+na|victory\s+over|defeated|won\s+against|edged\s+out|loss\s+to|final\s+score|campaign\s+off\s+to\s+a\s+strong\s+start|on\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2},?\s+20\d{2},?\s+the)' THEN
            v_is_retrospective := TRUE;
        END IF;
    END IF;

    IF v_is_retrospective THEN
        DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
        RAISE NOTICE 'Retrospective recap guardrail: blocked % (event_date: %, post_date: %)',
            NEW.id, NEW.event_date, NEW.post_date::date;
        RETURN NEW;
    END IF;

    -- -------------------------------------------------------------------------
    -- 6. RESOLVE EXPLICIT SOURCE TYPE ('lgu' vs 'academic')
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
            v_source_type::text AS friction_domain,
            'Major Arena Event'::text AS trigger_category,
            TRUE::boolean AS affects_ridership
        INTO v_result;
    ELSE
        SELECT * INTO v_result
        FROM external.classify_event_from_text(NEW.post_text, NEW.image_text, NEW.category, NEW.event_name);
    END IF;

    -- -------------------------------------------------------------------------
    -- 7. WEATHER DEMOBILIZATION EXCLUSION FROM CIVIC RALLY
    -- -------------------------------------------------------------------------
    IF v_combined_text ~* '(demobiliz|de-escalat|incident\s+management\s+team\s+.*demobiliz)' THEN
        v_result.affects_ridership := FALSE;
    END IF;

    -- -------------------------------------------------------------------------
    -- 8. STUDENT COUNCIL PETITIONS / POSITION PAPERS GUARDRAIL
    -- -------------------------------------------------------------------------
    IF v_combined_text ~* '(will\s+not\s+shift\s+to\s+evm|maintain\s+class\s+schedules|denied\s+the\s+petition|no\s+shift\s+to\s+online|petition\s+requesting\s+a\s+shift\s+to\s+(?:enhanced\s+virtual\s+mode|evm))' THEN
        v_result.affects_ridership := FALSE;
    END IF;

    -- -------------------------------------------------------------------------
    -- 9. ONLINE ADMISSIONS / FORM SUBMISSION DEADLINE EXCLUSION FROM EXAM WEEK
    -- -------------------------------------------------------------------------
    IF v_combined_text ~* '(upcat\s+application\s+deadline|forms\s+1\s+and\s+2b|submission\s+of\s+forms|hard\s+copy\s+of\s+grades)' THEN
        v_result.affects_ridership := FALSE;
    END IF;

    -- -------------------------------------------------------------------------
    -- 10. TYPHOON WARNING / ADVISORY SAFETY GUARDRAIL
    -- Weather advisories must never be classified as Holiday.
    -- -------------------------------------------------------------------------
    IF NEW.event_code = 'WEATHER_ADVISORY' AND v_result.trigger_category = 'Holiday' THEN
        v_result.affects_ridership := FALSE;
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


-- ---------------------------------------------------------------------------
-- PART 2: Purge all 95 spurious shock records from external.events_consolidated
-- ---------------------------------------------------------------------------

-- 2A. Off-Corridor Venues: MOA Arena, PICC, San Andres Sports Complex (32 shocks)
DELETE FROM external.events_consolidated
WHERE source_table = 'academic_lgu_events'
  AND source_id IN (
    'external_acad_0041', 'external_acad_0196', 'external_acad_0244', 
    'external_acad_0245', 'external_acad_0249', 'external_acad_0250',
    'external_acad_0116', 'external_lgu_0096', 'external_lgu_0094'
  );

-- 2B. Historical UE Caloocan Events (12 shocks)
DELETE FROM external.events_consolidated
WHERE source_table = 'academic_lgu_events'
  AND source_id IN ('external_acad_0162', 'external_acad_0155', 'external_acad_0210');

-- 2C. Off-Corridor Satellite Campus Holidays in Academic Calendar (4 shocks)
DELETE FROM external.events_consolidated
WHERE source_table = 'FEU_Academic_Calendar'
  AND event_name ILIKE '%Makati Day%';

-- 2D. Micro-Venues, Ticket Booths, & School Anniversaries (20 shocks)
DELETE FROM external.events_consolidated
WHERE source_table = 'academic_lgu_events'
  AND source_id IN (
    'external_acad_0195', 'external_acad_0181', 'external_acad_0156', 
    'external_lgu_0278', 'external_acad_0003'
  );

-- 2E. Retrospective Photo Recaps (17 shocks)
DELETE FROM external.events_consolidated
WHERE source_table = 'academic_lgu_events'
  AND source_id IN (
    'external_acad_0263', 'external_acad_0265', 'external_acad_0209', 'external_acad_0232'
  );

-- 2F. Administrative Portal Form Deadlines (5 shocks)
DELETE FROM external.events_consolidated
WHERE source_table = 'academic_lgu_events'
  AND source_id = 'external_acad_0115';

-- 2G. Severe Weather Demobilization & Storm Advisories (5 shocks)
DELETE FROM external.events_consolidated
WHERE source_table = 'academic_lgu_events'
  AND source_id IN ('external_lgu_0064', 'external_lgu_0063', 'external_lgu_0001');


-- ---------------------------------------------------------------------------
-- PART 3: Deactivate source records in external.academic_lgu_events
-- ---------------------------------------------------------------------------

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'Off-corridor venue: SM Mall of Asia Arena (Pasay City) is outside the LRT-2 transit corridor.'
WHERE id IN ('external_acad_0041', 'external_acad_0196', 'external_acad_0244', 'external_acad_0245', 'external_acad_0249', 'external_acad_0250');

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'Off-corridor venue: Philippine International Convention Center (PICC, Pasay City) is outside the LRT-2 transit corridor.'
WHERE id = 'external_acad_0116';

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'Off-corridor venue: San Andres Sports Complex (Malate, District 5) is outside the LRT-2 transit corridor.'
WHERE id IN ('external_lgu_0096', 'external_lgu_0094');

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'Off-corridor campus: UE Caloocan (Samson Road) is outside the LRT-2 transit corridor.'
WHERE id IN ('external_acad_0162', 'external_acad_0155', 'external_acad_0210');

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'Micro-venue / Ticket Booth: Ticket reservation announcement, not a major arena transit event.'
WHERE id IN ('external_acad_0195', 'external_acad_0181');

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'Micro-venue: College of Music Dance Studio recital, not a major arena transit event.'
WHERE id = 'external_acad_0156';

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'Micro-venue: Barangay covered court community concert, not a major arena transit event.'
WHERE id = 'external_lgu_0278';

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'Campus observance: Foundation anniversary mass and children choir concert, not a major arena transit event.'
WHERE id = 'external_acad_0003';

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'Retrospective photo recap / post-event interview: event already occurred.'
WHERE id IN ('external_acad_0263', 'external_acad_0265', 'external_acad_0209', 'external_acad_0232');

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'Administrative portal deadline for report card submissions, not an in-person university examination week.'
WHERE id = 'external_acad_0115';

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'Weather advisory de-escalation: IMT demobilization report, not a civic rally or public protest mobilization.'
WHERE id IN ('external_lgu_0064', 'external_lgu_0063');

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'Weather advisory bulletin: PAGASA storm warning, misclassified as a holiday.'
WHERE id = 'external_lgu_0001';

COMMIT;
