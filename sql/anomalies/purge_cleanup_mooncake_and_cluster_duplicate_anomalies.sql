-- ============================================================================
-- PURGE CLEANUP, MOONCAKE & CLUSTER DUPLICATE ANOMALIES & HARDEN FILTERS
-- Target Supabase Project: kthioobzfyepokrrykem
-- Execution Date: 2026-09-20 / 2026-09-21
--
-- 1. Purge exactly 31 spurious shock records from external.events_consolidated:
--    - external_lgu_0287 (Pasig coastal cleanup, false holiday shock): 2 records
--    - external_lgu_0293 (QC Mooncake Fest at Banawe, retrospective street fest): 5 records
--    - external_acad_0272 (FEU CSO duplicate of official FEU strike external_acad_0271): 24 records
-- 2. Mark source records in external.academic_lgu_events as is_cancelled = true
-- 3. Harden external.classify_event_from_text():
--    - Constrain "araw ng" to statutory holidays (araw ng kagitingan, maynila, etc.)
--    - Classify civic/environmental cleanups as non-ridership infrastructure
-- 4. Harden external.sync_academic_lgu_to_events_consolidated():
--    - Add "idinaos na" and "napuno ng masasayang aktibidad" to retrospective filter
--    - Add "banawe", "chinatown", "mooncake" to micro-venue / off-corridor filters
--    - Enforce institutional cluster parent-child deduplication
-- ============================================================================

BEGIN;

-- Step 1: Purge spurious shocks from external.events_consolidated
DELETE FROM external.events_consolidated
WHERE source_id IN ('external_lgu_0287', 'external_lgu_0293', 'external_acad_0272');

-- Step 2: Mark source records in external.academic_lgu_events as cancelled / audit-logged
UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'Civic cleanup activity erroneously matched unconstrained araw ng holiday filter; does not affect transit ridership.'
WHERE id = 'external_lgu_0287';

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'Retrospective street festival post (idinaos na) at Banawe Chinatown (off-corridor micro-venue, non-arena); does not affect transit ridership.'
WHERE id = 'external_lgu_0293';

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'Duplicate student council advisory of official university announcement external_acad_0271; suppressed under institutional cluster deduplication.'
WHERE id = 'external_acad_0272';

