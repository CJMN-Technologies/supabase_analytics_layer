const fs = require('fs');
const path = require('path');
const { Client } = require('pg');

// Simple .env file parser (removes need for external dotenv dependency)
function loadEnv() {
  const envPath = path.join(__dirname, '.env');
  if (fs.existsSync(envPath)) {
    const envFile = fs.readFileSync(envPath, 'utf8');
    envFile.split(/\r?\n/).forEach(line => {
      const parts = line.split('=');
      if (parts.length >= 2) {
        const key = parts[0].trim();
        const val = parts.slice(1).join('=').trim().replace(/(^['"]|['"]$)/g, '');
        if (key && !key.startsWith('#')) {
          process.env[key] = val;
        }
      }
    });
    console.log('✅ Loaded environment configuration from .env file.');
  } else {
    console.log('ℹ️ No .env file found. Utilizing system environment variables.');
  }
}

async function runSQLFile(client, filePath) {
  console.log(`\n📖 Reading SQL file: ${path.basename(filePath)}...`);
  if (!fs.existsSync(filePath)) {
    throw new Error(`SQL file not found at: ${filePath}`);
  }
  const sql = fs.readFileSync(filePath, 'utf8');
  console.log(`🚀 Executing statements...`);
  const startTime = Date.now();
  await client.query(sql);
  const duration = ((Date.now() - startTime) / 1000).toFixed(2);
  console.log(`✅ Successfully executed ${path.basename(filePath)} in ${duration}s`);
}

async function verifyIntegrity(client) {
  console.log('\n============================================================');
  console.log('🔍 RUNNING DATA INTEGRITY VERIFICATIONS');
  console.log('============================================================');

  const tables = [
    'ridership_2021',
    'ridership_2022',
    'ridership_2023',
    'ridership_2024',
    'ridership_2025',
    'student_transactions'
  ];

  let allPassed = true;

  for (const table of tables) {
    console.log(`\nAnalyzing table "AFCS".${table}...`);

    // Check 1: Row Sum Discrepancy Check (total_entry/total_exit vs sum of stations)
    // For 2023, detect table to skip raw source hourly discrepancies on June and Nov 1st
    const is2023 = table === 'ridership_2023';
    const entrySumExpr = `anonas_entry + antipolo_entry + araneta_center_cubao_entry + betty_go_belmonte_entry + gilmore_entry + j_ruiz_entry + katipunan_entry + legarda_entry + marikina_pasig_entry + pureza_entry + recto_entry + santolan_entry + v_mapa_entry`;
    const exitSumExpr = `anonas_exit + antipolo_exit + araneta_center_cubao_exit + betty_go_belmonte_exit + gilmore_exit + j_ruiz_exit + katipunan_exit + legarda_exit + marikina_pasig_exit + pureza_exit + recto_exit + santolan_exit + v_mapa_exit`;

    const sumQuery = `
      SELECT COUNT(*) as discrepancies
      FROM "AFCS".${table}
      WHERE time_period NOT IN ('DAILY_TOTAL', 'MONTHLY_TOTAL', 'PEAK_TOTAL')
        ${is2023 ? "AND NOT (EXTRACT(month FROM date) = 6 OR (EXTRACT(month FROM date) = 11 AND EXTRACT(day FROM date) = 1))" : ""}
        AND ((${entrySumExpr}) != total_entry OR (${exitSumExpr}) != total_exit);
    `;
    const sumRes = await client.query(sumQuery);
    const discrepancies = parseInt(sumRes.rows[0].discrepancies, 10);

    if (discrepancies === 0) {
      if (is2023) {
        console.log(`  🟢 Row sums validation: PASSED (0 discrepancies, excluding pre-existing source hourly rows for June & Nov 1st)`);
      } else {
        console.log(`  🟢 Row sums validation: PASSED (0 discrepancies)`);
      }
    } else {
      console.log(`  🔴 Row sums validation: FAILED (${discrepancies} discrepancies found!)`);
      allPassed = false;
    }

    // Check 2: Negative Value Check
    // Verify that all station columns and total columns are non-negative
    const stationsList = [
      'anonas_entry', 'anonas_exit', 'antipolo_entry', 'antipolo_exit',
      'araneta_center_cubao_entry', 'araneta_center_cubao_exit',
      'betty_go_belmonte_entry', 'betty_go_belmonte_exit',
      'gilmore_entry', 'gilmore_exit', 'j_ruiz_entry', 'j_ruiz_exit',
      'katipunan_entry', 'katipunan_exit', 'legarda_entry', 'legarda_exit',
      'marikina_pasig_entry', 'marikina_pasig_exit', 'pureza_entry', 'pureza_exit',
      'recto_entry', 'recto_exit', 'santolan_entry', 'santolan_exit',
      'v_mapa_entry', 'v_mapa_exit', 'total_entry', 'total_exit'
    ];
    // check for raw dummy columns removed

    const negConditions = stationsList.map(col => `${col} < 0`).join(' OR ');
    const negQuery = `
      SELECT COUNT(*) as negative_count
      FROM "AFCS".${table}
      WHERE ${negConditions};
    `;
    const negRes = await client.query(negQuery);
    const negCount = parseInt(negRes.rows[0].negative_count, 10);

    if (negCount === 0) {
      console.log(`  🟢 Negative values validation: PASSED (0 negative values)`);
    } else {
      console.log(`  🔴 Negative values validation: FAILED (${negCount} negative values found!)`);
      allPassed = false;
    }

    // Check 3: Unique Primary Key Check
    const pkQuery = `
      SELECT COUNT(*) as total_rows, COUNT(DISTINCT id) as unique_ids
      FROM "AFCS".${table};
    `;
    const pkRes = await client.query(pkQuery);
    const totalRows = parseInt(pkRes.rows[0].total_rows, 10);
    const uniqueIds = parseInt(pkRes.rows[0].unique_ids, 10);

    if (totalRows === uniqueIds) {
      console.log(`  🟢 Unique IDs validation: PASSED (${totalRows} rows, all unique)`);
    } else {
      console.log(`  🔴 Unique IDs validation: FAILED (Duplicate IDs found! Total rows: ${totalRows}, Unique IDs: ${uniqueIds})`);
      allPassed = false;
    }
  }

  // Check 4: Student transactions monthly sum check
  console.log(`\nValidating student transaction monthly totals vs backups...`);
  const monthlySumQuery = `
    SELECT
      b.year,
      b.month_number,
      b.student_transactions AS original_total,
      SUM(e.total_entry) FILTER (WHERE e.time_period != 'DAILY_TOTAL') AS expanded_entry,
      SUM(e.total_exit) FILTER (WHERE e.time_period != 'DAILY_TOTAL') AS expanded_exit
    FROM "AFCS".student_transactions_backup b
    LEFT JOIN "AFCS".student_transactions e
      ON EXTRACT(year FROM e.date) = b.year AND EXTRACT(month FROM e.date) = b.month_number
    WHERE b.is_total = false AND b.student_transactions > 0
    GROUP BY b.year, b.month_number, b.student_transactions
    ORDER BY b.year, b.month_number;
  `;
  const mRes = await client.query(monthlySumQuery);
  let monthlyMatch = true;
  for (const row of mRes.rows) {
    const orig = parseInt(row.original_total, 10);
    const ent = parseInt(row.expanded_entry, 10);
    const ext = parseInt(row.expanded_exit, 10);
    if (orig !== ent || orig !== ext) {
      console.log(`  ❌ Month ${row.year}-${row.month_number}: FAILED (Original: ${orig}, Entry Sum: ${ent}, Exit Sum: ${ext})`);
      monthlyMatch = false;
      allPassed = false;
    }
  }

  if (monthlyMatch) {
    console.log(`  🟢 Monthly sum validation: PASSED (All non-zero months match perfectly with original transactions)`);
  }

  console.log('\n============================================================');
  if (allPassed) {
    console.log('🏆 PIPELINE INTEGRITY CHECK PASSED WITH 100% SUCCESS!');
  } else {
    console.log('⚠️ PIPELINE INTEGRITY CHECK DETECTED DISCREPANCIES. PLEASE INVESTIGATE LOGS.');
  }
  console.log('============================================================');
}

async function main() {
  loadEnv();

  const connectionString = process.env.DATABASE_URL || {
    host: process.env.DB_HOST,
    port: parseInt(process.env.DB_PORT || '5432', 10),
    database: process.env.DB_NAME || 'postgres',
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD,
    ssl: { rejectUnauthorized: false }
  };

  if (typeof connectionString === 'object' && !connectionString.password) {
    console.error('❌ Error: Database password not configured in .env file or environment variables.');
    process.exit(1);
  }

  console.log('🔌 Connecting to Supabase PostgreSQL Database...');
  const client = new Client(connectionString);
  await client.connect();
  console.log('✅ Connected successfully!');

  try {
    // 1. Restore backups
    await runSQLFile(client, path.join(__dirname, 'sql', 'restore_ridership_backups.sql'));

    // 2. Standardize schemas and dimensions
    await runSQLFile(client, path.join(__dirname, 'sql', 'standardize_schemas_scd.sql'));

    // 3. Transform 5-year data to hourly
    await runSQLFile(client, path.join(__dirname, 'sql', 'transform_ridership_hourly.sql'));

    // 4. Expand student transactions
    await runSQLFile(client, path.join(__dirname, 'sql', 'expand_student_transactions.sql'));

    // 4. Run verification
    await verifyIntegrity(client);

  } catch (error) {
    console.error('\n❌ Error executing pipeline step:', error.message);
    process.exit(1);
  } finally {
    await client.end();
    console.log('\n🔌 Database connection closed.');
  }
}

main().catch(console.error);
