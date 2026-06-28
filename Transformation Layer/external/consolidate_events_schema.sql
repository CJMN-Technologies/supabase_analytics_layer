-- ============================================================================
-- Migration: Events Classification, Consolidation & Normalization Pipeline
-- Implements EventsNormalizationToFrictionIndex.md with CFI_Variables.md labels
-- Classification: External Dataset (Events Scraper/API)
-- ============================================================================

-- 1a. Create the consolidated events table
CREATE TABLE IF NOT EXISTS external.events_consolidated (
    id text PRIMARY KEY,
    station text NOT NULL,
    event_date date NOT NULL,
    source_table text NOT NULL,
    source_id text NOT NULL,
    source_name text,
    event_name text NOT NULL,
    event_category text NOT NULL,
    friction_domain text NOT NULL,
    trigger_category text NOT NULL,
    -- Normalized score: A_sw (Academic Surge Weight) or L_sp (Surge Probability Multiplier)
    normalized_score numeric NOT NULL DEFAULT 0.0,
    -- Raw literature weight from friction_weight for traceability
    friction_weight_ref numeric NOT NULL DEFAULT 0.0,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_events_consolidated_lookup
ON external.events_consolidated (station, event_date, event_category);

-- 1b. Keyword-based event classifier function (CASE-INSENSITIVE)
CREATE OR REPLACE FUNCTION external.classify_event_from_text(
    p_post_text text,
    p_image_text text,
    p_category text
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
    v_combined := LOWER(COALESCE(p_post_text, '') || ' ' || COALESCE(p_image_text, ''));

    -- Global filter for planning, coordination meetings, and ocular visits
    -- Bypassed if the text explicitly declares active suspension or strike actions
    IF (v_combined ~* '(coordination\s+meeting|ocular\s+visit|ocular\s+meeting|planning\s+meeting|planning\s+session|preparatory\s+meeting|committee\s+meeting|coordination\s+visit|pre-event\s+coordination)'
        OR (v_combined ~* '(meeting|ocular|planning|preparation|discussion)' 
            AND NOT v_combined ~* '(suspend|walang\s+pasok|no\s+class|strike|tigil\s+pasada|welga)')) THEN
        event_name := 'Planning/Coordination Meeting';
        event_category := 'administrative';
        friction_domain := NULL;
        trigger_category := NULL;
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Global filter for administrative/internal events (grade posting, release, deliberation, dropping, leave filing)
    IF v_combined ~* '(promotions?\s+board|posting\s+of.*(grade|result)|deliberation|grade\s+release|final\s+grade|drop(ping)?\s+of\s+subject|leave\s+of\s+absence|filing\s+of\s+leave)' THEN
        event_name := 'Administrative/Internal Notice';
        event_category := 'administrative';
        friction_domain := NULL;
        trigger_category := NULL;
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    IF v_combined ~* '(typhoon|tropical\s+cyclone|signal\s+no|rainfall\s+warning|heavy\s+rain(shower)?s?\s+(warning|advisory)|thunderstorm\s+advisory|flood\s+advisory|habagat|southwest\s+monsoon|weather\s+advisory)' THEN
        event_name := 'Weather Advisory'; event_category := 'weather_advisory'; friction_domain := 'pagasa'; trigger_category := NULL; affects_ridership := FALSE;
        RETURN NEXT; RETURN;
    END IF;

    IF v_combined ~* '(road\s+repair|drainage|infrastructure|kalsada|sirang\s+kalsada|construction|asphalting)' 
       AND NOT v_combined ~* '(suspend|pasok|class|exam)' THEN
        event_name := 'Infrastructure Notice'; event_category := 'infrastructure'; friction_domain := NULL; trigger_category := NULL; affects_ridership := FALSE;
        RETURN NEXT; RETURN;
    END IF;

    IF v_combined ~* '(semestral\s+break|sem\s+break|christmas\s+break|summer\s+break|vacation)' THEN
        event_name := 'School Break'; event_category := 'school_break'; friction_domain := 'academic'; trigger_category := 'School Break'; affects_ridership := TRUE;
        RETURN NEXT; RETURN;
    END IF;

    IF v_combined ~* '(class(es)?\s+(and\s+office\s+)?(operations?\s+)?(will\s+be\s+|are\s+|is\s+)?suspend|suspend(ed|ing)?\s+(class|office)|walang\s+pasok|no\s+class|non[- ]?working\s+(day|holiday)|special\s+(non[- ]?working|public)\s+(day|holiday)|regular\s+holiday|araw\s+ng|founding\s+anniversary|holiday)' THEN
        event_name := 'Class Suspension / Holiday'; event_category := 'class_suspension'; friction_domain := 'academic'; trigger_category := 'Class Suspension / Holiday'; affects_ridership := TRUE;
        RETURN NEXT; RETURN;
    END IF;

    IF v_combined ~* '(transport\s+strike|tigil\s+pasada|welga|jeepney\s+strike|piston|manibela|transport\s+group)' THEN
        event_name := 'Transport Strike'; event_category := 'transport_strike'; friction_domain := 'academic'; trigger_category := 'Transport Strike'; affects_ridership := TRUE;
        RETURN NEXT; RETURN;
    END IF;

    IF v_combined ~* '(uaap|ncaa|concert|sports\s+event|arena\s+event|basketball|volleyball|cheerdance|pep\s+squad|send[- ]?off|rally|pep\s+rally|game\s+day)' THEN
        event_name := 'Major Arena / Sports Event'; event_category := 'major_event'; friction_domain := 'academic'; trigger_category := 'Major Arena Event'; affects_ridership := TRUE;
        RETURN NEXT; RETURN;
    END IF;

    IF v_combined ~* '(exam(ination)?s?|midterm|finals?\s+(exam|week)|prelim(inary)?\s+exam|long\s+exam|qualifying\s+exam)' THEN
        event_name := 'Examination Period'; event_category := 'exam_week'; friction_domain := 'academic'; trigger_category := 'University Exam Week'; affects_ridership := TRUE;
        RETURN NEXT; RETURN;
    END IF;

    IF v_combined ~* '(enrollment|orientation|first\s+day\s+of\s+(class|regular\s+class)|start\s+of\s+class|opening\s+of\s+class)' THEN
        event_name := 'Academic Start / Enrollment'; event_category := 'regular_class_day'; friction_domain := 'academic'; trigger_category := 'Regular Class Day'; affects_ridership := TRUE;
        RETURN NEXT; RETURN;
    END IF;

    event_name := 'Unclassified'; event_category := 'unclassified'; friction_domain := NULL; trigger_category := NULL; affects_ridership := FALSE;
    RETURN NEXT; RETURN;
END;
$$ LANGUAGE plpgsql STABLE;

-- 1c. Trigger function for academic_lgu_events → events_consolidated
CREATE OR REPLACE FUNCTION external.sync_academic_lgu_to_events_consolidated()
RETURNS trigger AS $$
DECLARE
    v_result RECORD;
    v_weight numeric;
    v_event_date date;
    v_consolidated_id text;
    v_scrape_id text;
    v_cat_code text;
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM external.events_consolidated WHERE source_id = OLD.id AND source_table = 'academic_lgu_events';
        RETURN OLD;
    END IF;

    SELECT * INTO v_result
    FROM external.classify_event_from_text(NEW.post_text, NEW.image_text, NEW.category);

    IF v_result.affects_ridership = FALSE OR v_result.affects_ridership IS NULL THEN
        DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
        RETURN NEW;
    END IF;

    SELECT fw.friction_weight INTO v_weight
    FROM external.friction_weight fw
    WHERE fw.friction_domain = v_result.friction_domain 
      AND fw.trigger_category = v_result.trigger_category
    LIMIT 1;
    v_weight := COALESCE(v_weight, 0.0);

    v_event_date := COALESCE(NEW.post_date::date, CURRENT_DATE);

    v_cat_code := CASE v_result.event_category
        WHEN 'class_suspension' THEN 'CS'
        WHEN 'transport_strike' THEN 'TS'
        WHEN 'major_event' THEN 'ME'
        WHEN 'exam_week' THEN 'EX'
        ELSE 'RC'
    END;
    v_scrape_id := 'SCR-' || v_cat_code || '-' || TO_CHAR(v_event_date, 'MMDD') || '-' || NEW.id;

    INSERT INTO external.events_consolidated (
        id, station, event_date, source_table, source_id, source_name,
        event_name, event_category, friction_domain, trigger_category,
        normalized_score, friction_weight_ref, updated_at
    )
    VALUES (
        v_scrape_id,
        COALESCE(NEW.station, 'All Stations'),
        v_event_date,
        'academic_lgu_events',
        NEW.id,
        NEW.source_name,
        v_result.event_name,
        v_result.event_category,
        v_result.friction_domain,
        v_result.trigger_category,
        CASE
            WHEN v_result.event_category IN ('class_suspension', 'holiday', 'school_break') THEN 1.0
            ELSE v_weight
        END,
        v_weight,
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
        normalized_score = EXCLUDED.normalized_score,
        friction_weight_ref = EXCLUDED.friction_weight_ref,
        updated_at = now();

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 1d. Attach trigger to academic_lgu_events
DROP TRIGGER IF EXISTS tg_sync_academic_lgu_events ON external.academic_lgu_events;
CREATE TRIGGER tg_sync_academic_lgu_events
AFTER INSERT OR UPDATE OR DELETE ON external.academic_lgu_events
FOR EACH ROW EXECUTE FUNCTION external.sync_academic_lgu_to_events_consolidated();


-- ============================================================================
-- WORKSTREAM 2: Academic Calendar Ingestion
-- ============================================================================

-- 2a. Tracking table for processed calendar tables
CREATE TABLE IF NOT EXISTS external.processed_calendar_tables (
    table_name text PRIMARY KEY,
    rows_processed integer DEFAULT 0,
    last_processed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);

-- 2b. Classifier for structured academic calendar event_name
CREATE OR REPLACE FUNCTION external.classify_calendar_event(
    p_event_name text
) RETURNS TABLE (
    event_category text,
    friction_domain text,
    trigger_category text,
    affects_ridership boolean
) AS $$
DECLARE
    v_lower text;
BEGIN
    v_lower := LOWER(COALESCE(p_event_name, ''));

    -- Promotions Board / Grade posting / Dropping of subjects / Leave filing (internal, no ridership impact)
    IF v_lower ~* '(promotions?\s+board|posting\s+of.*(grade|result)|deliberation|grade\s+release|final\s+grade|drop(ping)?\s+of\s+subject|leave\s+of\s+absence|filing)' THEN
        event_category := 'administrative';
        friction_domain := NULL;
        trigger_category := NULL;
        affects_ridership := FALSE;
        RETURN NEXT; RETURN;
    END IF;

    -- Exam events
    IF v_lower ~* '(exam(ination)?|long\s+exam|qualifying|prelim(inary)?|midterm|finals?)' THEN
        event_category := 'exam_week';
        friction_domain := 'academic';
        trigger_category := 'University Exam Week';
        affects_ridership := TRUE;
        RETURN NEXT; RETURN;
    END IF;

    -- School Breaks (scheduled academic breaks)
    IF v_lower ~* '(semestral\s+break|sem\s+break|christmas\s+break|summer\s+break|vacation)' THEN
        event_category := 'school_break';
        friction_domain := 'academic';
        trigger_category := 'School Break';
        affects_ridership := TRUE;
        RETURN NEXT; RETURN;
    END IF;

    -- Holidays / Class Suspensions (unscheduled or holiday class off)
    IF v_lower ~* '(holiday|holy\s+week|class(es)?\s+suspend|suspend(ed)?\s+class)' THEN
        event_category := 'class_suspension';
        friction_domain := 'academic';
        trigger_category := 'Class Suspension / Holiday';
        affects_ridership := TRUE;
        RETURN NEXT; RETURN;
    END IF;

    -- Graduation / Commencement (major event surge)
    IF v_lower ~* '(graduation|commencement|baccalaureate|recognition\s+(day|rites))' THEN
        event_category := 'major_event';
        friction_domain := 'academic';
        trigger_category := 'Major Arena Event';
        affects_ridership := TRUE;
        RETURN NEXT; RETURN;
    END IF;

    -- Enrollment period (regular operations)
    IF v_lower ~* '(enrollment|enrolment|registration|first\s+day\s+of\s+(class|regular)|orientation|opening)' THEN
        event_category := 'regular_class_day';
        friction_domain := 'academic';
        trigger_category := 'Regular Class Day';
        affects_ridership := TRUE;
        RETURN NEXT; RETURN;
    END IF;

    -- Last day of classes (regular operations)
    IF v_lower ~* '(last\s+day\s+of\s+(regular\s+)?class|end\s+of\s+(regular\s+)?class)' THEN
        event_category := 'regular_class_day';
        friction_domain := 'academic';
        trigger_category := 'Regular Class Day';
        affects_ridership := TRUE;
        RETURN NEXT; RETURN;
    END IF;

    -- Default: unclassified / no ridership impact
    event_category := 'unclassified';
    friction_domain := NULL;
    trigger_category := NULL;
    affects_ridership := FALSE;
    RETURN NEXT; RETURN;
END;
$$ LANGUAGE plpgsql STABLE;

-- 2c. Function to process a single academic calendar table
CREATE OR REPLACE FUNCTION external.process_academic_calendar(p_table_name text)
RETURNS integer AS $$
DECLARE
    v_row RECORD;
    v_class RECORD;
    v_weight numeric;
    v_count integer := 0;
    v_consolidated_id text;
    v_school_acronym text;
    v_event_date date;
BEGIN
    -- Prevent duplicates: delete all existing consolidated rows for this table first
    DELETE FROM external.events_consolidated WHERE source_table = p_table_name;

    -- Extract school acronym from table name (e.g., 'UERM_Academic_Calendar' -> 'UERM')
    v_school_acronym := SPLIT_PART(p_table_name, '_Academic_Calendar', 1);

    -- Iterate over all rows in the calendar table
    FOR v_row IN EXECUTE format(
        'SELECT id, station, source_name, event_date, event_name, category FROM external.%I',
        p_table_name
    ) LOOP
        -- Classify the event
        SELECT * INTO v_class
        FROM external.classify_calendar_event(v_row.event_name);

        -- Skip non-ridership events
        IF v_class.affects_ridership = FALSE OR v_class.affects_ridership IS NULL THEN
            CONTINUE;
        END IF;

        -- Look up literature weight
        SELECT fw.friction_weight INTO v_weight
        FROM external.friction_weight fw
        WHERE fw.friction_domain = v_class.friction_domain
          AND fw.trigger_category = v_class.trigger_category
        LIMIT 1;
        v_weight := COALESCE(v_weight, 0.0);

        -- Parse event_date safely
        BEGIN
            v_event_date := v_row.event_date::date;
        EXCEPTION WHEN OTHERS THEN
            v_event_date := CURRENT_DATE;
        END;

        -- Build consolidated ID: CAL-[SCH]-[MMDD]-[ROW_ID]
        v_consolidated_id := 'CAL-' || UPPER(v_school_acronym) || '-' || TO_CHAR(v_event_date, 'MMDD') || '-' || COALESCE(v_row.id, v_count::text);

        INSERT INTO external.events_consolidated (
            id, station, event_date, source_table, source_id, source_name,
            event_name, event_category, friction_domain, trigger_category,
            normalized_score, friction_weight_ref, updated_at
        )
        VALUES (
            v_consolidated_id,
            COALESCE(v_row.station, 'All Stations'),
            v_event_date,
            p_table_name,
            COALESCE(v_row.id, 'row-' || v_count),
            COALESCE(v_row.source_name, v_school_acronym),
            v_row.event_name,
            v_class.event_category,
            v_class.friction_domain,
            v_class.trigger_category,
            CASE
                WHEN v_class.event_category IN ('class_suspension', 'holiday', 'school_break') THEN 1.0
                ELSE v_weight
            END,
            v_weight,
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
            normalized_score = EXCLUDED.normalized_score,
            friction_weight_ref = EXCLUDED.friction_weight_ref,
            updated_at = now();

        v_count := v_count + 1;
    END LOOP;

    -- Track this table as processed
    INSERT INTO external.processed_calendar_tables (table_name, rows_processed, last_processed_at)
    VALUES (p_table_name, v_count, now())
    ON CONFLICT (table_name) DO UPDATE SET
        rows_processed = v_count,
        last_processed_at = now();

    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- 2d. Polling function: scan for new *_Academic_Calendar tables
CREATE OR REPLACE FUNCTION external.scan_and_process_new_calendars()
RETURNS text AS $$
DECLARE
    v_table RECORD;
    v_processed integer;
    v_results text := '';
BEGIN
    FOR v_table IN
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = 'external'
          AND table_name LIKE '%\_Academic\_Calendar'
          AND table_name NOT IN (SELECT table_name FROM external.processed_calendar_tables)
        ORDER BY table_name
    LOOP
        v_processed := external.process_academic_calendar(v_table.table_name);
        v_results := v_results || v_table.table_name || ': ' || v_processed || ' events processed. ';
    END LOOP;

    IF v_results = '' THEN
        RETURN 'No new Academic Calendar tables found.';
    END IF;

    RETURN v_results;
END;
$$ LANGUAGE plpgsql;