-- Step 3: Harden external.classify_event_from_text()
CREATE OR REPLACE FUNCTION external.classify_event_from_text(p_post_text text, p_image_text text, p_category text, p_event_name text DEFAULT NULL::text)
 RETURNS TABLE(event_name text, event_category text, friction_domain text, trigger_category text, affects_ridership boolean)
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    v_combined text;
BEGIN
    v_combined := LOWER(COALESCE(p_post_text, '') || ' ' || COALESCE(p_image_text, '') || ' ' || COALESCE(p_event_name, ''));

    -- Filter 1: Planning / Administrative meetings & Non-Disruptive Assemblies
    IF (v_combined ~* '(coordination\s+meeting|ocular\s+visit|ocular\s+meeting|planning\s+meeting|planning\s+session|preparatory\s+meeting|committee\s+meeting|coordination\s+visit|pre-event\s+coordination|parent\s+orientation|parents?\s+orientation|general\s+assembly)'
        OR (v_combined ~* '(meeting|ocular|planning|preparation|discussion)' 
            AND NOT v_combined ~* '(suspend|walang\s*pasok|no\s+class|strike|tigil\s+pasada|welga)')) THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Planning/Coordination Meeting');
        event_category := 'administrative';
        friction_domain := NULL;
        trigger_category := NULL;
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 2: Administrative / Internal notices
    IF v_combined ~* '(promotions?\s+board|posting\s+of.*(grade|result)|deliberation|grade\s+release|final\s+grade|drop(ping)?\s+of\s+subject|leave\s+of\s+absence|filing\s+of\s+leave)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Administrative/Internal Notice');
        event_category := 'administrative';
        friction_domain := NULL;
        trigger_category := NULL;
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 3: Transport Strike (HIGHEST DISRUPTION PRIORITY)
    IF (v_combined ~* '(transport\s+strike|tigil\s+pasada|welga|jeepney\s+strike|piston|manibela|transport\s+group)')
       AND NOT v_combined ~* '(cancel(lation|led)?\s+of\s+strike|strike\s+is\s+cancelled|call(ed)?\s+off)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Nationwide Transport Strike (MANIBELA Advisory)'); 
        event_category := 'transport_strike'; 
        friction_domain := 'academic'; 
        trigger_category := 'Transport Strike'; 
        affects_ridership := TRUE;
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 4: Online / Asynchronous Modality Shift
    IF v_combined ~* '(shift\s+to\s+(online|asynchronous)|asynchronous\s+(classes|modality|learning)|online\s+(classes|modality|learning|synchronous)|remote\s+learning)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Shift to Online / Asynchronous Modality'); 
        event_category := 'class_suspension'; 
        friction_domain := 'academic'; 
        trigger_category := 'Online / Asynchronous Class Shift'; 
        affects_ridership := TRUE;
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 5a: Statutory, National, LGU, and University Holidays (Constrained regex for araw ng)
    IF v_combined ~* '(non[- ]?working\s+(day|holiday)?|special\s+(non[- ]?working|public)\s+(day|holiday)?|regular\s+holiday|araw\s+ng\s+(kagitingan|maynila|kalayaan|quezon|pasig|marikina|san\s+juan|manggagawa|mga\s+bayani|wika)|founding\s+anniversary|\bholiday\b|holy\s+week|lenten\s+break|undas|traslacion|black\s+nazarene|day\s+of\s+valor|rizal\s+day|bonifacio\s+day|independence\s+day|labor\s+day|ninoy\s+aquino|national\s+heroes|all\s+saint|all\s+soul|christmas|new\s+year|maundy\s+thursday|good\s+friday|black\s+saturday|easter|immaculate\s+conception|edsa|eid|ramadan|quezon\s+city\s+day|manila\s+day|pasig\s+day|marikina\s+day|san\s+juan\s+day|antipolo\s+day|feast\s+of\s+st|up\s+foundation|chinese\s+new\s+year)' 
       AND NOT v_combined ~* '(walang\s*pasok\s+dahil\s+sa\s+(baha|bagyo|ulan|heat)|class(es)?\s+are\s+suspended\s+due\s+to)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'National / Academic Holiday'); 
        event_category := 'holiday'; 
        friction_domain := 'academic'; 
        trigger_category := 'Holiday'; 
        affects_ridership := TRUE; 
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 5b: School / Term Breaks
    IF v_combined ~* '(semestral\s+break|summer\s+break|midyear\s+break|christmas\s+break|term\s+break|academic\s+break)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'School Break'); 
        event_category := 'school_break'; 
        friction_domain := 'academic'; 
        trigger_category := 'School Break'; 
        affects_ridership := TRUE; 
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 5c: Rescheduled / Postponed Arena & Sports Events
    IF v_combined ~* '(uaap|ncaa|concert|sports\s+event|arena\s+event|basketball|volleyball|cheerdance|pep\s+squad|send[- ]?off|pep\s+rally|game\s+day|paskuhan|lantern\s+parade|exhibition\s+(game|match)|celebrity\s+match|kick\s*off)'
       AND v_combined ~* '(reschedul|postpon|move(d|s)\s+to|moved\s+to)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Major Arena / Sports Event (Rescheduled)'); 
        event_category := 'major_event'; 
        friction_domain := 'academic'; 
        trigger_category := 'Major Arena Event'; 
        affects_ridership := TRUE; 
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 5d: Dynamic Class / Work Suspensions
    IF v_combined ~* '((class(es)?|klase|work|trabaho|office|opisina|school|campus|transaction(s)?|operation(s)?)\s+.*(suspend|suspens|cancelled)|(suspend(ed|ing|sion)?|suspensyon|kanselado|cancel(led|lation)?)\s+.*(class|klase|work|office|school|campus|transaction|operation|onsite)|walang\s*pasok|no\s+class(es)?|in-person\s+class(es)?\s+suspension|cancel(lation|led)?\s+of\s+(medical\s+)?exam)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Class Suspension'); 
        event_category := 'class_suspension'; 
        friction_domain := 'academic'; 
        trigger_category := 'Class Suspension'; 
        affects_ridership := TRUE; 
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 6: LGU Weather / Flood / Incident Management Monitoring
    IF (v_combined ~* '(weather\s+update|heavy\s+rainfall|rainfall\s+warning|habagat|southwest\s+monsoon|monsoon|water\s+level|river\s+level|alert\s+level|incident\s+management\s+team|demobiliz|wild\s+diseases)'
        AND NOT v_combined ~* '(suspend|walang\s*pasok|no\s+class|shift\s+to\s+online|strike|tigil\s+pasada)') THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'LGU Weather Advisory'); 
        event_category := 'weather_advisory'; 
        friction_domain := 'lgu'; 
        trigger_category := 'LGU Weather & Flooding Monitoring'; 
        affects_ridership := FALSE;
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 7: LGU Maintenance / Tree Trimming / Clearing / Environmental Cleanups
    IF v_combined ~* '(tree\s+trimming|road\s+clearance|clearing\s+operation|pruning|tree\s+pruning|declogging|drainage|flushing|sewer|relief\s+goods|street\s+repair|road\s+maintenance|coastal\s+cleanup|simultaneous\s+cleanup|cleanup\s+activity|paglilinis|clean\s+seas)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'LGU Clearing & Maintenance Activity'); 
        event_category := 'infrastructure'; 
        friction_domain := 'lgu'; 
        trigger_category := 'LGU Municipal Clearing & Maintenance'; 
        affects_ridership := FALSE;
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 8: Major Arena Events
    IF v_combined ~* '(uaap|ncaa|concert|sports\s+event|arena\s+event|basketball|volleyball|cheerdance|pep\s+squad|send[- ]?off|pep\s+rally|game\s+day|paskuhan|lantern\s+parade)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Major Arena / Sports Event'); 
        event_category := 'major_event'; 
        friction_domain := 'academic'; 
        trigger_category := 'Major Arena Event'; 
        affects_ridership := TRUE; 
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 9: Graduation & Commencement Rites
    IF v_combined ~* '(commencement|graduation|baccalaureate|solemn\s+investiture|hooding|closing\s+exercises)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Graduation & Commencement Rites'); 
        event_category := 'major_event'; 
        friction_domain := 'academic'; 
        trigger_category := 'Graduation & Commencement Rites'; 
        affects_ridership := TRUE; 
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 10: Civic Rallies & Public Mobilizations
    IF (v_combined ~* '(sona\s+rally|protest|labor\s+rally|peace\s+rally|march\s+for|piket|first\s+week\s+rage|marcos\s*singilin|duterte\s*panagutin|\b(public|mass|student|youth)\s+mobilization\b)'
        OR (v_combined ~* '\bmobilization\b' AND NOT v_combined ~* '(demobiliz|incident\s+management)')) THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Civic Rally & Public Mobilization'); 
        event_category := 'major_event'; 
        friction_domain := 'academic'; 
        trigger_category := 'Civic Rally & Public Mobilization'; 
        affects_ridership := TRUE; 
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 11: Examination Period (Guarded against incidental background mentions)
    IF v_combined ~* '(exam(ination)?s?|midterm|finals?\s+(exam|week)|prelim(inary)?\s+exam|long\s+exam|qualifying\s+exam)' 
       AND NOT v_combined ~* '(cancel|suspend|walang\s*pasok|no\s+class|parent\s+orientation|parents?\s+orientation)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Examination Period'); 
        event_category := 'exam_week'; 
        friction_domain := 'academic'; 
        trigger_category := 'University Exam Week'; 
        affects_ridership := TRUE; 
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Default fallback
    event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Regular Academic Schedule');
    event_category := 'regular_class_day';
    friction_domain := 'academic';
    trigger_category := 'Regular Class Day';
    affects_ridership := FALSE;
    RETURN NEXT;
    RETURN;
