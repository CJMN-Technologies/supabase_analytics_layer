-- ============================================================================
-- PURGE SCRAPED EVENT ANOMALIES & HARDEN TRIGGER GUARDRAILS (SEPT 26, 2026)
-- Target Supabase Project: kthioobzfyepokrrykem
-- Execution Date: 2026-09-26
--
-- Anomalies Addressed:
-- 1. external_lgu_0328: QC Gov Pop Up Payatas Youth Market Expo 2026 on Sto Nino St.
--    Hyper-local barangay street food market misclassified as MAJOR_ARENA_EVENT
--    (50 spurious shocks across 5 QC stations over 10 days purged).
-- 2. external_acad_0285: FEU Manila Bakood Festival Musiko Drumline Battle.
--    Off-corridor Bacoor Cavite venue (Strike Gymnasium) and retrospective competition
--    recap misclassified as MAJOR_ARENA_EVENT (4 spurious arena shocks purged).
-- 3. external_lgu_0329: Pasig River Ferry Tour reclassified to CIVIC_COMMUNITY.
-- 4. external_acad_0286: FEU weekly advisory standardized as CAMPUS_ACADEMIC_EVENT.
-- ============================================================================

BEGIN;

-- Step 1: Purge 54 spurious shocks from external.events_consolidated
DELETE FROM external.events_consolidated
WHERE source_id IN ('external_lgu_0328', 'external_acad_0285');

-- Step 2: Soft-cancel Payatas pop-up market anomaly in academic_lgu_events
UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'ANOMALY REMEDIATED: Hyper-local Payatas street food market/bazaar misclassified as MAJOR_ARENA_EVENT. 50 spurious shocks purged.'
WHERE id = 'external_lgu_0328';

-- Step 3: Soft-cancel Bacoor Cavite drumline recap anomaly in academic_lgu_events
UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'ANOMALY REMEDIATED: Off-corridor Bacoor Cavite venue (Strike Gymnasium) and retrospective competition recap misclassified as MAJOR_ARENA_EVENT. 4 spurious shocks purged.'
WHERE id = 'external_acad_0285';

-- Step 4: Correct classification for Pasig river ferry tour
UPDATE external.academic_lgu_events
SET event_code = 'CIVIC_COMMUNITY',
    category = 'lgu',
    cancellation_reason = 'Reclassified from MAJOR_ARENA_EVENT: 40-pax guided river ferry tour.'
WHERE id = 'external_lgu_0329';

-- Step 5: Standardize FEU weekly advisory
UPDATE external.academic_lgu_events
SET event_code = 'CAMPUS_ACADEMIC_EVENT',
    cancellation_reason = 'Informational weekly academic calendar notice. Active transport strike shocks handled by external_acad_0284.'
WHERE id = 'external_acad_0286';

