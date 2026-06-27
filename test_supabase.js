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

async function main() {
  console.log("Checking vw_pakiship_descriptive...");
  const { data, error } = await supabase.from('vw_pakiship_descriptive').select('*');
  if (error) {
    console.error("Error querying vw_pakiship_descriptive:", error);
  } else {
    console.log("vw_pakiship_descriptive exists and returned data:", data);
  }

  console.log("Checking vw_pakiship_predictive...");
  const { data: predData, error: predError } = await supabase.from('vw_pakiship_predictive').select('*');
  if (predError) {
    console.error("Error querying vw_pakiship_predictive:", predError);
  } else {
    console.log("vw_pakiship_predictive exists and returned data:", predData);
  }

  console.log("Checking vw_pakiship_prescriptive...");
  const { data: presData, error: presError } = await supabase.from('vw_pakiship_prescriptive').select('*');
  if (presError) {
    console.error("Error querying vw_pakiship_prescriptive:", presError);
  } else {
    console.log("vw_pakiship_prescriptive exists and returned data:", presData);
  }
}

main().catch(console.error);
