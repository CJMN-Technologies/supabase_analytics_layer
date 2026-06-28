-- ============================================================================
-- SQL Script: Transform 5-Year Ridership Data to Hourly
-- Classification: Internal Dataset (5-Year AFCS)
-- ============================================================================

-- 3a. Create dynamic transformation procedure
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

-- Execute transformation for each historical year
SELECT external.transform_ridership_table(2021) as rows_2021;
SELECT external.transform_ridership_table(2022) as rows_2022;
SELECT external.transform_ridership_table(2023) as rows_2023;
SELECT external.transform_ridership_table(2024) as rows_2024;
SELECT external.transform_ridership_table(2025) as rows_2025;
