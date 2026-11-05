-- ============================================================================
-- PURGE SCRAPED ANOMALIES & HARDEN DUAL-LAYER GUARDRAILS
-- Target Supabase Project: kthioobzfyepokrrykem
--
-- Anomalies Addressed:
-- 1. external_acad_0304: NCAA basketball match (San Beda vs EAC) physically hosted
--    at Filoil EcoOil Centre (San Juan / J. Ruiz) was erroneously routed to San Beda's
--    home campus Manila cluster (Legarda, Pureza, Recto, V. Mapa), generating 4 spurious
--    shocks. Re-routed to J. Ruiz station (1 legitimate shock).
-- 2. external_acad_0308: PUP early cut-off of administrative office operations for
--    Foundation Day convocation/fellowship (classes maintained) misclassified as a
--    full university Holiday (friction 0.85), generating 4 spurious shocks.
-- 3. external_acad_0311: UP Diliman GANAP 10th anniversary choral concert at IBG-KAL
--    Theater (a 300-seat campus recital hall) published 25 days in advance (>14-day
--    horizon guardrail violation) misclassified as Major Arena Event and inflated across
--    5 stations (Anonas, Araneta Center Cubao, Betty Go-Belmonte, Gilmore, Katipunan).
-- 4. external_acad_0315: PUP Executive Order 28 suspending Saturday administrative
--    office services ingested as an additional Holiday shock on top of the already
--    captured Undas academic modality shift (external_acad_0313), generating 4 duplicate
--    spurious shocks.
-- 5. external_acad_0307: UST Saturday campus evacuation and shift to Enhanced Virtual
--    Mode (EVM) following bomb threat letter discovery missed by classifier regex
--    (regex gap on enhanced virtual mode and shifts to virtual classes). Legitimate
--    modality shift shocks inserted across Manila cluster.
-- 6. external_lgu_0377: Cainta Free Theoretical Driving Course (TDC) caravan (routine
--    municipal driver licensing seminar at multipurpose hall) ingested as LGU notice.
-- 7. Verified clean records annotated across academic and LGU pipelines.
-- ============================================================================
-- Step 1: Purge 17 spurious operational shocks from external.events_consolidated
DELETE FROM external.events_consolidated
WHERE source_id IN (
    'external_acad_0304', -- 4 spurious shocks (Filoil arena match mapped to Manila cluster)
    'external_acad_0308', -- 4 spurious shocks (routine administrative office cut-off misclassified as Holiday)
    'external_acad_0311', -- 5 spurious shocks (>14-day advance notice & 300-seat recital hall mapped to 5 stations)
    'external_acad_0315'  -- 4 duplicate shocks (PUP Saturday office service cut-off duplicating external_acad_0313)
);

-- Step 2: Re-insert corrected shock for external_acad_0304 at J. Ruiz station
INSERT INTO external.events_consolidated (
    id, station, event_date, source_table, source_id, source_name,
    event_name, event_category, friction_domain, trigger_category,
    source_url, description, normalized_score, friction_weight_ref,
    announcement_time, updated_at, source_type
)
VALUES (
    'SCR-ME-1019-external_acad_0304-j_ruiz',
    'J. Ruiz',
    '2026-10-19'::date,
    'academic_lgu_events',
    'external_acad_0304',
    'San Beda Student Council',
    'NCAA Basketball: San Beda vs EAC Generals',
    'major_event',
    'academic',
    'Major Arena Event',
    'https://www.facebook.com/sanbedasc/posts/pfbid0bWFtM1Pgri3KuzVLJmBQGhaLQMsom5Sq3UDwT5dTRq3xQRKYBg3rG34ifn4QPw21l',
    'NCAA Season 102 Men Basketball crossover game held at Filoil EcoOil Centre in San Juan City.',
    0.5,
    0.65,
    '2026-10-19 05:54:36.487955+00'::timestamptz,
    now(),
    'academic'
)
ON CONFLICT (id) DO UPDATE SET
    station = EXCLUDED.station,
    event_name = EXCLUDED.event_name,
    event_category = EXCLUDED.event_category,
    trigger_category = EXCLUDED.trigger_category,
    friction_weight_ref = EXCLUDED.friction_weight_ref,
    normalized_score = EXCLUDED.normalized_score,
    description = EXCLUDED.description,
    updated_at = now();

