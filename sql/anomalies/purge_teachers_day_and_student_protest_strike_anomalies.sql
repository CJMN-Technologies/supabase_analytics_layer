-- ============================================================================
-- PURGE UNCHECKED SCRAPED ANOMALIES & HARDEN TRIGGER GUARDRAILS (OCTOBER 01, 2026)
-- Target Supabase Project: kthioobzfyepokrrykem
-- Execution Date: 2026-10-01
--
-- Anomalies Addressed:
-- 1. external_acad_0294: San Beda World Teachers' Day Celebration advisory
--    (General Memorandum No. 17) had zero mention of class suspension. The LLM
--    classifier hallucinated "Class Suspension" into the title and generated
--    4 spurious shocks on 2026-10-05 across Legarda, Pureza, Recto, and V. Mapa.
-- 2. external_acad_0295: UP Diliman USC student council protest rally invitation
--    (Welcome Rotonda / Mendiola) was misclassified as line-wide TRANSPORT_STRIKE
--    (friction 0.90), generating 13 spurious shocks across all 13 stations on 2026-09-30.
-- 3. external_acad_0293: UP Diliman USC strike solidarity / campus mobilization
--    recap (Vinzons Hall / Philcoa) was misclassified as TRANSPORT_STRIKE (friction 0.90),
--    generating 5 redundant shocks on 2026-09-29 across Quezon City stations.
-- 4. external_lgu_0351: Marikina PIO routine street furniture and curb repainting
--    at Marikina Freedom Park ingested due to substring match on "bahagi" containing "baha".
-- 5. external_lgu_0352: Manila PIO routine clearing of a fallen tree on Kalye Agua
--    Marina ingested due to "disaster" matching in MCDRRMD department title.
-- ============================================================================

BEGIN;

