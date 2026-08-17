const fs = require('fs');
const path = require('path');
const { Client } = require('pg');
const dns = require('dns');

// Force DNS resolution to prefer IPv4 to bypass broken local IPv6 environments
if (typeof dns.setDefaultResultOrder === 'function') {
  dns.setDefaultResultOrder('ipv4first');
}


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

  // Check 5: Events Consolidated Classification & Normalization Checks
  console.log(`\nValidating events classification & normalization...`);
  
  // 5a. False Positive Meeting/Ocular Check
  const falsePosQuery = `
    SELECT COUNT(*) AS false_positives
    FROM external.events_consolidated ec
    JOIN external.academic_lgu_events al ON ec.source_id = al.id AND ec.source_table = 'academic_lgu_events'
    WHERE ec.event_category != 'administrative'
      AND (
        al.post_text ~* '(coordination\\s+meeting|ocular\\s+visit|ocular\\s+meeting|planning\\s+meeting|planning\\s+session|preparatory\\s+meeting|committee\\s+meeting|coordination\\s+visit|pre-event\\s+coordination)'
        OR (al.post_text ~* '(meeting|ocular|planning|preparation|discussion)' AND NOT al.post_text ~* '(suspend|walang\\s+pasok|no\\s+class|strike|tigil\\s+pasada|welga)')
      );
  `;
  const fpRes = await client.query(falsePosQuery);
  const falsePositives = parseInt(fpRes.rows[0].false_positives, 10);
  
  if (falsePositives === 0) {
    console.log(`  🟢 Classifier false positives: PASSED (0 planning/meeting events classified as active transit anomalies)`);
  } else {
    console.log(`  🔴 Classifier false positives: FAILED (${falsePositives} coordination/planning meetings incorrectly classified!)`);
    allPassed = false;
  }

  // 5b. Class Suspension and School Break Score Check
  const csQuery = `
    SELECT COUNT(*) AS invalid_suspensions
    FROM external.events_consolidated
    WHERE event_category IN ('class_suspension', 'school_break') AND normalized_score != 1.0;
  `;
  const csRes = await client.query(csQuery);
  const invalidSuspensions = parseInt(csRes.rows[0].invalid_suspensions, 10);

  if (invalidSuspensions === 0) {
    console.log(`  🟢 Class suspension and school break normalization: PASSED (All class suspensions/breaks have normalized_score = 1.0)`);
  } else {
    console.log(`  🔴 Class suspension and school break normalization: FAILED (${invalidSuspensions} suspensions/breaks have invalid scores!)`);
    allPassed = false;
  }

  // 5c. Academic Surge Weight (A_sw) Density Score Check (Step 3b)
  const aswQuery = `
    SELECT COUNT(*) AS invalid_groups
    FROM (
        SELECT event_date, station, COUNT(*) as event_count, MIN(normalized_score) as min_score, MAX(normalized_score) as max_score
        FROM external.events_consolidated
        WHERE event_category = 'major_event'
        GROUP BY event_date, station
    ) g
    WHERE (event_count >= 3 AND (min_score != 1.0 OR max_score != 1.0))
       OR (event_count BETWEEN 1 AND 2 AND (min_score != 0.5 OR max_score != 0.5));
  `;
  const aswRes = await client.query(aswQuery);
  const invalidAswGroups = parseInt(aswRes.rows[0].invalid_groups, 10);

  if (invalidAswGroups === 0) {
    console.log(`  🟢 Academic surge weight (A_sw) density normalization: PASSED (All major events normalized according to event count density per station/date)`);
  } else {
    console.log(`  🔴 Academic surge weight (A_sw) density normalization: FAILED (${invalidAswGroups} station/date groups have incorrect A_sw scores!)`);
    allPassed = false;
  }

  // Check 6: Analytics threshold baselines validation
  console.log(`\nValidating Analytics threshold baselines...`);
  const thresholdQuery = `
    SELECT COUNT(*) as total_rows, COUNT(DISTINCT (station_name, day_of_week, hour_period, flow_type)) as unique_keys
    FROM "Analytics".hourly_threshold_baselines;
  `;
  try {
    const tRes = await client.query(thresholdQuery);
    const totalThresholdRows = parseInt(tRes.rows[0].total_rows, 10);
    const uniqueThresholdKeys = parseInt(tRes.rows[0].unique_keys, 10);

    // 13 stations * 7 days * 17 hours (05:00 to 21:00) * 2 flow types (entry/exit) = 3094 rows expected (or more if early/late hours exist)
    if (totalThresholdRows >= 3094 && totalThresholdRows === uniqueThresholdKeys) {
      console.log(`  🟢 Threshold baselines validation: PASSED (${totalThresholdRows} baseline records calculated and verified)`);
    } else {
      console.log(`  🔴 Threshold baselines validation: FAILED (Expected 3094 rows, found ${totalThresholdRows} total, ${uniqueThresholdKeys} unique)`);
      allPassed = false;
    }
  } catch (err) {
    console.log(`  🔴 Threshold baselines validation: FAILED (Error querying table: ${err.message})`);
    allPassed = false;
  }

  // Check 7: Descriptive View query validation
  console.log(`\nValidating Analytics.descriptive_historical_capacity_benchmarking view accessibility & CFI...`);
  const viewQuery = `
    SELECT COUNT(*) as test_rows, COUNT(*) FILTER (WHERE cfi IS NOT NULL) as valid_cfi_rows
    FROM "Analytics".descriptive_historical_capacity_benchmarking
    LIMIT 100;
  `;
  try {
    const vRes = await client.query(viewQuery);
    const testRows = parseInt(vRes.rows[0].test_rows, 10);
    const validCfiRows = parseInt(vRes.rows[0].valid_cfi_rows, 10);
    if (testRows > 0 && testRows === validCfiRows) {
      console.log(`  🟢 Descriptive view validation: PASSED (View is queryable and CFI is calculated for all rows)`);
    } else {
      console.log(`  🔴 Descriptive view validation: FAILED (Query returned ${testRows} rows, but only ${validCfiRows} have valid CFI)`);
      allPassed = false;
    }
  } catch (err) {
    console.log(`  🔴 Descriptive view validation: FAILED (Error querying view: ${err.message})`);
    allPassed = false;
  }

  // Check 7b: Live Event Feed view validation
  console.log(`\nValidating Analytics.descriptive_live_event_feed view...`);
  try {
    const feedRes = await client.query('SELECT COUNT(*) as count FROM "Analytics".descriptive_live_event_feed');
    console.log(`  🟢 Live event feed view validation: PASSED (View is queryable, currently ${feedRes.rows[0].count} active triggers for today)`);
  } catch (err) {
    console.log(`  🔴 Live event feed view validation: FAILED (Error querying view: ${err.message})`);
    allPassed = false;
  }

  // Check 7c: Simulation History table validation
  console.log(`\nValidating Analytics.simulation_history table...`);
  try {
    const histRes = await client.query('SELECT COUNT(*) as count FROM "Analytics".simulation_history');
    console.log(`  🟢 Simulation history table validation: PASSED (Table is queryable, holds ${histRes.rows[0].count} archived records)`);
  } catch (err) {
    console.log(`  🔴 Simulation history table validation: FAILED (Error: ${err.message})`);
    allPassed = false;
  }

  // Check 8: Feature engineering view validation
  console.log(`\nValidating Analytics.vw_predictive_features view...`);
  const featQuery = `
    SELECT COUNT(*) as test_rows
    FROM "Analytics".vw_predictive_features
    LIMIT 10;
  `;
  try {
    const featRes = await client.query(featQuery);
    const testRows = parseInt(featRes.rows[0].test_rows, 10);
    if (testRows > 0) {
      console.log(`  🟢 Feature engineering view validation: PASSED (View is queryable)`);
    } else {
      console.log(`  🔴 Feature engineering view validation: FAILED (Returned 0 rows)`);
      allPassed = false;
    }
  } catch (err) {
    console.log(`  🔴 Feature engineering view validation: FAILED (Error: ${err.message})`);
    allPassed = false;
  }

  // Check 8b: Model Auditing view validation
  console.log(`\nValidating Analytics.descriptive_model_auditing_drift_tracking view...`);
  try {
    await client.query('SELECT COUNT(*) FROM "Analytics".descriptive_model_auditing_drift_tracking LIMIT 1');
    console.log(`  🟢 Model auditing view validation: PASSED (View is queryable and ready to compute prediction errors)`);
  } catch (err) {
    console.log(`  🔴 Model auditing view validation: FAILED (Error querying view: ${err.message})`);
    allPassed = false;
  }

  // Check 9: Scenario simulation function validation
  console.log(`\nValidating Analytics.simulate_scenario function...`);
  const simQuery = `
    SELECT * FROM "Analytics".simulate_scenario('Katipunan', 1, '17:00', 'entry', 0.8, 1.0, 0.0, 1000);
  `;
  try {
    const simRes = await client.query(simQuery);
    if (simRes.rows.length > 0) {
      const row = simRes.rows[0];
      const base = parseFloat(row.baseline_mean_forecast);
      const peak = parseFloat(row.simulated_forecasted_peak);
      const variance = parseFloat(row.forecasted_peak_variance);
      const threat = row.simulated_threat_level;
      
      // Math check: base = 1000, academic = 1.0 (surge), weather = 0.8 (rain)
      // Adjustment = (0.30 * 1.0) - (0.175 * 0.8) = 0.30 - 0.14 = +0.16 (16%)
      // Peak = 1000 * 1.16 = 1160
      // Variance = +16.00%
      if (base === 1000 && peak === 1160 && variance === 16.00) {
        console.log(`  🟢 Simulation function validation: PASSED (Base: ${base}, Peak: ${peak}, Variance: ${variance}%, Threat: ${threat})`);
      } else {
        console.log(`  🔴 Simulation function validation: FAILED (Math check mismatch! Expected base 1000/peak 1160/variance 16%, got: base ${base}/peak ${peak}/variance ${variance}%)`);
        allPassed = false;
      }
    } else {
      console.log(`  🔴 Simulation function validation: FAILED (Returned 0 rows)`);
      allPassed = false;
    }
  } catch (err) {
    console.log(`  🔴 Simulation function validation: FAILED (Error: ${err.message})`);
    allPassed = false;
  }

  // Check 10: Multi-horizon views query validation
  console.log(`\nValidating Analytics multi-horizon views...`);
  const horizonViews = [
    'predictive_passenger_volume_forecast_24h',
    'predictive_passenger_volume_forecast_1w',
    'predictive_passenger_volume_forecast_1m',
    'predictive_passenger_volume_forecast_quarterly',
    'predictive_passenger_volume_forecast_1y'
  ];
  for (const view of horizonViews) {
    try {
      const hRes = await client.query(`SELECT COUNT(*) as count FROM "Analytics".${view}`);
      console.log(`  🟢 View "Analytics".${view} query: PASSED (${hRes.rows[0].count} rows)`);
    } catch (err) {
      console.log(`  🔴 View "Analytics".${view} query: FAILED (Error: ${err.message})`);
      allPassed = false;
    }
  }

  // Check 11: Prescriptive Tier verification (APTA Schema Integration)
  console.log(`\nValidating Analytics prescriptive layer (APTA Schema)...`);
  try {
    const capRes = await client.query('SELECT COUNT(*) as count FROM "Analytics".prescriptive_station_capacities');
    const capCount = parseInt(capRes.rows[0].count, 10);
    
    const protoRes = await client.query('SELECT COUNT(*) as count FROM "APTA".apta_protocols');
    const protoCount = parseInt(protoRes.rows[0].count, 10);

    const auditRes = await client.query('SELECT symbolic_heuristic_compliance_rate_scr as scr FROM "Analytics".prescriptive_compliance_audit');
    const scrValue = parseFloat(auditRes.rows[0].scr);

    // Verify deployments schema has latency fields
    const columnsRes = await client.query(`
      SELECT column_name 
      FROM information_schema.columns 
      WHERE table_schema = 'Analytics' AND table_name = 'prescriptive_protocol_deployments'
    `);
    const cols = columnsRes.rows.map(r => r.column_name);
    const hasThrottling = cols.includes('turnstile_throttling_rate');
    const hasLatencyFields = cols.includes('ingestion_timestamp') && cols.includes('broadcast_timestamp');

    const recQuery = `
      SELECT decision_action, capacity_utilization
      FROM "Analytics".prescriptive_action_recommendations
      WHERE station_name = 'Legarda' AND flow_type = 'exit' AND date = '2026-11-18' AND time = '04:00'
    `;
    const recRes = await client.query(recQuery);
    
    let stepPassed = true;
    if (capCount !== 13) {
      console.log(`  🔴 FAILED: Expected 13 capacities, got ${capCount}`);
      stepPassed = false;
    }
    if (protoCount < 6) {
      console.log(`  🔴 FAILED: Expected at least 6 valid protocols in APTA schema, got ${protoCount}`);
      stepPassed = false;
    }
    if (scrValue !== 100.0) {
      console.log(`  🔴 FAILED: Expected SCR of 100.0 (empty log default), got ${scrValue}`);
      stepPassed = false;
    }
    if (hasThrottling) {
      console.log(`  🔴 FAILED: prescriptive_protocol_deployments still has turnstile_throttling_rate column`);
      stepPassed = false;
    }
    if (!hasLatencyFields) {
      console.log(`  🔴 FAILED: prescriptive_protocol_deployments is missing ingestion_timestamp or broadcast_timestamp`);
      stepPassed = false;
    }
    if (recRes.rows.length === 0) {
      console.log(`  🔴 FAILED: Active recommendation not found for Legarda on 2026-11-18`);
      stepPassed = false;
    } else {
      const actions = recRes.rows.map(r => r.decision_action);
      if (!actions.includes('APTA-02')) {
        console.log(`  🔴 FAILED: Mismatch in recommendation! Expected list to contain 'APTA-02', got: ${JSON.stringify(actions)}`);
        stepPassed = false;
      }
    }

    if (stepPassed) {
      console.log(`  🟢 Prescriptive validation: PASSED (Capacities: ${capCount}, APTA Protocols: ${protoCount}, Default SCR: ${scrValue}%)`);
    } else {
      allPassed = false;
    }
  } catch (err) {
    console.log(`  🔴 Prescriptive validation: FAILED (Error: ${err.message})`);
    allPassed = false;
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

  let dbHost = process.env.DB_HOST;
  if (!process.env.DATABASE_URL && dbHost) {
    console.log(`🔍 Resolving database host ${dbHost} to IPv4 first...`);
    try {
      const address = await new Promise((resolve, reject) => {
        dns.resolve4(dbHost, (err, addresses) => {
          if (err) reject(err);
          else if (!addresses || addresses.length === 0) reject(new Error('No addresses found'));
          else resolve(addresses[0]);
        });
      });
      console.log(`✅ Resolved to IPv4 (resolve4): ${address}`);
      dbHost = address;
    } catch (err) {
      console.warn(`⚠️ DNS resolve4 failed: ${err.message}. Trying dns.lookup...`);
      try {
        const address = await new Promise((resolve, reject) => {
          dns.lookup(dbHost, { family: 4 }, (err, addr) => {
            if (err) reject(err);
            else resolve(addr);
          });
        });
        console.log(`✅ Resolved to IPv4 (lookup): ${address}`);
        dbHost = address;
      } catch (err2) {
        console.warn(`⚠️ DNS lookup failed: ${err2.message}.`);
      }
    }
  }

  const connectionString = process.env.DATABASE_URL || {
    host: dbHost,
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
    await runSQLFile(client, path.join(__dirname, 'Transformation Layer', 'internal', 'restore_ridership_backups.sql'));

    // 2. Standardize internal dimensions
    await runSQLFile(client, path.join(__dirname, 'Transformation Layer', 'internal', 'standardize_internal_dimensions.sql'));

    // 3. Standardize literature dimensions
    await runSQLFile(client, path.join(__dirname, 'Transformation Layer', 'literature', 'standardize_literature_dimensions.sql'));

    // 4. Standardize external triggers
    await runSQLFile(client, path.join(__dirname, 'Transformation Layer', 'external', 'standardize_external_triggers.sql'));

    // 4b. Deploy Application Schemas (IAM Portal & Ground Control)
    console.log('🚀 Deploying IAM Portal & Ground Control Application Schemas...');
    await runSQLFile(client, path.join(__dirname, 'Transformation Layer', 'applications', 'iam_portal_schema.sql'));
    await runSQLFile(client, path.join(__dirname, 'Transformation Layer', 'applications', 'ground_control_schema.sql'));

    // 5. Transform 5-year data to hourly
    await runSQLFile(client, path.join(__dirname, 'Transformation Layer', 'internal', 'transform_ridership_hourly.sql'));

    // 6. Expand student transactions
    await runSQLFile(client, path.join(__dirname, 'Transformation Layer', 'internal', 'expand_student_transactions.sql'));

    // 7. Generate Descriptive Analytics Layer (New Analytics Step)
    await runSQLFile(client, path.join(__dirname, 'Analytics Layer', 'descriptive', 'generate_descriptive_analytics.sql'));

    // 8. Generate Predictive Analytics Layer (New Analytics Step)
    await runSQLFile(client, path.join(__dirname, 'Analytics Layer', 'predictive', 'generate_predictive_analytics.sql'));

    // 8b. Generate Prescriptive Analytics Layer (New Prescriptive Step)
    await runSQLFile(client, path.join(__dirname, 'Analytics Layer', 'prescriptive', 'generate_prescriptive_analytics.sql'));

    // 9. Run verification
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