-- Step 3: Insert legitimate operational shocks for external_acad_0307 (UST EVM shift due to bomb threat)
INSERT INTO external.events_consolidated (
    id, station, event_date, source_table, source_id, source_name,
    event_name, event_category, friction_domain, trigger_category,
    source_url, description, normalized_score, friction_weight_ref,
    announcement_time, updated_at, source_type
)
VALUES
(
    'SCR-CS-1024-external_acad_0307-legarda',
    'Legarda',
    '2026-10-24'::date,
    'academic_lgu_events',
    'external_acad_0307',
    'The Varsitarian',
    'UST Virtual Classes Shift: Bomb Threat',
    'class_suspension',
    'academic',
    'Online / Asynchronous Class Shift',
    'https://www.facebook.com/varsitarian/posts/pfbid02VXxGcY4nbxWa5komnFh854EQb6qa3wjNUHzg1MhaJVd1MQu3pAb2BPB4td9ATbJbl',
    'UST shifted to Enhanced Virtual Mode (EVM) and remote work arrangements following campus bomb threat evacuation.',
    0.8,
    0.85,
    '2026-10-23 12:10:05.279307+00'::timestamptz,
    now(),
    'academic'
),
(
    'SCR-CS-1024-external_acad_0307-pureza',
    'Pureza',
    '2026-10-24'::date,
    'academic_lgu_events',
    'external_acad_0307',
    'The Varsitarian',
    'UST Virtual Classes Shift: Bomb Threat',
    'class_suspension',
    'academic',
    'Online / Asynchronous Class Shift',
    'https://www.facebook.com/varsitarian/posts/pfbid02VXxGcY4nbxWa5komnFh854EQb6qa3wjNUHzg1MhaJVd1MQu3pAb2BPB4td9ATbJbl',
    'UST shifted to Enhanced Virtual Mode (EVM) and remote work arrangements following campus bomb threat evacuation.',
    0.8,
    0.85,
    '2026-10-23 12:10:05.279307+00'::timestamptz,
    now(),
    'academic'
),
(
    'SCR-CS-1024-external_acad_0307-recto',
    'Recto',
    '2026-10-24'::date,
    'academic_lgu_events',
    'external_acad_0307',
    'The Varsitarian',
    'UST Virtual Classes Shift: Bomb Threat',
    'class_suspension',
    'academic',
    'Online / Asynchronous Class Shift',
    'https://www.facebook.com/varsitarian/posts/pfbid02VXxGcY4nbxWa5komnFh854EQb6qa3wjNUHzg1MhaJVd1MQu3pAb2BPB4td9ATbJbl',
    'UST shifted to Enhanced Virtual Mode (EVM) and remote work arrangements following campus bomb threat evacuation.',
    0.8,
    0.85,
    '2026-10-23 12:10:05.279307+00'::timestamptz,
    now(),
    'academic'
),
(
    'SCR-CS-1024-external_acad_0307-v_mapa',
    'V. Mapa',
    '2026-10-24'::date,
    'academic_lgu_events',
    'external_acad_0307',
    'The Varsitarian',
    'UST Virtual Classes Shift: Bomb Threat',
    'class_suspension',
    'academic',
    'Online / Asynchronous Class Shift',
    'https://www.facebook.com/varsitarian/posts/pfbid02VXxGcY4nbxWa5komnFh854EQb6qa3wjNUHzg1MhaJVd1MQu3pAb2BPB4td9ATbJbl',
    'UST shifted to Enhanced Virtual Mode (EVM) and remote work arrangements following campus bomb threat evacuation.',
    0.8,
    0.85,
    '2026-10-23 12:10:05.279307+00'::timestamptz,
    now(),
    'academic'
)
ON CONFLICT (id) DO UPDATE SET
    station = EXCLUDED.station,
    event_name = EXCLUDED.event_name,
    event_category = EXCLUDED.event_category,
    trigger_category = EXCLUDED.trigger_category,
    friction_weight_ref = EXCLUDED.friction_weight_ref,
    normalized_score = EXCLUDED.normalized_score,
    description = EXCLUDED.description,
    updated_at = now();

-- Step 4: Soft-cancel and annotate anomalous source records in external.academic_lgu_events
UPDATE external.academic_lgu_events
SET is_cancelled = FALSE,
    cancellation_reason = 'STATION RE-ROUTED: NCAA Season 102 Men Basketball game held at Filoil EcoOil Centre San Juan re-routed to J. Ruiz from Manila cluster (4 spurious shocks purged, 1 arena shock re-inserted).'
WHERE id = 'external_acad_0304';

UPDATE external.academic_lgu_events
SET is_cancelled = FALSE,
    cancellation_reason = 'AUDIT VERIFIED: UST Saturday campus evacuation & shift to Enhanced Virtual Mode (EVM) following bomb threat letters. Legitimate operational shift calibrated to Manila cluster.'
WHERE id = 'external_acad_0307';

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'ANOMALY REMEDIATED: Routine administrative office operations early cut-off for Foundation Day convocation/fellowship with classes continuing on-site; misclassified as Holiday (0.85). 4 spurious shocks purged.'
WHERE id = 'external_acad_0308';

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'ANOMALY REMEDIATED: Intra-campus choral concert at 300-seat IBG-KAL Theater published 25 days in advance (>14-day advance horizon guardrail violation); misclassified as Major Arena Event across 5 stations. 5 spurious shocks purged.'
WHERE id = 'external_acad_0311';

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'ANOMALY REMEDIATED: Routine administrative Saturday office service suspension notice duplicating already captured Undas modality shift (external_acad_0313); misclassified as separate Holiday (0.85). 4 spurious shocks purged.'
WHERE id = 'external_acad_0315';

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'ANOMALY REMEDIATED: Routine municipal driver licensing seminar / Theoretical Driving Course (TDC) caravan at barangay hall with zero rail transit impact. Excluded at ingestion edge.'
WHERE id = 'external_lgu_0377';

