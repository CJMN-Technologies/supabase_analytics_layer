-- ============================================================
-- SQL Script: Re-aggregate Active Hourly Tables to Backup Tables
-- Schema: AFCS
-- Targets: ridership_2021_backup to ridership_2025_backup
-- ============================================================

-- Restore 2021 Backup
DROP TABLE IF EXISTS "AFCS".ridership_2021_backup;
CREATE TABLE "AFCS".ridership_2021_backup (
  id text PRIMARY KEY,
  date date,
  time_period text,
  anonas_entry integer, anonas_exit integer,
  antipolo_entry integer, antipolo_exit integer,
  araneta_center_cubao_entry integer, araneta_center_cubao_exit integer,
  betty_go_belmonte_entry integer, betty_go_belmonte_exit integer,
  gilmore_entry integer, gilmore_exit integer,
  j_ruiz_entry integer, j_ruiz_exit integer,
  katipunan_entry integer, katipunan_exit integer,
  legarda_entry integer, legarda_exit integer,
  marikina_pasig_entry integer, marikina_pasig_exit integer,
  pureza_entry integer, pureza_exit integer,
  recto_entry integer, recto_exit integer,
  santolan_entry integer, santolan_exit integer,
  v_mapa_entry integer, v_mapa_exit integer,
  total_entry integer, total_exit integer,
  load_timestamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO "AFCS".ridership_2021_backup
WITH aggregated_rows AS (
  SELECT
    date,
    CASE
      WHEN time_period IN ('05:00', '06:00') THEN '5-7am (OFF PEAK)'
      WHEN time_period IN ('07:00', '08:00') THEN '7-9am (AM PEAK)'
      WHEN time_period IN ('09:00', '10:00', '11:00', '12:00', '13:00', '14:00', '15:00', '16:00') THEN '9am-5pm (OFF PEAK)'
      WHEN time_period IN ('17:00', '18:00') THEN '5-7pm (PM PEAK)'
      WHEN time_period IN ('19:00', '20:00', '21:00') THEN '7-10pm (OFF PEAK)'
      WHEN time_period = 'DAILY_TOTAL' THEN 'Daily Total'
      ELSE time_period
    END as time_period_band,
    SUM(anonas_entry)::integer as anonas_entry, SUM(anonas_exit)::integer as anonas_exit,
    SUM(antipolo_entry)::integer as antipolo_entry, SUM(antipolo_exit)::integer as antipolo_exit,
    SUM(araneta_center_cubao_entry)::integer as araneta_center_cubao_entry, SUM(araneta_center_cubao_exit)::integer as araneta_center_cubao_exit,
    SUM(betty_go_belmonte_entry)::integer as betty_go_belmonte_entry, SUM(betty_go_belmonte_exit)::integer as betty_go_belmonte_exit,
    SUM(gilmore_entry)::integer as gilmore_entry, SUM(gilmore_exit)::integer as gilmore_exit,
    SUM(j_ruiz_entry)::integer as j_ruiz_entry, SUM(j_ruiz_exit)::integer as j_ruiz_exit,
    SUM(katipunan_entry)::integer as katipunan_entry, SUM(katipunan_exit)::integer as katipunan_exit,
    SUM(legarda_entry)::integer as legarda_entry, SUM(legarda_exit)::integer as legarda_exit,
    SUM(marikina_pasig_entry)::integer as marikina_pasig_entry, SUM(marikina_pasig_exit)::integer as marikina_pasig_exit,
    SUM(pureza_entry)::integer as pureza_entry, SUM(pureza_exit)::integer as pureza_exit,
    SUM(recto_entry)::integer as recto_entry, SUM(recto_exit)::integer as recto_exit,
    SUM(santolan_entry)::integer as santolan_entry, SUM(santolan_exit)::integer as santolan_exit,
    SUM(v_mapa_entry)::integer as v_mapa_entry, SUM(v_mapa_exit)::integer as v_mapa_exit,
    SUM(total_entry)::integer as total_entry, SUM(total_exit)::integer as total_exit
  FROM "AFCS".ridership_2021
  GROUP BY date, time_period_band
)
SELECT
  'YR2021-' || LPAD((ROW_NUMBER() OVER (ORDER BY date, 
    CASE time_period_band
      WHEN '5-7am (OFF PEAK)' THEN 1
      WHEN '7-9am (AM PEAK)' THEN 2
      WHEN '9am-5pm (OFF PEAK)' THEN 3
      WHEN '5-7pm (PM PEAK)' THEN 4
      WHEN '7-10pm (OFF PEAK)' THEN 5
      WHEN 'Daily Total' THEN 6
      ELSE 7
    END
  ))::text, 4, '0') as id,
  date, time_period_band,
  anonas_entry, anonas_exit,
  antipolo_entry, antipolo_exit,
  araneta_center_cubao_entry, araneta_center_cubao_exit,
  betty_go_belmonte_entry, betty_go_belmonte_exit,
  gilmore_entry, gilmore_exit,
  j_ruiz_entry, j_ruiz_exit,
  katipunan_entry, katipunan_exit,
  legarda_entry, legarda_exit,
  marikina_pasig_entry, marikina_pasig_exit,
  pureza_entry, pureza_exit,
  recto_entry, recto_exit,
  santolan_entry, santolan_exit,
  v_mapa_entry, v_mapa_exit,
  total_entry, total_exit,
  CURRENT_TIMESTAMP
FROM aggregated_rows;


-- Restore 2022 Backup
DROP TABLE IF EXISTS "AFCS".ridership_2022_backup;
CREATE TABLE "AFCS".ridership_2022_backup AS 
SELECT * FROM "AFCS".ridership_2021_backup WHERE 1=0;

INSERT INTO "AFCS".ridership_2022_backup
WITH aggregated_rows AS (
  SELECT
    date,
    CASE
      WHEN time_period IN ('05:00', '06:00') THEN '5-7am (OFF PEAK)'
      WHEN time_period IN ('07:00', '08:00') THEN '7-9am (AM PEAK)'
      WHEN time_period IN ('09:00', '10:00', '11:00', '12:00', '13:00', '14:00', '15:00', '16:00') THEN '9am-5pm (OFF PEAK)'
      WHEN time_period IN ('17:00', '18:00') THEN '5-7pm (PM PEAK)'
      WHEN time_period IN ('19:00', '20:00', '21:00') THEN '7-10pm (OFF PEAK)'
      WHEN time_period = 'DAILY_TOTAL' THEN 'Daily Total'
      ELSE time_period
    END as time_period_band,
    SUM(anonas_entry)::integer as anonas_entry, SUM(anonas_exit)::integer as anonas_exit,
    SUM(antipolo_entry)::integer as antipolo_entry, SUM(antipolo_exit)::integer as antipolo_exit,
    SUM(araneta_center_cubao_entry)::integer as araneta_center_cubao_entry, SUM(araneta_center_cubao_exit)::integer as araneta_center_cubao_exit,
    SUM(betty_go_belmonte_entry)::integer as betty_go_belmonte_entry, SUM(betty_go_belmonte_exit)::integer as betty_go_belmonte_exit,
    SUM(gilmore_entry)::integer as gilmore_entry, SUM(gilmore_exit)::integer as gilmore_exit,
    SUM(j_ruiz_entry)::integer as j_ruiz_entry, SUM(j_ruiz_exit)::integer as j_ruiz_exit,
    SUM(katipunan_entry)::integer as katipunan_entry, SUM(katipunan_exit)::integer as katipunan_exit,
    SUM(legarda_entry)::integer as legarda_entry, SUM(legarda_exit)::integer as legarda_exit,
    SUM(marikina_pasig_entry)::integer as marikina_pasig_entry, SUM(marikina_pasig_exit)::integer as marikina_pasig_exit,
    SUM(pureza_entry)::integer as pureza_entry, SUM(pureza_exit)::integer as pureza_exit,
    SUM(recto_entry)::integer as recto_entry, SUM(recto_exit)::integer as recto_exit,
    SUM(santolan_entry)::integer as santolan_entry, SUM(santolan_exit)::integer as santolan_exit,
    SUM(v_mapa_entry)::integer as v_mapa_entry, SUM(v_mapa_exit)::integer as v_mapa_exit,
    SUM(total_entry)::integer as total_entry, SUM(total_exit)::integer as total_exit
  FROM "AFCS".ridership_2022
  GROUP BY date, time_period_band
)
SELECT
  'YR2022-' || LPAD((ROW_NUMBER() OVER (ORDER BY date, 
    CASE time_period_band
      WHEN '5-7am (OFF PEAK)' THEN 1
      WHEN '7-9am (AM PEAK)' THEN 2
      WHEN '9am-5pm (OFF PEAK)' THEN 3
      WHEN '5-7pm (PM PEAK)' THEN 4
      WHEN '7-10pm (OFF PEAK)' THEN 5
      WHEN 'Daily Total' THEN 6
      ELSE 7
    END
  ))::text, 4, '0') as id,
  date, time_period_band,
  anonas_entry, anonas_exit,
  antipolo_entry, antipolo_exit,
  araneta_center_cubao_entry, araneta_center_cubao_exit,
  betty_go_belmonte_entry, betty_go_belmonte_exit,
  gilmore_entry, gilmore_exit,
  j_ruiz_entry, j_ruiz_exit,
  katipunan_entry, katipunan_exit,
  legarda_entry, legarda_exit,
  marikina_pasig_entry, marikina_pasig_exit,
  pureza_entry, pureza_exit,
  recto_entry, recto_exit,
  santolan_entry, santolan_exit,
  v_mapa_entry, v_mapa_exit,
  total_entry, total_exit,
  CURRENT_TIMESTAMP
FROM aggregated_rows;


-- Restore 2023 Backup
DROP TABLE IF EXISTS "AFCS".ridership_2023_backup;
CREATE TABLE "AFCS".ridership_2023_backup (
  id text PRIMARY KEY,
  date date,
  time_period text,
  anonas_entry integer, anonas_exit integer,
  antipolo_entry integer, antipolo_exit integer,
  araneta_center_cubao_entry integer, araneta_center_cubao_exit integer,
  betty_go_belmonte_entry integer, betty_go_belmonte_exit integer,
  gilmore_entry integer, gilmore_exit integer,
  j_ruiz_entry integer, j_ruiz_exit integer,
  katipunan_entry integer, katipunan_exit integer,
  legarda_entry integer, legarda_exit integer,
  marikina_pasig_entry integer, marikina_pasig_exit integer,
  pureza_entry integer, pureza_exit integer,
  recto_entry integer, recto_exit integer,
  santolan_entry integer, santolan_exit integer,
  v_mapa_entry integer, v_mapa_exit integer,
  total_entry integer, total_exit integer,
  load_timestamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO "AFCS".ridership_2023_backup
WITH raw_rows AS (
  SELECT
    date,
    -- Detect if date was originally hourly (June 2023 or Nov 1, 2023)
    (EXTRACT(month FROM date) = 6 OR (EXTRACT(month FROM date) = 11 AND EXTRACT(day FROM date) = 1)) as is_hourly_date,
    time_period,
    anonas_entry, anonas_exit,
    antipolo_entry, antipolo_exit,
    araneta_center_cubao_entry, araneta_center_cubao_exit,
    betty_go_belmonte_entry, betty_go_belmonte_exit,
    gilmore_entry, gilmore_exit,
    j_ruiz_entry, j_ruiz_exit,
    katipunan_entry, katipunan_exit,
    legarda_entry, legarda_exit,
    marikina_pasig_entry, marikina_pasig_exit,
    pureza_entry, pureza_exit,
    recto_entry, recto_exit,
    santolan_entry, santolan_exit,
    v_mapa_entry, v_mapa_exit,
    total_entry, total_exit
  FROM "AFCS".ridership_2023
),
aggregated_2023 AS (
  -- Hourly dates mapping (restore 05:00 -> 05:00-06:00 format, except aggregates)
  SELECT
    date,
    CASE
      WHEN time_period = 'DAILY_TOTAL' THEN 'Daily Total'
      WHEN time_period = 'MONTHLY_TOTAL' THEN 'Monthly Total'
      WHEN time_period = 'PEAK_TOTAL' THEN 'Peak Total'
      WHEN time_period ~ '^[0-2][0-9]:00$' THEN
        time_period || '-' || 
        CASE 
          WHEN time_period = '23:00' THEN '00:00'
          ELSE TO_CHAR((time_period::time + interval '1 hour'), 'HH24:MI')
        END
      ELSE time_period
    END as time_period_band,
    anonas_entry, anonas_exit,
    antipolo_entry, antipolo_exit,
    araneta_center_cubao_entry, araneta_center_cubao_exit,
    betty_go_belmonte_entry, betty_go_belmonte_exit,
    gilmore_entry, gilmore_exit,
    j_ruiz_entry, j_ruiz_exit,
    katipunan_entry, katipunan_exit,
    legarda_entry, legarda_exit,
    marikina_pasig_entry, marikina_pasig_exit,
    pureza_entry, pureza_exit,
    recto_entry, recto_exit,
    santolan_entry, santolan_exit,
    v_mapa_entry, v_mapa_exit,
    total_entry, total_exit
  FROM raw_rows
  WHERE is_hourly_date = true

  UNION ALL

  -- Band dates mapping (reaggregate to bands)
  SELECT
    date,
    CASE
      WHEN time_period IN ('05:00', '06:00') THEN '5-7am (OFF PEAK)'
      WHEN time_period IN ('07:00', '08:00') THEN '7-9am (AM PEAK)'
      WHEN time_period IN ('09:00', '10:00', '11:00', '12:00', '13:00', '14:00', '15:00', '16:00') THEN '9am-5pm (OFF PEAK)'
      WHEN time_period IN ('17:00', '18:00') THEN '5-7pm (PM PEAK)'
      WHEN time_period IN ('19:00', '20:00', '21:00') THEN '7-10pm (OFF PEAK)'
      WHEN time_period = 'DAILY_TOTAL' THEN 'Daily Total'
      WHEN time_period = 'MONTHLY_TOTAL' THEN 'Monthly Total'
      WHEN time_period = 'PEAK_TOTAL' THEN 'Peak Total'
      ELSE time_period
    END as time_period_band,
    SUM(anonas_entry)::integer as anonas_entry, SUM(anonas_exit)::integer as anonas_exit,
    SUM(antipolo_entry)::integer as antipolo_entry, SUM(antipolo_exit)::integer as antipolo_exit,
    SUM(araneta_center_cubao_entry)::integer as araneta_center_cubao_entry, SUM(araneta_center_cubao_exit)::integer as araneta_center_cubao_exit,
    SUM(betty_go_belmonte_entry)::integer as betty_go_belmonte_entry, SUM(betty_go_belmonte_exit)::integer as betty_go_belmonte_exit,
    SUM(gilmore_entry)::integer as gilmore_entry, SUM(gilmore_exit)::integer as gilmore_exit,
    SUM(j_ruiz_entry)::integer as j_ruiz_entry, SUM(j_ruiz_exit)::integer as j_ruiz_exit,
    SUM(katipunan_entry)::integer as katipunan_entry, SUM(katipunan_exit)::integer as katipunan_exit,
    SUM(legarda_entry)::integer as legarda_entry, SUM(legarda_exit)::integer as legarda_exit,
    SUM(marikina_pasig_entry)::integer as marikina_pasig_entry, SUM(marikina_pasig_exit)::integer as marikina_pasig_exit,
    SUM(pureza_entry)::integer as pureza_entry, SUM(pureza_exit)::integer as pureza_exit,
    SUM(recto_entry)::integer as recto_entry, SUM(recto_exit)::integer as recto_exit,
    SUM(santolan_entry)::integer as santolan_entry, SUM(santolan_exit)::integer as santolan_exit,
    SUM(v_mapa_entry)::integer as v_mapa_entry, SUM(v_mapa_exit)::integer as v_mapa_exit,
    SUM(total_entry)::integer as total_entry, SUM(total_exit)::integer as total_exit
  FROM raw_rows
  WHERE is_hourly_date = false
  GROUP BY date, time_period_band
)
SELECT
  'YR2023-' || LPAD((ROW_NUMBER() OVER (ORDER BY date, 
    CASE time_period_band
      WHEN '5-7am (OFF PEAK)' THEN 1
      WHEN '7-9am (AM PEAK)' THEN 2
      WHEN '9am-5pm (OFF PEAK)' THEN 3
      WHEN '5-7pm (PM PEAK)' THEN 4
      WHEN '7-10pm (OFF PEAK)' THEN 5
      WHEN 'Daily Total' THEN 6
      WHEN 'Monthly Total' THEN 7
      WHEN 'Peak Total' THEN 8
      -- Hourly range orders
      ELSE 9
    END,
    time_period_band -- secondary sort for range times
  ))::text, 4, '0') as id,
  date, time_period_band,
  anonas_entry, anonas_exit,
  antipolo_entry, antipolo_exit,
  araneta_center_cubao_entry, araneta_center_cubao_exit,
  betty_go_belmonte_entry, betty_go_belmonte_exit,
  gilmore_entry, gilmore_exit,
  j_ruiz_entry, j_ruiz_exit,
  katipunan_entry, katipunan_exit,
  legarda_entry, legarda_exit,
  marikina_pasig_entry, marikina_pasig_exit,
  pureza_entry, pureza_exit,
  recto_entry, recto_exit,
  santolan_entry, santolan_exit,
  v_mapa_entry, v_mapa_exit,
  total_entry, total_exit,
  CURRENT_TIMESTAMP
FROM aggregated_2023;


-- Restore 2024 Backup
DROP TABLE IF EXISTS "AFCS".ridership_2024_backup;
CREATE TABLE "AFCS".ridership_2024_backup AS 
SELECT * FROM "AFCS".ridership_2021_backup WHERE 1=0;

INSERT INTO "AFCS".ridership_2024_backup
WITH aggregated_rows AS (
  SELECT
    date,
    CASE
      WHEN time_period IN ('05:00', '06:00') THEN '5-7am (OFF PEAK)'
      WHEN time_period IN ('07:00', '08:00') THEN '7-9am (AM PEAK)'
      WHEN time_period IN ('09:00', '10:00', '11:00', '12:00', '13:00', '14:00', '15:00', '16:00') THEN '9am-5pm (OFF PEAK)'
      WHEN time_period IN ('17:00', '18:00') THEN '5-7pm (PM PEAK)'
      WHEN time_period IN ('19:00', '20:00', '21:00') THEN '7-10pm (OFF PEAK)'
      WHEN time_period = 'DAILY_TOTAL' THEN 'Daily Total'
      ELSE time_period
    END as time_period_band,
    SUM(anonas_entry)::integer as anonas_entry, SUM(anonas_exit)::integer as anonas_exit,
    SUM(antipolo_entry)::integer as antipolo_entry, SUM(antipolo_exit)::integer as antipolo_exit,
    SUM(araneta_center_cubao_entry)::integer as araneta_center_cubao_entry, SUM(araneta_center_cubao_exit)::integer as araneta_center_cubao_exit,
    SUM(betty_go_belmonte_entry)::integer as betty_go_belmonte_entry, SUM(betty_go_belmonte_exit)::integer as betty_go_belmonte_exit,
    SUM(gilmore_entry)::integer as gilmore_entry, SUM(gilmore_exit)::integer as gilmore_exit,
    SUM(j_ruiz_entry)::integer as j_ruiz_entry, SUM(j_ruiz_exit)::integer as j_ruiz_exit,
    SUM(katipunan_entry)::integer as katipunan_entry, SUM(katipunan_exit)::integer as katipunan_exit,
    SUM(legarda_entry)::integer as legarda_entry, SUM(legarda_exit)::integer as legarda_exit,
    SUM(marikina_pasig_entry)::integer as marikina_pasig_entry, SUM(marikina_pasig_exit)::integer as marikina_pasig_exit,
    SUM(pureza_entry)::integer as pureza_entry, SUM(pureza_exit)::integer as pureza_exit,
    SUM(recto_entry)::integer as recto_entry, SUM(recto_exit)::integer as recto_exit,
    SUM(santolan_entry)::integer as santolan_entry, SUM(santolan_exit)::integer as santolan_exit,
    SUM(v_mapa_entry)::integer as v_mapa_entry, SUM(v_mapa_exit)::integer as v_mapa_exit,
    SUM(total_entry)::integer as total_entry, SUM(total_exit)::integer as total_exit
  FROM "AFCS".ridership_2024
  GROUP BY date, time_period_band
)
SELECT
  'YR2024-' || LPAD((ROW_NUMBER() OVER (ORDER BY date, 
    CASE time_period_band
      WHEN '5-7am (OFF PEAK)' THEN 1
      WHEN '7-9am (AM PEAK)' THEN 2
      WHEN '9am-5pm (OFF PEAK)' THEN 3
      WHEN '5-7pm (PM PEAK)' THEN 4
      WHEN '7-10pm (OFF PEAK)' THEN 5
      WHEN 'Daily Total' THEN 6
      ELSE 7
    END
  ))::text, 4, '0') as id,
  date, time_period_band,
  anonas_entry, anonas_exit,
  antipolo_entry, antipolo_exit,
  araneta_center_cubao_entry, araneta_center_cubao_exit,
  betty_go_belmonte_entry, betty_go_belmonte_exit,
  gilmore_entry, gilmore_exit,
  j_ruiz_entry, j_ruiz_exit,
  katipunan_entry, katipunan_exit,
  legarda_entry, legarda_exit,
  marikina_pasig_entry, marikina_pasig_exit,
  pureza_entry, pureza_exit,
  recto_entry, recto_exit,
  santolan_entry, santolan_exit,
  v_mapa_entry, v_mapa_exit,
  total_entry, total_exit,
  CURRENT_TIMESTAMP
FROM aggregated_rows;


-- Restore 2025 Backup
DROP TABLE IF EXISTS "AFCS".ridership_2025_backup;
CREATE TABLE "AFCS".ridership_2025_backup AS 
SELECT * FROM "AFCS".ridership_2021_backup WHERE 1=0;

INSERT INTO "AFCS".ridership_2025_backup
WITH aggregated_rows AS (
  SELECT
    date,
    CASE
      WHEN time_period IN ('05:00', '06:00') THEN '5-7am (OFF PEAK)'
      WHEN time_period IN ('07:00', '08:00') THEN '7-9am (AM PEAK)'
      WHEN time_period IN ('09:00', '10:00', '11:00', '12:00', '13:00', '14:00', '15:00', '16:00') THEN '9am-5pm (OFF PEAK)'
      WHEN time_period IN ('17:00', '18:00') THEN '5-7pm (PM PEAK)'
      WHEN time_period IN ('19:00', '20:00', '21:00') THEN '7-10pm (OFF PEAK)'
      WHEN time_period = 'DAILY_TOTAL' THEN 'Daily Total'
      ELSE time_period
    END as time_period_band,
    SUM(anonas_entry)::integer as anonas_entry, SUM(anonas_exit)::integer as anonas_exit,
    SUM(antipolo_entry)::integer as antipolo_entry, SUM(antipolo_exit)::integer as antipolo_exit,
    SUM(araneta_center_cubao_entry)::integer as araneta_center_cubao_entry, SUM(araneta_center_cubao_exit)::integer as araneta_center_cubao_exit,
    SUM(betty_go_belmonte_entry)::integer as betty_go_belmonte_entry, SUM(betty_go_belmonte_exit)::integer as betty_go_belmonte_exit,
    SUM(gilmore_entry)::integer as gilmore_entry, SUM(gilmore_exit)::integer as gilmore_exit,
    SUM(j_ruiz_entry)::integer as j_ruiz_entry, SUM(j_ruiz_exit)::integer as j_ruiz_exit,
    SUM(katipunan_entry)::integer as katipunan_entry, SUM(katipunan_exit)::integer as katipunan_exit,
    SUM(legarda_entry)::integer as legarda_entry, SUM(legarda_exit)::integer as legarda_exit,
    SUM(marikina_pasig_entry)::integer as marikina_pasig_entry, SUM(marikina_pasig_exit)::integer as marikina_pasig_exit,
    SUM(pureza_entry)::integer as pureza_entry, SUM(pureza_exit)::integer as pureza_exit,
    SUM(recto_entry)::integer as recto_entry, SUM(recto_exit)::integer as recto_exit,
    SUM(santolan_entry)::integer as santolan_entry, SUM(santolan_exit)::integer as santolan_exit,
    SUM(v_mapa_entry)::integer as v_mapa_entry, SUM(v_mapa_exit)::integer as v_mapa_exit,
    SUM(total_entry)::integer as total_entry, SUM(total_exit)::integer as total_exit
  FROM "AFCS".ridership_2025
  GROUP BY date, time_period_band
)
SELECT
  'YR2025-' || LPAD((ROW_NUMBER() OVER (ORDER BY date, 
    CASE time_period_band
      WHEN '5-7am (OFF PEAK)' THEN 1
      WHEN '7-9am (AM PEAK)' THEN 2
      WHEN '9am-5pm (OFF PEAK)' THEN 3
      WHEN '5-7pm (PM PEAK)' THEN 4
      WHEN '7-10pm (OFF PEAK)' THEN 5
      WHEN 'Daily Total' THEN 6
      ELSE 7
    END
  ))::text, 4, '0') as id,
  date, time_period_band,
  anonas_entry, anonas_exit,
  antipolo_entry, antipolo_exit,
  araneta_center_cubao_entry, araneta_center_cubao_exit,
  betty_go_belmonte_entry, betty_go_belmonte_exit,
  gilmore_entry, gilmore_exit,
  j_ruiz_entry, j_ruiz_exit,
  katipunan_entry, katipunan_exit,
  legarda_entry, legarda_exit,
  marikina_pasig_entry, marikina_pasig_exit,
  pureza_entry, pureza_exit,
  recto_entry, recto_exit,
  santolan_entry, santolan_exit,
  v_mapa_entry, v_mapa_exit,
  total_entry, total_exit,
  CURRENT_TIMESTAMP
FROM aggregated_rows;
