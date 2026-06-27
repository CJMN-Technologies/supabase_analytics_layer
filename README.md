# Supabase Transformation & Orchestration Layer (LRT-2 Commuter Friction Index)

This repository contains the database DDL, sync triggers, dynamic ingestion scripts, and validation pipeline for standardizing and transforming the LRT-2 transit ridership logs and environmental factors. 

This layer serves as the **landing and transformation zone** to compute the **Commuter Friction Index (CFI)**, which measures the "transport impedance" exerted on commuters by real-world anomalies (like severe weather, university calendar events, and LGU class suspensions).

---

## 1. Tech Stack
* **Database Engine:** Supabase PostgreSQL (Version 15+)
* **Transformation Language:** PostgreSQL PL/pgSQL (Stored procedures, Triggers, Views)
* **Orchestration:** Built-in `pg_cron` extension (Database-internal scheduling)
* **Pipeline Validation:** Node.js (v18+) using `pg` driver

---

## 2. Directory Structure

```text
├── sql/
│   ├── restore_ridership_backups.sql  # Aggregates raw ridership inputs to backups
│   ├── standardize_schemas_scd.sql    # Standardizes dimensions, sets up dynamic transform, triggers & cron jobs
│   ├── transform_ridership_hourly.sql # Dynamic transformation calling wrapper
│   ├── expand_student_transactions.sql# Distributes student monthly transactions to hourly format
│   ├── consolidate_events_schema.sql  # Text classification classification functions & scraped events sync
│   └── consolidate_weather_schema.sql # Pagasa alert parsing & current/forecast weather sync
├── run_pipeline.js                    # Core orchestration runner and data integrity check suite
├── package.json                       # Node dependencies (pg, @supabase/supabase-js)
├── .env.example                       # Template for database credentials
└── README.md                          # Project Documentation
```

---

## 3. Database Schema & Standardization Rules

### 3a. Dimension Tables (SCD Type 1)
All lookups have been standardized to clean, human-readable primary keys instead of long composite formats:
- `APTA.apta_protocols` (IDs: `APTA-01`, `APTA-02`, ...)
- `PSOR.psor_incidents` (IDs: `PSOR-01`, `PSOR-02`, ...)
- `"Station Capacity".station_platform_capacity` (IDs: `CAP-REC` for Recto, `CAP-LEG` for Legarda, ...)
- `external.friction_weight` (IDs: `FRI-ACxx` for Academic Surge, `FRI-PAxx` for Weather Alerts)

### 3b. Real-Time Consolidated Tables
Triggers process qualitative logs on-write and save them under short, unique IDs:
- **Events Consolidated (`external.events_consolidated`):**
  - Scraped events: `SCR-[CATEGORY_CODE]-[MMDD]-[RAW_ID]`
  - Calendar events: `CAL-[SCHOOL_ACRONYM]-[MMDD]-[ROW_ID]`
  - Auto-normalizes class suspension events to binary score `1.0` (Step 3c).
  - Automatically deduplicates and updates existing rows `ON CONFLICT (id) DO UPDATE` to prevent data duplication.
- **Weather Consolidated (`external.weather_consolidated`):**
  - Weather Current: `WTH-CUR-[STATION]`
  - Weather Forecasts: `WTH-FCT-[ID]`

### 3c. Dynamic Proportional Ingestion
Ridership tables (`ridership_2021` to `ridership_2025` and incoming future tables) are transformed from non-standard daily/off-peak bands into a continuous hourly scale:
- Auto-renames incoming source tables to `*_backup` to preserve data lineage.
- Scans and maps station columns dynamically, ignoring garbage or dummy columns.
- Performs **double-layered cumulative rounding** distribution to ensure that the sum of the allocated hourly records matches the raw daily totals exactly with **0 row-sum discrepancies**.
- Inserts hourly records with format `YR[YY]-[MMDD]-[HH]` (e.g. `YR21-0101-05`), daily total records `YR[YY]-[MMDD]-DT`, and monthly total records `YR[YY]-[MM]-MT`.

---

## 4. Setup & Running the Pipeline

### Prerequisites
- Node.js (v18+)
- A running Supabase PostgreSQL database with the `pg_cron` extension enabled.

### 1. Configure Credentials
Duplicate `.env.example` to `.env` and fill in your connection details:
```bash
cp .env.example .env
```

### 2. Install Dependencies
```bash
npm install
```

### 3. Run the Database Rebuild & Verification Pipeline
This script runs the database restores, standardizes schemas and dimensions, executes dynamic transformations, expands student transactions, and performs structural verifications:
```bash
node run_pipeline.js
```

---

## 5. Verification & Integrity Checks

The Node validation script performs three core integrity checks on every active table:
1. **Row Sum Discrepancy Check:** Verifies that the sum of all individual station entry/exit columns matches the `total_entry` and `total_exit` columns exactly.
2. **Negative Value Check:** Scans all stations and total columns to guarantee that no negative values exist.
3. **Unique IDs Check:** Validates that there are no duplicate Primary Keys.