-- Step 5: Annotate verified clean records for audit traceability
UPDATE external.academic_lgu_events
SET cancellation_reason = 'AUDIT VERIFIED: Legitimate operational modality shift or onsite class suspension.'
WHERE id IN ('external_acad_0303', 'external_acad_0306', 'external_acad_0309', 'external_acad_0313', 'external_acad_0314');

UPDATE external.academic_lgu_events
SET cancellation_reason = 'AUDIT VERIFIED: Legitimate major arena event at Smart Araneta Coliseum correctly routed to Araneta Center Cubao.'
WHERE id IN ('external_acad_0318', 'external_acad_0321');

UPDATE external.academic_lgu_events
SET cancellation_reason = 'AUDIT VERIFIED: Non-disruptive informational post, routine academic calendar notice, student engagement, or drill (0 shocks in consolidated).'
WHERE id IN ('external_acad_0305', 'external_acad_0310', 'external_acad_0312', 'external_acad_0316', 'external_acad_0317', 'external_acad_0319', 'external_acad_0320');

UPDATE external.academic_lgu_events
SET cancellation_reason = 'AUDIT VERIFIED: Non-disruptive LGU traffic advisory, statutory holiday coding notice, routine weather tracking, or local road scheme (0 shocks in consolidated).'
WHERE id IN (
    'external_lgu_0360', 'external_lgu_0361', 'external_lgu_0362', 'external_lgu_0363',
    'external_lgu_0364', 'external_lgu_0365', 'external_lgu_0366', 'external_lgu_0367',
    'external_lgu_0368', 'external_lgu_0369', 'external_lgu_0370', 'external_lgu_0371',
    'external_lgu_0372', 'external_lgu_0373', 'external_lgu_0374', 'external_lgu_0375',
    'external_lgu_0376'
);

