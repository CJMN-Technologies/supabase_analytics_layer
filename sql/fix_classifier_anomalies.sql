-- =============================================================================
-- LRT-2 Decision Support System — Classifier Anomaly Fixes & Data Cleanup
-- Target Engine: PostgreSQL 15+ / Supabase
-- Purpose:
--   1. Guardrail against routine photoshoots, toga fittings, and TOR claiming
--   2. Guardrail against municipal drainage, estero, and garbage cleanups
--   3. Tighten statutory holiday matching (prevent 'araw ng operasyon' false matches)
--   4. Purge contaminated false-positive records from external.events_consolidated
-- =============================================================================

CREATE OR REPLACE FUNCTION external.classify_event_from_text(
    p_post_text text,
    p_image_text text,
    p_event_name text,
    p_category text
)
RETURNS TABLE (
    event_name text,
    event_category text,
    friction_domain text,
    trigger_category text,
    affects_ridership boolean
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_combined text;
BEGIN
    v_combined := LOWER(COALESCE(p_post_text, '') || ' ' || COALESCE(p_image_text, '') || ' ' || COALESCE(p_event_name, ''));

    -- Filter 0: Student Council Petitions, Appeals, Position Papers & Political Statements/Critiques
    IF (v_combined ~* '(petition\s+(to|for|letter)|submitted\s+(a\s+)?petition|urging\s+the\s+administration|requests?\s+the\s+suspension|petitioning\s+for|petition\s+letter|call\s+for\s+suspension|urgent\s+requests?|sent\s+a\s+letter\s+to\s+the\s+(office|administration|chancellor)|requests?\s+(academic\s+)?leniency|appeal(s|ing)?\s+for\s+leniency|call\s+on\s+the\s+university\s+administration|panawagan\s+ng\s+(student\s+council|konseho)|usc\s+has\s+requested)'
        OR (v_combined ~* '(korapsyon|pananagutan|failure\s+of\s+governance|demand\s+accountability|flood-control\s+scandal|climatejusticenow|surge\s+into\s+the\s+streets|hindi\s+nakalimot\s+ang\s+bayan|position\s+paper|press\s+statement|unity\s+statement|pahayag\s+ng\s+(konseho|estudyante|mag-aaral)|statement\s+on|solidarity\s+statement)'
            AND v_combined ~* '(usc|student\s+council|konseho|sanggunian|cso|sandigan|bayan|estudyante|updusc)'))
       AND NOT v_combined ~* '(official\s+(announcement|declaration|advisory)|president\s+has\s+declared|office\s+of\s+the\s+(president|chancellor)\s+memo|executive\s+order|memorandum\s+no\.)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Student Council Statement / Advocacy');
        event_category := 'administrative';
        friction_domain := NULL;
        trigger_category := NULL;
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 1: Student ID transactions, Processing, Claiming & Printing
    IF v_combined ~* '(id\s+printing|id\s+processing|id\s+claiming|id\s+issuance|freshm(an|en)\s+id|schedule\s+for\s+id|distribution\s+of\s+id)'
       AND NOT v_combined ~* '(shift\s+to\s+(online|asynchronous|alternative)|alternative\s+delivery\s+mode|class(es)?\s+.*(suspend|shifted)|suspension\s+of\s+(campus\s+operations|classes)|walang\s*pasok|no\s+class)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Student ID Processing Advisory');
        event_category := 'administrative';
        friction_domain := NULL;
        trigger_category := NULL;
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 1a: Studio Photoshoots, Pictorials, Toga Rentals, Yearbook / TOR Photo Sessions
    IF v_combined ~* '(photoshoot|pictorial|tor\s+photo|toga\s+(fitting|rental|distribution)|yearbook|grad\s+pic|relans|photo\s+services)'
       AND NOT v_combined ~* '(shift\s+to\s+(online|asynchronous)|walang\s*pasok|no\s+class|class(es)?\s+.*suspend|commencement\s+exercise)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Graduation Photoshoot / Studio Advisory');
        event_category := 'administrative';
        friction_domain := NULL;
        trigger_category := NULL;
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 1b: Medical, Clinical & Health Services
    IF (v_combined ~* '(breast\s+exam|medical\s+exam|health\s+exam|dental\s+exam|physical\s+exam|birth\s+control|implant|clinic|friendlycare|vaccin(ation|e)|blood\s+donation|medical\s+mission|leptospirosis)'
        OR (v_combined ~* '(examination|exam)' AND v_combined ~* '(breast|implant|clinic|friendlycare|medical\s+center|health|doctor|dental)'))
       AND NOT v_combined ~* '(shift\s+to\s+(online|asynchronous)|walang\s*pasok|no\s+class|class(es)?\s+.*suspend)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Health / Clinical Services Advisory');
        event_category := 'administrative';
        friction_domain := NULL;
        trigger_category := NULL;
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 1c: Public Employment & Job Fairs
    IF (v_combined ~* '(job\s+fair|recruitment\s+activity|local\s+recruitment|peso\s+|public\s+employment\s+service|hiring\s+activity|career\s+fair|job\s+hiring|spes\s+)'
        OR (v_combined ~* '(recruitment|job\s+fair)' AND v_combined ~* '(cancel|suspend|postpone|moved)'))
       AND NOT v_combined ~* '(shift\s+to\s+(online|asynchronous)|walang\s*pasok|no\s+class|class(es)?\s+.*suspend)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Public Employment / Recruitment Advisory');
        event_category := 'administrative';
        friction_domain := NULL;
        trigger_category := NULL;
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 2: Planning / Administrative meetings
    IF (v_combined ~* '(coordination\s+meeting|ocular\s+visit|ocular\s+meeting|planning\s+meeting|planning\s+session|preparatory\s+meeting|committee\s+meeting|coordination\s+visit|pre-event\s+coordination)'
        OR (v_combined ~* '(meeting|ocular|planning|discussion)' 
            AND NOT v_combined ~* '(suspend|suspens|walang\s*pasok|no\s+class|strike|tigil\s+pasada|welga|shift\s+to|asynchronous|online\s+class)')) THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Planning/Coordination Meeting');
        event_category := 'administrative';
        friction_domain := NULL;
        trigger_category := NULL;
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 3: Administrative / Internal notices
    IF v_combined ~* '(promotions?\s+board|posting\s+of.*(grade|result)|deliberation|grade\s+release|final\s+grade|drop(ping)?\s+of\s+subject|leave\s+of\s+absence|filing\s+of\s+leave)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Administrative/Internal Notice');
        event_category := 'administrative';
        friction_domain := NULL;
        trigger_category := NULL;
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 4: Transport Strike (HIGHEST DISRUPTION PRIORITY)
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

    -- Filter 5: Online / Asynchronous Modality Shift
    IF v_combined ~* '(shift\s+to\s+(online|asynchronous)|asynchronous\s+(classes|modality|learning)|online\s+(classes|modality|learning|synchronous)|remote\s+learning|alternative\s+delivery\s+mode|\badm\b)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Shift to Online / Asynchronous Modality'); 
        event_category := 'class_suspension'; 
        friction_domain := 'academic'; 
        trigger_category := 'Online / Asynchronous Class Shift'; 
        affects_ridership := TRUE; 
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 6: Dynamic Class & Work Suspensions (ALWAYS EVALUATED BEFORE HOLIDAYS)
    IF v_combined ~* '((class(es)?|klase|work|trabaho|office|opisina|school|campus|transaction(s)?|operation(s)?)\s+.*(suspend|suspens|cancelled)|(suspend(ed|ing|sion)?|suspensyon|kanselado|cancel(led|lation)?)\s+.*(class|klase|work|office|school|campus|transaction|operation|onsite)|walang\s*pasok|no\s+class(es)?|in-person\s+class(es)?\s+suspension|cancel(lation|led)?\s+of\s+(medical\s+)?exam)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Class Suspension'); 
        event_category := 'class_suspension'; 
        friction_domain := 'academic'; 
        trigger_category := 'Class Suspension'; 
        affects_ridership := TRUE; 
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 7: School / Term Breaks
    IF v_combined ~* '(semestral\s+break|summer\s+break|midyear\s+break|christmas\s+break|term\s+break|academic\s+break)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'School Break'); 
        event_category := 'school_break'; 
        friction_domain := 'academic'; 
        trigger_category := 'School Break'; 
        affects_ridership := TRUE; 
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 8: Statutory, National, LGU, and University Holidays
    -- Note: 'araw ng' is strictly constrained to recognized holiday names to prevent matching 'araw ng operasyon'
    IF v_combined ~* '(non[- ]?working\s+(day|holiday)?|special\s+(non[- ]?working|public)\s+(day|holiday)?|regular\s+holiday|araw\s+ng\s+(kagitingan|maynila|kalayaan|quezon|pasig|marikina|san\s+juan|manggagawa|mga\s+bayani|wika)|founding\s+anniversary|\bholiday\b|holy\s+week|lenten\s+break|undas|traslacion|black\s+nazarene|day\s+of\s+valor|rizal\s+day|bonifacio\s+day|independence\s+day|labor\s+day|ninoy\s+aquino|national\s+heroes|all\s+saint|all\s+soul|christmas|new\s+year|maundy\s+thursday|good\s+friday|black\s+saturday|easter|immaculate\s+conception|edsa|eid|ramadan|quezon\s+city\s+day|manila\s+day|pasig\s+day|marikina\s+day|san\s+juan\s+day|antipolo\s+day|feast\s+of\s+st|up\s+foundation|chinese\s+new\s+year)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'National / Academic Holiday'); 
        event_category := 'holiday'; 
        friction_domain := 'academic'; 
        trigger_category := 'Holiday'; 
        affects_ridership := TRUE; 
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 9: Major Arena Events
    IF v_combined ~* '(uaap|ncaa|concert|sports\s+event|arena\s+event|basketball|volleyball|cheerdance|pep\s+squad|send[- ]?off|rally|pep\s+rally|game\s+day|paskuhan|lantern\s+parade)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Major Arena / Sports Event'); 
        event_category := 'major_event'; 
        friction_domain := 'academic'; 
        trigger_category := 'Major Arena Event'; 
        affects_ridership := TRUE; 
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 10: Graduation & Commencement Ceremonies
    IF v_combined ~* '(commencement(\s+exercises?)?|graduation(\s+rites?|\s+ceremon(y|ies))|baccalaureate(\s+mass)?|solemn\s+investiture|hooding(\s+ceremony)?|closing\s+exercises)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Graduation & Commencement Rites'); 
        event_category := 'major_event'; 
        friction_domain := 'academic'; 
        trigger_category := 'Graduation & Commencement Rites'; 
        affects_ridership := TRUE; 
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 11: Civic Rallies & Public Mobilizations
    IF v_combined ~* '(sona\s+rally|protest|mobilization|mass\s+gathering|labor\s+rally|peace\s+rally|march\s+for|piket|first\s+week\s+rage|marcos\s*singilin|duterte\s*panagutin)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Civic Rally & Public Mobilization'); 
        event_category := 'major_event'; 
        friction_domain := 'academic'; 
        trigger_category := 'Civic Rally & Public Mobilization'; 
        affects_ridership := TRUE; 
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 12: Examination Period
    IF v_combined ~* '(exam(ination)?s?|midterm|finals?\s+(exam|week)|prelim(inary)?\s+exam|long\s+exam|qualifying\s+exam)' 
       AND NOT v_combined ~* '(cancel|suspend|suspens|walang\s*pasok|no\s+class|medical|physical|breast|dental|clinical|health|implant|clinic)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'Examination Period'); 
        event_category := 'exam_week'; 
        friction_domain := 'academic'; 
        trigger_category := 'University Exam Week'; 
        affects_ridership := TRUE;
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 13: LGU Maintenance / Tree Trimming / Estero Clean-Up / Declogging Activities
    IF v_combined ~* '(tree\s+trimming|road\s+clearance|clearing\s+operation|pruning|tree\s+pruning|declogging|drainage|flushing|sewer|relief\s+goods|estero|clean[- ]?up|basura|garbage|trash\s+collection|waste\s+collection|dredging)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'LGU Clearing & Maintenance Activity'); 
        event_category := 'infrastructure'; 
        friction_domain := 'lgu'; 
        trigger_category := 'LGU Municipal Clearing & Maintenance'; 
        affects_ridership := FALSE;
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 14: LGU Weather, Rainfall Warnings & Road Flooding Status
    IF p_category = 'lgu' OR v_combined ~* '(heavy\s+rainfall\s+warning|orange\s+warning|yellow\s+warning|red\s+warning|weather\s+advisory|status\s+of\s+roads|baha\s+sa|pagasa|habagat|southwest\s+monsoon)' THEN
        event_name := COALESCE(NULLIF(TRIM(p_event_name), ''), 'LGU Weather / Flooding Advisory');
        event_category := 'lgu';
        friction_domain := 'lgu';
        trigger_category := 'LGU Weather Advisory';
        affects_ridership := FALSE;
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
$$;

-- =============================================================================
-- One-time Data Cleanup: Purge false-positive contaminated rows
-- =============================================================================

-- 1. Purge Estero clean-up false-positive holiday records from consolidated table
DELETE FROM external.events_consolidated
WHERE source_id = 'external_lgu_0086';

-- 2. Purge PUP graduation photoshoot false-positive warning records from consolidated table
DELETE FROM external.events_consolidated
WHERE source_id = 'external_acad_0114';

-- 3. Fix OCR year drift for San Beda Southwest Monsoon post
UPDATE external.academic_lgu_events
SET event_date = '2026-08-10'
WHERE id = 'external_acad_0021' AND event_date = '2020-08-10';
