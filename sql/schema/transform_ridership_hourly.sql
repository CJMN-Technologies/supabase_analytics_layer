-- ============================================================
-- SQL Script: Proportional Hourly Expansion of 5-Year Ridership (Auto-Generated)
-- Schema: AFCS
-- Source Tables: ridership_2021_backup to ridership_2025_backup
-- Target Tables: ridership_2021 to ridership_2025
-- ============================================================

-- ============================================================
-- TRANSFORM ridership_2021
-- ============================================================
DROP TABLE IF EXISTS "AFCS".ridership_2021;
CREATE TABLE "AFCS".ridership_2021 (
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

INSERT INTO "AFCS".ridership_2021 (
  id,
  date,
  time_period,
  anonas_entry,
  antipolo_entry,
  araneta_center_cubao_entry,
  betty_go_belmonte_entry,
  gilmore_entry,
  j_ruiz_entry,
  katipunan_entry,
  legarda_entry,
  marikina_pasig_entry,
  pureza_entry,
  recto_entry,
  santolan_entry,
  v_mapa_entry,
  anonas_exit,
  antipolo_exit,
  araneta_center_cubao_exit,
  betty_go_belmonte_exit,
  gilmore_exit,
  j_ruiz_exit,
  katipunan_exit,
  legarda_exit,
  marikina_pasig_exit,
  pureza_exit,
  recto_exit,
  santolan_exit,
  v_mapa_exit,
  total_entry,
  total_exit,
  load_timestamp
)
WITH hour_weights (band, time_period, seq, weight, cum_weight, cum_weight_prev) AS (
  VALUES
    ('5-7am (OFF PEAK)',   '05:00', 1, 0.294976632537090, 0.294976632537090, 0.0),
    ('5-7am (OFF PEAK)',   '06:00', 2, 0.705023367462910, 1.0,               0.294976632537090),
    ('7-9am (AM PEAK)',    '07:00', 1, 0.544024908634851, 0.544024908634851, 0.0),
    ('7-9am (AM PEAK)',    '08:00', 2, 0.455975091365149, 1.0,               0.544024908634851),
    ('9am-5pm (OFF PEAK)', '09:00', 1, 0.115810405840533, 0.115810405840533, 0.0),
    ('9am-5pm (OFF PEAK)', '10:00', 2, 0.109552336053815, 0.225362741894348, 0.115810405840533),
    ('9am-5pm (OFF PEAK)', '11:00', 3, 0.112527198170051, 0.337889940064399, 0.225362741894348),
    ('9am-5pm (OFF PEAK)', '12:00', 4, 0.125297635652118, 0.463187575716517, 0.337889940064399),
    ('9am-5pm (OFF PEAK)', '13:00', 5, 0.122739214381356, 0.585926790097873, 0.463187575716517),
    ('9am-5pm (OFF PEAK)', '14:00', 6, 0.122510819491823, 0.708437609589696, 0.585926790097873),
    ('9am-5pm (OFF PEAK)', '15:00', 7, 0.133837412726751, 0.842275022316447, 0.708437609589696),
    ('9am-5pm (OFF PEAK)', '16:00', 8, 0.157724977683553, 1.0,               0.842275022316447),
    ('5-7pm (PM PEAK)',    '17:00', 1, 0.514927690590153, 0.514927690590153, 0.0),
    ('5-7pm (PM PEAK)',    '18:00', 2, 0.485072309409847, 1.0,               0.514927690590153),
    ('7-10pm (OFF PEAK)',  '19:00', 1, 0.511999956428162, 0.511999956428162, 0.0),
    ('7-10pm (OFF PEAK)',  '20:00', 2, 0.367992309570645, 0.879992265998807, 0.511999956428162),
    ('7-10pm (OFF PEAK)',  '21:00', 3, 0.120007734001193, 1.0,               0.879992265998807)
),
base_rows AS (
  SELECT
    r.*,
    (COALESCE(r.anonas_entry, 0) + COALESCE(r.antipolo_entry, 0) + COALESCE(r.araneta_center_cubao_entry, 0) + COALESCE(r.betty_go_belmonte_entry, 0) + COALESCE(r.gilmore_entry, 0) + COALESCE(r.j_ruiz_entry, 0) + COALESCE(r.katipunan_entry, 0) + COALESCE(r.legarda_entry, 0) + COALESCE(r.marikina_pasig_entry, 0) + COALESCE(r.pureza_entry, 0) + COALESCE(r.recto_entry, 0) + COALESCE(r.santolan_entry, 0) + COALESCE(r.v_mapa_entry, 0)) as c_ent_sum,
    (COALESCE(r.anonas_exit, 0) + COALESCE(r.antipolo_exit, 0) + COALESCE(r.araneta_center_cubao_exit, 0) + COALESCE(r.betty_go_belmonte_exit, 0) + COALESCE(r.gilmore_exit, 0) + COALESCE(r.j_ruiz_exit, 0) + COALESCE(r.katipunan_exit, 0) + COALESCE(r.legarda_exit, 0) + COALESCE(r.marikina_pasig_exit, 0) + COALESCE(r.pureza_exit, 0) + COALESCE(r.recto_exit, 0) + COALESCE(r.santolan_exit, 0) + COALESCE(r.v_mapa_exit, 0)) as c_ext_sum
  FROM "AFCS".ridership_2021_backup r
  WHERE r.time_period != 'Daily Total'
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
SELECT
  'YR2021-' || TO_CHAR(date, 'YYYYMMDD') || '-' || LEFT(hr_period, 2) as id,
  date, hr_period,
  
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as anonas_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as antipolo_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as araneta_center_cubao_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as betty_go_belmonte_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as gilmore_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as j_ruiz_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as katipunan_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as legarda_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as marikina_pasig_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as pureza_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0) + COALESCE(recto_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as recto_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0) + COALESCE(recto_entry, 0) + COALESCE(santolan_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0) + COALESCE(recto_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as santolan_entry,
  hr_total_entry - (
    CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0) + COALESCE(recto_entry, 0) + COALESCE(santolan_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END
  ) as v_mapa_entry,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as anonas_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as antipolo_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as araneta_center_cubao_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as betty_go_belmonte_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as gilmore_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as j_ruiz_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as katipunan_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as legarda_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as marikina_pasig_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as pureza_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0) + COALESCE(recto_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as recto_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0) + COALESCE(recto_exit, 0) + COALESCE(santolan_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0) + COALESCE(recto_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as santolan_exit,
  hr_total_exit - (
    CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0) + COALESCE(recto_exit, 0) + COALESCE(santolan_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END
  ) as v_mapa_exit,
  
  hr_total_entry as total_entry,
  hr_total_exit as total_exit,
  CURRENT_TIMESTAMP
FROM hourly_distributed_totals;

-- Insert Daily Total Rows
INSERT INTO "AFCS".ridership_2021 (
  anonas_entry, anonas_exit, antipolo_entry, antipolo_exit, araneta_center_cubao_entry, araneta_center_cubao_exit, betty_go_belmonte_entry, betty_go_belmonte_exit, gilmore_entry, gilmore_exit, j_ruiz_entry, j_ruiz_exit, katipunan_entry, katipunan_exit, legarda_entry, legarda_exit, marikina_pasig_entry, marikina_pasig_exit, pureza_entry, pureza_exit, recto_entry, recto_exit, santolan_entry, santolan_exit, v_mapa_entry, v_mapa_exit,
  id, date, time_period, total_entry, total_exit, load_timestamp
)
SELECT
  anonas_entry, anonas_exit, antipolo_entry, antipolo_exit, araneta_center_cubao_entry, araneta_center_cubao_exit, betty_go_belmonte_entry, betty_go_belmonte_exit, gilmore_entry, gilmore_exit, j_ruiz_entry, j_ruiz_exit, katipunan_entry, katipunan_exit, legarda_entry, legarda_exit, marikina_pasig_entry, marikina_pasig_exit, pureza_entry, pureza_exit, recto_entry, recto_exit, santolan_entry, santolan_exit, v_mapa_entry, v_mapa_exit,
  id, date, 'DAILY_TOTAL', total_entry, total_exit, CURRENT_TIMESTAMP
FROM "AFCS".ridership_2021_backup
WHERE time_period = 'Daily Total';


-- ============================================================
-- TRANSFORM ridership_2022
-- ============================================================
DROP TABLE IF EXISTS "AFCS".ridership_2022;
CREATE TABLE "AFCS".ridership_2022 AS SELECT * FROM "AFCS".ridership_2021 WHERE 1=0;

INSERT INTO "AFCS".ridership_2022 (
  id,
  date,
  time_period,
  anonas_entry,
  antipolo_entry,
  araneta_center_cubao_entry,
  betty_go_belmonte_entry,
  gilmore_entry,
  j_ruiz_entry,
  katipunan_entry,
  legarda_entry,
  marikina_pasig_entry,
  pureza_entry,
  recto_entry,
  santolan_entry,
  v_mapa_entry,
  anonas_exit,
  antipolo_exit,
  araneta_center_cubao_exit,
  betty_go_belmonte_exit,
  gilmore_exit,
  j_ruiz_exit,
  katipunan_exit,
  legarda_exit,
  marikina_pasig_exit,
  pureza_exit,
  recto_exit,
  santolan_exit,
  v_mapa_exit,
  total_entry,
  total_exit,
  load_timestamp
)
WITH hour_weights (band, time_period, seq, weight, cum_weight, cum_weight_prev) AS (
  VALUES
    ('5-7am (OFF PEAK)',   '05:00', 1, 0.294976632537090, 0.294976632537090, 0.0),
    ('5-7am (OFF PEAK)',   '06:00', 2, 0.705023367462910, 1.0,               0.294976632537090),
    ('7-9am (AM PEAK)',    '07:00', 1, 0.544024908634851, 0.544024908634851, 0.0),
    ('7-9am (AM PEAK)',    '08:00', 2, 0.455975091365149, 1.0,               0.544024908634851),
    ('9am-5pm (OFF PEAK)', '09:00', 1, 0.115810405840533, 0.115810405840533, 0.0),
    ('9am-5pm (OFF PEAK)', '10:00', 2, 0.109552336053815, 0.225362741894348, 0.115810405840533),
    ('9am-5pm (OFF PEAK)', '11:00', 3, 0.112527198170051, 0.337889940064399, 0.225362741894348),
    ('9am-5pm (OFF PEAK)', '12:00', 4, 0.125297635652118, 0.463187575716517, 0.337889940064399),
    ('9am-5pm (OFF PEAK)', '13:00', 5, 0.122739214381356, 0.585926790097873, 0.463187575716517),
    ('9am-5pm (OFF PEAK)', '14:00', 6, 0.122510819491823, 0.708437609589696, 0.585926790097873),
    ('9am-5pm (OFF PEAK)', '15:00', 7, 0.133837412726751, 0.842275022316447, 0.708437609589696),
    ('9am-5pm (OFF PEAK)', '16:00', 8, 0.157724977683553, 1.0,               0.842275022316447),
    ('5-7pm (PM PEAK)',    '17:00', 1, 0.514927690590153, 0.514927690590153, 0.0),
    ('5-7pm (PM PEAK)',    '18:00', 2, 0.485072309409847, 1.0,               0.514927690590153),
    ('7-10pm (OFF PEAK)',  '19:00', 1, 0.511999956428162, 0.511999956428162, 0.0),
    ('7-10pm (OFF PEAK)',  '20:00', 2, 0.367992309570645, 0.879992265998807, 0.511999956428162),
    ('7-10pm (OFF PEAK)',  '21:00', 3, 0.120007734001193, 1.0,               0.879992265998807)
),
base_rows AS (
  SELECT
    r.*,
    (COALESCE(r.anonas_entry, 0) + COALESCE(r.antipolo_entry, 0) + COALESCE(r.araneta_center_cubao_entry, 0) + COALESCE(r.betty_go_belmonte_entry, 0) + COALESCE(r.gilmore_entry, 0) + COALESCE(r.j_ruiz_entry, 0) + COALESCE(r.katipunan_entry, 0) + COALESCE(r.legarda_entry, 0) + COALESCE(r.marikina_pasig_entry, 0) + COALESCE(r.pureza_entry, 0) + COALESCE(r.recto_entry, 0) + COALESCE(r.santolan_entry, 0) + COALESCE(r.v_mapa_entry, 0)) as c_ent_sum,
    (COALESCE(r.anonas_exit, 0) + COALESCE(r.antipolo_exit, 0) + COALESCE(r.araneta_center_cubao_exit, 0) + COALESCE(r.betty_go_belmonte_exit, 0) + COALESCE(r.gilmore_exit, 0) + COALESCE(r.j_ruiz_exit, 0) + COALESCE(r.katipunan_exit, 0) + COALESCE(r.legarda_exit, 0) + COALESCE(r.marikina_pasig_exit, 0) + COALESCE(r.pureza_exit, 0) + COALESCE(r.recto_exit, 0) + COALESCE(r.santolan_exit, 0) + COALESCE(r.v_mapa_exit, 0)) as c_ext_sum
  FROM "AFCS".ridership_2022_backup r
  WHERE r.time_period != 'Daily Total'
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
SELECT
  'YR2022-' || TO_CHAR(date, 'YYYYMMDD') || '-' || LEFT(hr_period, 2) as id,
  date, hr_period,
  
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as anonas_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as antipolo_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as araneta_center_cubao_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as betty_go_belmonte_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as gilmore_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as j_ruiz_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as katipunan_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as legarda_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as marikina_pasig_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as pureza_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0) + COALESCE(recto_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as recto_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0) + COALESCE(recto_entry, 0) + COALESCE(santolan_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0) + COALESCE(recto_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as santolan_entry,
  hr_total_entry - (
    CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0) + COALESCE(recto_entry, 0) + COALESCE(santolan_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END
  ) as v_mapa_entry,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as anonas_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as antipolo_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as araneta_center_cubao_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as betty_go_belmonte_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as gilmore_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as j_ruiz_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as katipunan_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as legarda_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as marikina_pasig_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as pureza_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0) + COALESCE(recto_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as recto_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0) + COALESCE(recto_exit, 0) + COALESCE(santolan_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0) + COALESCE(recto_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as santolan_exit,
  hr_total_exit - (
    CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0) + COALESCE(recto_exit, 0) + COALESCE(santolan_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END
  ) as v_mapa_exit,
  
  hr_total_entry as total_entry,
  hr_total_exit as total_exit,
  CURRENT_TIMESTAMP
FROM hourly_distributed_totals;

-- Insert Daily Total Rows
INSERT INTO "AFCS".ridership_2022 (
  anonas_entry, anonas_exit, antipolo_entry, antipolo_exit, araneta_center_cubao_entry, araneta_center_cubao_exit, betty_go_belmonte_entry, betty_go_belmonte_exit, gilmore_entry, gilmore_exit, j_ruiz_entry, j_ruiz_exit, katipunan_entry, katipunan_exit, legarda_entry, legarda_exit, marikina_pasig_entry, marikina_pasig_exit, pureza_entry, pureza_exit, recto_entry, recto_exit, santolan_entry, santolan_exit, v_mapa_entry, v_mapa_exit,
  id, date, time_period, total_entry, total_exit, load_timestamp
)
SELECT
  anonas_entry, anonas_exit, antipolo_entry, antipolo_exit, araneta_center_cubao_entry, araneta_center_cubao_exit, betty_go_belmonte_entry, betty_go_belmonte_exit, gilmore_entry, gilmore_exit, j_ruiz_entry, j_ruiz_exit, katipunan_entry, katipunan_exit, legarda_entry, legarda_exit, marikina_pasig_entry, marikina_pasig_exit, pureza_entry, pureza_exit, recto_entry, recto_exit, santolan_entry, santolan_exit, v_mapa_entry, v_mapa_exit,
  id, date, 'DAILY_TOTAL', total_entry, total_exit, CURRENT_TIMESTAMP
FROM "AFCS".ridership_2022_backup
WHERE time_period = 'Daily Total';


-- ============================================================
-- TRANSFORM ridership_2023
-- ============================================================
DROP TABLE IF EXISTS "AFCS".ridership_2023;
CREATE TABLE "AFCS".ridership_2023 (
  id text PRIMARY KEY,
  date date,
  time_period text,
  anonas_entry integer, anonas_exit integer,
  antipolo_entry integer, antipolo_exit integer,
  araneta_center_cubao_entry integer, araneta_center_cubao_exit integer,
  betty_go_belmonte_entry integer, betty_go_belmonte_exit integer,
  entry_entry integer, exit_entry integer, -- 2023 extra columns
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

-- Part 1: Copy over original true hourly range rows and map format (e.g. '05:00-06:00' -> '05:00')
INSERT INTO "AFCS".ridership_2023 (
  id,
  date,
  time_period,
  anonas_entry,
  antipolo_entry,
  araneta_center_cubao_entry,
  betty_go_belmonte_entry,
  entry_entry,
  gilmore_entry,
  j_ruiz_entry,
  katipunan_entry,
  legarda_entry,
  marikina_pasig_entry,
  pureza_entry,
  recto_entry,
  santolan_entry,
  v_mapa_entry,
  anonas_exit,
  antipolo_exit,
  araneta_center_cubao_exit,
  betty_go_belmonte_exit,
  exit_entry,
  gilmore_exit,
  j_ruiz_exit,
  katipunan_exit,
  legarda_exit,
  marikina_pasig_exit,
  pureza_exit,
  recto_exit,
  santolan_exit,
  v_mapa_exit,
  total_entry,
  total_exit,
  load_timestamp
)
SELECT
  'YR2023-' || TO_CHAR(date, 'YYYYMMDD') || '-' || LEFT(time_period, 2) as id,
  date, LEFT(time_period, 5),
  anonas_entry, anonas_exit, antipolo_entry, antipolo_exit, araneta_center_cubao_entry, araneta_center_cubao_exit,
  betty_go_belmonte_entry, betty_go_belmonte_exit, entry_entry, exit_entry, gilmore_entry, gilmore_exit,
  j_ruiz_entry, j_ruiz_exit, katipunan_entry, katipunan_exit, legarda_entry, legarda_exit, marikina_pasig_entry, marikina_pasig_exit,
  pureza_entry, pureza_exit, recto_entry, recto_exit, santolan_entry, santolan_exit, v_mapa_entry, v_mapa_exit,
  total_entry, total_exit, CURRENT_TIMESTAMP
FROM "AFCS".ridership_2023_backup
WHERE time_period LIKE '__:__-__:__';

-- Part 2: Expand the band rows of 2023
INSERT INTO "AFCS".ridership_2023 (
  id,
  date,
  time_period,
  anonas_entry,
  antipolo_entry,
  araneta_center_cubao_entry,
  betty_go_belmonte_entry,
  entry_entry,
  gilmore_entry,
  j_ruiz_entry,
  katipunan_entry,
  legarda_entry,
  marikina_pasig_entry,
  pureza_entry,
  recto_entry,
  santolan_entry,
  v_mapa_entry,
  anonas_exit,
  antipolo_exit,
  araneta_center_cubao_exit,
  betty_go_belmonte_exit,
  exit_entry,
  gilmore_exit,
  j_ruiz_exit,
  katipunan_exit,
  legarda_exit,
  marikina_pasig_exit,
  pureza_exit,
  recto_exit,
  santolan_exit,
  v_mapa_exit,
  total_entry,
  total_exit,
  load_timestamp
)
WITH hour_weights (band, time_period, seq, weight, cum_weight, cum_weight_prev) AS (
  VALUES
    ('5-7am (OFF PEAK)',   '05:00', 1, 0.294976632537090, 0.294976632537090, 0.0),
    ('5-7am (OFF PEAK)',   '06:00', 2, 0.705023367462910, 1.0,               0.294976632537090),
    ('7-9am (AM PEAK)',    '07:00', 1, 0.544024908634851, 0.544024908634851, 0.0),
    ('7-9am (AM PEAK)',    '08:00', 2, 0.455975091365149, 1.0,               0.544024908634851),
    ('9am-5pm (OFF PEAK)', '09:00', 1, 0.115810405840533, 0.115810405840533, 0.0),
    ('9am-5pm (OFF PEAK)', '10:00', 2, 0.109552336053815, 0.225362741894348, 0.115810405840533),
    ('9am-5pm (OFF PEAK)', '11:00', 3, 0.112527198170051, 0.337889940064399, 0.225362741894348),
    ('9am-5pm (OFF PEAK)', '12:00', 4, 0.125297635652118, 0.463187575716517, 0.337889940064399),
    ('9am-5pm (OFF PEAK)', '13:00', 5, 0.122739214381356, 0.585926790097873, 0.463187575716517),
    ('9am-5pm (OFF PEAK)', '14:00', 6, 0.122510819491823, 0.708437609589696, 0.585926790097873),
    ('9am-5pm (OFF PEAK)', '15:00', 7, 0.133837412726751, 0.842275022316447, 0.708437609589696),
    ('9am-5pm (OFF PEAK)', '16:00', 8, 0.157724977683553, 1.0,               0.842275022316447),
    ('5-7pm (PM PEAK)',    '17:00', 1, 0.514927690590153, 0.514927690590153, 0.0),
    ('5-7pm (PM PEAK)',    '18:00', 2, 0.485072309409847, 1.0,               0.514927690590153),
    ('7-10pm (OFF PEAK)',  '19:00', 1, 0.511999956428162, 0.511999956428162, 0.0),
    ('7-10pm (OFF PEAK)',  '20:00', 2, 0.367992309570645, 0.879992265998807, 0.511999956428162),
    ('7-10pm (OFF PEAK)',  '21:00', 3, 0.120007734001193, 1.0,               0.879992265998807)
),
base_rows AS (
  SELECT
    r.*,
    (COALESCE(r.anonas_entry, 0) + COALESCE(r.antipolo_entry, 0) + COALESCE(r.araneta_center_cubao_entry, 0) + COALESCE(r.betty_go_belmonte_entry, 0) + COALESCE(r.entry_entry, 0) + COALESCE(r.gilmore_entry, 0) + COALESCE(r.j_ruiz_entry, 0) + COALESCE(r.katipunan_entry, 0) + COALESCE(r.legarda_entry, 0) + COALESCE(r.marikina_pasig_entry, 0) + COALESCE(r.pureza_entry, 0) + COALESCE(r.recto_entry, 0) + COALESCE(r.santolan_entry, 0) + COALESCE(r.v_mapa_entry, 0)) as c_ent_sum,
    (COALESCE(r.anonas_exit, 0) + COALESCE(r.antipolo_exit, 0) + COALESCE(r.araneta_center_cubao_exit, 0) + COALESCE(r.betty_go_belmonte_exit, 0) + COALESCE(r.exit_entry, 0) + COALESCE(r.gilmore_exit, 0) + COALESCE(r.j_ruiz_exit, 0) + COALESCE(r.katipunan_exit, 0) + COALESCE(r.legarda_exit, 0) + COALESCE(r.marikina_pasig_exit, 0) + COALESCE(r.pureza_exit, 0) + COALESCE(r.recto_exit, 0) + COALESCE(r.santolan_exit, 0) + COALESCE(r.v_mapa_exit, 0)) as c_ext_sum
  FROM "AFCS".ridership_2023_backup r
  WHERE r.time_period NOT IN ('Daily Total', 'Monthly Total', 'Peak Total') AND r.time_period NOT LIKE '__:__-__:__'
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
SELECT
  'YR2023-' || TO_CHAR(date, 'YYYYMMDD') || '-' || LEFT(hr_period, 2) as id,
  date, hr_period,
  
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as anonas_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as antipolo_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as araneta_center_cubao_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as betty_go_belmonte_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(entry_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as entry_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(entry_entry, 0) + COALESCE(gilmore_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(entry_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as gilmore_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(entry_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(entry_entry, 0) + COALESCE(gilmore_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as j_ruiz_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(entry_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(entry_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as katipunan_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(entry_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(entry_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as legarda_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(entry_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(entry_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as marikina_pasig_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(entry_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(entry_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as pureza_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(entry_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0) + COALESCE(recto_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(entry_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as recto_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(entry_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0) + COALESCE(recto_entry, 0) + COALESCE(santolan_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(entry_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0) + COALESCE(recto_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as santolan_entry,
  hr_total_entry - (
    CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(entry_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0) + COALESCE(recto_entry, 0) + COALESCE(santolan_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END
  ) as v_mapa_entry,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as anonas_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as antipolo_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as araneta_center_cubao_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as betty_go_belmonte_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(exit_entry, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as exit_entry,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(exit_entry, 0) + COALESCE(gilmore_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(exit_entry, 0))::double precision / c_ext_sum)::integer ELSE 0 END as gilmore_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(exit_entry, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(exit_entry, 0) + COALESCE(gilmore_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as j_ruiz_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(exit_entry, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(exit_entry, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as katipunan_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(exit_entry, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(exit_entry, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as legarda_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(exit_entry, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(exit_entry, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as marikina_pasig_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(exit_entry, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(exit_entry, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as pureza_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(exit_entry, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0) + COALESCE(recto_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(exit_entry, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as recto_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(exit_entry, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0) + COALESCE(recto_exit, 0) + COALESCE(santolan_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(exit_entry, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0) + COALESCE(recto_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as santolan_exit,
  hr_total_exit - (
    CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(exit_entry, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0) + COALESCE(recto_exit, 0) + COALESCE(santolan_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END
  ) as v_mapa_exit,
  
  hr_total_entry as total_entry,
  hr_total_exit as total_exit,
  CURRENT_TIMESTAMP
FROM hourly_distributed_totals;

-- Part 3: Copy Daily Total, Monthly Total, Peak Total aggregates for 2023
INSERT INTO "AFCS".ridership_2023 (
  anonas_entry, anonas_exit, antipolo_entry, antipolo_exit, araneta_center_cubao_entry, araneta_center_cubao_exit,
  betty_go_belmonte_entry, betty_go_belmonte_exit, entry_entry, exit_entry, gilmore_entry, gilmore_exit,
  j_ruiz_entry, j_ruiz_exit, katipunan_entry, katipunan_exit, legarda_entry, legarda_exit, marikina_pasig_entry, marikina_pasig_exit,
  pureza_entry, pureza_exit, recto_entry, recto_exit, santolan_entry, santolan_exit, v_mapa_entry, v_mapa_exit,
  id, date, time_period, total_entry, total_exit, load_timestamp
)
SELECT
  anonas_entry, anonas_exit, antipolo_entry, antipolo_exit, araneta_center_cubao_entry, araneta_center_cubao_exit,
  betty_go_belmonte_entry, betty_go_belmonte_exit, entry_entry, exit_entry, gilmore_entry, gilmore_exit,
  j_ruiz_entry, j_ruiz_exit, katipunan_entry, katipunan_exit, legarda_entry, legarda_exit, marikina_pasig_entry, marikina_pasig_exit,
  pureza_entry, pureza_exit, recto_entry, recto_exit, santolan_entry, santolan_exit, v_mapa_entry, v_mapa_exit,
  id, date,
  CASE 
    WHEN time_period = 'Daily Total' THEN 'DAILY_TOTAL'
    WHEN time_period = 'Monthly Total' THEN 'MONTHLY_TOTAL'
    WHEN time_period = 'Peak Total' THEN 'PEAK_TOTAL'
  END,
  total_entry, total_exit, CURRENT_TIMESTAMP
FROM "AFCS".ridership_2023_backup
WHERE time_period IN ('Daily Total', 'Monthly Total', 'Peak Total');


-- ============================================================
-- TRANSFORM ridership_2024
-- ============================================================
DROP TABLE IF EXISTS "AFCS".ridership_2024;
CREATE TABLE "AFCS".ridership_2024 AS SELECT * FROM "AFCS".ridership_2021 WHERE 1=0;

INSERT INTO "AFCS".ridership_2024 (
  id,
  date,
  time_period,
  anonas_entry,
  antipolo_entry,
  araneta_center_cubao_entry,
  betty_go_belmonte_entry,
  gilmore_entry,
  j_ruiz_entry,
  katipunan_entry,
  legarda_entry,
  marikina_pasig_entry,
  pureza_entry,
  recto_entry,
  santolan_entry,
  v_mapa_entry,
  anonas_exit,
  antipolo_exit,
  araneta_center_cubao_exit,
  betty_go_belmonte_exit,
  gilmore_exit,
  j_ruiz_exit,
  katipunan_exit,
  legarda_exit,
  marikina_pasig_exit,
  pureza_exit,
  recto_exit,
  santolan_exit,
  v_mapa_exit,
  total_entry,
  total_exit,
  load_timestamp
)
WITH hour_weights (band, time_period, seq, weight, cum_weight, cum_weight_prev) AS (
  VALUES
    ('5-7am (OFF PEAK)',   '05:00', 1, 0.294976632537090, 0.294976632537090, 0.0),
    ('5-7am (OFF PEAK)',   '06:00', 2, 0.705023367462910, 1.0,               0.294976632537090),
    ('7-9am (AM PEAK)',    '07:00', 1, 0.544024908634851, 0.544024908634851, 0.0),
    ('7-9am (AM PEAK)',    '08:00', 2, 0.455975091365149, 1.0,               0.544024908634851),
    ('9am-5pm (OFF PEAK)', '09:00', 1, 0.115810405840533, 0.115810405840533, 0.0),
    ('9am-5pm (OFF PEAK)', '10:00', 2, 0.109552336053815, 0.225362741894348, 0.115810405840533),
    ('9am-5pm (OFF PEAK)', '11:00', 3, 0.112527198170051, 0.337889940064399, 0.225362741894348),
    ('9am-5pm (OFF PEAK)', '12:00', 4, 0.125297635652118, 0.463187575716517, 0.337889940064399),
    ('9am-5pm (OFF PEAK)', '13:00', 5, 0.122739214381356, 0.585926790097873, 0.463187575716517),
    ('9am-5pm (OFF PEAK)', '14:00', 6, 0.122510819491823, 0.708437609589696, 0.585926790097873),
    ('9am-5pm (OFF PEAK)', '15:00', 7, 0.133837412726751, 0.842275022316447, 0.708437609589696),
    ('9am-5pm (OFF PEAK)', '16:00', 8, 0.157724977683553, 1.0,               0.842275022316447),
    ('5-7pm (PM PEAK)',    '17:00', 1, 0.514927690590153, 0.514927690590153, 0.0),
    ('5-7pm (PM PEAK)',    '18:00', 2, 0.485072309409847, 1.0,               0.514927690590153),
    ('7-10pm (OFF PEAK)',  '19:00', 1, 0.511999956428162, 0.511999956428162, 0.0),
    ('7-10pm (OFF PEAK)',  '20:00', 2, 0.367992309570645, 0.879992265998807, 0.511999956428162),
    ('7-10pm (OFF PEAK)',  '21:00', 3, 0.120007734001193, 1.0,               0.879992265998807)
),
base_rows AS (
  SELECT
    r.*,
    (COALESCE(r.anonas_entry, 0) + COALESCE(r.antipolo_entry, 0) + COALESCE(r.araneta_center_cubao_entry, 0) + COALESCE(r.betty_go_belmonte_entry, 0) + COALESCE(r.gilmore_entry, 0) + COALESCE(r.j_ruiz_entry, 0) + COALESCE(r.katipunan_entry, 0) + COALESCE(r.legarda_entry, 0) + COALESCE(r.marikina_pasig_entry, 0) + COALESCE(r.pureza_entry, 0) + COALESCE(r.recto_entry, 0) + COALESCE(r.santolan_entry, 0) + COALESCE(r.v_mapa_entry, 0)) as c_ent_sum,
    (COALESCE(r.anonas_exit, 0) + COALESCE(r.antipolo_exit, 0) + COALESCE(r.araneta_center_cubao_exit, 0) + COALESCE(r.betty_go_belmonte_exit, 0) + COALESCE(r.gilmore_exit, 0) + COALESCE(r.j_ruiz_exit, 0) + COALESCE(r.katipunan_exit, 0) + COALESCE(r.legarda_exit, 0) + COALESCE(r.marikina_pasig_exit, 0) + COALESCE(r.pureza_exit, 0) + COALESCE(r.recto_exit, 0) + COALESCE(r.santolan_exit, 0) + COALESCE(r.v_mapa_exit, 0)) as c_ext_sum
  FROM "AFCS".ridership_2024_backup r
  WHERE r.time_period != 'Daily Total'
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
SELECT
  'YR2024-' || TO_CHAR(date, 'YYYYMMDD') || '-' || LEFT(hr_period, 2) as id,
  date, hr_period,
  
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as anonas_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as antipolo_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as araneta_center_cubao_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as betty_go_belmonte_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as gilmore_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as j_ruiz_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as katipunan_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as legarda_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as marikina_pasig_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as pureza_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0) + COALESCE(recto_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as recto_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0) + COALESCE(recto_entry, 0) + COALESCE(santolan_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0) + COALESCE(recto_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as santolan_entry,
  hr_total_entry - (
    CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0) + COALESCE(recto_entry, 0) + COALESCE(santolan_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END
  ) as v_mapa_entry,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as anonas_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as antipolo_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as araneta_center_cubao_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as betty_go_belmonte_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as gilmore_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as j_ruiz_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as katipunan_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as legarda_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as marikina_pasig_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as pureza_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0) + COALESCE(recto_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as recto_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0) + COALESCE(recto_exit, 0) + COALESCE(santolan_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0) + COALESCE(recto_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as santolan_exit,
  hr_total_exit - (
    CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0) + COALESCE(recto_exit, 0) + COALESCE(santolan_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END
  ) as v_mapa_exit,
  
  hr_total_entry as total_entry,
  hr_total_exit as total_exit,
  CURRENT_TIMESTAMP
FROM hourly_distributed_totals;

-- Insert Daily Total Rows
INSERT INTO "AFCS".ridership_2024 (
  anonas_entry, anonas_exit, antipolo_entry, antipolo_exit, araneta_center_cubao_entry, araneta_center_cubao_exit, betty_go_belmonte_entry, betty_go_belmonte_exit, gilmore_entry, gilmore_exit, j_ruiz_entry, j_ruiz_exit, katipunan_entry, katipunan_exit, legarda_entry, legarda_exit, marikina_pasig_entry, marikina_pasig_exit, pureza_entry, pureza_exit, recto_entry, recto_exit, santolan_entry, santolan_exit, v_mapa_entry, v_mapa_exit,
  id, date, time_period, total_entry, total_exit, load_timestamp
)
SELECT
  anonas_entry, anonas_exit, antipolo_entry, antipolo_exit, araneta_center_cubao_entry, araneta_center_cubao_exit, betty_go_belmonte_entry, betty_go_belmonte_exit, gilmore_entry, gilmore_exit, j_ruiz_entry, j_ruiz_exit, katipunan_entry, katipunan_exit, legarda_entry, legarda_exit, marikina_pasig_entry, marikina_pasig_exit, pureza_entry, pureza_exit, recto_entry, recto_exit, santolan_entry, santolan_exit, v_mapa_entry, v_mapa_exit,
  id, date, 'DAILY_TOTAL', total_entry, total_exit, CURRENT_TIMESTAMP
FROM "AFCS".ridership_2024_backup
WHERE time_period = 'Daily Total';


-- ============================================================
-- TRANSFORM ridership_2025
-- ============================================================
DROP TABLE IF EXISTS "AFCS".ridership_2025;
CREATE TABLE "AFCS".ridership_2025 AS SELECT * FROM "AFCS".ridership_2021 WHERE 1=0;

INSERT INTO "AFCS".ridership_2025 (
  id,
  date,
  time_period,
  anonas_entry,
  antipolo_entry,
  araneta_center_cubao_entry,
  betty_go_belmonte_entry,
  gilmore_entry,
  j_ruiz_entry,
  katipunan_entry,
  legarda_entry,
  marikina_pasig_entry,
  pureza_entry,
  recto_entry,
  santolan_entry,
  v_mapa_entry,
  anonas_exit,
  antipolo_exit,
  araneta_center_cubao_exit,
  betty_go_belmonte_exit,
  gilmore_exit,
  j_ruiz_exit,
  katipunan_exit,
  legarda_exit,
  marikina_pasig_exit,
  pureza_exit,
  recto_exit,
  santolan_exit,
  v_mapa_exit,
  total_entry,
  total_exit,
  load_timestamp
)
WITH hour_weights (band, time_period, seq, weight, cum_weight, cum_weight_prev) AS (
  VALUES
    ('5-7am (OFF PEAK)',   '05:00', 1, 0.294976632537090, 0.294976632537090, 0.0),
    ('5-7am (OFF PEAK)',   '06:00', 2, 0.705023367462910, 1.0,               0.294976632537090),
    ('7-9am (AM PEAK)',    '07:00', 1, 0.544024908634851, 0.544024908634851, 0.0),
    ('7-9am (AM PEAK)',    '08:00', 2, 0.455975091365149, 1.0,               0.544024908634851),
    ('9am-5pm (OFF PEAK)', '09:00', 1, 0.115810405840533, 0.115810405840533, 0.0),
    ('9am-5pm (OFF PEAK)', '10:00', 2, 0.109552336053815, 0.225362741894348, 0.115810405840533),
    ('9am-5pm (OFF PEAK)', '11:00', 3, 0.112527198170051, 0.337889940064399, 0.225362741894348),
    ('9am-5pm (OFF PEAK)', '12:00', 4, 0.125297635652118, 0.463187575716517, 0.337889940064399),
    ('9am-5pm (OFF PEAK)', '13:00', 5, 0.122739214381356, 0.585926790097873, 0.463187575716517),
    ('9am-5pm (OFF PEAK)', '14:00', 6, 0.122510819491823, 0.708437609589696, 0.585926790097873),
    ('9am-5pm (OFF PEAK)', '15:00', 7, 0.133837412726751, 0.842275022316447, 0.708437609589696),
    ('9am-5pm (OFF PEAK)', '16:00', 8, 0.157724977683553, 1.0,               0.842275022316447),
    ('5-7pm (PM PEAK)',    '17:00', 1, 0.514927690590153, 0.514927690590153, 0.0),
    ('5-7pm (PM PEAK)',    '18:00', 2, 0.485072309409847, 1.0,               0.514927690590153),
    ('7-10pm (OFF PEAK)',  '19:00', 1, 0.511999956428162, 0.511999956428162, 0.0),
    ('7-10pm (OFF PEAK)',  '20:00', 2, 0.367992309570645, 0.879992265998807, 0.511999956428162),
    ('7-10pm (OFF PEAK)',  '21:00', 3, 0.120007734001193, 1.0,               0.879992265998807)
),
base_rows AS (
  SELECT
    r.*,
    (COALESCE(r.anonas_entry, 0) + COALESCE(r.antipolo_entry, 0) + COALESCE(r.araneta_center_cubao_entry, 0) + COALESCE(r.betty_go_belmonte_entry, 0) + COALESCE(r.gilmore_entry, 0) + COALESCE(r.j_ruiz_entry, 0) + COALESCE(r.katipunan_entry, 0) + COALESCE(r.legarda_entry, 0) + COALESCE(r.marikina_pasig_entry, 0) + COALESCE(r.pureza_entry, 0) + COALESCE(r.recto_entry, 0) + COALESCE(r.santolan_entry, 0) + COALESCE(r.v_mapa_entry, 0)) as c_ent_sum,
    (COALESCE(r.anonas_exit, 0) + COALESCE(r.antipolo_exit, 0) + COALESCE(r.araneta_center_cubao_exit, 0) + COALESCE(r.betty_go_belmonte_exit, 0) + COALESCE(r.gilmore_exit, 0) + COALESCE(r.j_ruiz_exit, 0) + COALESCE(r.katipunan_exit, 0) + COALESCE(r.legarda_exit, 0) + COALESCE(r.marikina_pasig_exit, 0) + COALESCE(r.pureza_exit, 0) + COALESCE(r.recto_exit, 0) + COALESCE(r.santolan_exit, 0) + COALESCE(r.v_mapa_exit, 0)) as c_ext_sum
  FROM "AFCS".ridership_2025_backup r
  WHERE r.time_period != 'Daily Total'
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
SELECT
  'YR2025-' || TO_CHAR(date, 'YYYYMMDD') || '-' || LEFT(hr_period, 2) as id,
  date, hr_period,
  
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as anonas_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as antipolo_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as araneta_center_cubao_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as betty_go_belmonte_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as gilmore_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as j_ruiz_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as katipunan_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as legarda_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as marikina_pasig_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as pureza_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0) + COALESCE(recto_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as recto_entry,
  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0) + COALESCE(recto_entry, 0) + COALESCE(santolan_entry, 0))::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0) + COALESCE(recto_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END as santolan_entry,
  hr_total_entry - (
    CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(anonas_entry, 0) + COALESCE(antipolo_entry, 0) + COALESCE(araneta_center_cubao_entry, 0) + COALESCE(betty_go_belmonte_entry, 0) + COALESCE(gilmore_entry, 0) + COALESCE(j_ruiz_entry, 0) + COALESCE(katipunan_entry, 0) + COALESCE(legarda_entry, 0) + COALESCE(marikina_pasig_entry, 0) + COALESCE(pureza_entry, 0) + COALESCE(recto_entry, 0) + COALESCE(santolan_entry, 0))::double precision / c_ent_sum)::integer ELSE 0 END
  ) as v_mapa_entry,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as anonas_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as antipolo_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as araneta_center_cubao_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as betty_go_belmonte_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as gilmore_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as j_ruiz_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as katipunan_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as legarda_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as marikina_pasig_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as pureza_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0) + COALESCE(recto_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as recto_exit,
  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0) + COALESCE(recto_exit, 0) + COALESCE(santolan_exit, 0))::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0) + COALESCE(recto_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END as santolan_exit,
  hr_total_exit - (
    CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(anonas_exit, 0) + COALESCE(antipolo_exit, 0) + COALESCE(araneta_center_cubao_exit, 0) + COALESCE(betty_go_belmonte_exit, 0) + COALESCE(gilmore_exit, 0) + COALESCE(j_ruiz_exit, 0) + COALESCE(katipunan_exit, 0) + COALESCE(legarda_exit, 0) + COALESCE(marikina_pasig_exit, 0) + COALESCE(pureza_exit, 0) + COALESCE(recto_exit, 0) + COALESCE(santolan_exit, 0))::double precision / c_ext_sum)::integer ELSE 0 END
  ) as v_mapa_exit,
  
  hr_total_entry as total_entry,
  hr_total_exit as total_exit,
  CURRENT_TIMESTAMP
FROM hourly_distributed_totals;

-- Insert Daily Total Rows
INSERT INTO "AFCS".ridership_2025 (
  anonas_entry, anonas_exit, antipolo_entry, antipolo_exit, araneta_center_cubao_entry, araneta_center_cubao_exit, betty_go_belmonte_entry, betty_go_belmonte_exit, gilmore_entry, gilmore_exit, j_ruiz_entry, j_ruiz_exit, katipunan_entry, katipunan_exit, legarda_entry, legarda_exit, marikina_pasig_entry, marikina_pasig_exit, pureza_entry, pureza_exit, recto_entry, recto_exit, santolan_entry, santolan_exit, v_mapa_entry, v_mapa_exit,
  id, date, time_period, total_entry, total_exit, load_timestamp
)
SELECT
  anonas_entry, anonas_exit, antipolo_entry, antipolo_exit, araneta_center_cubao_entry, araneta_center_cubao_exit, betty_go_belmonte_entry, betty_go_belmonte_exit, gilmore_entry, gilmore_exit, j_ruiz_entry, j_ruiz_exit, katipunan_entry, katipunan_exit, legarda_entry, legarda_exit, marikina_pasig_entry, marikina_pasig_exit, pureza_entry, pureza_exit, recto_entry, recto_exit, santolan_entry, santolan_exit, v_mapa_entry, v_mapa_exit,
  id, date, 'DAILY_TOTAL', total_entry, total_exit, CURRENT_TIMESTAMP
FROM "AFCS".ridership_2025_backup
WHERE time_period = 'Daily Total';
