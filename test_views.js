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

async function main() {
  await client.connect();
  console.log("Connected directly successfully!");
  const res = await client.query("SELECT CURRENT_USER, VERSION()");
  console.log("Result:", res.rows[0]);
  await client.end();
}

main().catch(console.error);
