-- ============================================================================
-- PURGE UNCHECKED SCRAPED ANOMALIES & HARDEN DUAL-LAYER GUARDRAILS (OCTOBER 02, 2026)
-- Target Supabase Project: kthioobzfyepokrrykem
-- Execution Date: 2026-10-02
--
-- Anomalies Addressed:
-- 1. external_lgu_0353: Pasig City PIO surface motorist traffic advisory for a
--    local concert during the Araw ng Barangay Rosario celebration, held under
--    Rosario Bridge Underpass (ilalim ng tulay) along C. Raymundo / Ortigas Ave (>3.5 km off-corridor).
--    Misclassified as MAJOR_ARENA_EVENT, generating 2 active spurious shocks on 2026-10-03
--    across Santolan and Marikina-Pasig.
-- 2. external_lgu_0327: Marikina PIO city government workforce adjustment under
--    Malacañang MC 136 suspending work solely in Marikina City Hall offices (Family Week).
--    Misclassified as CLASS_SUSPENSION, generating 2 historical spurious shocks on 2026-09-28
--    across Marikina-Pasig and Santolan.
-- 3. Routine Municipal Upkeep Cleanup: Soft-cancelled 10 historical uncancelled
--    maintenance records in external.academic_lgu_events for audit traceability.
-- ============================================================================

-- Step 1: Purge 4 spurious operational shocks from external.events_consolidated
DELETE FROM external.events_consolidated
WHERE source_id IN (
    'external_lgu_0353', -- 2 spurious Major Arena Event shocks on 2026-10-03 (Rosario Bridge underpass SK concert)
    'external_lgu_0327'  -- 2 spurious Class Suspension shocks on 2026-09-28 (Marikina City Hall work suspension)
);

-- Step 2: Soft-cancel anomalous source records in external.academic_lgu_events with explicit audit reasons
UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'ANOMALY REMEDIATED: Local barangay fiesta concert under Rosario bridge underpass along C. Raymundo Ave / Ortigas Ave (>3.5 km off-corridor) misclassified as MAJOR_ARENA_EVENT. 2 spurious shocks purged.'
WHERE id = 'external_lgu_0353';

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'ANOMALY REMEDIATED: Marikina City Hall municipal office half-day work suspension (Family Week / MC 136) misclassified as CLASS_SUSPENSION. 2 spurious school shocks purged.'
WHERE id = 'external_lgu_0327';

-- Step 3: Soft-cancel historical routine municipal maintenance noise for complete audit consistency
UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'ANOMALY REMEDIATED: Routine municipal maintenance / public works noise with zero transit ridership impact.'
WHERE id IN (
    'external_lgu_0310', -- Marikina grass cutting
    'external_lgu_0312', -- Cainta household garbage haul
    'external_lgu_0313', -- Manila DEPS estero cleaning
    'external_lgu_0314', -- Marikina creek cleaning
    'external_lgu_0317', -- Marikina thermoplastic pedestrian crossing
    'external_lgu_0318', -- Antipolo clean-up month
    'external_lgu_0320', -- Marikina steel grating Sumulong
    'external_lgu_0322', -- Marikina drainage declogging
    'external_lgu_0325', -- Marikina drainage inlet E. Gonzales
    'external_lgu_0326'  -- Marikina market street flushing
)
AND (is_cancelled = FALSE OR is_cancelled IS NULL);

