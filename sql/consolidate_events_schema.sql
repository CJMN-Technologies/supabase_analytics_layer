-- ============================================================================
-- Migration: Events Classification, Consolidation & Normalization Pipeline
-- Implements EventsNormalizationToFrictionIndex.md with CFI_Variables.md labels
-- ============================================================================

-- ============================================================================
-- WORKSTREAM 1: Events Consolidated Table & Keyword Classifier
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
-- Scans combined post_text + image_text for ridership-relevant keywords.
-- Returns NULL event_category if no ridership-relevant match found.
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
    -- Combine both text sources, lowercased for case-insensitive matching
    v_combined := LOWER(COALESCE(p_post_text, '') || ' ' || COALESCE(p_image_text, ''));

    -- Priority 1: Weather advisories (skip - handled by weather pipeline)
    IF v_combined ~* '(typhoon|tropical\s+cyclone|signal\s+no|rainfall\s+warning|heavy\s+rain(shower)?s?\s+(warning|advisory)|thunderstorm\s+advisory|flood\s+advisory|habagat|southwest\s+monsoon|weather\s+advisory)' THEN
        event_name := 'Weather Advisory';
        event_category := 'weather_advisory';
        friction_domain := 'pagasa';
        trigger_category := NULL;
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Priority 2: Infrastructure / non-ridership (skip)
    IF v_combined ~* '(road\s+repair|drainage|infrastructure|kalsada|sirang\s+kalsada|construction|asphalting)' 
       AND NOT v_combined ~* '(suspend|pasok|class|exam)' THEN
        event_name := 'Infrastructure Notice';
        event_category := 'infrastructure';
        friction_domain := NULL;
        trigger_category := NULL;
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Priority 3: Class suspension / Walang Pasok / Holiday
    IF v_combined ~* '(class(es)?\s+(and\s+office\s+)?(operations?\s+)?(will\s+be\s+|are\s+|is\s+)?suspend|suspend(ed|ing)?\s+(class|office)|walang\s+pasok|no\s+class|non[- ]?working\s+(day|holiday)|special\s+(non[- ]?working|public)\s+(day|holiday)|regular\s+holiday|araw\s+ng|founding\s+anniversary|holiday)' THEN
        event_name := 'Class Suspension / Holiday';
        event_category := 'class_suspension';
        friction_domain := 'academic';
        trigger_category := 'Mid-Day Class Suspension';
        affects_ridership := TRUE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Priority 4: Transport strike
    IF v_combined ~* '(transport\s+strike|tigil\s+pasada|welga|jeepney\s+strike|piston|manibela|transport\s+group)' THEN
        event_name := 'Transport Strike';
        event_category := 'transport_strike';
        friction_domain := 'academic';
        trigger_category := 'Transport Strike';
        affects_ridership := TRUE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Priority 5: Major arena/sports/concert events
    IF v_combined ~* '(uaap|ncaa|concert|sports\s+event|arena\s+event|basketball|volleyball|cheerdance|pep\s+squad|send[- ]?off|rally|pep\s+rally|game\s+day)' THEN
        event_name := 'Major Arena / Sports Event';
        event_category := 'major_event';
        friction_domain := 'academic';
        trigger_category := 'Major Arena Event';
        affects_ridership := TRUE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Priority 6: Exam week
    IF v_combined ~* '(exam(ination)?s?|midterm|finals?\s+(exam|week)|prelim(inary)?\s+exam|long\s+exam|qualifying\s+exam)' THEN
        event_name := 'Examination Period';
        event_category := 'exam_week';
        friction_domain := 'academic';
        trigger_category := 'University Exam Week';
        affects_ridership := TRUE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Priority 7: Enrollment / Orientation / First day (regular class day weight = 0.0)
    IF v_combined ~* '(enrollment|orientation|first\s+day\s+of\s+(class|regular\s+class)|start\s+of\s+class|opening\s+of\s+class)' THEN
        event_name := 'Academic Start / Enrollment';
        event_category := 'regular_class_day';
        friction_domain := 'academic';
        trigger_category := 'Regular Class Day';
        affects_ridership := TRUE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Default: no ridership-relevant match found
    event_name := 'Unclassified';
    event_category := 'unclassified';
    friction_domain := NULL;
    trigger_category := NULL;
    affects_ridership := FALSE;
    RETURN NEXT;
    RETURN;
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
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM external.events_consolidated WHERE source_id = OLD.id AND source_table = 'academic_lgu_events';
        RETURN OLD;
    END IF;

    -- Classify the event
    SELECT * INTO v_result
    FROM external.classify_event_from_text(NEW.post_text, NEW.image_text, NEW.category);

    -- Only proceed if the event affects ridership
    IF v_result.affects_ridership = FALSE OR v_result.affects_ridership IS NULL THEN
        -- Remove any previous entry if reclassified as non-relevant
        DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
        RETURN NEW;
    END IF;

    -- Look up the literature friction weight
    SELECT fw.friction_weight INTO v_weight
    FROM external.friction_weight fw
    WHERE fw.friction_domain = v_result.friction_domain 
      AND fw.trigger_category = v_result.trigger_category
    LIMIT 1;
    v_weight := COALESCE(v_weight, 0.0);

    -- Determine event date
    v_event_date := COALESCE(NEW.post_date::date, CURRENT_DATE);

    -- Build consolidated ID
    v_consolidated_id := 'EVT-SCRAPE-' || REPLACE(REPLACE(UPPER(COALESCE(NEW.station, 'ALL')), ' ', '-'), '.', '') || '-' || TO_CHAR(v_event_date, 'YYYYMMDD') || '-' || NEW.id;

    -- Compute normalized score per EventsNormalizationToFrictionIndex.md
    -- For class_suspension/holiday: L_sp = 1.0 (binary)
    -- For others: use friction_weight_ref as the base score
    INSERT INTO external.events_consolidated (
        id, station, event_date, source_table, source_id, source_name,
        event_name, event_category, friction_domain, trigger_category,
        normalized_score, friction_weight_ref, updated_at
    )
    VALUES (
        v_consolidated_id,
        COALESCE(NEW.station, 'All Stations'),
        v_event_date,
        'academic_lgu_events',
        NEW.id,
        NEW.source_name,
        v_result.event_name,
        v_result.event_category,
        v_result.friction_domain,
        v_result.trigger_category,
        -- L_sp normalization: class_suspension/holiday = 1.0 (binary per Step 3c)
        -- A_sw normalization: computed later per station/date aggregate (Step 3b)
        CASE
            WHEN v_result.event_category IN ('class_suspension', 'holiday') THEN 1.0
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

    -- Exam events
    IF v_lower ~* '(exam(ination)?|long\s+exam|qualifying|prelim(inary)?|midterm|finals?)' THEN
        event_category := 'exam_week';
        friction_domain := 'academic';
        trigger_category := 'University Exam Week';
        affects_ridership := TRUE;
        RETURN NEXT; RETURN;
    END IF;

    -- Breaks / Holidays (classes suspended)
    IF v_lower ~* '(semestral\s+break|christmas\s+break|summer\s+break|holiday|holy\s+week|vacation)' THEN
        event_category := 'class_suspension';
        friction_domain := 'academic';
        trigger_category := 'Mid-Day Class Suspension';
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

    -- Promotions Board / Grade posting (internal, no ridership impact)
    IF v_lower ~* '(promotions?\s+board|posting\s+of.*(grade|result)|deliberation|grade\s+release)' THEN
        event_category := 'administrative';
        friction_domain := NULL;
        trigger_category := NULL;
        affects_ridership := FALSE;
        RETURN NEXT; RETURN;
    END IF;

    -- Dropping of subjects / Leave filing (administrative, no impact)
    IF v_lower ~* '(drop(ping)?\s+of\s+subject|leave\s+of\s+absence|filing)' THEN
        event_category := 'administrative';
        friction_domain := NULL;
        trigger_category := NULL;
        affects_ridership := FALSE;
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

        -- Build consolidated ID
        v_consolidated_id := 'EVT-CAL-' || UPPER(v_school_acronym) || '-' || REPLACE(REPLACE(UPPER(COALESCE(v_row.station, 'ALL')), ' ', '-'), '.', '') || '-' || TO_CHAR(v_event_date, 'YYYYMMDD') || '-' || COALESCE(v_row.id, v_count::text);

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
                WHEN v_class.event_category IN ('class_suspension', 'holiday') THEN 1.0
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


-- ============================================================================
-- WORKSTREAM 3: Weather P_idx Normalization Correction
-- Per EventsNormalizationToFrictionIndex.md Step 3a & CFI_Variables.md
-- ============================================================================

-- 3a. Add friction_weight_ref column and rename friction_weight → p_idx
ALTER TABLE external.weather_consolidated ADD COLUMN IF NOT EXISTS friction_weight_ref numeric;

-- Populate friction_weight_ref with the current raw values before we overwrite
UPDATE external.weather_consolidated SET friction_weight_ref = friction_weight WHERE friction_weight_ref IS NULL;

-- Rename column: friction_weight → p_idx (Meteorological Friction)
ALTER TABLE external.weather_consolidated RENAME COLUMN friction_weight TO p_idx;

-- 3b. Update the calculation function to return normalized P_idx scale
-- Per EventsNormalizationToFrictionIndex.md Step 3a:
--   wind_signal == 0 AND rainfall_mm < 5  → P_idx = 0.0 (Clear)
--   wind_signal == 1 OR rainfall_mm > 15  → P_idx = 0.4 (Moderate)
--   wind_signal >= 2 OR rainfall_mm > 40  → P_idx = 0.8 to 1.0 (Severe)
-- Also store the raw friction_weight lookup for traceability.
CREATE OR REPLACE FUNCTION external.calculate_weather_friction(
    p_computed_rainfall_level text,
    p_rainfall_mm numeric,
    p_wind_speed numeric
) RETURNS TABLE (
    p_idx numeric,
    friction_weight_ref numeric
) AS $$
DECLARE
    v_raw_weight numeric;
    v_category text;
    v_p_idx numeric;
    v_wind_signal integer;
    v_rainfall numeric;
    v_rainfall_level text;
BEGIN
    v_rainfall := COALESCE(p_rainfall_mm, 0.0);
    v_rainfall_level := COALESCE(p_computed_rainfall_level, 'None');

    -- Determine PAGASA wind signal from wind speed (km/h)
    IF COALESCE(p_wind_speed, 0) >= 62.0 THEN
        v_wind_signal := 2;  -- Signal No. 2 or higher
    ELSIF COALESCE(p_wind_speed, 0) >= 39.0 THEN
        v_wind_signal := 1;  -- Signal No. 1
    ELSE
        v_wind_signal := 0;  -- No signal
    END IF;

    -- Determine PAGASA category for raw weight lookup
    IF v_wind_signal >= 2 THEN
        v_category := 'Typhoon (High)';
    ELSIF v_wind_signal = 1 THEN
        v_category := 'Typhoon (Low)';
    ELSIF v_rainfall_level = 'Orange' OR v_rainfall_level = 'Red' THEN
        v_category := 'Torrential Rain';
    ELSIF v_rainfall_level = 'Yellow' THEN
        v_category := 'Heavy Rain';
    ELSIF v_rainfall > 0 THEN
        v_category := 'Light/Moderate Rain';
    ELSE
        v_category := 'Clear / Fair';
    END IF;

    -- Fetch raw literature weight for traceability
    SELECT fw.friction_weight INTO v_raw_weight
    FROM external.friction_weight fw
    WHERE fw.friction_domain = 'pagasa' AND fw.trigger_category = v_category
    LIMIT 1;
    v_raw_weight := COALESCE(v_raw_weight, 0.0);

    -- Apply complete normalization per EventsNormalizationToFrictionIndex.md Step 3a with gap resolution:
    IF v_wind_signal >= 2 OR v_rainfall > 40.0 OR v_rainfall_level IN ('Orange', 'Red') THEN
        -- Severe friction: 0.8 to 1.0 (scale to 1.0 if both severe wind and rain occur)
        IF (v_wind_signal >= 2) AND (v_rainfall > 40.0 OR v_rainfall_level IN ('Orange', 'Red')) THEN
            v_p_idx := 1.0;
        ELSE
            v_p_idx := 0.8;
        END IF;
    ELSIF v_wind_signal = 0 AND v_rainfall < 5.0 AND v_rainfall_level = 'None' THEN
        v_p_idx := 0.0;  -- Clear weather, no friction
    ELSE
        v_p_idx := 0.4;  -- Moderate friction (covers wind_signal = 1, rainfall >= 5, or Yellow warning)
    END IF;

    p_idx := v_p_idx;
    friction_weight_ref := v_raw_weight;
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql STABLE;

-- 3c. Update trigger functions to use new return format
CREATE OR REPLACE FUNCTION external.sync_weather_current_to_consolidated()
RETURNS trigger AS $$
DECLARE
    v_result RECORD;
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM external.weather_consolidated WHERE id = 'WTH-CUR-' || REPLACE(REPLACE(UPPER(OLD.station), ' ', '-'), '.', '');
        RETURN OLD;
    ELSE
        SELECT * INTO v_result FROM external.calculate_weather_friction(NEW.computed_rainfall_level, NEW.rainfall_mm, NEW.wind_speed);

        INSERT INTO external.weather_consolidated (
            id, station, weather_date, record_type,
            temperature_temp_max, temp_min, humidity, wind_speed, rainfall_mm,
            computed_rainfall_level, p_idx, friction_weight_ref, observed_or_forecasted_at, updated_at
        )
        VALUES (
            'WTH-CUR-' || REPLACE(REPLACE(UPPER(NEW.station), ' ', '-'), '.', ''),
            NEW.station,
            COALESCE(NEW.observed_at::date, CURRENT_DATE),
            'CURRENT',
            NEW.temperature, NULL, NEW.humidity, NEW.wind_speed, NEW.rainfall_mm,
            NEW.computed_rainfall_level, v_result.p_idx, v_result.friction_weight_ref,
            NEW.observed_at, now()
        )
        ON CONFLICT (id) DO UPDATE SET
            station = EXCLUDED.station,
            weather_date = EXCLUDED.weather_date,
            temperature_temp_max = EXCLUDED.temperature_temp_max,
            humidity = EXCLUDED.humidity,
            wind_speed = EXCLUDED.wind_speed,
            rainfall_mm = EXCLUDED.rainfall_mm,
            computed_rainfall_level = EXCLUDED.computed_rainfall_level,
            p_idx = EXCLUDED.p_idx,
            friction_weight_ref = EXCLUDED.friction_weight_ref,
            observed_or_forecasted_at = EXCLUDED.observed_or_forecasted_at,
            updated_at = now();
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION external.sync_weather_forecasts_to_consolidated()
RETURNS trigger AS $$
DECLARE
    v_result RECORD;
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM external.weather_consolidated WHERE id = REPLACE(OLD.id, 'FCT-', 'WTH-FCT-');
        RETURN OLD;
    ELSE
        SELECT * INTO v_result FROM external.calculate_weather_friction(NEW.computed_rainfall_level, NEW.rainfall_sum_mm, NEW.wind_speed_max);

        INSERT INTO external.weather_consolidated (
            id, station, weather_date, record_type,
            temperature_temp_max, temp_min, humidity, wind_speed, rainfall_mm,
            computed_rainfall_level, p_idx, friction_weight_ref, observed_or_forecasted_at, updated_at
        )
        VALUES (
            REPLACE(NEW.id, 'FCT-', 'WTH-FCT-'),
            NEW.station, NEW.forecast_date, 'FORECAST',
            NEW.temp_max, NEW.temp_min, NEW.humidity_mean, NEW.wind_speed_max, NEW.rainfall_sum_mm,
            NEW.computed_rainfall_level, v_result.p_idx, v_result.friction_weight_ref,
            NEW.fetched_at, now()
        )
        ON CONFLICT (id) DO UPDATE SET
            station = EXCLUDED.station,
            weather_date = EXCLUDED.weather_date,
            temperature_temp_max = EXCLUDED.temperature_temp_max,
            temp_min = EXCLUDED.temp_min,
            humidity = EXCLUDED.humidity,
            wind_speed = EXCLUDED.wind_speed,
            rainfall_mm = EXCLUDED.rainfall_mm,
            computed_rainfall_level = EXCLUDED.computed_rainfall_level,
            p_idx = EXCLUDED.p_idx,
            friction_weight_ref = EXCLUDED.friction_weight_ref,
            observed_or_forecasted_at = EXCLUDED.observed_or_forecasted_at,
            updated_at = now();
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 3d. Recalculate all existing weather rows with proper P_idx normalization
UPDATE external.weather_consolidated wc
SET
    p_idx = calc.p_idx,
    friction_weight_ref = calc.friction_weight_ref
FROM (
    SELECT
        wc2.id,
        (external.calculate_weather_friction(wc2.computed_rainfall_level, wc2.rainfall_mm, wc2.wind_speed)).p_idx,
        (external.calculate_weather_friction(wc2.computed_rainfall_level, wc2.rainfall_mm, wc2.wind_speed)).friction_weight_ref
    FROM external.weather_consolidated wc2
) calc
WHERE wc.id = calc.id;


-- ============================================================================
-- INITIAL BACKFILL
-- ============================================================================

-- Backfill existing academic_lgu_events into events_consolidated
-- (Simulates trigger fire for each existing row)
DO $$
DECLARE
    v_row RECORD;
    v_result RECORD;
    v_weight numeric;
    v_event_date date;
    v_consolidated_id text;
BEGIN
    FOR v_row IN SELECT * FROM external.academic_lgu_events LOOP
        SELECT * INTO v_result
        FROM external.classify_event_from_text(v_row.post_text, v_row.image_text, v_row.category);

        IF v_result.affects_ridership = FALSE OR v_result.affects_ridership IS NULL THEN
            CONTINUE;
        END IF;

        SELECT fw.friction_weight INTO v_weight
        FROM external.friction_weight fw
        WHERE fw.friction_domain = v_result.friction_domain
          AND fw.trigger_category = v_result.trigger_category
        LIMIT 1;
        v_weight := COALESCE(v_weight, 0.0);

        v_event_date := COALESCE(v_row.post_date::date, CURRENT_DATE);
        v_consolidated_id := 'EVT-SCRAPE-' || REPLACE(REPLACE(UPPER(COALESCE(v_row.station, 'ALL')), ' ', '-'), '.', '') || '-' || TO_CHAR(v_event_date, 'YYYYMMDD') || '-' || v_row.id;

        INSERT INTO external.events_consolidated (
            id, station, event_date, source_table, source_id, source_name,
            event_name, event_category, friction_domain, trigger_category,
            normalized_score, friction_weight_ref, updated_at
        )
        VALUES (
            v_consolidated_id,
            COALESCE(v_row.station, 'All Stations'),
            v_event_date,
            'academic_lgu_events',
            v_row.id,
            v_row.source_name,
            v_result.event_name,
            v_result.event_category,
            v_result.friction_domain,
            v_result.trigger_category,
            CASE
                WHEN v_result.event_category IN ('class_suspension', 'holiday') THEN 1.0
                ELSE v_weight
            END,
            v_weight,
            now()
        )
        ON CONFLICT (id) DO NOTHING;
    END LOOP;
END $$;

-- Backfill existing UERM_Academic_Calendar
SELECT external.process_academic_calendar('UERM_Academic_Calendar');
