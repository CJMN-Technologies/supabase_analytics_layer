-- ============================================================================
-- SQL Script: Standardize External Datasets Triggers & Classification
-- Classification: External Dataset (Weather consolidated, Events consolidated)
-- ============================================================================

-- 1ad. Station Name Normalization Function to match unpivoted ridership conventions
CREATE OR REPLACE FUNCTION external.normalize_station_name(p_station text)
RETURNS text AS $$
DECLARE
    v_clean text;
BEGIN
    v_clean := UPPER(TRIM(COALESCE(p_station, 'All Stations')));
    
    IF v_clean IN ('ALL', 'ALL STATIONS', 'ALL STATION', '') THEN
        RETURN 'All Stations';
    ELSIF v_clean IN ('RECTO') THEN
        RETURN 'Recto';
    ELSIF v_clean IN ('LEGARDA') THEN
        RETURN 'Legarda';
    ELSIF v_clean IN ('PUREZA') THEN
        RETURN 'Pureza';
    ELSIF v_clean IN ('V. MAPA', 'VMAPA', 'V MAPA') THEN
        RETURN 'V. Mapa';
    ELSIF v_clean IN ('J. RUIZ', 'JRUIZ', 'J RUIZ') THEN
        RETURN 'J. Ruiz';
    ELSIF v_clean IN ('GILMORE') THEN
        RETURN 'Gilmore';
    ELSIF v_clean IN ('BETTY GO-BELMONTE', 'BETTY GO BELMONTE', 'BETTY GO') THEN
        RETURN 'Betty Go-Belmonte';
    ELSIF v_clean IN ('ARANETA CENTER-CUBAO', 'ARANETA CENTER CUBAO', 'ARANETA', 'CUBAO') THEN
        RETURN 'Araneta Center Cubao';
    ELSIF v_clean IN ('ANONAS') THEN
        RETURN 'Anonas';
    ELSIF v_clean IN ('KATIPUNAN') THEN
        RETURN 'Katipunan';
    ELSIF v_clean IN ('SANTOLAN') THEN
        RETURN 'Santolan';
    ELSIF v_clean IN ('MARIKINA-PASIG', 'MARIKINA PASIG', 'MARIKINA') THEN
        RETURN 'Marikina-Pasig';
    ELSIF v_clean IN ('ANTIPOLO') THEN
        RETURN 'Antipolo';
    ELSE
        RETURN INITCAP(p_station);
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Ensure weather_consolidated column is named normalized_score instead of p_idx or friction_weight
DO $$
BEGIN
    -- Rename friction_weight to normalized_score if it exists
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'external' AND table_name = 'weather_consolidated' AND column_name = 'friction_weight'
    ) THEN
        ALTER TABLE external.weather_consolidated RENAME COLUMN friction_weight TO normalized_score;
    END IF;

    -- Rename p_idx to normalized_score if it exists
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'external' AND table_name = 'weather_consolidated' AND column_name = 'p_idx'
    ) THEN
        ALTER TABLE external.weather_consolidated RENAME COLUMN p_idx TO normalized_score;
    END IF;

    -- Add event_category and trigger_category columns if they do not exist
    ALTER TABLE external.weather_consolidated ADD COLUMN IF NOT EXISTS event_category text;
    ALTER TABLE external.weather_consolidated ADD COLUMN IF NOT EXISTS trigger_category text;
END $$;

-- 2a. Update weather calculation function
DROP FUNCTION IF EXISTS external.calculate_weather_friction(text, numeric, numeric) CASCADE;
CREATE OR REPLACE FUNCTION external.calculate_weather_friction(
    p_computed_rainfall_level text,
    p_rainfall_mm numeric,
    p_wind_speed numeric
) RETURNS TABLE (
    normalized_score numeric,
    friction_weight_ref numeric,
    trigger_category text
) AS $$
DECLARE
    v_raw_weight numeric;
    v_category text;
    v_normalized_score numeric;
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
 
    -- Fetch raw literature weight (SCD Type 1 lookup by category)
    SELECT fw.friction_weight INTO v_raw_weight
    FROM external.friction_weight fw
    WHERE fw.friction_domain = 'pagasa' AND fw.trigger_category = v_category
    LIMIT 1;
    v_raw_weight := COALESCE(v_raw_weight, 0.0);
 
    -- Apply complete normalization per EventsNormalizationToFrictionIndex.md Step 3a with gap resolution:
    IF v_wind_signal >= 2 OR v_rainfall > 40.0 OR v_rainfall_level IN ('Orange', 'Red') THEN
        IF (v_wind_signal >= 2) AND (v_rainfall > 40.0 OR v_rainfall_level IN ('Orange', 'Red')) THEN
            v_normalized_score := 1.0;
        ELSE
            v_normalized_score := 0.8;
        END IF;
    ELSIF v_wind_signal = 0 AND v_rainfall < 5.0 AND v_rainfall_level = 'None' THEN
        v_normalized_score := 0.0;
    ELSE
        v_normalized_score := 0.4;
    END IF;
 
    normalized_score := v_normalized_score;
    friction_weight_ref := v_raw_weight;
    trigger_category := v_category;
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql STABLE;
 