END;
$function$;

-- Step 4: Harden external.sync_academic_lgu_to_events_consolidated()
CREATE OR REPLACE FUNCTION external.sync_academic_lgu_to_events_consolidated()
 RETURNS trigger
 LANGUAGE plpgsql
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

    -- Guardrail: Institutional Cluster Deduplication (Student Council vs University Admin)
    -- If a student council posts about an event code where the parent university has already filed, suppress student council post.
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

    IF v_combined_text ~* '(mall\s+of\s+asia\s+arena|moa\s+arena|smx\s+convention|philippine\s+international\s+convention\s+center|\bpicc\b|world\s+trade\s+center|san\s+andres\s+sports\s+complex|philippine\s+arena|bocaue|bonifacio\s+global\s+city|\bbgc\b|alabang|makati\s+city|foro\s+de\s+intramuros|\bintramuros\b|tourism\s+expo|heritage\s+spaces|\bbanawe\b|\bchinatown\b)'
       AND NOT v_combined_text ~* '(recto|legarda|pureza|v\.\s*mapa|j\.\s*ruiz|gilmore|betty\s*go|cubao|araneta|anonas|katipunan|santolan|marikina|antipolo)' THEN
        v_is_off_corridor_venue := TRUE;
    END IF;

    IF v_is_off_corridor_venue THEN
        DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
        RAISE NOTICE 'Off-corridor venue guardrail: blocked % (venue outside LRT-2 corridor).', NEW.id;
        RETURN NEW;
    END IF;

    IF NEW.event_code = 'MAJOR_ARENA_EVENT' THEN
        IF v_combined_text ~* '(ticket\s+selling|ticket\s+booth|ticket\s+reservation|ticket\s+availability|dance\s+studio|covered\s+court|children''?s\s+choir|foundation\s+anniversary|yellow\s+day|banawe|chinatown|mooncake\s+fest(ival)?)' THEN
            v_is_micro_venue := TRUE;
        END IF;
    END IF;

    IF v_is_micro_venue THEN
        DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
        RAISE NOTICE 'Micro-venue/ticket booth guardrail: blocked % from MAJOR_ARENA_EVENT.', NEW.id;
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

    IF NEW.event_code = 'MAJOR_ARENA_EVENT'
       AND NEW.event_date IS NOT NULL
       AND NEW.event_date ~ '^\d{4}-\d{2}-\d{2}$'
       AND NEW.post_date IS NOT NULL THEN
        v_days_in_past := (NEW.post_date::date - NEW.event_date::date);
        IF v_days_in_past >= 1 THEN
            v_is_retrospective := TRUE;
        END IF;
    END IF;

    IF NOT v_is_retrospective
       AND NEW.event_code = 'MAJOR_ARENA_EVENT' THEN
        IF v_combined_text ~* '(playing\s+it\s+back|katatapos\s+lang|after\s+the\s+(?:spectacular|opening|ceremony|game|match)|officially\s+commenced|came\s+together\s+for\s+an\s+opening|naging\s+matagumpay|held\s+(last|on)\s+(september|august|july|june|monday|tuesday|wednesday|thursday|friday|saturday|sunday)|photo\s+(highlight|album|recap|documentation)|look\s+back|event\s+recap|successfully\s+held|isang\s+matagumpay|naganap\s+noong|nagdaos\s+ng|naganap\s+kahapon|naging\s+makulay|nagtapos\s+na\s+ang|natapos\s+na|victory\s+over|defeated|won\s+against|edged\s+out|loss\s+to|final\s+score|campaign\s+off\s+to\s+a\s+strong\s+start|thank\s+you\s+to\s+our\s+partner|couldn''?t\s+have\s+done\s+it\s+without|partner\s+companies|sponsors?\s+and\s+partners?|one\s+to\s+remember|for\s+helping\s+make\s+the|on\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2},?\s+20\d{2},?\s+the|idinaos\s+na|napuno\s+ng\s+masasayang\s+aktibidad)' THEN
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
$function$;

COMMIT;
