const fs = require('fs');
const path = require('path');
const { Client } = require('pg');

// Simple .env file parser
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
  }
}

loadEnv();

const connectionString = process.env.DATABASE_URL || {
  host: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT || '5432', 10),
  database: process.env.DB_NAME || 'postgres',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD,
  ssl: { rejectUnauthorized: false }
};

const client = new Client(connectionString);

async function runTests() {
  console.log('🔄 Connecting to Supabase PostgreSQL database...');
  await client.connect();
  console.log('✅ Connected successfully!\n');

  console.log('🧪 Starting Weather Consolidation Validation Tests...');
  console.log('============================================================');

  // Test 1: Check existing rows in weather_consolidated
  console.log('📊 TEST 1: Checking weather_consolidated row counts...');
  const countRes = await client.query('SELECT COUNT(*), record_type FROM external.weather_consolidated GROUP BY record_type');
  console.log('Current row counts in consolidated table:');
  countRes.rows.forEach(row => {
    console.log(`  - Record Type: ${row.record_type}, Count: ${row.count}`);
  });
  console.log('✅ Test 1 Passed!\n');

  // Test 2: Verify trigger sync on INSERT
  console.log('📝 TEST 2: Testing trigger sync on INSERT into weather_current...');
  const testStation = 'Test Station';
  const testId = 'CUR-TEST';

  // Ensure clean state before testing
  await client.query('DELETE FROM external.weather_current WHERE id = $1 OR station = $2', [testId, testStation]);

  const insertQuery = `
    INSERT INTO external.weather_current (id, station, temperature, humidity, wind_speed, rainfall_mm, computed_rainfall_level, observed_at)
    VALUES ($1, $2, 28.5, 75, 12.5, 0.0, 'None', NOW())
  `;
  await client.query(insertQuery, [testId, testStation]);
  console.log(`  - Mock row inserted into weather_current for: "${testStation}"`);

  // Verify it exists in consolidated table
  const checkInsert = await client.query('SELECT * FROM external.weather_consolidated WHERE id = $1', ['WTH-CUR-' + testStation.toUpperCase().replace(/ /g, '-').replace(/\./g, '')]);
  if (checkInsert.rows.length === 1) {
    const row = checkInsert.rows[0];
    console.log('  - Consolidated row found:');
    console.log(`    * Station: ${row.station}`);
    console.log(`    * Record Type: ${row.record_type}`);
    console.log(`    * Friction Weight (Expected 0.0): ${row.friction_weight}`);
    if (parseFloat(row.friction_weight) === 0.0) {
      console.log('✅ Test 2 Passed!\n');
    } else {
      throw new Error(`Friction weight was ${row.friction_weight} instead of 0.0`);
    }
  } else {
    throw new Error('Consolidated row was not created automatically by trigger.');
  }

  // Test 3: Verify trigger sync and weight recalculation on UPDATE
  console.log('🔄 TEST 3: Testing trigger sync and weight recalculation on UPDATE (Yellow Warning/Heavy Rain)...');
  const updateQuery = `
    UPDATE external.weather_current
    SET computed_rainfall_level = 'Yellow', rainfall_mm = 8.5
    WHERE id = $1
  `;
  await client.query(updateQuery, [testId]);
  console.log('  - Mock row updated in weather_current (computed_rainfall_level = "Yellow")');

  // Verify updated row in consolidated table
  const checkUpdate = await client.query('SELECT * FROM external.weather_consolidated WHERE id = $1', ['WTH-CUR-' + testStation.toUpperCase().replace(/ /g, '-').replace(/\./g, '')]);
  if (checkUpdate.rows.length === 1) {
    const row = checkUpdate.rows[0];
    console.log('  - Consolidated row updated values:');
    console.log(`    * Rainfall mm: ${row.rainfall_mm}`);
    console.log(`    * Computed Rainfall Level: ${row.computed_rainfall_level}`);
    console.log(`    * Friction Weight (Expected 0.65 for Heavy Rain/Yellow): ${row.friction_weight}`);
    if (parseFloat(row.friction_weight) === 0.65) {
      console.log('✅ Test 3 Passed!\n');
    } else {
      throw new Error(`Friction weight was ${row.friction_weight} instead of 0.65`);
    }
  } else {
    throw new Error('Consolidated row was not updated.');
  }

  // Test 4: Verify trigger sync on DELETE
  console.log('🗑️ TEST 4: Testing trigger sync on DELETE...');
  await client.query('DELETE FROM external.weather_current WHERE id = $1', [testId]);
  console.log('  - Mock row deleted from weather_current');

  // Verify deletion in consolidated table
  const checkDelete = await client.query('SELECT * FROM external.weather_consolidated WHERE id = $1', ['WTH-CUR-' + testStation.toUpperCase().replace(/ /g, '-').replace(/\./g, '')]);
  if (checkDelete.rows.length === 0) {
    console.log('  - Consolidated row successfully removed automatically.');
    console.log('✅ Test 4 Passed!\n');
  } else {
    throw new Error('Consolidated row was not deleted.');
  }

  console.log('============================================================');
  console.log('🎉 ALL WEATHER CONSOLIDATION AND TRIGGER TESTS PASSED SUCCESSFULLY!');
}

runTests()
  .catch(err => {
    console.error('❌ Test failed:', err);
    process.exit(1);
  })
  .finally(async () => {
    await client.end();
  });