-- Step 6: Deploy hardened external.classify_event_from_text()
CREATE OR REPLACE FUNCTION external.classify_event_from_text(p_post_text text, p_image_text text, p_category text, p_event_name text DEFAULT ''::text)
 RETURNS TABLE(event_name text, event_category text, friction_domain text, trigger_category text, affects_ridership boolean)
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    v_combined text;
BEGIN
    v_combined := LOWER(COALESCE(p_post_text, '') || ' ' || COALESCE(p_image_text, '') || ' ' || COALESCE(p_event_name, ''));

    -- Filter 0: PROVINCIAL & SATELLITE CAMPUS BRANCH DISCRIMINATION
    IF (v_combined ~* '\y(gensan|general\s+santos|santa\s+rosa|sta\.?\s*rosa|alabang\s+campus|cavite\s+campus|davao\s+campus|cebu\s+campus|pampanga\s+campus|clark\s+campus)\y'
        AND NOT v_combined ~* '\y(manila|recto|legarda|pureza|v\.\s*mapa|katipunan|aurora|lrt|quezon\s+city|marikina|pasig|san\s+juan)\y') THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Provincial Branch Campus Notice');
        event_category := 'administrative';
        friction_domain := NULL;
        trigger_category := NULL;
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 1: Planning / Administrative meetings & Non-Disruptive Assemblies
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

    -- Filter 1b: Routine Academic Calendar Reminders & Modality Clarifications
    IF (v_combined ~* '(post\s*[-–—]\s*(?:midterm|final|exam|prelim)|asynchronous\s+sessions?\s+after\s+(?:midterm|exam|finals?)|clarification\s+on\s+.*(?:class\s+modality|asynchronous|schedule)|(?:official|existing|routine|scheduled)\s+asynchronous\s+class\s+schedule|asynchronous\s+class\s+schedule\s+(?:will|shall)\s+be\s+(?:followed|maintained|observed)|shall\s+proceed\s+as\s+scheduled|proceed\s+as\s+scheduled|as\s+per\s+academic\s+calendar|routine\s+asynchronous|scheduled\s+asynchronous|consultation\s+sessions?|insufficient\s+responses\s+to\s+support\s+the\s+proposed\s+petition|petition\s+for\s+changes\s+to\s+the\s+schedule)'
        AND NOT v_combined ~* '(suspend|walang\s*pasok|bagyo|typhoon|baha|flood|strike|welga|tigil\s+pasada|heat\s+index|emergency|earthquake|lindol)') THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Scheduled Academic Calendar Activity');
        event_category := 'administrative';
        friction_domain := 'academic';
        trigger_category := 'University Academic Calendar';
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 1c: University Administrative Office Cut-offs & Saturday Services (Broad-Spectrum Anti-Overfitting)
    IF (v_combined ~* '(early\s+cut[- ]?off\s+of\s+office\s+operations|suspension\s+of\s+(?:saturday\s+)?services?|office\s+operations\s+will\s+end\s+early|regular\s+office\s+transactions\s+will|early\s+closure\s+of\s+offices|suspension\s+of\s+office\s+operations)'
        AND NOT v_combined ~* '(walang\s*pasok|no\s+class(es)?|class(es)?\s+(are\s+)?suspended|suspensyon\s+ng\s+klase|shifts?\s+to\s+(online|asynchronous|virtual|evm))') THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'University Office Operations Adjustment');
        event_category := 'administrative';
        friction_domain := 'academic';
        trigger_category := 'University Office Operations';
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 1d: Routine Driver Licensing & Training Seminars (Theoretical Driving Course)
    IF (v_combined ~* '(theoretical\s+driving\s+course|tdc\s+caravan|tdc\s+certificate|student\s+permit\s+caravan|lto\s+caravan|driver''?s\s+license\s+caravan)'
        AND NOT v_combined ~* '(road\s+closure|traffic\s+rerouting|full\s+closure)') THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'LGU Driver Licensing Seminar');
        event_category := 'administrative';
        friction_domain := 'lgu';
        trigger_category := 'LGU Civic Services';
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

    -- Filter 2c: Retrospective Photo Albums and Past Recaps
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

    -- Filter 2d: Government & Public Employee Work Suspensions
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

    -- Filter 2e: Student Council Protest Mobilizations
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

    -- Filter 2f: Observances & Celebrations Without Suspension
    IF (v_combined ~* '(world\s+teachers''?\s+day|national\s+teachers''?\s+month|teachers''?\s+day|linggo\s+ng\s+wika|buwan\s+ng\s+wika|foundation\s+day)'
        AND NOT v_combined ~* '(walang\s*pasok|no\s+class(es)?|class(es)?\s+(are\s+)?suspended|suspensyon\s+ng\s+klase|shifts?\s+to\s+(online|asynchronous|virtual|evm))') THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Campus Observance / Celebration');
        event_category := 'administrative';
        friction_domain := 'academic';
        trigger_category := 'Campus Observance';
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 3: Broad-Spectrum Online / Asynchronous Modality Shift
    IF v_combined ~* '(shifts?\s+to\s+(online|asynchronous|evm|remote|virtual|modular|distance)|asynchronous\s+(classes|modality|learning)|online\s+(classes|modality|learning|synchronous)|remote\s+(learning|instruction|classes)|virtual\s+(classes|modality|learning|instruction|mode)|(enhanced|enriched)\s+virtual\s+mode|flexible\s+learning\s+modality)' THEN
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

    -- Filter 5c: Campus Academic Theaters & Recital Halls (Non-Disruptive Campus Venues)
    IF (v_combined ~* '(ibg[- ]kal|recital\s+hall|albertus\s+magnus|guerrero\s+theater)'
        OR (v_combined ~* '(theater|theatre|auditorium)' AND NOT v_combined ~* '(araneta|filoil|ecooil|philsports|rizal\s+memorial|moa\s+arena|marikina\s+sports)'))
       AND NOT v_combined ~* '(walang\s*pasok|no\s+class|class(es)?\s+suspended|shifts?\s+to\s+(online|asynchronous|virtual|evm))' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Campus Cultural / Theater Performance');
        event_category := 'administrative';
        friction_domain := 'academic';
        trigger_category := 'Campus Performance';
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 5d: Major Arena & Sports Events
    IF v_combined ~* '(uaap|ncaa|concert|sports\s+event|arena\s+event|basketball|volleyball|v-?league|cheerdance|pep\s+squad|game\s+day|paskuhan|lantern\s+parade|exhibition\s+(game|match))' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Major Arena / Sports Event'); 
        event_category := 'major_event'; 
        friction_domain := 'academic'; 
        trigger_category := 'Major Arena Event'; 
        affects_ridership := TRUE; 
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 5e: Dynamic Class Suspensions
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
    IF v_combined ~* '(tree\s+trimming|declogging|asphalting|road\s+reblocking|sidewalk|street\s+sweeping|flushing|drainage|estero|canal|debris|garbage|linis|clean[\s_-]*up|tupad|4ps|profiling|caravan|vaccinat|anti-rabies|blood\s+donation|ayuda|payout|job\s+fair|mega\s+job\s+fair|bazaar|tiangge|pop[\s_-]*up|night[\s_-]*market|street[\s_-]*food|food\s+market|ferry\s+tour|water\s+interruption|power\s+interruption|meralco|maynilad|manila\s+water|repainting|furniture|clearing\s+operation|rosario\s+bridge|bridge\s+underpass|ilalim\s+ng\s+tulay|flyover|overpass|sangguniang\s+kabataan|sk\s+council|barangay\s+(?:day|fiesta|anniversary|celebration)|theoretical\s+driving\s+course|tdc\s+caravan)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Civic Maintenance / Hyper-Local Event');
        event_category := 'infrastructure';
        friction_domain := 'lgu';
        trigger_category := 'LGU Maintenance Operations';
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Default Fallback
    event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'External Event');
    event_category := 'other';
    friction_domain := NULL;
    trigger_category := NULL;
    affects_ridership := FALSE;
    RETURN NEXT;
    RETURN;