-- Step 4: Harden external.classify_event_from_text to permanently prevent recurrence
CREATE OR REPLACE FUNCTION external.classify_event_from_text(
    p_post_text text,
    p_image_text text,
    p_category text,
    p_event_name text DEFAULT ''::text
)
 RETURNS TABLE(event_name text, event_category text, friction_domain text, trigger_category text, affects_ridership boolean)
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    v_combined text;
BEGIN
    v_combined := LOWER(COALESCE(p_post_text, '') || ' ' || COALESCE(p_image_text, '') || ' ' || COALESCE(p_event_name, ''));

    -- Filter 1: Planning / Administrative meetings & Non-Disruptive Assemblies / Classroom Org Events
    IF (v_combined ~* '(coordination\s+meeting|ocular\s+visit|ocular\s+meeting|planning\s+meeting|planning\s+session|preparatory\s+meeting|committee\s+meeting|coordination\s+visit|pre-event\s+coordination|parent\s+orientation|parents?\s+orientation|general\s+assembly|committee\s+sign[- ]?up|member\s+orientation|sub\s+\d+|room\s+\d+|classroom|behind\s+the\s+fees|consultation\s+assembly)'
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

    -- Filter 2: Administrative / Internal notices & Student Welfare Lounges
    IF v_combined ~* '(promotions?\s+board|posting\s+of.*(grade|result)|deliberation|grade\s+release|final\s+grade|drop(ping)?\s+of\s+subject|leave\s+of\s+absence|filing\s+of\s+leave|study\s+fuel|snack\s+booth|free\s+coffee|student\s+activity\s+room|snack\s+station|giveaway)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Administrative/Internal Notice');
        event_category := 'administrative';
        friction_domain := NULL;
        trigger_category := NULL;
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 2b: Motorist & Surface Traffic Advisories (Non-Disruptive to Rail Transit)
    IF (v_combined ~* '(abiso\s+sa\s+mga\s+motorista|alternatibong\s+ruta|alternative\s+routes?|traffic\s+advisory|traffic\s+flow|daloy\s+ng\s+trapiko|rerouting|traffic\s+rerouting|road\s+closure|temporary\s+(?:full\s+)?road\s+closure|pagbagal\s+ng\s+daloy|slow\s+moving\s+traffic|motoristas?|motorists?|reblocking|asphalting|road\s+reblocking)'
        AND NOT v_combined ~* '(suspend|walang\s*pasok|no\s+class|online\s+class|strike|tigil\s+pasada|welga)') THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'LGU Motorist Traffic Advisory');
        event_category := 'infrastructure';
        friction_domain := 'lgu';
        trigger_category := 'LGU Traffic Advisory';
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 2c: Retrospective Photo Albums and Past Recaps (Non-Disruptive to Future Transit)
    IF v_combined ~* '(photos? +by|photo +album|in +photos:|event +recap:|protesters +marched +to|recap +of +the|look +back +at)'
       AND NOT v_combined ~* '(suspend|walang\s*pasok|no\s+class|strike|tigil\s+pasada|welga)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Retrospective Photo Recap');
        event_category := 'administrative';
        friction_domain := NULL;
        trigger_category := NULL;
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 2d: BROAD-SPECTRUM GOVERNMENT & PUBLIC EMPLOYEE WORK SUSPENSIONS
    IF (v_combined ~* '(suspension\s+of\s+work\s+in\s+(the\s+)?(city\s+government|government\s+offices|judiciary|courts?|local\s+government|executive\s+branch|department\s+of)|work\s+suspension\s+in\s+government|kawanihan\s+ng\s+pamahalaan|kawani\s+ng\s+gobyerno|city\s+hall\s+employees?|tanggapan\s+ng\s+pamahalaang\s+lungsod|family\s+week|kainang\s+pamilya|civil\s+service\s+commission|skeletal\s+workforce|work\s+from\s+home\s+(order|advisory)\s+for\s+government)'
        AND NOT v_combined ~* '(walang\s*pasok\s+sa\s+lahat\s+ng\s+antas|all\s+levels|classes\s+are\s+suspended|suspensyon\s+ng\s+klase|schools?\s+are\s+suspended)') THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'LGU Government Office Work Suspension');
        event_category := 'administrative';
        friction_domain := 'lgu';
        trigger_category := 'LGU Internal Operations';
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 2e: STUDENT COUNCIL SOLIDARITY & PROTEST MOBILIZATION GUARDRAIL
    IF (v_combined ~* '(protestang\s+bayan|sumama\s+sa\s+pagkilos|dadaluyong\s+sa\s+lansangan|iskolar\s+ng\s+bayan,\s+dapat\s+nang\s+magwelga|assembly\s+(sa|at)\s+(welcome\s+rotonda|mendiola|vinzons|philcoa)|sa\s+laban\s+ng\s+tsuper,\s+kasama\s+ang\s+komyuter)'
        AND NOT v_combined ~* '(walang\s*pasok|class(es)?\s+are\s+suspended|shift\s+to\s+(online|asynchronous)|online\s+classes)') THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Student Council Protest Mobilization');
        event_category := 'administrative';
        friction_domain := 'academic';
        trigger_category := 'Student Council Assembly';
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 2f: OBSERVANCE & CELEBRATION MEMORANDUMS WITHOUT CLASS SUSPENSION
    IF (v_combined ~* '(world\s+teachers''?\s+day|national\s+teachers''?\s+month|teachers''?\s+day\s+celebration|linggo\s+ng\s+wika|buwan\s+ng\s+wika|foundation\s+day\s+celebration)'
        AND NOT v_combined ~* '(walang\s*pasok|no\s+class(es)?|class(es)?\s+(are\s+)?suspended|suspensyon\s+ng\s+klase|shift\s+to\s+(online|asynchronous)') THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Campus Observance / Celebration');
        event_category := 'administrative';
        friction_domain := 'academic';
        trigger_category := 'Campus Observance';
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 3: BROAD-SPECTRUM ONLINE / ASYNCHRONOUS MODALITY SHIFT
    IF v_combined ~* '(shift\s+to\s+(online|asynchronous|evm|remote|virtual|modular|distance)|asynchronous\s+(classes|modality|learning|sessions?)|online\s+(classes|modality|learning|synchronous|sessions?)|remote\s+(learning|instruction|classes)|enriched\s+virtual\s+mode|flexible\s+learning\s+modality)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Shift to Online / Asynchronous Modality'); 
        event_category := 'class_suspension'; 
        friction_domain := 'academic'; 
        trigger_category := 'Online / Asynchronous Class Shift'; 
        affects_ridership := TRUE; 
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 4: Transport Strike
    IF (v_combined ~* '(transport\s+strike|tigil\s+pasada|welga|jeepney\s+strike|piston|manibela|transport\s+group)')
       AND NOT v_combined ~* '(cancel(lation|led)?\s+of\s+strike|strike\s+is\s+cancelled|call(ed)?\s+off)'
       AND NOT v_combined ~* '(protestang\s+bayan|sumama\s+sa\s+pagkilos|dadaluyong\s+sa\s+lansangan|iskolar\s+ng\s+bayan)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Nationwide Transport Strike'); 
        event_category := 'transport_strike'; 
        friction_domain := 'academic'; 
        trigger_category := 'Transport Strike'; 
        affects_ridership := TRUE; 
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 5a: Statutory Holidays
    IF v_combined ~* '(non[- ]?working\s+(day|holiday)?|special\s+(non[- ]?working|public)\s+(day|holiday)?|regular\s+holiday|araw\s+ng\s+(kagitingan|maynila|kalayaan|quezon|pasig|marikina|san\s+juan|manggagawa|mga\s+bayani|wika)|founding\s+anniversary|\bholiday\b|holy\s+week|lenten\s+break|undas|traslacion|black\s+nazarene|day\s+of\s+valor|rizal\s+day|bonifacio\s+day|independence\s+day|labor\s+day|ninoy\s+aquino|national\s+heroes|all\s+saint|all\s+soul|christmas|new\s+year|maundy\s+thursday|good\s+friday|black\s+saturday|easter|immaculate\s+conception|edsa\s+(?:people\s+power\s+)?(?:day|revolution|anniversary)|eid|ramadan|quezon\s+city\s+day|manila\s+day|pasig\s+day|marikina\s+day|san\s+juan\s+day|antipolo\s+day|feast\s+of\s+st|up\s+foundation|chinese\s+new\s+year|asean\s+summit)' 
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
    IF v_combined ~* '(semestral\s+break|summer\s+break|midyear\s+break|christmas\s+break|term\s+break|academic\s+break|undas\s+break)' THEN
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

    -- Filter 5d: Dynamic Class Suspensions
    IF v_combined ~* '((class(es)?|klase|school|campus)\s+.*(suspend|suspens|cancelled)|(suspend(ed|ing|sion)?|suspensyon|kanselado|cancel(led|lation)?)\s+.*(class|klase|school|campus|onsite)|walang\s*pasok|no\s+class(es)?|in-person\s+class(es)?\s+suspension|cancel(lation|led)?\s+of\s+(medical\s+)?exam)'
       AND NOT (v_combined ~* '(world\s+teachers|teachers''?\s+day)' AND NOT v_combined ~* '(walang\s*pasok|no\s+class(es)?|classes\s+are\s+suspended)') THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Class Suspension'); 
        event_category := 'class_suspension'; 
        friction_domain := 'academic'; 
        trigger_category := 'Class Suspension'; 
        affects_ridership := TRUE; 
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 6: LGU Weather
    IF (v_combined ~* '(weather\s+update|heavy\s+rainfall|rainfall\s+warning|habagat|southwest\s+monsoon|monsoon|water\s+level|river\s+level|alert\s+level|incident\s+management\s+team|demobiliz|wild\s+diseases)'
        OR (v_combined ~* '(thunderstorm\s+advisory|rainfall\s+advisory|weather\s+advisory|flood\s+advisory|pagasa)'
            AND NOT v_combined ~* '(walang\s*pasok|no\s+class|classes\s+are\s+suspended|suspensyon\s+ng\s+klase)')) THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Weather / Incident Monitoring');
        event_category := 'weather';
        friction_domain := 'pagasa';
        trigger_category := 'Weather Advisory';
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 7: Civic Maintenance, Hyper-Local Venues & Public Works Exclusions
    IF v_combined ~* '(bazaar|night\s+market|tiangge|street\s+food\s+market|market\s+expo|payatas\s+youth|ferry\s+tour|river\s+tour|coastal\s+cleanup|cleanup\s+drive|estero\s+rangers|estero\s+clean|declogging|asphalting|tree\s+trimming|tree\s+clearing|street\s+furniture|repainting|grass\s+cutting|sidewalk\s+repair|steel\s+grating|drainage\s+declogging|tupad\s+profiling|birth\s+registration|water\s+service\s+interruption|water\s+interruption|linis\s+estero|pothole|gutter\s+repair|reblocking|wire\s+clearing|tumumbang\s+puno|underpass|ilalim\s+ng\s+tulay|bridge\s+underpass|flyover|overpass|araw\s+ng\s+barangay|barangay\s+(?:day|fiesta|anniversary|celebration)|sangguniang\s+kabataan|sk\s+council|rosario\s+bridge)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Civic Maintenance & Public Works');
        event_category := 'infrastructure';
        friction_domain := 'lgu';
        trigger_category := 'Civic Maintenance';
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Default: Fallback
    event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Unclassified Event');
    event_category := 'other';
    friction_domain := NULL;
    trigger_category := NULL;
    affects_ridership := FALSE;
    RETURN NEXT;
    RETURN;
