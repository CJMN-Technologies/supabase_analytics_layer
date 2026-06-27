-- ============================================================================
-- SQL Script: Dimension Re-standardization (SCD Type 1) & Dynamic Ridership Ingestion
-- ============================================================================

-- ============================================================================
-- WORKSTREAM 1: Re-standardize Dimensions to SCD Type 1 & Simplified IDs
-- ============================================================================

-- 1a. Rename tables to backup (linage preservation) using conditional execution
DO $$
BEGIN
  -- APTA
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'APTA' AND table_name = 'apta_protocols')
     AND NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'APTA' AND table_name = 'apta_protocols_backup') THEN
     ALTER TABLE "APTA".apta_protocols RENAME TO apta_protocols_backup;
  END IF;

  -- PSOR
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'PSOR' AND table_name = 'psor_incidents')
     AND NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'PSOR' AND table_name = 'psor_incidents_backup') THEN
     ALTER TABLE "PSOR".psor_incidents RENAME TO psor_incidents_backup;
  END IF;

  -- Station Capacity
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'Station Capacity' AND table_name = 'station_platform_capacity')
     AND NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'Station Capacity' AND table_name = 'station_platform_capacity_backup') THEN
     ALTER TABLE "Station Capacity".station_platform_capacity RENAME TO station_platform_capacity_backup;
  END IF;

  -- external.friction_weight
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'external' AND table_name = 'friction_weight')
     AND NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'external' AND table_name = 'friction_weight_backup') THEN
     ALTER TABLE "external".friction_weight RENAME TO friction_weight_backup;
  END IF;
END $$;