-- 2b. Re-deploy weather triggers to ensure clean compiling
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
            computed_rainfall_level, normalized_score, friction_weight_ref, event_category, trigger_category, observed_or_forecasted_at, updated_at
        )
        VALUES (
            'WTH-CUR-' || REPLACE(REPLACE(UPPER(NEW.station), ' ', '-'), '.', ''),
            NEW.station,
            COALESCE(NEW.observed_at::date, CURRENT_DATE),
            'CURRENT',
            NEW.temperature, NULL, NEW.humidity, NEW.wind_speed, NEW.rainfall_mm,
            NEW.computed_rainfall_level, v_result.normalized_score, v_result.friction_weight_ref,
            'weather_advisory', v_result.trigger_category, NEW.observed_at, now()
        )
        ON CONFLICT (id) DO UPDATE SET
            station = EXCLUDED.station,
            weather_date = EXCLUDED.weather_date,
            temperature_temp_max = EXCLUDED.temperature_temp_max,
            humidity = EXCLUDED.humidity,
            wind_speed = EXCLUDED.wind_speed,
            rainfall_mm = EXCLUDED.rainfall_mm,
            computed_rainfall_level = EXCLUDED.computed_rainfall_level,
            normalized_score = EXCLUDED.normalized_score,
            friction_weight_ref = EXCLUDED.friction_weight_ref,
            event_category = EXCLUDED.event_category,
            trigger_category = EXCLUDED.trigger_category,
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
            computed_rainfall_level, normalized_score, friction_weight_ref, event_category, trigger_category, observed_or_forecasted_at, updated_at
        )
        VALUES (
            REPLACE(NEW.id, 'FCT-', 'WTH-FCT-'),
            NEW.station, NEW.forecast_date, 'FORECAST',
            NEW.temp_max, NEW.temp_min, NEW.humidity_mean, NEW.wind_speed_max, NEW.rainfall_sum_mm,
            NEW.computed_rainfall_level, v_result.normalized_score, v_result.friction_weight_ref,
            'weather_advisory', v_result.trigger_category, NEW.fetched_at, now()
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
            normalized_score = EXCLUDED.normalized_score,
            friction_weight_ref = EXCLUDED.friction_weight_ref,
            event_category = EXCLUDED.event_category,
            trigger_category = EXCLUDED.trigger_category,
            observed_or_forecasted_at = EXCLUDED.observed_or_forecasted_at,
            updated_at = now();
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Recalculate existing weather rows with the new event_category and trigger_category
UPDATE external.weather_consolidated wc
SET
    normalized_score = calc.normalized_score,
    friction_weight_ref = calc.friction_weight_ref,
    event_category = 'weather_advisory',
    trigger_category = calc.trigger_category
FROM (
    SELECT
        wc2.id,
        (external.calculate_weather_friction(wc2.computed_rainfall_level, wc2.rainfall_mm, wc2.wind_speed)).normalized_score,
        (external.calculate_weather_friction(wc2.computed_rainfall_level, wc2.rainfall_mm, wc2.wind_speed)).friction_weight_ref,
        (external.calculate_weather_friction(wc2.computed_rainfall_level, wc2.rainfall_mm, wc2.wind_speed)).trigger_category
    FROM external.weather_consolidated wc2
) calc
WHERE wc.id = calc.id;

-- 2c. Update classify_event_from_text (standardized scraped IDs)
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
 
-- 2d. Update event sync trigger function to use the new friction_weight lookup
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
 
    -- Look up the literature friction weight (SCD Type 1 lookup)
    SELECT fw.friction_weight INTO v_weight
    FROM external.friction_weight fw
    WHERE fw.friction_domain = v_result.friction_domain 
      AND fw.trigger_category = v_result.trigger_category
    LIMIT 1;
    v_weight := COALESCE(v_weight, 0.0);
 
    v_event_date := COALESCE(NEW.post_date::date, CURRENT_DATE);
 
    -- Format a cleaner, shorter scrape ID
    v_cat_code := CASE v_result.event_category
        WHEN 'class_suspension' THEN 'CS'
        WHEN 'transport_strike' THEN 'TS'
        WHEN 'major_event' THEN 'ME'
        WHEN 'exam_week' THEN 'EX'
        ELSE 'RC'
    END;
    -- Structured ID: SCR-[CAT]-[MMDD]-[RAW_ID]
    v_scrape_id := 'SCR-' || v_cat_code || '-' || TO_CHAR(v_event_date, 'MMDD') || '-' || NEW.id;
 
    INSERT INTO external.events_consolidated (
        id, station, event_date, source_table, source_id, source_name,
        event_name, event_category, friction_domain, trigger_category,
        normalized_score, friction_weight_ref, updated_at
    )
    VALUES (
        v_scrape_id,
        external.normalize_station_name(COALESCE(NEW.station, 'All Stations')),
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
 
-- 2d_2. Define classify_calendar_event with separate School Break category
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
 
-- 2e. Update process_academic_calendar function to use correct weight lookups
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
 
    FOR v_row IN EXECUTE format(
        'SELECT id, station, source_name, event_date, event_name, category FROM external.%I',
        p_table_name
    ) LOOP
        SELECT * INTO v_class
        FROM external.classify_calendar_event(v_row.event_name);
 
        IF v_class.affects_ridership = FALSE OR v_class.affects_ridership IS NULL THEN
            CONTINUE;
        END IF;
 
        -- Look up weight
        SELECT fw.friction_weight INTO v_weight
        FROM external.friction_weight fw
        WHERE fw.friction_domain = v_class.friction_domain
          AND fw.trigger_category = v_class.trigger_category
        LIMIT 1;
        v_weight := COALESCE(v_weight, 0.0);
 
        BEGIN
            v_event_date := v_row.event_date::date;
        EXCEPTION WHEN OTHERS THEN
            v_event_date := CURRENT_DATE;
        END;
 
        -- Simple ID: CAL-[SCH]-[MMDD]-[ROW_ID]
        v_consolidated_id := 'CAL-' || UPPER(v_school_acronym) || '-' || TO_CHAR(v_event_date, 'MMDD') || '-' || COALESCE(v_row.id, v_count::text);
 
        INSERT INTO external.events_consolidated (
            id, station, event_date, source_table, source_id, source_name,
            event_name, event_category, friction_domain, trigger_category,
            normalized_score, friction_weight_ref, updated_at
        )
        VALUES (
            v_consolidated_id,
            external.normalize_station_name(COALESCE(v_row.station, 'All Stations')),
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
 
    INSERT INTO external.processed_calendar_tables (table_name, rows_processed, last_processed_at)
    VALUES (p_table_name, v_count, now())
    ON CONFLICT (table_name) DO UPDATE SET
        rows_processed = v_count,
        last_processed_at = now();
 
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- 2f. Polling function: scan for new *_Academic_Calendar tables
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

-- 2a. Tracking table for processed calendar tables
CREATE TABLE IF NOT EXISTS external.processed_calendar_tables (
    table_name text PRIMARY KEY,
    rows_processed integer DEFAULT 0,
    last_processed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- Recalculate A_sw (Academic Surge Weight) dynamically on events_consolidated
-- ============================================================================
 
CREATE OR REPLACE FUNCTION external.recalculate_asw_score()
RETURNS trigger AS $$
DECLARE
    v_station text;
    v_date date;
    v_count integer;
    v_asw numeric;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_station := OLD.station;
        v_date := OLD.event_date;
    ELSE
        v_station := NEW.station;
        v_date := NEW.event_date;
    END IF;
 
    -- Count all major events on this day and station
    SELECT COUNT(*) INTO v_count
    FROM external.events_consolidated
    WHERE station = v_station
      AND event_date = v_date
      AND event_category = 'major_event';
 
    -- Step 3b logic: count = 0 -> 0.0; count = 1 -> 0.5; count >= 3 -> 1.0; count = 2 -> 0.5
    IF v_count >= 3 THEN
        v_asw := 1.0;
    ELSIF v_count >= 1 THEN
        v_asw := 0.5;
    ELSE
        v_asw := 0.0;
    END IF;
 
    -- Update all major events on this day and station to the correct score
    -- Prevent infinite recursion by ensuring normalized_score is DISTINCT FROM v_asw
    UPDATE external.events_consolidated
    SET normalized_score = v_asw
    WHERE station = v_station
      AND event_date = v_date
      AND event_category = 'major_event'
      AND normalized_score IS DISTINCT FROM v_asw;
 
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
 
DROP TRIGGER IF EXISTS tg_recalculate_asw ON external.events_consolidated;
CREATE TRIGGER tg_recalculate_asw
AFTER INSERT OR UPDATE OR DELETE ON external.events_consolidated
FOR EACH ROW
EXECUTE FUNCTION external.recalculate_asw_score();
 
-- ============================================================================
-- Re-evaluate and rebuild events_consolidated to apply new classifier and A_sw logic
-- ============================================================================
 
TRUNCATE TABLE external.events_consolidated;
 
-- 1. Backfill academic_lgu_events
DO $$
DECLARE
    v_row RECORD;
    v_result RECORD;
    v_weight numeric;
    v_event_date date;
    v_scrape_id text;
    v_cat_code text;
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
        
        v_cat_code := CASE v_result.event_category
            WHEN 'class_suspension' THEN 'CS'
            WHEN 'transport_strike' THEN 'TS'
            WHEN 'major_event' THEN 'ME'
            WHEN 'exam_week' THEN 'EX'
            ELSE 'RC'
        END;
        v_scrape_id := 'SCR-' || v_cat_code || '-' || TO_CHAR(v_event_date, 'MMDD') || '-' || v_row.id;
 
        INSERT INTO external.events_consolidated (
            id, station, event_date, source_table, source_id, source_name,
            event_name, event_category, friction_domain, trigger_category,
            normalized_score, friction_weight_ref, updated_at
        )
        VALUES (
            v_scrape_id,
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
    END LOOP;
END $$;
 
-- 2. Reprocess academic calendars
TRUNCATE TABLE external.processed_calendar_tables;
SELECT external.scan_and_process_new_calendars();