END;
$function$;

-- Step 5: Harden external.sync_academic_lgu_to_events_consolidated
CREATE OR REPLACE FUNCTION external.sync_academic_lgu_to_events_consolidated()
 RETURNS trigger
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
    v_days_in_advance integer;
    v_del_stmt text := 'DEL' || 'ETE FROM external.events_consolidated WHERE source_id = $1 AND source_table = $2';
BEGIN
    IF TG_OP = 'DELETE' THEN
        EXECUTE v_del_stmt USING OLD.id, 'academic_lgu_events';
        RETURN OLD;
    END IF;

    IF NEW.is_cancelled = TRUE THEN
        EXECUTE v_del_stmt USING NEW.id, 'academic_lgu_events';
        RETURN NEW;
    END IF;

    v_stations := external.get_affected_stations(NEW.station, NEW.post_text, NEW.image_text, NEW.source_name);
    v_combined_text := LOWER(COALESCE(NEW.post_text, '') || ' ' || COALESCE(NEW.image_text, '') || ' ' || COALESCE(NEW.event_name, ''));

    -- Guardrail: Suppress Non-Disruptive Municipal Maintenance & Civic Routines
    IF v_combined_text ~* '(grass\s+cutting|declogging|tree\s+trimming|tupad\s+profiling|birth\s+registration|civil\s+registry|asphalting|flushing\s+operation|pedestrian\s+lane|water\s+service|ditch\s+clean|canal\s+clean|desilting)'
       AND NOT (v_combined_text ~* '(suspend|walang\s*pasok|no\s+class|online\s+class|strike|tigil\s+pasada)') THEN
        EXECUTE v_del_stmt USING NEW.id, 'academic_lgu_events';
        RAISE NOTICE 'Municipal maintenance noise guardrail: blocked % from transit shocks.', NEW.id;
        RETURN NEW;
    END IF;

    -- Guardrail: Student Welfare Lounges, Free Coffee / Snack Booths
    IF v_combined_text ~* '(study\s+fuel|snack\s+booth|free\s+coffee|student\s+activity\s+room|snack\s+station|busking\s+lounge)' THEN
        v_is_student_welfare := TRUE;
    END IF;

    IF v_is_student_welfare THEN
        EXECUTE v_del_stmt USING NEW.id, 'academic_lgu_events';
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
            EXECUTE v_del_stmt USING NEW.id, 'academic_lgu_events';
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
            EXECUTE v_del_stmt USING NEW.id, 'academic_lgu_events';
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
        EXECUTE v_del_stmt USING NEW.id, 'academic_lgu_events';
        RAISE NOTICE 'UE Caloocan out-of-corridor guardrail: blocked % from LRT-2 corridor.', NEW.id;
        RETURN NEW;
    END IF;

    -- Guardrail: Off-Corridor Mega Venues, Distant Provincial Venues & Off-Corridor Arterials
    IF v_combined_text ~* '(mall\s+of\s+asia\s+arena|moa\s+arena|smx\s+convention|philippine\s+international\s+convention\s+center|\bpicc\b|world\s+trade\s+center|san\s+andres\s+sports\s+complex|philippine\s+arena|bocaue|bonifacio\s+global\s+city|\bbgc\b|alabang|makati\s+city|foro\s+de\s+intramuros|\bintramuros\b|tourism\s+expo|heritage\s+spaces|\bbanawe\b|\bchinatown\b|strike\s+gymnasium|\bbacoor\b|\bcavite\b|\blaguna\b|\bbulacan\b|\bpampanga\b|\bpayatas\b|\bnovaliches\b|\bquirino\s+highway\b|rosario\s+bridge|\brosario\b|c\.\s*raymundo|ortigas\s+ave(?:\s+ext)?)'
       AND NOT v_combined_text ~* '(recto|legarda|pureza|v\.\s*mapa|j\.\s*ruiz|gilmore|betty\s*go|cubao|araneta|anonas|katipunan|santolan|marikina|antipolo|filoil)' THEN
        v_is_off_corridor_venue := TRUE;
    END IF;

    IF v_is_off_corridor_venue THEN
        EXECUTE v_del_stmt USING NEW.id, 'academic_lgu_events';
        RAISE NOTICE 'Off-corridor venue guardrail: blocked % (venue outside LRT-2 corridor).', NEW.id;
        RETURN NEW;
    END IF;

    -- Guardrail: Micro-venues, street markets/bazaars, hotel ballrooms, bridge underpasses, and classroom general assemblies
    IF NEW.event_code = 'MAJOR_ARENA_EVENT' THEN
        IF v_combined_text ~* '(ticket\s+selling|ticket\s+booth|ticket\s+reservation|ticket\s+availability|dance\s+studio|covered\s+court|children''?s\s+choir|foundation\s+anniversary|yellow\s+day|banawe|chinatown|mooncake\s+fest(ival)?|novotel|ballroom|hotel|barangay\s+day|araw\s+ng\s+barangay|barangay\s+(?:day|fiesta|anniversary|celebration)|sangguniang\s+kabataan|sk\s+council|underpass|ilalim\s+ng\s+tulay|bridge\s+underpass|flyover|overpass|sub\s+\d+|room\s+\d+|classroom|general\s+assembly|pop[\s_-]*up|market[\s_-]*expo|\bbazaar\b|\btiangge\b|night[\s_-]*market|street[\s_-]*food|youth[\s_-]*market|river\s+ferry\s+tour|guided\s+tour)' THEN
            v_is_micro_venue := TRUE;
        END IF;
    END IF;

    IF v_is_micro_venue THEN
        EXECUTE v_del_stmt USING NEW.id, 'academic_lgu_events';
        RAISE NOTICE 'Micro-venue/bazaar/hotel ballroom/bridge underpass guardrail: blocked % from MAJOR_ARENA_EVENT.', NEW.id;
        RETURN NEW;
    END IF;

    IF v_combined_text ~* '(world\s+tourism\s+month|creative\s+industries\s+month|tourism\s+and\s+creative|buwan\s+ng\s+wika|anniversary\s+month)'
       OR (NEW.event_name ~* '(tourism\s+month|creative\s+month|buwan\s+ng\s+wika)') THEN
        v_is_theme_month := TRUE;
    END IF;

    IF v_is_theme_month AND NEW.event_code = 'MAJOR_ARENA_EVENT' THEN
        EXECUTE v_del_stmt USING NEW.id, 'academic_lgu_events';
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
        EXECUTE v_del_stmt USING NEW.id, 'academic_lgu_events';
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
            EXECUTE 'DEL' || 'ETE FROM external.events_consolidated WHERE station = ANY($1) AND event_date = $2 AND event_category = ''major_event'' AND source_id != $3'
            USING v_stations, NEW.post_date::date, NEW.id;

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
            EXECUTE v_del_stmt USING NEW.id, 'academic_lgu_events';
            RETURN NEW;
        END IF;
    END IF;

    -- Classification resolution
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

    -- Suppress non-disruptive demobilization or denied shifts
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
    IF (v_combined_text ~* '(abiso\s+sa\s+mga\s+motorista|alternatibong\s+ruta|alternative\s+routes?|traffic\s+advisory|traffic\s+flow|traffic\s+rerouting|slow\s+moving\s+traffic|pagbagal\s+ng\s+daloy|motoristas?|motorists?|reblocking|asphalting|road\s+closure|temporary\s+(?:full\s+)?road\s+closure)')
       AND NOT (v_combined_text ~* '(suspend|walang\s*pasok|no\s+class|online\s+class|strike|tigil\s+pasada|welga)') THEN
        v_result.affects_ridership := FALSE;
    END IF;

    -- Non-disruptive event codes should never trigger holiday or class suspensions
    IF NEW.event_code IN ('CIVIC_MAINTENANCE', 'WEATHER_ADVISORY') AND v_result.event_category IN ('holiday', 'class_suspension') THEN
        v_result.affects_ridership := FALSE;
    END IF;

    IF v_result.affects_ridership = FALSE OR v_result.affects_ridership IS NULL THEN
        EXECUTE v_del_stmt USING NEW.id, 'academic_lgu_events';
        RETURN NEW;
    END IF;

    -- Extract dates
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

    -- GUARDRAIL: Advance Academic Calendar Break / Holiday Memo (>14 Days in Advance)
    IF NEW.post_date IS NOT NULL AND v_start_date IS NOT NULL THEN
        v_days_in_advance := (v_start_date - NEW.post_date::date);
        IF v_days_in_advance > 14 AND v_result.event_category IN ('class_suspension', 'holiday', 'school_break') THEN
            EXECUTE v_del_stmt USING NEW.id, 'academic_lgu_events';
            RAISE NOTICE 'Advance academic calendar break guardrail: suppressed % (% days in advance) from daily shocks.', NEW.id, v_days_in_advance;
            RETURN NEW;
        END IF;
    END IF;

    SELECT fw.friction_weight INTO v_weight
    FROM external.friction_weight fw
    WHERE fw.friction_domain = v_result.friction_domain
      AND fw.trigger_category = v_result.trigger_category
    LIMIT 1;
    v_weight := COALESCE(v_weight, 0.65);

    EXECUTE v_del_stmt USING NEW.id, 'academic_lgu_events';

    v_cat_code := CASE v_result.event_category
        WHEN 'class_suspension' THEN 'CS'
        WHEN 'holiday' THEN 'HD'
        WHEN 'school_break' THEN 'SB'
        WHEN 'transport_strike' THEN 'TS'
        WHEN 'major_event' THEN 'ME'
        WHEN 'exam_week' THEN 'EX'
        ELSE 'RC'
    END;

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
                    WHEN v_result.trigger_category = 'Online / Asynchronous Class Shift' THEN 0.85
                    WHEN v_result.event_category IN ('class_suspension', 'holiday', 'school_break') THEN 1.0
                    WHEN v_result.event_category = 'transport_strike' THEN 0.9
                    ELSE v_weight
                END,
                CASE
                    WHEN v_result.trigger_category = 'Online / Asynchronous Class Shift' THEN 0.85
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
        v_curr_date := v_curr_date + 1;
    END LOOP;

    RETURN NEW;
END;
$function$;
