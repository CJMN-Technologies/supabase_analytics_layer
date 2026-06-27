const fs = require('fs');
const path = require('path');

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
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !SERVICE_ROLE_KEY) {
  console.error('❌ SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not configured in .env');
  process.exit(1);
}

// Auto-detect project reference from SUPABASE_URL
const match = supabaseUrl.match(/https?:\/\/([^.]+)/);
const PROJECT_REF = match ? match[1] : '';

if (!PROJECT_REF) {
  console.error('❌ Could not parse PROJECT_REF from SUPABASE_URL');
  process.exit(1);
}

async function runSQL(statement, label) {
  try {
    const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ query: statement }),
    });
    const text = await res.text();
    console.log(`[${label}] HTTP ${res.status}: ${text.slice(0, 500)}`);
    return { status: res.status, body: text };
  } catch (err) {
    console.error(`[${label}] error:`, err);
    return null;
  }
}

async function main() {
  await runSQL("SELECT CURRENT_USER, VERSION()", "test-connection");
}

main().catch(console.error);