-- Step 1: Purge 22 spurious operational shocks from external.events_consolidated
DELETE FROM external.events_consolidated
WHERE source_id IN (
    'external_acad_0294', -- 4 spurious shocks on 2026-10-05 (hallucinated World Teachers' Day class suspension)
    'external_acad_0295', -- 13 spurious line-wide shocks on 2026-09-30 (student council protest mobilization)
    'external_acad_0293'  -- 5 spurious shocks on 2026-09-29 (student council protest mobilization)
);

-- Step 2: Soft-cancel anomalous source records in external.academic_lgu_events with explicit audit reasons
UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'ANOMALY REMEDIATED: SBU General Memorandum No. 17 celebrates World Teachers Day with NO class suspension declared; hallucinated CLASS_SUSPENSION purged.'
WHERE id = 'external_acad_0294';

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'ANOMALY REMEDIATED: UP Diliman USC rally mobilization call (Welcome Rotonda / Mendiola) misclassified as line-wide TRANSPORT_STRIKE (13 spurious shocks purged).'
WHERE id = 'external_acad_0295';

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'ANOMALY REMEDIATED: UP Diliman USC strike solidarity / campus rally mobilization misclassified as active transit TRANSPORT_STRIKE (5 spurious shocks purged).'
WHERE id = 'external_acad_0293';

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'ANOMALY REMEDIATED: Routine municipal maintenance noise (Freedom Park street furniture repainting); falsely ingested due to substring match on bahagi.'
WHERE id = 'external_lgu_0351';

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'ANOMALY REMEDIATED: Routine municipal clearing noise (fallen tree removal on interior street Kalye Agua Marina) with zero transit ridership impact.'
WHERE id = 'external_lgu_0352';

-- Step 3: Harden external.classify_event_from_text to permanently prevent recurrence
CREATE OR REPLACE FUNCTION external.classify_event_from_text(
    p_post_text text,
    p_image_text text,
    p_source_type text,
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
    IF (v_combined ~* '(abiso\s+sa\s+mga\s+motorista|alternatibong\s+ruta|traffic\s+advisory|daloy\s+ng\s+trapiko|rerouting|road\s+closure|pagbagal\s+ng\s+daloy|motorista|reblocking|asphalting|road\s+reblocking)'
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
    IF (v_combined ~* '(suspension\s+of\s+work\s+in\s+(the\s+)?(city\s+government|government\s+offices|judiciary|courts?|local\s+government|executive\s+branch|department\s+of)|work\s+suspension\s+in\s+government|kawanihan\s+ng\s+pamahalaan|kawani\s+ng\s+gobyerno|city\s+hall\s+employees?|family\s+week|kainang\s+pamilya|civil\s+service\s+commission|skeletal\s+workforce|work\s+from\s+home\s+(order|advisory)\s+for\s+government)'
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
    -- Student council rally mobilizations, assembly callouts, or political manifestos
    -- must NOT trigger line-wide transport strike operational shocks.
    IF (v_combined ~* '(protestang\s+bayan|sumama\s+sa\s+pagkilos|dadaluyong\s+sa\s+lansangan|iskolar\s+ng\s+bayan,\s+dapat\s+nang\s+magwelga|assembly\s+(sa|at)\s+(welcome\s+rotonda|mendiola|vinzons|philcoa)|sa\s+laban\s+ng\s+tsuper,\s+kasama\s+ang\s+komyuter)'
        AND NOT v_combined ~* '(walang\s*pasok|class(es)?\s+are\s+suspended|shift\s+to\s+(online|asynchronous)|online\s+classes)')) THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Student Council Protest Mobilization');
        event_category := 'administrative';
        friction_domain := 'academic';
        trigger_category := 'Student Council Assembly';
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 2f: OBSERVANCE & CELEBRATION MEMORANDUMS WITHOUT CLASS SUSPENSION
    -- School memorandums celebrating World Teachers Day, Foundation Day, or cultural observances
    -- that lack explicit "walang pasok" / "classes suspended" text must NOT generate CLASS_SUSPENSION.
    IF (v_combined ~* '(world\s+teachers''?\s+day|national\s+teachers''?\s+month|teachers''?\s+day\s+celebration|linggo\s+ng\s+wika|buwan\s+ng\s+wika|foundation\s+day\s+celebration)'
        AND NOT v_combined ~* '(walang\s*pasok|no\s+class(es)?|class(es)?\s+(are\s+)?suspended|suspensyon\s+ng\s+klase|shift\s+to\s+(online|asynchronous))') THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Campus Observance / Celebration');
        event_category := 'administrative';
        friction_domain := 'academic';
        trigger_category := 'Campus Observance';
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 3: BROAD-SPECTRUM ONLINE / ASYNCHRONOUS MODALITY SHIFT (PRECEDENCE OVER ALL EXTERNAL CAUSES)
    IF v_combined ~* '(shift\s+to\s+(online|asynchronous|evm|remote|virtual|modular|distance)|asynchronous\s+(classes|modality|learning|sessions?)|online\s+(classes|modality|learning|synchronous|sessions?)|remote\s+(learning|instruction|classes)|enriched\s+virtual\s+mode|flexible\s+learning\s+modality)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Shift to Online / Asynchronous Modality'); 
        event_category := 'class_suspension'; 
        friction_domain := 'academic'; 
        trigger_category := 'Online / Asynchronous Class Shift'; 
        affects_ridership := TRUE; 
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 4: Transport Strike (Official transit disruptions only)
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

    -- Filter 5a: Statutory, National, LGU, and University Holidays
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

    -- Filter 5d: Dynamic Class Suspensions (Strictly excluding government employee internal work & celebrations)
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

    -- Filter 6: LGU Weather / Flood / Incident Management Monitoring
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

    -- Filter 7: Civic Maintenance & Public Works Exclusions
    IF v_combined ~* '(bazaar|night\s+market|tiangge|street\s+food\s+market|market\s+expo|payatas\s+youth|ferry\s+tour|river\s+tour|coastal\s+cleanup|cleanup\s+drive|estero\s+rangers|estero\s+clean|declogging|asphalting|tree\s+trimming|tree\s+clearing|street\s+furniture|repainting|grass\s+cutting|sidewalk\s+repair|steel\s+grating|drainage\s+declogging|tupad\s+profiling|birth\s+registration|water\s+service\s+interruption|water\s+interruption|linis\s+estero|pothole|gutter\s+repair|reblocking|wire\s+clearing|tumumbang\s+puno)' THEN
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

-- Step 4: Harden external.get_affected_stations to prevent student council manifestos from triggering corridor-wide routing
CREATE OR REPLACE FUNCTION external.get_affected_stations(
    p_text text,
    p_image_text text,
    p_source_station text
)
 RETURNS text[]
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    v_combined text;
    v_stations text[] := ARRAY[]::text[];
    v_station_normalized text;
    v_city text := NULL;
    v_all_stations text[] := ARRAY[
        'Recto', 'Legarda', 'Pureza', 'V. Mapa', 'J. Ruiz', 'Gilmore',
        'Betty Go-Belmonte', 'Araneta Center Cubao', 'Anonas', 'Katipunan',
        'Santolan', 'Marikina-Pasig', 'Antipolo'
    ];
BEGIN
    v_combined := LOWER(COALESCE(p_text, '') || ' ' || COALESCE(p_image_text, ''));
    v_station_normalized := external.normalize_station_name(p_source_station);

    -- 0. STADIUM & ARENA PHYSICAL VENUE OVERRIDE (ANTI-OVERFITTING DIRECTIVE)
    IF v_combined ~* '\y(filoil|eco-?oil|san\s+juan\s+arena|flying\s+v\s+centre)\y' THEN
        RETURN ARRAY['J. Ruiz'];
    END IF;

    IF v_combined ~* '\y(araneta|big\s+dome|smart\s+araneta)\y' THEN
        RETURN ARRAY['Araneta Center Cubao'];
    END IF;

    IF v_combined ~* '\y(marikina\s+sports\s+center|msc)\y' THEN
        RETURN ARRAY['Marikina-Pasig'];
    END IF;

    IF v_combined ~* '\y(blue\s+eagle\s+gym|loyola\s+gym|up\s+gym)\y' THEN
        RETURN ARRAY['Katipunan'];
    END IF;

    IF v_combined ~* '\y(quadricentennial\s+pavilion|ust\s+gym)\y' THEN
        RETURN ARRAY['Legarda'];
    END IF;

    IF v_combined ~* '\y(pup\s+gym)\y' THEN
        RETURN ARRAY['Pureza'];
    END IF;

    IF v_combined ~* '\y(philsports|ultra)\y' THEN
        RETURN ARRAY['Santolan', 'Marikina-Pasig'];
    END IF;

    IF v_combined ~* '\y(rizal\s+memorial|ninoy\s+aquino\s+stadium)\y' THEN
        RETURN ARRAY['Recto'];
    END IF;

    -- 1. Check for corridor-wide / NCR-wide / Presidential / Malacañang declarations
    -- Explicitly suppress student council manifestos / political rhetoric from triggering corridor-wide routing
    IF ((v_combined ~* '\y(metro\s+manila|ncr\s+wide|all\s+public\s+and\s+private|across\s+metro\s+manila|nationwide|malacañang|malacanang|asean\s+summit)\y'
        AND NOT v_combined ~* '\y(quezon\s+city\s+only|manila\s+only|san\s+juan\s+only)\y')
        OR v_station_normalized = 'All Stations')
        AND NOT (v_combined ~* '(protestang\s+bayan|sumama\s+sa\s+pagkilos|dadaluyong|living\s+wage|iskolar\s+ng\s+bayan)') THEN
        RETURN v_all_stations;
    END IF;

    -- 2. Check for specific local city holiday keywords
    IF v_combined ~* '\y(manila\s+day|araw\s+ng\s+maynila|founding\s+anniversary\s+of\s+manila)\y' THEN
        v_city := 'Manila';
    ELSIF v_combined ~* '\y(quezon\s+city\s+day|araw\s+ng\s+quezon|qc\s+day)\y' THEN
        v_city := 'Quezon City';
    ELSIF v_combined ~* '\y(san\s+juan\s+day|araw\s+ng\s+san\s+juan|wattah\s+wattah)\y' THEN
        v_city := 'San Juan';
    ELSIF v_combined ~* '\y(marikina\s+day|araw\s+ng\s+marikina)\y' THEN
        v_city := 'Pasig and Marikina';
    ELSIF v_combined ~* '\y(pasig\s+day|araw\s+ng\s+pasig)\y' THEN
        v_city := 'Pasig and Marikina';
    ELSIF v_combined ~* '\y(antipolo\s+day|araw\s+ng\s+antipolo)\y' THEN
        v_city := 'Antipolo';
    END IF;

    -- 3. Map source station to city group if present
    IF v_city IS NULL AND v_station_normalized IS NOT NULL AND v_station_normalized != '' THEN
        IF v_station_normalized IN ('Recto', 'Legarda', 'Pureza', 'V. Mapa') THEN
            v_city := 'Manila';
        ELSIF v_station_normalized IN ('J. Ruiz') THEN
            v_city := 'San Juan';
        ELSIF v_station_normalized IN ('Gilmore', 'Betty Go-Belmonte', 'Araneta Center Cubao', 'Anonas', 'Katipunan') THEN
            v_city := 'Quezon City';
        ELSIF v_station_normalized IN ('Santolan', 'Marikina-Pasig') THEN
            v_city := 'Pasig and Marikina';
        ELSIF v_station_normalized IN ('Antipolo') THEN
            v_city := 'Antipolo';
        END IF;
    END IF;

    -- 4. Check for place/city keywords in the combined text
    IF v_city = 'Manila' OR v_combined ~* '\y(manila|recto|legarda|pureza|v\.?\s*mapa)\y' THEN
        v_stations := v_stations || ARRAY['Recto', 'Legarda', 'Pureza', 'V. Mapa'];
    END IF;

    IF v_city = 'San Juan' OR v_combined ~* '\y(san\s+juan|j\.?\s*ruiz)\y' THEN
        v_stations := v_stations || ARRAY['J. Ruiz'];
    END IF;

    IF v_city = 'Quezon City' OR v_combined ~* '\y(quezon\s+city|qc|gilmore|betty\s+go|araneta|cubao|anonas|katipunan)\y' THEN
        v_stations := v_stations || ARRAY['Gilmore', 'Betty Go-Belmonte', 'Araneta Center Cubao', 'Anonas', 'Katipunan'];
    END IF;

    IF v_city = 'Pasig and Marikina' OR v_combined ~* '\y(pasig|marikina|santolan)\y' THEN
        v_stations := v_stations || ARRAY['Santolan', 'Marikina-Pasig'];
    END IF;

    IF v_city = 'Antipolo' OR v_combined ~* '\y(antipolo|rizal)\y' THEN
        v_stations := v_stations || ARRAY['Antipolo'];
    END IF;

    -- 5. Deduplicate the stations array
    IF array_length(v_stations, 1) > 0 THEN
        SELECT ARRAY(SELECT DISTINCT unnest(v_stations)) INTO v_stations;
    ELSE
        IF v_station_normalized IS NOT NULL AND v_station_normalized != '' AND v_station_normalized != 'All Stations' THEN
            v_stations := ARRAY[v_station_normalized];
        ELSE
            v_stations := v_all_stations;
        END IF;
    END IF;

    RETURN v_stations;
END;
$function$;

COMMIT;