END;
$function$;

-- Step 7: Deploy hardened external.get_affected_stations()
CREATE OR REPLACE FUNCTION external.get_affected_stations(p_station text, p_post_text text, p_image_text text, p_source_name text)
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
    v_combined := LOWER(COALESCE(p_post_text, '') || ' ' || COALESCE(p_image_text, '') || ' ' || COALESCE(p_source_name, ''));
    v_station_normalized := external.normalize_station_name(p_station);

    -- 0. COMPREHENSIVE CORRIDOR SPORTS ARENA & STADIUM VENUE OVERRIDE:
    -- If a specific stadium/arena venue along the line is identified, route strictly to the station serving that arena,
    -- overriding any school home campus or posting organization location!
    -- Includes NCAA regular basketball tournaments & ticket giveaways hosted at Filoil EcoOil Centre
    IF (v_combined ~* '\y(filoil|flying\s+v|ecooil\s+centre|filoil\s+centre|playtime\s+filoil|san\s+juan\s+arena|san\s+juan\s+gym|v-?league(\s+collegiate\s+challenge)?|ncaa\s+(?:season\s+\d+\s+)?(?:men''?s\s+)?basketball|ncaa\s+game|ncaa\s+tickets?)\y'
        AND NOT v_combined ~* '\y(araneta|big\s+dome|mall\s+of\s+asia|moa\s+arena)\y') THEN
        RETURN ARRAY['J. Ruiz'];
    END IF;

    IF v_combined ~* '\y(araneta\s+coliseum|big\s+dome|smart\s+araneta)\y' THEN
        RETURN ARRAY['Araneta Center Cubao'];
    END IF;

    IF v_combined ~* '\y(marikina\s+sports\s+center|marikina\s+sports\s+park)\y' THEN
        RETURN ARRAY['Marikina-Pasig'];
    END IF;

    IF v_combined ~* '\y(blue\s+eagle\s+gym|moro\s+lorenzo|loyola\s+gym|up\s+gym|up\s+track\s+and\s+field)\y' THEN
        RETURN ARRAY['Katipunan'];
    END IF;

    IF v_combined ~* '\y(quadricentennial\s+pavilion|tiger\s+dome|ust\s+gym)\y' THEN
        RETURN ARRAY['Legarda'];
    END IF;

    IF v_combined ~* '\y(pup\s+gym|pup\s+gymnasium)\y' THEN
        RETURN ARRAY['Pureza'];
    END IF;

    IF v_combined ~* '\y(philsports|ultra)\y' THEN
        RETURN ARRAY['Santolan', 'Marikina-Pasig'];
    END IF;

    IF v_combined ~* '\y(rizal\s+memorial|ninoy\s+aquino\s+stadium)\y' THEN
        RETURN ARRAY['Recto'];
    END IF;

    -- 1. Check for corridor-wide / NCR-wide / Presidential / Malacañang declarations
    IF (v_combined ~* '\y(metro\s+manila|ncr\s+wide|all\s+public\s+and\s+private|across\s+metro\s+manila|nationwide|malacañang|malacanang|asean\s+summit)\y'
        AND NOT v_combined ~* '\y(quezon\s+city\s+only|manila\s+only|san\s+juan\s+only)\y')
       OR v_station_normalized = 'All' THEN
        RETURN v_all_stations;
    END IF;

    -- 2. Check for city-wide declarations
    IF v_combined ~* '\y(manila|maynila)\y'
       AND v_combined ~* '\y(walang\s*pasok|class(es)?\s+suspended|suspensyon|all\s+levels|traffic|road\s+closure)\y' THEN
        v_city := 'Manila';
    ELSIF v_combined ~* '\y(quezon\s+city|qc)\y'
       AND v_combined ~* '\y(walang\s*pasok|class(es)?\s+suspended|suspensyon|all\s+levels|traffic|road\s+closure)\y' THEN
        v_city := 'Quezon City';
    ELSIF v_combined ~* '\y(san\s+juan)\y'
       AND v_combined ~* '\y(walang\s*pasok|class(es)?\s+suspended|suspensyon|all\s+levels)\y' THEN
        v_city := 'San Juan';
    ELSIF v_combined ~* '\y(marikina)\y'
       AND v_combined ~* '\y(walang\s*pasok|class(es)?\s+suspended|suspensyon|all\s+levels)\y' THEN
        v_city := 'Marikina';
    ELSIF v_combined ~* '\y(pasig)\y'
       AND v_combined ~* '\y(walang\s*pasok|class(es)?\s+suspended|suspensyon|all\s+levels)\y' THEN
        v_city := 'Pasig';
    ELSIF v_combined ~* '\y(antipolo|rizal)\y'
       AND v_combined ~* '\y(walang\s*pasok|class(es)?\s+suspended|suspensyon|all\s+levels)\y' THEN
        v_city := 'Antipolo';
    END IF;

    IF v_city IS NOT NULL THEN
        SELECT ARRAY_AGG(station_name) INTO v_stations
        FROM (
            SELECT 'Recto' as station_name, 'Manila' as city UNION ALL
            SELECT 'Legarda', 'Manila' UNION ALL
            SELECT 'Pureza', 'Manila' UNION ALL
            SELECT 'V. Mapa', 'Manila' UNION ALL
            SELECT 'J. Ruiz', 'San Juan' UNION ALL
            SELECT 'Gilmore', 'Quezon City' UNION ALL
            SELECT 'Betty Go-Belmonte', 'Quezon City' UNION ALL
            SELECT 'Araneta Center Cubao', 'Quezon City' UNION ALL
            SELECT 'Anonas', 'Quezon City' UNION ALL
            SELECT 'Katipunan', 'Quezon City' UNION ALL
            SELECT 'Santolan', 'Pasig' UNION ALL
            SELECT 'Marikina-Pasig', 'Marikina' UNION ALL
            SELECT 'Antipolo', 'Antipolo'
        ) s
        WHERE s.city = v_city;

        IF v_stations IS NOT NULL AND array_length(v_stations, 1) > 0 THEN
            RETURN v_stations;
        END IF;
    END IF;

    -- 3. Check for specific station names
    IF v_combined ~* '\yrecto\y' THEN v_stations := array_append(v_stations, 'Recto'); END IF;
    IF v_combined ~* '\ylegarda\y' THEN v_stations := array_append(v_stations, 'Legarda'); END IF;
    IF v_combined ~* '\ypureza\y' THEN v_stations := array_append(v_stations, 'Pureza'); END IF;
    IF v_combined ~* '\yv\.?\s*mapa\y' THEN v_stations := array_append(v_stations, 'V. Mapa'); END IF;
    IF v_combined ~* '\yj\.?\s*ruiz\y' THEN v_stations := array_append(v_stations, 'J. Ruiz'); END IF;
    IF v_combined ~* '\ygilmore\y' THEN v_stations := array_append(v_stations, 'Gilmore'); END IF;
    IF v_combined ~* '\ybetty\s*go\y' THEN v_stations := array_append(v_stations, 'Betty Go-Belmonte'); END IF;
    IF v_combined ~* '\y(cubao|araneta)\y' THEN v_stations := array_append(v_stations, 'Araneta Center Cubao'); END IF;
    IF v_combined ~* '\yanonas\y' THEN v_stations := array_append(v_stations, 'Anonas'); END IF;
    IF v_combined ~* '\ykatipunan\y' THEN v_stations := array_append(v_stations, 'Katipunan'); END IF;
    IF v_combined ~* '\ysantolan\y' THEN v_stations := array_append(v_stations, 'Santolan'); END IF;
    IF v_combined ~* '\ymarikina\y' THEN v_stations := array_append(v_stations, 'Marikina-Pasig'); END IF;
    IF v_combined ~* '\yantipolo\y' THEN v_stations := array_append(v_stations, 'Antipolo'); END IF;

    IF array_length(v_stations, 1) > 0 THEN
        RETURN v_stations;
    END IF;

    -- 4. Check for institution-to-station mapping
    IF v_combined ~* '\y(pup|polytechnic\s+university)\y' THEN
        RETURN ARRAY['Pureza', 'Legarda', 'Recto', 'V. Mapa'];
    ELSIF v_combined ~* '\y(ust|santo\s+tomas|varsitarian)\y' THEN
        RETURN ARRAY['Legarda', 'Recto', 'Pureza', 'V. Mapa'];
    ELSIF v_combined ~* '\y(ue|university\s+of\s+the\s+east)\y' THEN
        RETURN ARRAY['Recto', 'Legarda', 'Pureza', 'V. Mapa'];
    ELSIF v_combined ~* '\y(feu|far\s+eastern)\y' THEN
        RETURN ARRAY['Recto', 'Legarda', 'Pureza', 'V. Mapa'];
    ELSIF v_combined ~* '\y(san\s+beda|sbu)\y' THEN
        RETURN ARRAY['Legarda', 'Recto', 'Pureza', 'V. Mapa'];
    ELSIF v_combined ~* '\y(ceub?|centro\s+escolar)\y' THEN
        RETURN ARRAY['Legarda', 'Recto', 'Pureza', 'V. Mapa'];
    ELSIF v_combined ~* '\y(tip|technological\s+institute)\y' THEN
        IF v_combined ~* '\y(qc|quezon\s+city|cubao)\y' THEN
            RETURN ARRAY['Araneta Center Cubao', 'Anonas'];
        ELSE
            RETURN ARRAY['Araneta Center Cubao'];
        END IF;
    ELSIF v_combined ~* '\y(ateneo|admu)\y' THEN
        RETURN ARRAY['Katipunan'];
    ELSIF v_combined ~* '\y(up\s+diliman|upd|university\s+of\s+the\s+philippines)\y' THEN
        RETURN ARRAY['Katipunan', 'Anonas'];
    ELSIF v_combined ~* '\y(uerm|ramon\s+magsaysay)\y' THEN
        RETURN ARRAY['V. Mapa', 'Pureza'];
    ELSIF v_combined ~* '\y(st\.?\s*paul|spuqc)\y' THEN
        RETURN ARRAY['Gilmore', 'Betty Go-Belmonte'];
    ELSIF v_combined ~* '\y(wcc|world\s+citi)\y' THEN
        RETURN ARRAY['Anonas', 'Araneta Center Cubao'];
    ELSIF v_combined ~* '\y(olfu|fatima)\y' THEN
        RETURN ARRAY['Antipolo'];
    END IF;

    -- 5. Fall back to normalized source station
    IF v_station_normalized IS NOT NULL AND v_station_normalized != '' THEN
        IF v_station_normalized = 'Recto' OR v_station_normalized = 'Legarda' THEN
            RETURN ARRAY['Recto', 'Legarda', 'Pureza', 'V. Mapa'];
        ELSIF v_station_normalized = 'Pureza' OR v_station_normalized = 'V. Mapa' THEN
            RETURN ARRAY['Pureza', 'V. Mapa', 'Legarda', 'Recto'];
        ELSIF v_station_normalized = 'Katipunan' THEN
            RETURN ARRAY['Katipunan', 'Anonas'];
        ELSIF v_station_normalized = 'Araneta Center Cubao' THEN
            RETURN ARRAY['Araneta Center Cubao'];
        ELSE
            RETURN ARRAY[v_station_normalized];
        END IF;
    END IF;

    -- 6. Last resort
    RETURN v_all_stations;
