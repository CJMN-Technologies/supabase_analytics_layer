-- ============================================================
-- SQL Script: Proportional Hourly Expansion of Student Transactions
-- Target Table: "AFCS".student_transactions
-- Baseline Table: "AFCS".ridership_2025
-- Backup Source: "AFCS".student_transactions_backup
-- Period: June 2025 - March 2026 (non-zero months)
-- Classification: Internal Dataset (Student Transactions)
-- ============================================================

-- Step 1: Recreate Table
DROP TABLE IF EXISTS "AFCS".student_transactions;
CREATE TABLE "AFCS".student_transactions (
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

-- Step 2: Insert Hourly Proportional Rows
INSERT INTO "AFCS".student_transactions (
  id, date, time_period,
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
  load_timestamp
)
WITH RECURSIVE dates AS (
  -- We only generate dates in the non-zero student transactions period: June 2025 - March 2026
  SELECT DATE '2025-06-01' as d
  UNION ALL
  SELECT d + 1
  FROM dates
  WHERE d < '2026-03-31'
),
calendar_mapping AS (
  SELECT
    d as date_actual,
    EXTRACT(year FROM d)::integer as yr,
    EXTRACT(month FROM d)::integer as mth,
    CASE
      WHEN EXTRACT(year FROM d) = 2025 THEN d
      ELSE (
        SELECT d_2025
        FROM (
          SELECT (DATE '2025-01-01' + (n || ' days')::interval)::date as d_2025
          FROM generate_series(0, 364) n
        ) dates_2025
        WHERE EXTRACT(month FROM d_2025) = EXTRACT(month FROM d)
          AND EXTRACT(isodow FROM d_2025) = EXTRACT(isodow FROM d)
        ORDER BY ABS(EXTRACT(day FROM d_2025) - EXTRACT(day FROM d)) ASC
        LIMIT 1
      )
    END as baseline_date
  FROM dates
),
baseline_hourly AS (
  SELECT
    cm.date_actual,
    cm.yr,
    cm.mth,
    r.time_period,
    -- Entries
    r.anonas_entry,
    r.antipolo_entry,
    r.araneta_center_cubao_entry,
    r.betty_go_belmonte_entry,
    r.gilmore_entry,
    r.j_ruiz_entry,
    r.katipunan_entry,
    r.legarda_entry,
    r.marikina_pasig_entry,
    r.pureza_entry,
    r.recto_entry,
    r.santolan_entry,
    r.v_mapa_entry,
    -- Exits
    r.anonas_exit,
    r.antipolo_exit,
    r.araneta_center_cubao_exit,
    r.betty_go_belmonte_exit,
    r.gilmore_exit,
    r.j_ruiz_exit,
    r.katipunan_exit,
    r.legarda_exit,
    r.marikina_pasig_exit,
    r.pureza_exit,
    r.recto_exit,
    r.santolan_exit,
    r.v_mapa_exit,
    -- Totals in commuter table
    r.total_entry as c_ent_tot,
    r.total_exit as c_ext_tot,
    -- Actual sum of station columns to prevent negative numbers due to inconsistent totals in source
    (r.anonas_entry + r.antipolo_entry + r.araneta_center_cubao_entry + r.betty_go_belmonte_entry + r.gilmore_entry + r.j_ruiz_entry + r.katipunan_entry + r.legarda_entry + r.marikina_pasig_entry + r.pureza_entry + r.recto_entry + r.santolan_entry + r.v_mapa_entry) as c_ent_sum,
    (r.anonas_exit + r.antipolo_exit + r.araneta_center_cubao_exit + r.betty_go_belmonte_exit + r.gilmore_exit + r.j_ruiz_exit + r.katipunan_exit + r.legarda_exit + r.marikina_pasig_exit + r.pureza_exit + r.recto_exit + r.santolan_exit + r.v_mapa_exit) as c_ext_sum
  FROM calendar_mapping cm
  JOIN "AFCS".ridership_2025 r ON r.date = cm.baseline_date
  WHERE r.time_period != 'DAILY_TOTAL'
),
monthly_commuter_totals AS (
  SELECT
    yr,
    mth,
    SUM(c_ent_tot) as tot_ent,
    SUM(c_ext_tot) as tot_ext
  FROM baseline_hourly
  GROUP BY yr, mth
),
hourly_with_running_totals AS (
  SELECT
    bh.*,
    COALESCE(st.student_transactions, 0) as st_m,
    -- Running sums for cumulative rounding over the month
    SUM(bh.c_ent_tot) OVER (PARTITION BY bh.yr, bh.mth ORDER BY bh.date_actual, bh.time_period ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as run_ent,
    SUM(bh.c_ext_tot) OVER (PARTITION BY bh.yr, bh.mth ORDER BY bh.date_actual, bh.time_period ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as run_ext,
    mct.tot_ent,
    mct.tot_ext
  FROM baseline_hourly bh
  JOIN monthly_commuter_totals mct ON mct.yr = bh.yr AND mct.mth = bh.mth
  LEFT JOIN "AFCS".student_transactions_backup st ON st.year = bh.yr AND st.month_number = bh.mth AND st.is_total = false
),
row_student_totals AS (
  SELECT
    *,
    CASE WHEN tot_ent > 0 THEN ROUND(st_m * run_ent::double precision / tot_ent)::integer ELSE 0 END as cum_tgt_ent,
    CASE WHEN tot_ext > 0 THEN ROUND(st_m * run_ext::double precision / tot_ext)::integer ELSE 0 END as cum_tgt_ext
  FROM hourly_with_running_totals
),
row_student_totals_with_lag AS (
  SELECT
    *,
    COALESCE(LAG(cum_tgt_ent) OVER (PARTITION BY yr, mth ORDER BY date_actual, time_period), 0) as cum_tgt_ent_prev,
    COALESCE(LAG(cum_tgt_ext) OVER (PARTITION BY yr, mth ORDER BY date_actual, time_period), 0) as cum_tgt_ext_prev
  FROM row_student_totals
),
allocated_row_totals AS (
  SELECT
    *,
    (cum_tgt_ent - cum_tgt_ent_prev) as row_ent,
    (cum_tgt_ext - cum_tgt_ext_prev) as row_ext
  FROM row_student_totals_with_lag
)
SELECT
  'ST' || TO_CHAR(date_actual, 'YY') || '-' || TO_CHAR(date_actual, 'MMDD') || '-' || LEFT(time_period, 2) as id,
  date_actual,
  time_period,
  -- Station entries
  CASE WHEN c_ent_sum > 0 THEN ROUND(row_ent * (anonas_entry)::double precision / c_ent_sum)::integer ELSE 0 END as anonas_entry,
  CASE WHEN c_ext_sum > 0 THEN ROUND(row_ext * (anonas_exit)::double precision / c_ext_sum)::integer ELSE 0 END as anonas_exit,

  CASE WHEN c_ent_sum > 0 THEN ROUND(row_ent * (anonas_entry + antipolo_entry)::double precision / c_ent_sum)::integer - ROUND(row_ent * (anonas_entry)::double precision / c_ent_sum)::integer ELSE 0 END as antipolo_entry,
  CASE WHEN c_ext_sum > 0 THEN ROUND(row_ext * (anonas_exit + antipolo_exit)::double precision / c_ext_sum)::integer - ROUND(row_ext * (anonas_exit)::double precision / c_ext_sum)::integer ELSE 0 END as antipolo_exit,

  CASE WHEN c_ent_sum > 0 THEN ROUND(row_ent * (anonas_entry + antipolo_entry + araneta_center_cubao_entry)::double precision / c_ent_sum)::integer - ROUND(row_ent * (anonas_entry + antipolo_entry)::double precision / c_ent_sum)::integer ELSE 0 END as araneta_center_cubao_entry,
  CASE WHEN c_ext_sum > 0 THEN ROUND(row_ext * (anonas_exit + antipolo_exit + araneta_center_cubao_exit)::double precision / c_ext_sum)::integer - ROUND(row_ext * (anonas_exit + antipolo_exit)::double precision / c_ext_sum)::integer ELSE 0 END as araneta_center_cubao_exit,

  CASE WHEN c_ent_sum > 0 THEN ROUND(row_ent * (anonas_entry + antipolo_entry + araneta_center_cubao_entry + betty_go_belmonte_entry)::double precision / c_ent_sum)::integer - ROUND(row_ent * (anonas_entry + antipolo_entry + araneta_center_cubao_entry)::double precision / c_ent_sum)::integer ELSE 0 END as betty_go_belmonte_entry,
  CASE WHEN c_ext_sum > 0 THEN ROUND(row_ext * (anonas_exit + antipolo_exit + araneta_center_cubao_exit + betty_go_belmonte_exit)::double precision / c_ext_sum)::integer - ROUND(row_ext * (anonas_exit + antipolo_exit + araneta_center_cubao_exit)::double precision / c_ext_sum)::integer ELSE 0 END as betty_go_belmonte_exit,

  CASE WHEN c_ent_sum > 0 THEN ROUND(row_ent * (anonas_entry + antipolo_entry + araneta_center_cubao_entry + betty_go_belmonte_entry + gilmore_entry)::double precision / c_ent_sum)::integer - ROUND(row_ent * (anonas_entry + antipolo_entry + araneta_center_cubao_entry + betty_go_belmonte_entry)::double precision / c_ent_sum)::integer ELSE 0 END as gilmore_entry,
  CASE WHEN c_ext_sum > 0 THEN ROUND(row_ext * (anonas_exit + antipolo_exit + araneta_center_cubao_exit + betty_go_belmonte_exit + gilmore_exit)::double precision / c_ext_sum)::integer - ROUND(row_ext * (anonas_exit + antipolo_exit + araneta_center_cubao_exit + betty_go_belmonte_exit)::double precision / c_ext_sum)::integer ELSE 0 END as gilmore_exit,

  CASE WHEN c_ent_sum > 0 THEN ROUND(row_ent * (anonas_entry + antipolo_entry + araneta_center_cubao_entry + betty_go_belmonte_entry + gilmore_entry + j_ruiz_entry)::double precision / c_ent_sum)::integer - ROUND(row_ent * (anonas_entry + antipolo_entry + araneta_center_cubao_entry + betty_go_belmonte_entry + gilmore_entry)::double precision / c_ent_sum)::integer ELSE 0 END as j_ruiz_entry,
  CASE WHEN c_ext_sum > 0 THEN ROUND(row_ext * (anonas_exit + antipolo_exit + araneta_center_cubao_exit + betty_go_belmonte_exit + gilmore_exit + j_ruiz_exit)::double precision / c_ext_sum)::integer - ROUND(row_ext * (anonas_exit + antipolo_exit + araneta_center_cubao_exit + betty_go_belmonte_exit + gilmore_exit)::double precision / c_ext_sum)::integer ELSE 0 END as j_ruiz_exit,

  CASE WHEN c_ent_sum > 0 THEN ROUND(row_ent * (anonas_entry + antipolo_entry + araneta_center_cubao_entry + betty_go_belmonte_entry + gilmore_entry + j_ruiz_entry + katipunan_entry)::double precision / c_ent_sum)::integer - ROUND(row_ent * (anonas_entry + antipolo_entry + araneta_center_cubao_entry + betty_go_belmonte_entry + gilmore_entry + j_ruiz_entry)::double precision / c_ent_sum)::integer ELSE 0 END as katipunan_entry,
  CASE WHEN c_ext_sum > 0 THEN ROUND(row_ext * (anonas_exit + antipolo_exit + araneta_center_cubao_exit + betty_go_belmonte_exit + gilmore_exit + j_ruiz_exit + katipunan_exit)::double precision / c_ext_sum)::integer - ROUND(row_ext * (anonas_exit + antipolo_exit + araneta_center_cubao_exit + betty_go_belmonte_exit + gilmore_exit + j_ruiz_exit)::double precision / c_ext_sum)::integer ELSE 0 END as katipunan_exit,

  CASE WHEN c_ent_sum > 0 THEN ROUND(row_ent * (anonas_entry + antipolo_entry + araneta_center_cubao_entry + betty_go_belmonte_entry + gilmore_entry + j_ruiz_entry + katipunan_entry + legarda_entry)::double precision / c_ent_sum)::integer - ROUND(row_ent * (anonas_entry + antipolo_entry + araneta_center_cubao_entry + betty_go_belmonte_entry + gilmore_entry + j_ruiz_entry + katipunan_entry)::double precision / c_ent_sum)::integer ELSE 0 END as legarda_entry,
  CASE WHEN c_ext_sum > 0 THEN ROUND(row_ext * (anonas_exit + antipolo_exit + araneta_center_cubao_exit + betty_go_belmonte_exit + gilmore_exit + j_ruiz_exit + katipunan_exit + legarda_exit)::double precision / c_ext_sum)::integer - ROUND(row_ext * (anonas_exit + antipolo_exit + araneta_center_cubao_exit + betty_go_belmonte_exit + gilmore_exit + j_ruiz_exit + katipunan_exit)::double precision / c_ext_sum)::integer ELSE 0 END as legarda_exit,

  CASE WHEN c_ent_sum > 0 THEN ROUND(row_ent * (anonas_entry + antipolo_entry + araneta_center_cubao_entry + betty_go_belmonte_entry + gilmore_entry + j_ruiz_entry + katipunan_entry + legarda_entry + marikina_pasig_entry)::double precision / c_ent_sum)::integer - ROUND(row_ent * (anonas_entry + antipolo_entry + araneta_center_cubao_entry + betty_go_belmonte_entry + gilmore_entry + j_ruiz_entry + katipunan_entry + legarda_entry)::double precision / c_ent_sum)::integer ELSE 0 END as marikina_pasig_entry,
  CASE WHEN c_ext_sum > 0 THEN ROUND(row_ext * (anonas_exit + antipolo_exit + araneta_center_cubao_exit + betty_go_belmonte_exit + gilmore_exit + j_ruiz_exit + katipunan_exit + legarda_exit + marikina_pasig_exit)::double precision / c_ext_sum)::integer - ROUND(row_ext * (anonas_exit + antipolo_exit + araneta_center_cubao_exit + betty_go_belmonte_exit + gilmore_exit + j_ruiz_exit + katipunan_exit + legarda_exit)::double precision / c_ext_sum)::integer ELSE 0 END as marikina_pasig_exit,

  CASE WHEN c_ent_sum > 0 THEN ROUND(row_ent * (anonas_entry + antipolo_entry + araneta_center_cubao_entry + betty_go_belmonte_entry + gilmore_entry + j_ruiz_entry + katipunan_entry + legarda_entry + marikina_pasig_entry + pureza_entry)::double precision / c_ent_sum)::integer - ROUND(row_ent * (anonas_entry + antipolo_entry + araneta_center_cubao_entry + betty_go_belmonte_entry + gilmore_entry + j_ruiz_entry + katipunan_entry + legarda_entry + marikina_pasig_entry)::double precision / c_ent_sum)::integer ELSE 0 END as pureza_entry,
  CASE WHEN c_ext_sum > 0 THEN ROUND(row_ext * (anonas_exit + antipolo_exit + araneta_center_cubao_exit + betty_go_belmonte_exit + gilmore_exit + j_ruiz_exit + katipunan_exit + legarda_exit + marikina_pasig_exit + pureza_exit)::double precision / c_ext_sum)::integer - ROUND(row_ext * (anonas_exit + antipolo_exit + araneta_center_cubao_exit + betty_go_belmonte_exit + gilmore_exit + j_ruiz_exit + katipunan_exit + legarda_exit + marikina_pasig_exit)::double precision / c_ext_sum)::integer ELSE 0 END as pureza_exit,

  CASE WHEN c_ent_sum > 0 THEN ROUND(row_ent * (anonas_entry + antipolo_entry + araneta_center_cubao_entry + betty_go_belmonte_entry + gilmore_entry + j_ruiz_entry + katipunan_entry + legarda_entry + marikina_pasig_entry + pureza_entry + recto_entry)::double precision / c_ent_sum)::integer - ROUND(row_ent * (anonas_entry + antipolo_entry + araneta_center_cubao_entry + betty_go_belmonte_entry + gilmore_entry + j_ruiz_entry + katipunan_entry + legarda_entry + marikina_pasig_entry + pureza_entry)::double precision / c_ent_sum)::integer ELSE 0 END as recto_entry,
  CASE WHEN c_ext_sum > 0 THEN ROUND(row_ext * (anonas_exit + antipolo_exit + araneta_center_cubao_exit + betty_go_belmonte_exit + gilmore_exit + j_ruiz_exit + katipunan_exit + legarda_exit + marikina_pasig_exit + pureza_exit + recto_exit)::double precision / c_ext_sum)::integer - ROUND(row_ext * (anonas_exit + antipolo_exit + araneta_center_cubao_exit + betty_go_belmonte_exit + gilmore_exit + j_ruiz_exit + katipunan_exit + legarda_exit + marikina_pasig_exit + pureza_exit)::double precision / c_ext_sum)::integer ELSE 0 END as recto_exit,

  CASE WHEN c_ent_sum > 0 THEN ROUND(row_ent * (anonas_entry + antipolo_entry + araneta_center_cubao_entry + betty_go_belmonte_entry + gilmore_entry + j_ruiz_entry + katipunan_entry + legarda_entry + marikina_pasig_entry + pureza_entry + recto_entry + santolan_entry)::double precision / c_ent_sum)::integer - ROUND(row_ent * (anonas_entry + antipolo_entry + araneta_center_cubao_entry + betty_go_belmonte_entry + gilmore_entry + j_ruiz_entry + katipunan_entry + legarda_entry + marikina_pasig_entry + pureza_entry + recto_entry)::double precision / c_ent_sum)::integer ELSE 0 END as santolan_entry,
  CASE WHEN c_ext_sum > 0 THEN ROUND(row_ext * (anonas_exit + antipolo_exit + araneta_center_cubao_exit + betty_go_belmonte_exit + gilmore_exit + j_ruiz_exit + katipunan_exit + legarda_exit + marikina_pasig_exit + pureza_exit + recto_exit + santolan_exit)::double precision / c_ext_sum)::integer - ROUND(row_ext * (anonas_exit + antipolo_exit + araneta_center_cubao_exit + betty_go_belmonte_exit + gilmore_exit + j_ruiz_exit + katipunan_exit + legarda_exit + marikina_pasig_exit + pureza_exit + recto_exit)::double precision / c_ext_sum)::integer ELSE 0 END as santolan_exit,

  row_ent - (
    CASE WHEN c_ent_sum > 0 THEN ROUND(row_ent * (anonas_entry + antipolo_entry + araneta_center_cubao_entry + betty_go_belmonte_entry + gilmore_entry + j_ruiz_entry + katipunan_entry + legarda_entry + marikina_pasig_entry + pureza_entry + recto_entry + santolan_entry)::double precision / c_ent_sum)::integer ELSE 0 END
  ) as v_mapa_entry,
  row_ext - (
    CASE WHEN c_ext_sum > 0 THEN ROUND(row_ext * (anonas_exit + antipolo_exit + araneta_center_cubao_exit + betty_go_belmonte_exit + gilmore_exit + j_ruiz_exit + katipunan_exit + legarda_exit + marikina_pasig_exit + pureza_exit + recto_exit + santolan_exit)::double precision / c_ext_sum)::integer ELSE 0 END
  ) as v_mapa_exit,

  row_ent as total_entry,
  row_ext as total_exit,
  CURRENT_TIMESTAMP
FROM allocated_row_totals
ORDER BY date_actual, time_period;


-- Step 3: Insert Daily Totals
INSERT INTO "AFCS".student_transactions (
  id, date, time_period,
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
  load_timestamp
)
SELECT
  'ST' || TO_CHAR(date, 'YY') || '-' || TO_CHAR(date, 'MMDD') || '-DT' as id,
  date,
  'DAILY_TOTAL' as time_period,
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
FROM (
  SELECT
    date,
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
  FROM "AFCS".student_transactions
  GROUP BY date
) s;
