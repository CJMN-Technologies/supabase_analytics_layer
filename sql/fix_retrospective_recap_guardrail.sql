-- =============================================================================
-- LRT-2 DSS | fix_retrospective_recap_guardrail.sql
-- =============================================================================
-- Purpose:
--   1. Purge retroactive past-event recap records that leaked into
--      external.events_consolidated when Facebook photo/recap posts
--      referenced past event dates.
--   2. Remove duplicate student-council disruption entries where the
--      parent university page already provides the canonical announcement.
--   3. Purge spurious disruption shocks:
--      - UST Central Student Council EVM petition denial (misclassified as 0.9 strike)
--      - Pasig City World Tourism and Creative Month (misclassified as 17-day arena shock)
--      - UAAP Season 89 Opener post-game recap
--      - Manila International Book Fair at SMX Pasay
--   4. Re-number external_acad_0002 to external_acad_0267 to eliminate clobbered ID.
--   5. Upgrade external.sync_academic_lgu_to_events_consolidated() with hardened
--      retrospective filters, sports recap keywords, student petition isolation,
--      civic theme month isolation, and UE Caloocan out-of-corridor guardrail.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- PART 1: Purge retroactive and spurious disruption records
-- ---------------------------------------------------------------------------

-- 1A. Manila International Book Fair 2026 — SMX Pasay outside LRT-2 corridor, posted Sept 14 for Sept 9.
DELETE FROM external.events_consolidated
WHERE source_id = 'external_lgu_0251'
  AND source_table = 'academic_lgu_events';

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'Retrospective photo recap: posted 2026-09-14 referencing past event_date 2026-09-09. MIBF venue (SMX Pasay) is outside LRT-2 corridor. Deactivated by fix_retrospective_recap_guardrail.sql.'
WHERE id = 'external_lgu_0251';

-- 1B. SBU Rizal Pep Rally for NCAA Season 102 — posted as photo recap on Sept 12, event_date = 2026-09-01.
DELETE FROM external.events_consolidated
WHERE source_id = 'external_acad_0251'
  AND source_table = 'academic_lgu_events';

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'Retrospective photo recap: posted 2026-09-12 referencing past event_date 2026-09-01. Post-event celebratory album, not a forward disruption notice. Deactivated by fix_retrospective_recap_guardrail.sql.'
WHERE id = 'external_acad_0251';

-- 1C. FEU Central Student Organization duplicate of external_acad_0256.
DELETE FROM external.events_consolidated
WHERE source_id = 'external_acad_0257'
  AND source_table = 'academic_lgu_events';

UPDATE external.academic_lgu_events
SET cancellation_reason = 'Duplicate of external_acad_0256 (Far Eastern University Manila official). Same campus, same date range 2026-09-14 to 2026-09-16, same ONLINE_CLASS_SHIFT code. Removed from events_consolidated to prevent double-counting by fix_retrospective_recap_guardrail.sql.'
WHERE id = 'external_acad_0257';

-- 1D. UAAP Season 89 Basketball Tournament Opener — posted Sept 14 as game recap for Sept 13 victory.
DELETE FROM external.events_consolidated
WHERE source_id = 'external_acad_0264'
  AND source_table = 'academic_lgu_events';

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'Retrospective post-game score report: posted 2026-09-14 referencing past Sept 13 game outcome. Deactivated by fix_retrospective_recap_guardrail.sql.'
WHERE id = 'external_acad_0264';

-- 1E. UST Central Student Council EVM petition denial — non-disruptive administrative notice falsely tagged as transport strike.
DELETE FROM external.events_consolidated
WHERE source_id = 'external_acad_cal_0001'
  AND source_table = 'academic_lgu_events'
  AND event_category = 'transport_strike';

UPDATE external.academic_lgu_events
SET category = 'academic',
    event_code = 'ADMINISTRATIVE',
    is_cancelled = TRUE,
    cancellation_reason = 'Student council EVM petition denial: non-disruptive administrative notice, classes maintained on-site. Deactivated by fix_retrospective_recap_guardrail.sql.'
WHERE id = 'external_acad_cal_0001';

-- 1F. Pasig City World Tourism and Creative Month — 17-day theme celebration falsely tagged as MAJOR_ARENA_EVENT.
DELETE FROM external.events_consolidated
WHERE source_id = 'external_lgu_0271'
  AND source_table = 'academic_lgu_events';

UPDATE external.academic_lgu_events
SET event_code = 'CIVIC_MAINTENANCE',
    cancellation_reason = 'Pasig City World Tourism and Creative Month: general civic observance, not a single major arena event shock. Reclassified to CIVIC_MAINTENANCE by fix_retrospective_recap_guardrail.sql.'
WHERE id = 'external_lgu_0271';


-- ---------------------------------------------------------------------------
-- PART 2: Re-number external_acad_0002 to external_acad_0267
-- ---------------------------------------------------------------------------

