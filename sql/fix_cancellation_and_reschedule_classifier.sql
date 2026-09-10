-- ============================================================================
-- MIGRATION: Fix Cancellation & Rescheduling Event Classification
-- Target Tables: external.academic_lgu_events, external.events_consolidated
-- Target Functions: external.classify_event_from_text, external.sync_academic_lgu_to_events_consolidated
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Upgrade external.classify_event_from_text()
--    Prevents secondary suspension clauses (e.g. "following suspension of classes")
--    from hijacking the classification of rescheduled sports, arena, or concert events.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION external.classify_event_from_text(
    p_post_text text,
    p_image_text text,
    p_category text,
    p_event_name text DEFAULT NULL::text
) RETURNS TABLE (
    event_name text,
    event_category text,
    friction_domain text,
    trigger_category text,
    affects_ridership boolean
) AS $$
DECLARE
    v_combined text;
BEGIN
    v_combined := LOWER(COALESCE(p_post_text, '') || ' ' || COALESCE(p_image_text, '') || ' ' || COALESCE(p_event_name, ''));

    -- Filter 1: Planning / Administrative meetings
    IF (v_combined ~* '(coordination\s+meeting|ocular\s+visit|ocular\s+meeting|planning\s+meeting|planning\s+session|preparatory\s+meeting|committee\s+meeting|coordination\s+visit|pre-event\s+coordination)'
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

    -- Filter 5a: Statutory, National, LGU, and University Holidays (Distinct from Suspensions)
    IF v_combined ~* '(non[- ]?working\s+(day|holiday)?|special\s+(non[- ]?working|public)\s+(day|holiday)?|regular\s+holiday|araw\s+ng|founding\s+anniversary|\bholiday\b|holy\s+week|lenten\s+break|undas|traslacion|black\s+nazarene|day\s+of\s+valor|rizal\s+day|bonifacio\s+day|independence\s+day|labor\s+day|ninoy\s+aquino|national\s+heroes|all\s+saint|all\s+soul|christmas|new\s+year|maundy\s+thursday|good\s+friday|black\s+saturday|easter|immaculate\s+conception|edsa|eid|ramadan|quezon\s+city\s+day|manila\s+day|pasig\s+day|marikina\s+day|san\s+juan\s+day|antipolo\s+day|feast\s+of\s+st|up\s+foundation|chinese\s+new\s+year)' 
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
    -- Evaluated BEFORE general class suspensions so that secondary causes (e.g. "rescheduled due to class suspension") do not hijack the event!
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

    -- Filter 5d: Dynamic Class / Work Suspensions (Emergency, Weather, Heat Index)
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

    -- Filter 7: LGU Maintenance / Tree Trimming / Clearing
    IF v_combined ~* '(tree\s+trimming|road\s+clearance|clearing\s+operation|pruning|tree\s+pruning|declogging|drainage|flushing|sewer|relief\s+goods|street\s+repair|road\s+maintenance)' THEN
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

    -- Filter 11: Examination Period
    IF v_combined ~* '(exam(ination)?s?|midterm|finals?\s+(exam|week)|prelim(inary)?\s+exam|long\s+exam|qualifying\s+exam)' 
       AND NOT v_combined ~* '(cancel|suspend|walang\s*pasok|no\s+class)' THEN
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
$$ LANGUAGE plpgsql IMMUTABLE;

-- ----------------------------------------------------------------------------
-- 2. Upgrade external.sync_academic_lgu_to_events_consolidated()
--    - Honors NEW.event_date from LLM/scraped stage when available.
--    - Handles cancellations: if is_cancellation = true, cancels/removes the
--      prior event from events_consolidated on the announcement date.
--    - Places rescheduled events on the new target date as major_event (0.65).
-- ----------------------------------------------------------------------------
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
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM external.events_consolidated WHERE source_id = OLD.id AND source_table = 'academic_lgu_events';
        RETURN OLD;
    END IF;

    -- Resolve affected stations
    v_stations := external.get_affected_stations(NEW.station, NEW.post_text, NEW.image_text, NEW.source_name);

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
            normalized_score, friction_weight_ref, announcement_time, updated_at
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
                ELSE v_weight
            END,
            v_weight,
            NEW.post_date,
            now()
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
            updated_at = now();
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- 3. Data Cleanup & Rescheduling Reconciliation
-- ----------------------------------------------------------------------------

-- 3a. Remove the false Critical Class Suspension rows on Sept 10
DELETE FROM external.events_consolidated
WHERE id IN (
    'SCR-CS-0910-external_acad_0224-legarda',
    'SCR-CS-0910-external_acad_0224-pureza',
    'SCR-CS-0910-external_acad_0224-recto',
    'SCR-CS-0910-external_acad_0224-v._mapa'
);

-- 3b. Mark the original Sept 10 Kickoff Party (external_acad_0208) as cancelled
UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'Rescheduled to Sept 11 per UST IPEA / Varsitarian advisory (external_acad_0224)'
WHERE id = 'external_acad_0208';

-- 3c. Delete the cancelled Sept 10 Kickoff Party from events_consolidated
DELETE FROM external.events_consolidated
WHERE source_id = 'external_acad_0208';

-- 3d. Insert the rescheduled UAAP Kick Off event on Sept 11, 2026 as Major Arena Event (0.65)
INSERT INTO external.events_consolidated (
    id, station, event_date, source_table, source_id, source_name,
    event_name, event_category, friction_domain, trigger_category,
    source_url, description, normalized_score, friction_weight_ref,
    announcement_time, updated_at
)
VALUES
(
    'SCR-ME-0911-external_acad_0224-legarda', 'Legarda', '2026-09-11', 'academic_lgu_events', 'external_acad_0224', 'The Varsitarian',
    'UAAP Season 89 Kick Off Program (Rescheduled)', 'major_event', 'academic', 'Major Arena Event',
    'https://www.facebook.com/varsitarian/posts/pfbid02BTBfjutJcfmUnjS3H4yhRLTNQbpoakgDuYEpNYiSCL6o6zBpyfLJGVLrAPz42bvml',
    'UAAP SEASON 89 KICK OFF MOVES TO SEPT. 11 ADVISORY: The UAAP Season 89 Kick Off Program, originally set for today, Sept. 10, has been rescheduled to tomorrow, Sept. 11, following Malacanang’s directive to suspend onsite classes. Ticket selling for the UAAP Opening Ceremony and Men’s Basketball will begin tomorrow as scheduled. Source: UST Institute of Physical Education and Athletics',
    0.65, 0.65, '2026-09-10 01:18:13.686792+00', now()
),
(
    'SCR-ME-0911-external_acad_0224-pureza', 'Pureza', '2026-09-11', 'academic_lgu_events', 'external_acad_0224', 'The Varsitarian',
    'UAAP Season 89 Kick Off Program (Rescheduled)', 'major_event', 'academic', 'Major Arena Event',
    'https://www.facebook.com/varsitarian/posts/pfbid02BTBfjutJcfmUnjS3H4yhRLTNQbpoakgDuYEpNYiSCL6o6zBpyfLJGVLrAPz42bvml',
    'UAAP SEASON 89 KICK OFF MOVES TO SEPT. 11 ADVISORY: The UAAP Season 89 Kick Off Program, originally set for today, Sept. 10, has been rescheduled to tomorrow, Sept. 11, following Malacanang’s directive to suspend onsite classes. Ticket selling for the UAAP Opening Ceremony and Men’s Basketball will begin tomorrow as scheduled. Source: UST Institute of Physical Education and Athletics',
    0.65, 0.65, '2026-09-10 01:18:13.686792+00', now()
),
(
    'SCR-ME-0911-external_acad_0224-recto', 'Recto', '2026-09-11', 'academic_lgu_events', 'external_acad_0224', 'The Varsitarian',
    'UAAP Season 89 Kick Off Program (Rescheduled)', 'major_event', 'academic', 'Major Arena Event',
    'https://www.facebook.com/varsitarian/posts/pfbid02BTBfjutJcfmUnjS3H4yhRLTNQbpoakgDuYEpNYiSCL6o6zBpyfLJGVLrAPz42bvml',
    'UAAP SEASON 89 KICK OFF MOVES TO SEPT. 11 ADVISORY: The UAAP Season 89 Kick Off Program, originally set for today, Sept. 10, has been rescheduled to tomorrow, Sept. 11, following Malacanang’s directive to suspend onsite classes. Ticket selling for the UAAP Opening Ceremony and Men’s Basketball will begin tomorrow as scheduled. Source: UST Institute of Physical Education and Athletics',
    0.65, 0.65, '2026-09-10 01:18:13.686792+00', now()
),
(
    'SCR-ME-0911-external_acad_0224-v._mapa', 'V. Mapa', '2026-09-11', 'academic_lgu_events', 'external_acad_0224', 'The Varsitarian',
    'UAAP Season 89 Kick Off Program (Rescheduled)', 'major_event', 'academic', 'Major Arena Event',
    'https://www.facebook.com/varsitarian/posts/pfbid02BTBfjutJcfmUnjS3H4yhRLTNQbpoakgDuYEpNYiSCL6o6zBpyfLJGVLrAPz42bvml',
    'UAAP SEASON 89 KICK OFF MOVES TO SEPT. 11 ADVISORY: The UAAP Season 89 Kick Off Program, originally set for today, Sept. 10, has been rescheduled to tomorrow, Sept. 11, following Malacanang’s directive to suspend onsite classes. Ticket selling for the UAAP Opening Ceremony and Men’s Basketball will begin tomorrow as scheduled. Source: UST Institute of Physical Education and Athletics',
    0.65, 0.65, '2026-09-10 01:18:13.686792+00', now()
)
ON CONFLICT (id) DO UPDATE SET
    event_name = EXCLUDED.event_name,
    event_category = EXCLUDED.event_category,
    friction_domain = EXCLUDED.friction_domain,
    trigger_category = EXCLUDED.trigger_category,
    normalized_score = EXCLUDED.normalized_score,
    friction_weight_ref = EXCLUDED.friction_weight_ref,
    event_date = EXCLUDED.event_date,
    updated_at = now();

-- 3e. Fix analogous historical record: external_acad_0199 ("The Roar: A Celebrity Match" postponed on Sept 8)
DELETE FROM external.events_consolidated
WHERE source_id = 'external_acad_0199' AND event_category = 'class_suspension';

UPDATE external.academic_lgu_events
SET is_cancelled = TRUE,
    cancellation_reason = 'Postponed until further notice per Varsitarian advisory (external_acad_0199)'
WHERE id IN ('external_acad_0199', 'external_acad_0200');
