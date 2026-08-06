const fs = require('fs');
const path = require('path');

// Hour Weights CTE values definition
const WEIGHTS_CTE = `WITH hour_weights (band, time_period, seq, weight, cum_weight, cum_weight_prev) AS (
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
)`;

function generateYearSQL(year) {
  const is2023 = (year === 2023);

  // List of entry/exit columns in order
  let entryCols = [
    'anonas_entry', 'antipolo_entry', 'araneta_center_cubao_entry', 'betty_go_belmonte_entry',
    'gilmore_entry', 'j_ruiz_entry', 'katipunan_entry', 'legarda_entry', 'marikina_pasig_entry',
    'pureza_entry', 'recto_entry', 'santolan_entry', 'v_mapa_entry'
  ];
  let exitCols = [
    'anonas_exit', 'antipolo_exit', 'araneta_center_cubao_exit', 'betty_go_belmonte_exit',
    'gilmore_exit', 'j_ruiz_exit', 'katipunan_exit', 'legarda_exit', 'marikina_pasig_exit',
    'pureza_exit', 'recto_exit', 'santolan_exit', 'v_mapa_exit'
  ];

  if (is2023) {
    // 2023 has entry_entry and exit_entry columns in position 4 (0-indexed: index 4)
    entryCols.splice(4, 0, 'entry_entry');
    exitCols.splice(4, 0, 'exit_entry');
  }

  // Generate the COALESCE sum expression
  const c_ent_sum_expr = entryCols.map(col => `COALESCE(r.${col}, 0)`).join(' + ');
  const c_ext_sum_expr = exitCols.map(col => `COALESCE(r.${col}, 0)`).join(' + ');

  // Generate station-level cumulative rounding SELECT fields
  const fields = [];

  // For entries
  for (let i = 0; i < entryCols.length - 1; i++) {
    const col = entryCols[i];
    const prevCols = entryCols.slice(0, i + 1);
    const sumCurrent = prevCols.map(c => `COALESCE(${c}, 0)`).join(' + ');
    
    if (i === 0) {
      fields.push(`  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (COALESCE(${col}, 0))::double precision / c_ent_sum)::integer ELSE 0 END as ${col}`);
    } else {
      const prevSumOnly = entryCols.slice(0, i).map(c => `COALESCE(${c}, 0)`).join(' + ');
      fields.push(`  CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (${sumCurrent})::double precision / c_ent_sum)::integer - ROUND(hr_total_entry * (${prevSumOnly})::double precision / c_ent_sum)::integer ELSE 0 END as ${col}`);
    }
  }
  // Last entry column (v_mapa_entry) takes the remainder
  const entryAllExceptLastSum = entryCols.slice(0, entryCols.length - 1).map(c => `COALESCE(${c}, 0)`).join(' + ');
  fields.push(`  hr_total_entry - (
    CASE WHEN c_ent_sum > 0 THEN ROUND(hr_total_entry * (${entryAllExceptLastSum})::double precision / c_ent_sum)::integer ELSE 0 END
  ) as ${entryCols[entryCols.length - 1]}`);

  // For exits
  for (let i = 0; i < exitCols.length - 1; i++) {
    const col = exitCols[i];
    const prevCols = exitCols.slice(0, i + 1);
    const sumCurrent = prevCols.map(c => `COALESCE(${c}, 0)`).join(' + ');
    
    if (i === 0) {
      fields.push(`  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (COALESCE(${col}, 0))::double precision / c_ext_sum)::integer ELSE 0 END as ${col}`);
    } else {
      const prevSumOnly = exitCols.slice(0, i).map(c => `COALESCE(${c}, 0)`).join(' + ');
      fields.push(`  CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (${sumCurrent})::double precision / c_ext_sum)::integer - ROUND(hr_total_exit * (${prevSumOnly})::double precision / c_ext_sum)::integer ELSE 0 END as ${col}`);
    }
  }
  // Last exit column (v_mapa_exit) takes the remainder
  const exitAllExceptLastSum = exitCols.slice(0, exitCols.length - 1).map(c => `COALESCE(${c}, 0)`).join(' + ');
  fields.push(`  hr_total_exit - (
    CASE WHEN c_ext_sum > 0 THEN ROUND(hr_total_exit * (${exitAllExceptLastSum})::double precision / c_ext_sum)::integer ELSE 0 END
  ) as ${exitCols[exitCols.length - 1]}`);

  const selectFieldsSQL = fields.join(',\n');

  // Let's build the SQL statement
  let sql = `-- ============================================================
-- TRANSFORM ridership_${year}
-- ============================================================
DROP TABLE IF EXISTS "AFCS".ridership_${year};
`;

  if (year === 2021) {
    sql += `CREATE TABLE "AFCS".ridership_2021 (
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
`;
  } else if (is2023) {
    sql += `CREATE TABLE "AFCS".ridership_2023 (
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
`;
  } else {
    sql += `CREATE TABLE "AFCS".ridership_${year} AS SELECT * FROM "AFCS".ridership_2021 WHERE 1=0;
`;
  }

  // Determine insert columns list
  let allCols = [
    'id', 'date', 'time_period',
    ...entryCols, ...exitCols,
    'total_entry', 'total_exit', 'load_timestamp'
  ];

  if (is2023) {
    sql += `
-- Part 1: Copy over original true hourly range rows and map format (e.g. '05:00-06:00' -> '05:00')
INSERT INTO "AFCS".ridership_2023 (
  ${allCols.join(',\n  ')}
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
  ${allCols.join(',\n  ')}
)
`;
  } else {
    sql += `
INSERT INTO "AFCS".ridership_${year} (
  ${allCols.join(',\n  ')}
)
`;
  }

  // CTE and base row select
  sql += `${WEIGHTS_CTE},
base_rows AS (
  SELECT
    r.*,
    (${c_ent_sum_expr}) as c_ent_sum,
    (${c_ext_sum_expr}) as c_ext_sum
  FROM "AFCS".ridership_${year}_backup r
  WHERE r.time_period ${is2023 ? "NOT IN ('Daily Total', 'Monthly Total', 'Peak Total') AND r.time_period NOT LIKE '__:__-__:__'" : "!= 'Daily Total'"}
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
  'YR${year}-' || TO_CHAR(date, 'YYYYMMDD') || '-' || LEFT(hr_period, 2) as id,
  date, hr_period,
  
${selectFieldsSQL},
  
  hr_total_entry as total_entry,
  hr_total_exit as total_exit,
  CURRENT_TIMESTAMP
FROM hourly_distributed_totals;
`;

  // Insert Daily Total rows
  if (is2023) {
    sql += `
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
`;
  } else {
    // Determine standard columns for aggregates
    let stdColsExceptID = [
      'anonas_entry', 'anonas_exit', 'antipolo_entry', 'antipolo_exit', 'araneta_center_cubao_entry', 'araneta_center_cubao_exit',
      'betty_go_belmonte_entry', 'betty_go_belmonte_exit', 'gilmore_entry', 'gilmore_exit', 'j_ruiz_entry', 'j_ruiz_exit',
      'katipunan_entry', 'katipunan_exit', 'legarda_entry', 'legarda_exit', 'marikina_pasig_entry', 'marikina_pasig_exit',
      'pureza_entry', 'pureza_exit', 'recto_entry', 'recto_exit', 'santolan_entry', 'santolan_exit', 'v_mapa_entry', 'v_mapa_exit'
    ];
    sql += `
-- Insert Daily Total Rows
INSERT INTO "AFCS".ridership_${year} (
  ${stdColsExceptID.join(', ')},
  id, date, time_period, total_entry, total_exit, load_timestamp
)
SELECT
  ${stdColsExceptID.join(', ')},
  id, date, 'DAILY_TOTAL', total_entry, total_exit, CURRENT_TIMESTAMP
FROM "AFCS".ridership_${year}_backup
WHERE time_period = 'Daily Total';
`;
  }

  return sql;
}

const finalSQL = `-- ============================================================
-- SQL Script: Proportional Hourly Expansion of 5-Year Ridership (Auto-Generated)
-- Schema: AFCS
-- Source Tables: ridership_2021_backup to ridership_2025_backup
-- Target Tables: ridership_2021 to ridership_2025
-- ============================================================

` +
  [2021, 2022, 2023, 2024, 2025].map(generateYearSQL).join('\n\n');

const outDir = path.join(__dirname, 'sql');
if (!fs.existsSync(outDir)) {
  fs.mkdirSync(outDir, { recursive: true });
}
fs.writeFileSync(path.join(outDir, 'transform_ridership_hourly.sql'), finalSQL);
console.log('Successfully generated transform_ridership_hourly.sql inside sql/ folder with robust COALESCE logic and correct station offsets!');