-- Step 6: Harden external.sync_academic_lgu_to_events_consolidated trigger function
CREATE OR REPLACE FUNCTION external.sync_academic_lgu_to_events_consolidated()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
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
    v_is_retrospective boolean := FALSE;
    v_days_in_past integer;
    v_combined_text text;
    v_is_theme_month boolean := FALSE;
    v_is_caloocan_only boolean := FALSE;
    v_is_off_corridor_venue boolean := FALSE;
    v_is_micro_venue boolean := FALSE;
    v_is_student_welfare boolean := FALSE;
    v_is_calendar_duplicate boolean := FALSE;
    v_parent_exists boolean := FALSE;
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM external.events_consolidated WHERE source_id = OLD.id AND source_table = 'academic_lgu_events';
        RETURN OLD;
    END IF;

    IF NEW.is_cancelled = TRUE THEN
        DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
        RETURN NEW;
    END IF;

    v_stations := external.get_affected_stations(NEW.station, NEW.post_text, NEW.image_text, NEW.source_name);
    v_combined_text := LOWER(COALESCE(NEW.post_text, '') || ' ' || COALESCE(NEW.image_text, '') || ' ' || COALESCE(NEW.event_name, ''));

    -- Guardrail: Student Welfare Lounges, Free Coffee / Snack Booths
    IF v_combined_text ~* '(study\s+fuel|snack\s+booth|free\s+coffee|student\s+activity\s+room|snack\s+station|busking\s+lounge)' THEN
        v_is_student_welfare := TRUE;
    END IF;

    IF v_is_student_welfare THEN
        DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
        RAISE NOTICE 'Student welfare lounge guardrail: blocked % from transit shocks.', NEW.id;
        RETURN NEW;
    END IF;

    -- Guardrail: Institutional Cluster Deduplication (Student Council vs University Admin)
    IF NEW.source_name ~* '(student council|sanggunian|central student|cso|usc|sc\b)' THEN
        SELECT EXISTS (
            SELECT 1 FROM external.academic_lgu_events p
            WHERE p.id != NEW.id
              AND p.is_cancelled = FALSE
              AND p.source_name !~* '(student council|sanggunian|central student|cso|usc|sc\b)'
              AND (
                  (NEW.source_name ~* 'feu' AND p.source_name ~* 'far eastern university')
                  OR (NEW.source_name ~* 'ust' AND p.source_name ~* 'university of santo tomas')
                  OR (NEW.source_name ~* 'ue' AND p.source_name ~* 'university of the east')
                  OR (NEW.source_name ~* 'uerm' AND p.source_name ~* 'uerm')
                  OR (NEW.source_name ~* 'up' AND p.source_name ~* 'university of the philippines')
              )
              AND p.event_code = NEW.event_code
              AND (
                  p.event_date = NEW.event_date
                  OR (NEW.event_date IS NOT NULL AND p.event_date IS NOT NULL AND (
                      p.event_date LIKE '%' || SPLIT_PART(NEW.event_date, ' to ', 1) || '%'
                      OR NEW.event_date LIKE '%' || SPLIT_PART(p.event_date, ' to ', 1) || '%'
                  ))
              )
        ) INTO v_parent_exists;

        IF v_parent_exists THEN
            DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
            RAISE NOTICE 'Institutional cluster duplicate guardrail: suppressed student council post % because parent university announcement already filed.', NEW.id;
            RETURN NEW;
        END IF;
    END IF;

    -- Guardrail: Social media exam cheer duplicating active institutional calendar
    IF v_combined_text ~* '(give\s+it\s+your\s+best|you(''?ve)?\s+got\s+this|good\s+luck|fighting|kaya\s+ninyo\s+yan)'
       AND v_combined_text ~* '(exam|midterm|prelim|final)' THEN
        SELECT EXISTS (
            SELECT 1 FROM external.events_consolidated c
            WHERE c.source_table = 'academic_calendar'
              AND c.event_date = NEW.post_date::date
              AND c.event_category = 'exam_week'
              AND c.station = ANY(v_stations)
        ) INTO v_is_calendar_duplicate;

        IF v_is_calendar_duplicate THEN
            DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
            RAISE NOTICE 'Social media exam cheer duplicate guardrail: suppressed % (institutional calendar already exists).', NEW.id;
            RETURN NEW;
        END IF;
    END IF;

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

    -- Guardrail: Off-Corridor Mega Venues & Distant Provincial Venues
    IF v_combined_text ~* '(mall\s+of\s+asia\s+arena|moa\s+arena|smx\s+convention|philippine\s+international\s+convention\s+center|\bpicc\b|world\s+trade\s+center|san\s+andres\s+sports\s+complex|philippine\s+arena|bocaue|bonifacio\s+global\s+city|\bbgc\b|alabang|makati\s+city|foro\s+de\s+intramuros|\bintramuros\b|tourism\s+expo|heritage\s+spaces|\bbanawe\b|\bchinatown\b|strike\s+gymnasium|\bbacoor\b|\bcavite\b|\blaguna\b|\bbulacan\b|\bpampanga\b|\bpayatas\b)'
       AND NOT v_combined_text ~* '(recto|legarda|pureza|v\.\s*mapa|j\.\s*ruiz|gilmore|betty\s*go|cubao|araneta|anonas|katipunan|santolan|marikina|antipolo)' THEN
        v_is_off_corridor_venue := TRUE;
    END IF;

    IF v_is_off_corridor_venue THEN
        DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
        RAISE NOTICE 'Off-corridor venue guardrail: blocked % (venue outside LRT-2 corridor).', NEW.id;
        RETURN NEW;
    END IF;

    -- Guardrail: Micro-venues, street markets/bazaars, hotel ballrooms, and classroom general assemblies
    IF NEW.event_code = 'MAJOR_ARENA_EVENT' THEN
        IF v_combined_text ~* '(ticket\s+selling|ticket\s+booth|ticket\s+reservation|ticket\s+availability|dance\s+studio|covered\s+court|children''?s\s+choir|foundation\s+anniversary|yellow\s+day|banawe|chinatown|mooncake\s+fest(ival)?|novotel|ballroom|hotel|barangay\s+day|sub\s+\d+|room\s+\d+|classroom|general\s+assembly|pop[\s_-]*up|market[\s_-]*expo|\bbazaar\b|\btiangge\b|night[\s_-]*market|street[\s_-]*food|youth[\s_-]*market|river\s+ferry\s+tour|guided\s+tour)' THEN
            v_is_micro_venue := TRUE;
        END IF;
    END IF;

    IF v_is_micro_venue THEN
        DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
        RAISE NOTICE 'Micro-venue/bazaar/hotel ballroom guardrail: blocked % from MAJOR_ARENA_EVENT.', NEW.id;
        RETURN NEW;
    END IF;

    IF v_combined_text ~* '(world\s+tourism\s+month|creative\s+industries\s+month|tourism\s+and\s+creative|buwan\s+ng\s+wika|anniversary\s+month)'
       OR (NEW.event_name ~* '(tourism\s+month|creative\s+month|buwan\s+ng\s+wika)') THEN
        v_is_theme_month := TRUE;
    END IF;

    IF v_is_theme_month AND NEW.event_code = 'MAJOR_ARENA_EVENT' THEN
        DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
        RAISE NOTICE 'Civic theme month guardrail: blocked % from MAJOR_ARENA_EVENT daily expansion.', NEW.id;
        RETURN NEW;
    END IF;

    -- Retrospective recaps: post date after event date
    IF NEW.event_code = 'MAJOR_ARENA_EVENT'
       AND NEW.event_date IS NOT NULL
       AND NEW.event_date ~ '^\d{4}-\d{2}-\d{2}$'
       AND NEW.post_date IS NOT NULL THEN
        v_days_in_past := (NEW.post_date::date - NEW.event_date::date);
        IF v_days_in_past >= 1 THEN
            v_is_retrospective := TRUE;
        END IF;
    END IF;

    -- Retrospective recaps: photo albums, recaps, competition wins, post-event coverage
    IF NOT v_is_retrospective THEN
        IF v_combined_text ~* '(photos?\s+by\b|photo\s+album\b|in\s+photos:\b|event\s+recap:\b|protesters\s+marched\s+to\b|playing\s+it\s+back|katatapos\s+lang|after\s+the\s+(?:spectacular|opening|ceremony|game|match)|officially\s+commenced|came\s+together\s+for\s+an\s+opening|naging\s+matagumpay|held\s+(last|on)\s+(september|august|july|june|monday|tuesday|wednesday|thursday|friday|saturday|sunday)|photo\s+(highlight|album|recap|documentation)|look\s+back|event\s+recap|successfully\s+held|isang\s+matagumpay|naganap\s+noong|nagdaos\s+ng|naganap\s+kahapon|naging\s+makulay|nagtapos\s+na\s+ang|natapos\s+na|victory\s+over|defeated|won\s+against|edged\s+out|loss\s+to|final\s+score|campaign\s+off\s+to\s+a\s+strong\s+start|thank\s+you\s+to\s+our\s+partner|couldn''?t\s+have\s+done\s+it\s+without|partner\s+companies|sponsors?\s+and\s+partners?|one\s+to\s+remember|for\s+helping\s+make\s+the|on\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2},?\s+20\d{2},?\s+the|idinaos\s+na|napuno\s+ng\s+masasayang\s+aktibidad|\bcongratulat(ions?|ory)\b|\bpagbati\b|\bchampion(ship)?\b|\bbagged\b|won\s+(the|against|first|championship)|\bmusiko\b|\bdrumline\b)' THEN
            v_is_retrospective := TRUE;
        END IF;
    END IF;

    IF v_is_retrospective THEN
        DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
        RAISE NOTICE 'Retrospective recap guardrail: blocked % (event_date: %, post_date: %)',
            NEW.id, NEW.event_date, NEW.post_date::date;
        RETURN NEW;
    END IF;

    v_source_type := CASE
        WHEN NEW.source_name ~* '(university|college|school|institute|sanggunian|student council|varsitarian|konseho|tamaraw|bedan|ateneo|ust|feu|pup|uerm|tip|wcc|st\.?\s*paul|stella maris)' THEN 'academic'
        WHEN NEW.category = 'lgu'
             OR NEW.id LIKE 'external_lgu_%'
             OR NEW.source_name ~* '(government|pio|public information|municipality|\blgu\b|metropolitan|mmda|cainta|lungsod ng|pamahalaang lungsod)' THEN 'lgu'
        ELSE 'academic'
    END;

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

    IF NEW.event_code = 'MAJOR_ARENA_EVENT' THEN
        SELECT
            COALESCE(NULLIF(TRIM(NEW.event_name), ''), 'Major Arena / Sports Event')::text AS event_name,
            'major_event'::text AS event_category,
            v_source_type::text AS friction_domain,
            'Major Arena Event'::text AS trigger_category,
            TRUE::boolean AS affects_ridership
        INTO v_result;
    ELSIF NEW.event_code = 'CIVIC_RALLY' THEN
        SELECT
            COALESCE(NULLIF(TRIM(NEW.event_name), ''), 'Civic Rally & Public Mobilization')::text AS event_name,
            'major_event'::text AS event_category,
            v_source_type::text AS friction_domain,
            'Civic Rally & Public Mobilization'::text AS trigger_category,
            TRUE::boolean AS affects_ridership
        INTO v_result;
    ELSE
        SELECT * INTO v_result
        FROM external.classify_event_from_text(NEW.post_text, NEW.image_text, NEW.category, NEW.event_name);
    END IF;

    IF v_combined_text ~* '(demobiliz|de-escalat|incident\s+management\s+team\s+.*demobiliz)' THEN
        v_result.affects_ridership := FALSE;
    END IF;

    IF v_combined_text ~* '(will\s+not\s+shift\s+to\s+evm|maintain\s+class\s+schedules|denied\s+the\s+petition|no\s+shift\s+to\s+online|petition\s+requesting\s+a\s+shift\s+to\s+(?:enhanced\s+virtual\s+mode|evm))' THEN
        v_result.affects_ridership := FALSE;
    END IF;

    IF v_combined_text ~* '(upcat\s+application\s+deadline|forms\s+1\s+and\s+2b|submission\s+of\s+forms|hard\s+copy\s+of\s+grades)' THEN
        v_result.affects_ridership := FALSE;
    END IF;

    -- Motorist / Roadway Traffic Advisories do not impact rail operations
    IF (v_combined_text ~* '(abiso\s+sa\s+mga\s+motorista|alternatibong\s+ruta|traffic\s+rerouting|slow\s+moving\s+traffic|pagbagal\s+ng\s+daloy|motorista)')
       AND NOT (v_combined_text ~* '(suspend|walang\s*pasok|no\s+class|online\s+class|strike|tigil\s+pasada|welga)') THEN
        v_result.affects_ridership := FALSE;
    END IF;

    -- Non-disruptive event codes should never trigger holiday or class suspensions
    IF NEW.event_code IN ('CIVIC_MAINTENANCE', 'WEATHER_ADVISORY') AND v_result.event_category IN ('holiday', 'class_suspension') THEN
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
$function$;

COMMIT;