END;
$function$;

-- Step 8: Deploy hardened external.sync_academic_lgu_to_events_consolidated()
CREATE OR REPLACE FUNCTION external.sync_academic_lgu_to_events_consolidated()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_result RECORD;
    v_stations text[];
    v_station text;
    v_station_norm text;
    v_weight numeric;
    v_event_date date;
    v_start_date date;
    v_end_date date;
    v_curr_date date;
    v_cat_code text;
    v_date_code text;
    v_slug text;
    v_id text;
    v_del_stmt text;
    v_ins_stmt text;
    v_rows_affected int := 0;
    v_is_resumption boolean := FALSE;
    v_days_in_advance int;
    v_date_match text[];
BEGIN
    v_del_stmt := 'DELETE FROM external.events_consolidated WHERE source_id = $1 AND source_table = $2';

    IF TG_OP = 'DELETE' THEN
        EXECUTE v_del_stmt USING OLD.id, 'academic_lgu_events';
        RETURN OLD;
    END IF;

    IF TG_OP = 'UPDATE' AND (NEW.is_cancelled = TRUE OR NEW.is_cancelled IS TRUE) THEN
        EXECUTE v_del_stmt USING NEW.id, 'academic_lgu_events';
        RETURN NEW;
    END IF;

    IF NEW.is_cancelled = TRUE THEN
        EXECUTE v_del_stmt USING NEW.id, 'academic_lgu_events';
        RETURN NEW;
    END IF;

    SELECT * INTO v_result
    FROM external.classify_event_from_text(NEW.post_text, NEW.image_text, NEW.category, NEW.event_name)
    LIMIT 1;

    IF v_result.affects_ridership = FALSE OR v_result.affects_ridership IS FALSE THEN
        EXECUTE v_del_stmt USING NEW.id, 'academic_lgu_events';
        RETURN NEW;
    END IF;

    v_stations := external.get_affected_stations(NEW.station, NEW.post_text, NEW.image_text, NEW.source_name);

    IF v_stations IS NULL OR array_length(v_stations, 1) = 0 THEN
        v_stations := ARRAY[external.normalize_station_name(NEW.station)];
    END IF;

    v_start_date := NULL;
    v_end_date := NULL;

    -- Parse date range format (e.g. '2026-08-19 to 2026-08-31')
    IF NEW.event_date ~ '^\d{4}-\d{2}-\d{2}\s+to\s+\d{4}-\d{2}-\d{2}$' THEN
        v_date_match := regexp_matches(NEW.event_date, '^(\d{4}-\d{2}-\d{2})\s+to\s+(\d{4}-\d{2}-\d{2})$');
        v_start_date := v_date_match[1]::date;
        v_end_date := v_date_match[2]::date;
        IF v_end_date > v_start_date + INTERVAL '14 days' THEN
            v_end_date := v_start_date + INTERVAL '14 days';
        END IF;
    ELSIF NEW.event_date ~ '^\d{4}-\d{2}-\d{2}$' THEN
        v_event_date := NEW.event_date::date;
        v_start_date := v_event_date;
        v_end_date := v_event_date;
    ELSIF NEW.event_date IS NOT NULL AND NEW.event_date != '' THEN
        BEGIN
            v_start_date := NEW.event_date::date;
            v_end_date := v_start_date;
        EXCEPTION WHEN OTHERS THEN
            v_start_date := external.extract_event_date_from_text(NEW.post_text, NEW.image_text, NEW.post_date);
            v_end_date := v_start_date;
        END;
    ELSE
        v_start_date := external.extract_event_date_from_text(NEW.post_text, NEW.image_text, NEW.post_date);
        v_end_date := v_start_date;
    END IF;

    IF v_start_date IS NULL THEN
        IF NEW.post_date IS NOT NULL THEN
            v_start_date := NEW.post_date::date;
            v_end_date := v_start_date;
        ELSE
            EXECUTE v_del_stmt USING NEW.id, 'academic_lgu_events';
            RETURN NEW;
        END IF;
    END IF;

    -- GUARDRAIL: Advance Operational Notice Memo (>14 Days in Advance)
    -- Suppress operational daily shocks for ANY break, holiday, concert, arena event, or strike published >14 days ahead
    IF NEW.post_date IS NOT NULL AND v_start_date IS NOT NULL THEN
        v_days_in_advance := (v_start_date - NEW.post_date::date);
        IF v_days_in_advance > 14 AND v_result.event_category IN ('class_suspension', 'holiday', 'school_break', 'major_event', 'transport_strike') THEN
            EXECUTE v_del_stmt USING NEW.id, 'academic_lgu_events';
            RAISE NOTICE 'Advance operational notice guardrail: suppressed % (% days in advance, category %) from daily shocks.', NEW.id, v_days_in_advance, v_result.event_category;
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
        WHEN 'exam_week' THEN 'EX'
        WHEN 'major_event' THEN 'ME'
        WHEN 'transport_strike' THEN 'TS'
        WHEN 'weather' THEN 'WX'
        ELSE 'EV'
    END;

    IF v_start_date IS NOT NULL AND v_end_date IS NOT NULL AND array_length(v_stations, 1) > 0 THEN
        v_curr_date := v_start_date;
        WHILE v_curr_date <= v_end_date LOOP
            v_date_code := to_char(v_curr_date, 'MMDD');

            FOREACH v_station IN ARRAY v_stations LOOP
                v_station_norm := external.normalize_station_name(v_station);
                v_slug := lower(regexp_replace(v_station_norm, '[^a-zA-Z0-9]+', '_', 'g'));
                v_slug := trim(both '_' from v_slug);
                v_id := 'SCR-' || v_cat_code || '-' || v_date_code || '-' || NEW.id || '-' || v_slug;

                INSERT INTO external.events_consolidated (
                    id, station, event_date, source_table, source_id, source_name,
                    event_name, event_category, friction_domain, trigger_category,
                    source_url, description, normalized_score, friction_weight_ref,
                    announcement_time, updated_at, source_type
                )
                VALUES (
                    v_id,
                    v_station_norm,
                    v_curr_date,
                    'academic_lgu_events',
                    NEW.id,
                    NEW.source_name,
                    COALESCE(NULLIF(TRIM(NEW.event_name), ''), v_result.event_name),
                    v_result.event_category,
                    v_result.friction_domain,
                    v_result.trigger_category,
                    NEW.source_url,
                    SUBSTRING(COALESCE(NEW.post_text, NEW.event_name, 'External Event') FROM 1 FOR 500),
                    0.5,
                    v_weight,
                    COALESCE(NEW.post_date, clock_timestamp()),
                    clock_timestamp(),
                    NEW.category
                )
                ON CONFLICT (id) DO UPDATE SET
                    station = EXCLUDED.station,
                    event_date = EXCLUDED.event_date,
                    event_name = EXCLUDED.event_name,
                    event_category = EXCLUDED.event_category,
                    friction_domain = EXCLUDED.friction_domain,
                    trigger_category = EXCLUDED.trigger_category,
                    friction_weight_ref = EXCLUDED.friction_weight_ref,
                    description = EXCLUDED.description,
                    updated_at = clock_timestamp();
            END LOOP;

            v_curr_date := v_curr_date + INTERVAL '1 day';
        END LOOP;
    END IF;

    RETURN NEW;
END;
$function$;