-- Update consolidated rows referencing external_acad_0002 to external_acad_0267
UPDATE external.events_consolidated
SET source_id = 'external_acad_0267',
    id = REPLACE(id, 'external_acad_0002', 'external_acad_0267')
WHERE source_id = 'external_acad_0002'
  AND source_table = 'academic_lgu_events';

-- In academic_lgu_events, copy external_acad_0002 to external_acad_0267 and delete 0002
INSERT INTO external.academic_lgu_events (
    id, station, source_name, source_url, post_text, image_text, category,
    event_name, event_date, event_code, is_cancellation, cancellation_target_code,
    scraped_at, post_date, is_cancelled, cancellation_reason
)
SELECT
    'external_acad_0267', station, source_name, source_url, post_text, image_text, category,
    event_name, event_date, event_code, is_cancellation, cancellation_target_code,
    scraped_at, post_date, is_cancelled, cancellation_reason
FROM external.academic_lgu_events
WHERE id = 'external_acad_0002'
ON CONFLICT (id) DO UPDATE SET
    station = EXCLUDED.station,
    source_name = EXCLUDED.source_name,
    event_name = EXCLUDED.event_name,
    event_date = EXCLUDED.event_date,
    event_code = EXCLUDED.event_code,
    scraped_at = EXCLUDED.scraped_at,
    post_date = EXCLUDED.post_date;

DELETE FROM external.academic_lgu_events WHERE id = 'external_acad_0002';


-- ---------------------------------------------------------------------------
-- PART 3: Upgrade sync trigger with hardened guardrails
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
    v_is_theme_month boolean := FALSE;
    v_is_caloocan_only boolean := FALSE;
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM external.events_consolidated WHERE source_id = OLD.id AND source_table = 'academic_lgu_events';
        RETURN OLD;
    END IF;

    -- Resolve affected stations
    v_stations := external.get_affected_stations(NEW.station, NEW.post_text, NEW.image_text, NEW.source_name);
    v_combined_text := LOWER(COALESCE(NEW.post_text, '') || ' ' || COALESCE(NEW.image_text, ''));

    -- -------------------------------------------------------------------------
    -- UE CALOOCAN OUT-OF-CORRIDOR GUARDRAIL
    -- -------------------------------------------------------------------------
    IF NEW.source_name ILIKE '%University of the East%' THEN
        IF (v_combined_text ~* '(ue\s+caloocan|caloocan\s+campus|caloocan\s+open\s+field|samson\s+road)')
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
    -- CIVIC THEME MONTH / BROAD MULTI-WEEK CELEBRATION GUARDRAIL
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
    -- RETROSPECTIVE PHOTO RECAP & SPORTS OUTCOME GUARDRAIL
    --
    -- Rule: If event_code = 'MAJOR_ARENA_EVENT' AND the extracted event_date
    -- is >= 1 day before post_date, or contains recap/outcome language.
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

    -- Retrospective phrasing detection (Filipino + English recap language + sports game outcomes)
    IF NOT v_is_retrospective
       AND NEW.event_code = 'MAJOR_ARENA_EVENT'
       AND NEW.event_date IS NOT NULL
       AND NEW.event_date ~ '^\d{4}-\d{2}-\d{2}$'
       AND NEW.event_date::date < COALESCE(NEW.post_date::date, CURRENT_DATE) THEN
        IF v_combined_text ~* '(naging\s+matagumpay|came\s+together|held\s+(last|on)\s+(september|august|july|june|monday|tuesday|wednesday|thursday|friday|saturday|sunday)|photo\s+(highlight|album|recap|documentation)|look\s+back|event\s+recap|successfully\s+held|isang\s+matagumpay|naganap\s+noong|nagdaos\s+ng|naganap\s+kahapon|naging\s+makulay|nagtapos\s+na\s+ang|natapos\s+na|victory\s+over|defeated|won\s+against|edged\s+out|loss\s+to|final\s+score|campaign\s+off\s+to\s+a\s+strong\s+start|on\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2},?\s+20\d{2},?\s+the)' THEN
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
            v_source_type::text AS friction_domain,
            'Major Arena Event'::text AS trigger_category,
            TRUE::boolean AS affects_ridership
        INTO v_result;
    ELSE
        SELECT * INTO v_result
        FROM external.classify_event_from_text(NEW.post_text, NEW.image_text, NEW.category, NEW.event_name);
    END IF;

    -- -------------------------------------------------------------------------
    -- STUDENT COUNCIL PETITIONS / POSITION PAPERS / EVM REQUEST DENIAL GUARDRAIL
    -- -------------------------------------------------------------------------
    IF v_combined_text ~* '(will\s+not\s+shift\s+to\s+evm|maintain\s+class\s+schedules|denied\s+the\s+petition|no\s+shift\s+to\s+online|petition\s+requesting\s+a\s+shift\s+to\s+(?:enhanced\s+virtual\s+mode|evm))' THEN
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

COMMIT;
