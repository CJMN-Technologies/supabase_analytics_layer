const fs = require('fs');
const path = require('path');
const { createClient } = require('@supabase/supabase-js');

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

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseKey) {
  console.error('❌ SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not configured in .env');
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

async function testRpc(name, args) {
  console.log(`Testing RPC '${name}'...`);
  const { data, error } = await supabase.rpc(name, args);
  if (error) {
    console.log(` - RPC '${name}' failed:`, error.message, error.code);
  } else {
    console.log(` - RPC '${name}' succeeded:`, data);
  }
}

async function main() {
  await testRpc('run_sql', { sql: 'SELECT 1' });
  await testRpc('exec_sql', { query: 'SELECT 1' });
  await testRpc('execute_sql', { sql: 'SELECT 1' });
}

main().catch(console.error);