-- 1b. Recreate dimension tables with simplified IDs as Primary Keys
DROP TABLE IF EXISTS "APTA".apta_protocols;
CREATE TABLE "APTA".apta_protocols (
    id text PRIMARY KEY,
    apta_standard_code text NOT NULL,
    official_document_title text NOT NULL,
    scope_relevance_to_surge_management text NOT NULL,
    human_centric_ground_tactics text NOT NULL,
    open_access_link_source text NOT NULL,
    load_timestamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

DROP TABLE IF EXISTS "PSOR".psor_incidents;
CREATE TABLE "PSOR".psor_incidents (
    id text PRIMARY KEY,
    category text NOT NULL,
    specific_incident_transgression text NOT NULL,
    load_timestamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

DROP TABLE IF EXISTS "Station Capacity".station_platform_capacity;
CREATE TABLE "Station Capacity".station_platform_capacity (
    id text PRIMARY KEY,
    station_name text NOT NULL,
    platform_design text NOT NULL,
    directional_usable_area_m2 numeric,
    directional_platform_limit_pax integer,
    total_concourse_limit_pax integer,
    total_station_limit_pax integer,
    load_timestamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

DROP TABLE IF EXISTS "external".friction_weight;
CREATE TABLE "external".friction_weight (
    id text PRIMARY KEY,
    friction_domain text NOT NULL,
    trigger_category text NOT NULL,
    specific_condition_api_input text NOT NULL,
    friction_weight numeric NOT NULL CHECK (friction_weight >= 0 AND friction_weight <= 1),
    ncr_literature_source_basis text NOT NULL,
    open_access_link text NOT NULL,
    load_timestamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- 1c. Populate new tables from backup tables using simplified ID formats
INSERT INTO "APTA".apta_protocols (id, apta_standard_code, official_document_title, scope_relevance_to_surge_management, human_centric_ground_tactics, open_access_link_source, load_timestamp)
SELECT 
  'APTA-' || LPAD((row_number() OVER (ORDER BY load_timestamp, apta_standard_code))::text, 2, '0') as id,
  apta_standard_code, official_document_title, scope_relevance_to_surge_management, human_centric_ground_tactics, open_access_link_source, load_timestamp
FROM "APTA".apta_protocols_backup;

INSERT INTO "PSOR".psor_incidents (id, category, specific_incident_transgression, load_timestamp)
SELECT 
  'PSOR-' || LPAD((row_number() OVER (ORDER BY load_timestamp, specific_incident_transgression))::text, 2, '0') as id,
  category, specific_incident_transgression, load_timestamp
FROM "PSOR".psor_incidents_backup;

INSERT INTO "Station Capacity".station_platform_capacity (id, station_name, platform_design, directional_usable_area_m2, directional_platform_limit_pax, total_concourse_limit_pax, total_station_limit_pax, load_timestamp)
SELECT 
  CASE UPPER(TRIM(station_name))
    WHEN 'RECTO' THEN 'CAP-REC'
    WHEN 'LEGARDA' THEN 'CAP-LEG'
    WHEN 'PUREZA' THEN 'CAP-PUR'
    WHEN 'V. MAPA' THEN 'CAP-VMA'
    WHEN 'J. RUIZ' THEN 'CAP-JRU'
    WHEN 'GILMORE' THEN 'CAP-GIL'
    WHEN 'BETTY GO-BELMONTE' THEN 'CAP-BET'
    WHEN 'ARANETA CENTER-CUBAO' THEN 'CAP-CUB'
    WHEN 'ANONAS' THEN 'CAP-ANO'
    WHEN 'KATIPUNAN' THEN 'CAP-KAT'
    WHEN 'SANTOLAN' THEN 'CAP-SAN'
    WHEN 'MARIKINA-PASIG' THEN 'CAP-MAR'
    WHEN 'ANTIPOLO' THEN 'CAP-ANT'
    ELSE 'CAP-' || UPPER(LEFT(REPLACE(station_name, ' ', ''), 3))
  END as id,
  station_name, platform_design, directional_usable_area_m2, directional_platform_limit_pax, total_concourse_limit_pax, total_station_limit_pax, load_timestamp
FROM "Station Capacity".station_platform_capacity_backup;

INSERT INTO "external".friction_weight (id, friction_domain, trigger_category, specific_condition_api_input, friction_weight, ncr_literature_source_basis, open_access_link, load_timestamp)
SELECT 
  'FRI-' || 
  CASE LOWER(friction_domain)
    WHEN 'academic' THEN 'AC'
    WHEN 'pagasa' THEN 'PA'
    WHEN 'operational' THEN 'OP'
    ELSE 'XX'
  END || 
  LPAD((row_number() OVER (PARTITION BY friction_domain ORDER BY load_timestamp, trigger_category))::text, 2, '0') as id,
  friction_domain, trigger_category, specific_condition_api_input, friction_weight, ncr_literature_source_basis, open_access_link, load_timestamp
FROM "external".friction_weight_backup;


-- ============================================================================
-- WORKSTREAM 2: Update Triggers and Lookups to Support Standardized IDs
-- ============================================================================

-- 2a. Update weather calculation function
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

    -- Fetch raw literature weight (SCD Type 1 lookup by category)
    SELECT fw.friction_weight INTO v_raw_weight
    FROM external.friction_weight fw
    WHERE fw.friction_domain = 'pagasa' AND fw.trigger_category = v_category
    LIMIT 1;
    v_raw_weight := COALESCE(v_raw_weight, 0.0);

    -- Apply complete normalization per EventsNormalizationToFrictionIndex.md Step 3a with gap resolution:
    IF v_wind_signal >= 2 OR v_rainfall > 40.0 OR v_rainfall_level IN ('Orange', 'Red') THEN
        IF (v_wind_signal >= 2) AND (v_rainfall > 40.0 OR v_rainfall_level IN ('Orange', 'Red')) THEN
            v_p_idx := 1.0;
        ELSE
            v_p_idx := 0.8;
        END IF;
    ELSIF v_wind_signal = 0 AND v_rainfall < 5.0 AND v_rainfall_level = 'None' THEN
        v_p_idx := 0.0;
    ELSE
        v_p_idx := 0.4;
    END IF;

    p_idx := v_p_idx;
    friction_weight_ref := v_raw_weight;
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

    IF v_combined ~* '(typhoon|tropical\s+cyclone|signal\s+no|rainfall\s+warning|heavy\s+rain(shower)?s?\s+(warning|advisory)|thunderstorm\s+advisory|flood\s+advisory|habagat|southwest\s+monsoon|weather\s+advisory)' THEN
        event_name := 'Weather Advisory'; event_category := 'weather_advisory'; friction_domain := 'pagasa'; trigger_category := NULL; affects_ridership := FALSE;
        RETURN NEXT; RETURN;
    END IF;

    IF v_combined ~* '(road\s+repair|drainage|infrastructure|kalsada|sirang\s+kalsada|construction|asphalting)'
       AND NOT v_combined ~* '(suspend|pasok|class|exam)' THEN
        event_name := 'Infrastructure Notice'; event_category := 'infrastructure'; friction_domain := NULL; trigger_category := NULL; affects_ridership := FALSE;
        RETURN NEXT; RETURN;
    END IF;

    IF v_combined ~* '(class(es)?\s+(and\s+office\s+)?(operations?\s+)?(will\s+be\s+|are\s+|is\s+)?suspend|suspend(ed|ing)?\s+(class|office)|walang\s+pasok|no\s+class|non[- ]?working\s+(day|holiday)|special\s+(non[- ]?working|public)\s+(day|holiday)|regular\s+holiday|araw\s+ng|founding\s+anniversary|holiday)' THEN
        event_name := 'Class Suspension / Holiday'; event_category := 'class_suspension'; friction_domain := 'academic'; trigger_category := 'Mid-Day Class Suspension'; affects_ridership := TRUE;
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

    INSERT INTO external.processed_calendar_tables (table_name, rows_processed, last_processed_at)
    VALUES (p_table_name, v_count, now())
    ON CONFLICT (table_name) DO UPDATE SET
        rows_processed = v_count,
        last_processed_at = now();

    RETURN v_count;
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- WORKSTREAM 3: Dynamic Ridership Transformation Procedure & Scheduler
-- ============================================================================

-- -- 3a. Create dynamic transformation procedure
CREATE OR REPLACE FUNCTION external.transform_ridership_table(p_year integer)
RETURNS integer AS $$
DECLARE
    v_table_name text;
    v_backup_table text;
    v_entry_cols text[];
    v_exit_cols text[];
    v_col text;
    v_sum_so_far text;
    v_sum_prev text;
    v_select_fields text := '';
    v_all_station_cols_str text := '';
    v_entry_coalesce_str text;
    v_exit_coalesce_str text;
    v_dml text;
    v_count integer := 0;
BEGIN
    v_table_name := 'ridership_' || p_year;
    v_backup_table := v_table_name || '_backup';

    -- 1. Verify source raw table exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'AFCS' AND table_name = v_table_name
    ) THEN
        RAISE EXCEPTION 'Rule Violation: Source table % does not exist in schema AFCS.', v_table_name;
    END IF;

    -- 2. Preserve lineage: rename original to _backup if it hasn't been renamed yet
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'AFCS' AND table_name = v_backup_table
    ) THEN
        EXECUTE format('ALTER TABLE "AFCS".%I RENAME TO %I', v_table_name, v_backup_table);
    END IF;

    -- 3. Discover entry/exit columns dynamically from backup
    SELECT array_agg(column_name::text ORDER BY ordinal_position) INTO v_entry_cols
    FROM information_schema.columns
    WHERE table_schema = 'AFCS' AND table_name = v_backup_table AND column_name LIKE '%_entry' AND column_name NOT IN ('total_entry', 'entry_entry', 'exit_entry');

    SELECT array_agg(column_name::text ORDER BY ordinal_position) INTO v_exit_cols
    FROM information_schema.columns
    WHERE table_schema = 'AFCS' AND table_name = v_backup_table AND column_name LIKE '%_exit' AND column_name NOT IN ('total_exit', 'entry_exit', 'exit_exit');

    -- 4. Create clean destination table matching schema
    EXECUTE format('DROP TABLE IF EXISTS "AFCS".%I', v_table_name);
    
    v_dml := format('CREATE TABLE "AFCS".%I (
        id text PRIMARY KEY,
        date date,
        time_period text,', v_table_name);
    
    FOR i IN 1..cardinality(v_entry_cols) LOOP
        v_dml := v_dml || format(' %I integer, %I integer,', v_entry_cols[i], v_exit_cols[i]);
    END LOOP;

    v_dml := v_dml || ' total_entry integer, total_exit integer, load_timestamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP);';
    EXECUTE v_dml;

    -- 5. Build coalesce sum strings for entries and exits
    SELECT array_to_string(array_agg('COALESCE(' || col || ', 0)'), ' + ') INTO v_entry_coalesce_str
    FROM unnest(v_entry_cols) as col;

    SELECT array_to_string(array_agg('COALESCE(' || col || ', 0)'), ' + ') INTO v_exit_coalesce_str
    FROM unnest(v_exit_cols) as col;

    -- 6. Build interleaved SELECT fields (with double-layered cumulative rounding)
    FOR i IN 1..cardinality(v_entry_cols) LOOP
        -- Entry column
        v_col := v_entry_cols[i];
        IF i < cardinality(v_entry_cols) THEN
            v_sum_so_far := '';
            FOR j IN 1..i LOOP
                v_sum_so_far := v_sum_so_far || 'COALESCE(' || v_entry_cols[j] || ', 0) + ';
            END LOOP;
            v_sum_so_far := rtrim(v_sum_so_far, ' + ');

            IF i = 1 THEN
                v_select_fields := v_select_fields || format('  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(%I, 0))::double precision / c_ent_sum)::integer ELSE 0 END as %I,', v_col, v_col) || E'\n';
            ELSE
                v_sum_prev := '';
                FOR j IN 1..i-1 LOOP
                    v_sum_prev := v_sum_prev || 'COALESCE(' || v_entry_cols[j] || ', 0) + ';
                END LOOP;
                v_sum_prev := rtrim(v_sum_prev, ' + ');
                v_select_fields := v_select_fields || format('  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (%s)::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (%s)::double precision / c_ent_sum)::integer ELSE 0 END as %I,', v_sum_so_far, v_sum_prev, v_col) || E'\n';
            END IF;
        ELSE
            -- Remainder for last entry column
            v_sum_prev := '';
            FOR j IN 1..cardinality(v_entry_cols)-1 LOOP
                v_sum_prev := v_sum_prev || 'COALESCE(' || v_entry_cols[j] || ', 0) + ';
            END LOOP;
            v_sum_prev := rtrim(v_sum_prev, ' + ');
            v_select_fields := v_select_fields || format('  hr_total_entry - (CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (%s)::double precision / c_ent_sum)::integer ELSE 0 END) as %I,', v_sum_prev, v_col) || E'\n';
        END IF;

        -- Exit column
        v_col := v_exit_cols[i];
        IF i < cardinality(v_exit_cols) THEN
            v_sum_so_far := '';
            FOR j IN 1..i LOOP
                v_sum_so_far := v_sum_so_far || 'COALESCE(' || v_exit_cols[j] || ', 0) + ';
            END LOOP;
            v_sum_so_far := rtrim(v_sum_so_far, ' + ');

            IF i = 1 THEN
                v_select_fields := v_select_fields || format('  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(%I, 0))::double precision / c_ext_sum)::integer ELSE 0 END as %I,', v_col, v_col) || E'\n';
            ELSE
                v_sum_prev := '';
                FOR j IN 1..i-1 LOOP
                    v_sum_prev := v_sum_prev || 'COALESCE(' || v_exit_cols[j] || ', 0) + ';
                END LOOP;
                v_sum_prev := rtrim(v_sum_prev, ' + ');
                v_select_fields := v_select_fields || format('  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (%s)::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (%s)::double precision / c_ext_sum)::integer ELSE 0 END as %I,', v_sum_so_far, v_sum_prev, v_col) || E'\n';
            END IF;
        ELSE
            -- Remainder for last exit column
            v_sum_prev := '';
            FOR j IN 1..cardinality(v_exit_cols)-1 LOOP
                v_sum_prev := v_sum_prev || 'COALESCE(' || v_exit_cols[j] || ', 0) + ';
            END LOOP;
            v_sum_prev := rtrim(v_sum_prev, ' + ');
            v_select_fields := v_select_fields || format('  hr_total_exit - (CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (%s)::double precision / c_ext_sum)::integer ELSE 0 END) as %I', v_sum_prev, v_col);
        END IF;
    END LOOP;

    -- Build column string lists
    FOR i IN 1..cardinality(v_entry_cols) LOOP
        v_all_station_cols_str := v_all_station_cols_str || v_entry_cols[i] || ', ' || v_exit_cols[i] || ', ';
    END LOOP;
    v_all_station_cols_str := rtrim(v_all_station_cols_str, ', ');

    -- 7. Insert hourly expanded rows
    v_dml := format('
      WITH hour_weights (band, time_period, seq, weight, cum_weight, cum_weight_prev) AS (
        VALUES
          (''5-7am (OFF PEAK)'',   ''05:00'', 1, 0.294976632537090, 0.294976632537090, 0.0),
          (''5-7am (OFF PEAK)'',   ''06:00'', 2, 0.705023367462910, 1.0,               0.294976632537090),
          (''7-9am (AM PEAK)'',    ''07:00'', 1, 0.544024908634851, 0.544024908634851, 0.0),
          (''7-9am (AM PEAK)'',    ''08:00'', 2, 0.455975091365149, 1.0,               0.544024908634851),
          (''9am-5pm (OFF PEAK)'', ''09:00'', 1, 0.115810405840533, 0.115810405840533, 0.0),
          (''9am-5pm (OFF PEAK)'', ''10:00'', 2, 0.109552336053815, 0.225362741894348, 0.115810405840533),
          (''9am-5pm (OFF PEAK)'', ''11:00'', 3, 0.112527198170051, 0.337889940064399, 0.225362741894348),
          (''9am-5pm (OFF PEAK)'', ''12:00'', 4, 0.125297635652118, 0.463187575716517, 0.337889940064399),
          (''9am-5pm (OFF PEAK)'', ''13:00'', 5, 0.122739214381356, 0.585926790097873, 0.463187575716517),
          (''9am-5pm (OFF PEAK)'', ''14:00'', 6, 0.122510819491823, 0.708437609589696, 0.585926790097873),
          (''9am-5pm (OFF PEAK)'', ''15:00'', 7, 0.133837412726751, 0.842275022316447, 0.708437609589696),
          (''9am-5pm (OFF PEAK)'', ''16:00'', 8, 0.157724977683553, 1.0,               0.842275022316447),
          (''5-7pm (PM PEAK)'',    ''17:00'', 1, 0.514927690590153, 0.514927690590153, 0.0),
          (''5-7pm (PM PEAK)'',    ''18:00'', 2, 0.485072309409847, 1.0,               0.514927690590153),
          (''7-10pm (OFF PEAK)'',  ''19:00'', 1, 0.511999956428162, 0.511999956428162, 0.0),
          (''7-10pm (OFF PEAK)'',  ''20:00'', 2, 0.367992309570645, 0.879992265998807, 0.511999956428162),
          (''7-10pm (OFF PEAK)'',  ''21:00'', 3, 0.120007734001193, 1.0,               0.879992265998807)
      ),
      base_rows AS (
        SELECT
          r.*,
          (%s) as c_ent_sum,
          (%s) as c_ext_sum
        FROM "AFCS".%I r
        WHERE r.time_period NOT IN (''Daily Total'', ''Monthly Total'', ''Peak Total'') AND r.time_period NOT LIKE ''__:__-__:__''
      ),
      hourly_distributed_totals AS (
        SELECT
          b.*,
          w.time_period as hr_period,
          COALESCE(ROUND(b.total_entry * w.cum_weight)::int - ROUND(b.total_entry * w.cum_weight_prev)::int, 0) as hr_total_entry,
          COALESCE(ROUND(b.total_exit * w.cum_weight)::int - ROUND(b.total_exit * w.cum_weight_prev)::int, 0) as hr_total_exit
        FROM base_rows b
        JOIN hour_weights w ON b.time_period = w.band
      )
      INSERT INTO "AFCS".%I (
        id, date, time_period,
        %s,
        total_entry, total_exit, load_timestamp
      )
      SELECT
        ''YR'' || %s || ''-'' || TO_CHAR(date, ''MMDD'') || ''-'' || LEFT(hr_period, 2) as id,
        date, hr_period,
        %s,
        hr_total_entry, hr_total_exit, CURRENT_TIMESTAMP
      FROM hourly_distributed_totals
    ',
      v_entry_coalesce_str,
      v_exit_coalesce_str,
      v_backup_table,
      v_table_name,
      v_all_station_cols_str,
      to_char(to_date(p_year::text, 'YYYY'), 'YY'),
      v_select_fields
    );
    EXECUTE v_dml;

    -- 8. Copy pre-existing true hourly rows (like June/Nov 1st in 2023)
    EXECUTE format('
      INSERT INTO "AFCS".%I (
        id, date, time_period,
        %s,
        total_entry, total_exit, load_timestamp
      )
      SELECT
        ''YR'' || %s || ''-'' || TO_CHAR(date, ''MMDD'') || ''-'' || LEFT(time_period, 2) as id,
        date, LEFT(time_period, 5),
        %s,
        total_entry, total_exit, CURRENT_TIMESTAMP
      FROM "AFCS".%I
      WHERE time_period LIKE ''__:__-__:__''
    ',
      v_table_name,
      v_all_station_cols_str,
      to_char(to_date(p_year::text, 'YYYY'), 'YY'),
      v_all_station_cols_str,
      v_backup_table
    );

    -- 9. Insert Daily Totals with simplified format: YR[YY]-[MMDD]-DT
    EXECUTE format('
      INSERT INTO "AFCS".%I (
        id, date, time_period,
        %s,
        total_entry, total_exit, load_timestamp
      )
      SELECT
        ''YR'' || %s || ''-'' || TO_CHAR(date, ''MMDD'') || ''-DT'' as id,
        date,
        ''DAILY_TOTAL'' as time_period,
        %s,
        total_entry, total_exit, CURRENT_TIMESTAMP
      FROM "AFCS".%I
      WHERE time_period = ''Daily Total''
    ',
      v_table_name,
      v_all_station_cols_str,
      to_char(to_date(p_year::text, 'YYYY'), 'YY'),
      v_all_station_cols_str,
      v_backup_table
    );

    -- 10. Insert other aggregates (Monthly/Peak Totals for 2023) with format: YR[YY]-[MM]-MT/PT
    EXECUTE format('
      INSERT INTO "AFCS".%I (
        id, date, time_period,
        %s,
        total_entry, total_exit, load_timestamp
      )
      SELECT
        ''YR'' || %s || ''-'' || TO_CHAR(date, ''MM'') || ''-'' || 
        CASE 
          WHEN time_period = ''Monthly Total'' THEN ''MT''
          WHEN time_period = ''Peak Total'' THEN ''PT''
        END as id,
        date,
        CASE 
          WHEN time_period = ''Monthly Total'' THEN ''MONTHLY_TOTAL''
          WHEN time_period = ''Peak Total'' THEN ''PEAK_TOTAL''
        END as time_period,
        %s,
        total_entry, total_exit, CURRENT_TIMESTAMP
      FROM "AFCS".%I
      WHERE time_period IN (''Monthly Total'', ''Peak Total'')
    ',
      v_table_name,
      v_all_station_cols_str,
      to_char(to_date(p_year::text, 'YYYY'), 'YY'),
      v_all_station_cols_str,
      v_backup_table
    );

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- 3b. Create scan and transform polling function
CREATE OR REPLACE FUNCTION external.scan_and_transform_new_ridership_tables()
RETURNS text AS $$
DECLARE
    v_table RECORD;
    v_year integer;
    v_processed integer;
    v_results text := '';
BEGIN
    FOR v_table IN
        -- Find tables named ridership_YYYY where no ridership_YYYY_backup exists yet
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = 'AFCS'
          AND table_name ~ '^ridership_\d{4}$'
          AND (table_name || '_backup') NOT IN (
              SELECT table_name 
              FROM information_schema.tables 
              WHERE table_schema = 'AFCS'
          )
        ORDER BY table_name
    LOOP
        v_year := SUBSTRING(v_table.table_name FROM 11)::integer;
        v_processed := external.transform_ridership_table(v_year);
        v_results := v_results || v_table.table_name || ' processed. ';
    END LOOP;

    IF v_results = '' THEN
        RETURN 'No new Ridership tables to transform.';
    END IF;

    RETURN v_results;
END;
$$ LANGUAGE plpgsql;
