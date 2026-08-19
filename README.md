# Supabase Transformation & Orchestration Layer (LRT-2 Commuter Friction Index)

This repository contains the database DDL, sync triggers, dynamic ingestion scripts, and validation pipeline for standardizing and transforming the LRT-2 transit ridership logs and environmental factors. 

This layer serves as the **landing and transformation zone** to compute the **Commuter Friction Index (CFI)**, which measures the "transport impedance" exerted on commuters by real-world anomalies (like severe weather, university calendar events, and LGU class suspensions).

---

## 1. Tech Stack

| Technology Layer | Tool / Engine | Purpose |
| :--- | :--- | :--- |
| **Database Engine** | Supabase PostgreSQL (v15+) | Staging landing zone & main database engine |
| **Transformation Language** | PostgreSQL PL/pgSQL | Custom triggers, classifications, and dynamic proportional distributions |
| **ML Forecasting** | Python (v3.10), XGBoost, Scikit-learn | Trains models and generates daily passenger volume forecasts ($B_m$) |
| **Automation & Scheduling** | GitHub Actions | Triggers daily forecasting pipelines (this repo) and hourly scrapers (`python-source-layer` repo) |
| **Pipeline Validation** | Node.js (v18+) | Executes pipeline DDL updates and performs data integrity checks |

---

## 2. Directory Structure

```text
├── Transformation Layer/
│   ├── internal/
│   │   ├── restore_ridership_backups.sql      # Aggregates raw ridership inputs to backups
│   │   ├── standardize_internal_dimensions.sql# Standardizes PSOR and Station Capacity dimensions
│   │   ├── transform_ridership_hourly.sql     # Converts backups to hourly active ridership
│   │   └── expand_student_transactions.sql    # Distributes student monthly transactions to hourly
│   ├── external/
│   │   ├── consolidate_events_schema.sql      # Text classification & scraped events sync
│   │   ├── consolidate_weather_schema.sql     # Pagasa weather alert parsing & current/forecast weather sync
│   │   └── standardize_external_triggers.sql  # Compiles classifiers and A_sw/PAGASA triggers
│   ├── literature/
│   │   └── standardize_literature_dimensions.sql # Sets up APTA tables and seeds weights
│   └── applications/
│       ├── iam_portal_schema.sql              # User profiles, administrative logs, and custom RBAC DDL
│       └── ground_control_schema.sql          # Mobile shifts, incidents, emergency contacts, and real-time sync triggers
├── run_pipeline.js                            # Core orchestration runner and data integrity check suite
├── package.json                               # Node dependencies (pg, @supabase/supabase-js)
├── .env.example                               # Template for database credentials
└── README.md                                  # Project Documentation
```

---

## 3. Database Schema & Standardization Rules

### 3a. Dimension Tables (SCD Type 1)
All lookups have been standardized to clean, human-readable primary keys instead of long composite formats:
- `APTA.apta_protocols` (IDs: `APTA-01`, `APTA-02`, ...)
- `PSOR.psor_incidents` (IDs: `PSOR-01`, `PSOR-02`, ...)
- `"Station Capacity".station_platform_capacity` (IDs: `CAP-REC` for Recto, `CAP-LEG` for Legarda, ...)
- `external.friction_weight` (IDs: `FRI-ACxx` for Academic Surge, `FRI-PAxx` for Weather Alerts, `FRI-OPxx` for GCS Incidents)

### 3ab. Standardized Application IDs
All application-level keys have been migrated from raw UUID hashes to sequence-based standardized string formats for direct readability:
- **`iam.users`:** `POxxxx` (Provision Officer), `CCOxxxx` (Command Center Officer), and `GCSxxxx` (Ground Control Staff).
- **`iam.audit_logs`:** `AUDxxxxxx` (Audit Logs).
- **`gcs.shifts`:** `SHFxxxxxx` (Ground Shifts).
- **`gcs.incidents`:** `INCxxxxxx` (Logged Incidents).
- **`gcs.emergency_contacts`:** `CONxxxx` (Emergency Contacts).
- **`Analytics.simulation_history`:** `SIMxxxxxx` (Stress Simulations).
- **`Analytics.prescriptive_protocol_deployments`:** `DEPxxxxxx` (APTA Deployments).

### 3b. Real-Time Consolidated Tables
Triggers process qualitative logs on-write and save them under short, unique IDs:
- **Events Consolidated (`external.events_consolidated`):**
  - Scraped events: `SCR-[CATEGORY_CODE]-[MMDD]-[RAW_ID]`
  - Calendar events: `CAL-[SCHOOL_ACRONYM]-[MMDD]-[ROW_ID]`
  - GCS Mobile Incidents: `INC-[MMDD]-[INCIDENT_ID]`
  - Auto-normalizes class suspension and online modality shift events to binary score `1.0` (Step 3c).
  - Automatically propagates `source_url` (Facebook announcement permalink) and `description` (raw post text) into consolidated records.
  - Non-disruptive LGU weather monitoring, rainfall advisories, river maintenance, and road flood updates are classified as `LGU Weather / Flooding Advisory` (`affects_ridership = FALSE`), preventing false-positive capacity dampeners or erroneous `"University Milestone / Surge"` tags.
  - Unofficial student council petitions, academic leniency requests, clinical/health examinations (e.g. FriendlyCare breast/dental/medical checkups), public employment/job fairs (PESO notices), and ID processing schedules are automatically categorized as non-disruptive administrative items (`affects_ridership = FALSE`), preventing false-positive passenger surges.
  - Position-aware regex date parser extracts the earliest primary event date (prioritizing Day-Month and Month-Day based on text appearance) to avoid picking up incidental holiday mentions in memo footnotes.
  - Automatically deduplicates and updates existing rows `ON CONFLICT (id) DO UPDATE` to prevent data duplication.
- **Weather Consolidated (`external.weather_consolidated`):**
  - Weather Current: `WTH-CUR-[STATION]`
  - Weather Forecasts: `WTH-FCT-[ID]`

### 3c. Application Schemas & Real-Time Sync Triggers
We support three personas (Provision Officers `PO`, Command Center Officers `CCO`, Ground Control Staff `GCS`) across two applications:
- **I.A.M Portal (`iam` Schema):**
  - `iam.users` manages system directories, unique security activation keys, and profile URLs linking to the `personnel-images` Supabase storage bucket.
  - `iam.audit_logs` tracks Provision Officer administrative actions (user provisioning, active status toggles) for audit compliance.
  - **Self-Binding & Profile Updates (`user_update_profile`):** Restricts anonymous visibility of registered user accounts and allows authenticated staff members to self-bind their authenticated user IDs (`auth_user_id = auth.uid()`) upon entering their unique `security_key` and update profile fields.
- **Ground Control System (`gcs` Schema):**
  - `gcs.shifts` maps GCS personnel shift jurisdiction assignments to specific LRT-2 stations.
  - `gcs.incidents` logs crowd, platform, sanitation, concourse, or emergency events reported from mobile devices. The `incident_type` is controlled via a custom PostgreSQL Enum (`gcs.incident_category`) aligned with the PSOR schema categories + `'Other'`. Severity is restricted to `'Critical'` and `'Warning'`.
  - `gcs.emergency_contacts` seeds and hosts dynamic dialer hotlines for mobile clients.
  - **Real-Time Sync Trigger (`tg_sync_gcs_incidents`):** Maps GCS incidents into `external.events_consolidated` as `'operational'` friction domain events. If the type is `'Other'`, the trigger captures their custom description and formats the event name as `'Other: <description> (<severity>)'`.
  - **Automatic Resolution Timestamp (`tg_set_resolved_timestamp`):** Automatically populates `resolved_at = now()` when an incident status is set to `'resolved'`, and clears it if reopened.
  - **Automatic Resolution Cleanup:** Setting an incident status to `'resolved'` or deleting the row immediately purges the record from the events feed in real-time.

### 3d. Dynamic Proportional Ingestion
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

## 5. Analytics Layers (Descriptive & Predictive)

### 5a. Descriptive Analytics
*   **Threshold Baselines (`Analytics.hourly_threshold_baselines`):** Pre-computes 80th (Warning) and 90th (Critical) percentiles for every station, day of week, hour period, and flow direction (3,172 baseline records).
*   **Historical Capacity Benchmarking (`public.descriptive_historical_capacity_benchmarking`):** Calculates the live Commuter Friction Index (CFI) by combining weather, academic, civic, and operational trigger weights (25% / 15% / 35% / 25%).

### 5b. Predictive Analytics (ML Integration & What-If Simulator)
*   **Model Predictions (`Analytics.predictive_model_outputs`):** Decoupled storage landing table for external ML model runner predictions ($B_m$).
*   **Model Performance (`Analytics.predictive_model_performance`):** Logs XGBoost MAPE/RMSE and RandomForest accuracy/recall.
*   **Dynamic Volume Adjuster (`Analytics.vw_predictive_metrics`):** Queries a rolling 366-day calendar CTE starting from `CURRENT_DATE`, dynamically scaling forecasts based on weather (-17.5%), academic (+30%), civic (-45%), and GCS operational standstills (-30%) shocks. Falls back to historical medians ($P_{50}$) if model outputs are not yet populated.
*   **What-If Simulator (`"Analytics".predictive_what_if_scenario_simulator`):** Analytics wrapper function to test hypothetical triggers and calculate peak variance and threat levels in under 5ms:
    ```sql
    SELECT * FROM "Analytics".predictive_what_if_scenario_simulator('Katipunan', 1, '17:00', 'entry', 0.8, 1.0, 0.0, 1000);
    ```

### 5c. Analytics Layer Views (Dashboard Endpoints)
Exposed in the `"Analytics"` schema for direct REST API client queries:
*   `"Analytics".descriptive_live_event_feed` (Live event feed & trigger aggregation with **3-tier literature-backed severity calibration**: Critical for $F_s \ge 0.80$ like class suspensions, transport strikes, Red rainfall ($>30$mm), and Typhoon Signal 2+; Warning for $0.45 \le F_s < 0.80$ like arena concerts, Orange/Yellow rainfall ($7.5–30$mm), and Typhoon Signal 1; and Informational/Low for $F_s < 0.45$ like late enrollments, regular registrations, exams, and light/fair weather. Preserves specific contextual event names across all academic, weather, and LGU records).
*   `"Analytics".predictive_known_events` (Consolidated notable events feed across multi-horizon forecast timelines: Horizon 0 for 24h, Horizon 1 for 1w, Horizons 2–5 for Quarters 1–4, and Horizon 6 for 1y, strictly filtered to specific, descriptive nationwide holidays and major events).
*   `"Analytics".descriptive_model_auditing_drift_tracking` (Model auditing actuals vs forecasts comparison)
*   `"Analytics".predictive_topological_route_map` (Node status classification for topological map)
*   `"Analytics".predictive_passenger_volume_forecast_24h` (Hourly rolling 24h window)
*   `"Analytics".predictive_passenger_volume_forecast_1w` (Daily rollup for 7 days)
*   `"Analytics".predictive_passenger_volume_forecast_1m` (Daily rollup for 30 days)
*   `"Analytics".predictive_passenger_volume_forecast_quarterly` (Monthly rollup by Quarter)
*   `"Analytics".predictive_passenger_volume_forecast_1y` (Monthly rollup for 12 months)
*   `"Analytics".prescriptive_active_checklists` (Actionable checklists mapping tactical steps to 'Command Center Officer' or 'Ground Control Staff' roles, compiling the union of tactics from all parallel recommendations).
*   `"Analytics".prescriptive_action_recommendations` (Actionable risk directives mapping to APTA protocol IDs `'APTA-01'` through `'APTA-06'`. Uses `UNNEST` on arrays to recommend multiple protocols simultaneously when thresholds are crossed).

### 5d. Model Training, Testing & UAT Audit Pipeline
The model training, testing, and validation pipeline partitions turnstile data chronologically (80% training / 20% test) and runs performance checks against the four operational benchmarks:
1. **Volume Prediction Variance ($MVP_{rmse}$):** Variance (RMSE % of mean volume) must be $< 5.00\%$.
2. **Risk Classification F1-Score ($MVP_{f1}$):** Weighted F1-score of the threat classifier must be $\ge 0.85$.
3. **Heuristic Compliance ($MVP_{scr}$):** Symbolic Heuristic Compliance Rate (SCR) of deployments must be $100\%$.
4. **Cloud Pipeline Latency ($MVP_{latency}$):** Ingestion-to-broadcast latency must be $< 3.0$ seconds.

#### Dual-Write Append-Only UAT Metrics Architecture:
Rather than overwriting single snapshot cells on repeat test runs, the pipeline uses a dual-write architecture to maintain immutable historical logs for certification and UAT auditing:
* **`"Analytics".predictive_model_performance`**: Latest performance snapshot for instant dashboard KPI querying.
* **`"Analytics".uat_predictive_evaluation_logs`**: Immutable time-series ledger capturing `run_id`, `model_name`, `sample_count`, `rmse`, `mape`, `classification_accuracy`, `f1_score`, and pass/fail gate statuses for every individual test trial.
* **`"Analytics".uat_prescriptive_execution_logs`**: Immutable ledger capturing prescriptive decision triggers, APTA protocol IDs, ingestion vs broadcast timestamps, and microsecond latency measurements. Evaluated on a **30-minute operational cadence** (`*/30 * * * *` in `pg_cron`), recording **2 distinct evaluation & reset entries per hour** per station.
* **`"Analytics".vw_uat_executive_summary`**: High-level audit view exposing cumulative all-time UAT passing rates, average historical MAPE/RMSE, overall SCR compliance %, and pipeline latency SLA compliance.

The validation pipeline can be executed:
- **Database-Natively (Recommended):** By calling `SELECT "Analytics".train_and_validate_models();` or executing `"Analytics Layer/model training, testing and validation"/train_and_validate.sql`.
- **Via Python Script:** By executing `python "Analytics Layer/model training, testing and validation/train_and_validate.py"`.

---

## 6. Verification & Integrity Checks

The Node validation script performs eleven core integrity checks on every active table:
1. **Row Sum Discrepancy Check:** Verifies that the sum of all individual station entry/exit columns matches the `total_entry` and `total_exit` columns exactly.
2. **Negative Value Check:** Scans all columns to guarantee that no negative values exist.
3. **Unique IDs Check:** Validates that there are no duplicate Primary Keys.
4. **Student Transaction Conservation:** Verifies expanded hourly rows match original monthly transactions.
5. **Meeting Classifier False Positives:** Asserts 0 planning meetings are classified as active disruptions.
6. **Class Suspension & Holiday/Break Normalization:** Asserts all school breaks have score `1.0`, and validates that midday suspension announcements apply the transition exit evacuation and decay curves correctly.
7. **Academic Surge Weight (A_sw) Density:** Validates major event grouping rules (0.5 for 1-2, 1.0 for >=3 events).
8. **Feature Ingestion Vector:** Validates `Analytics.vw_predictive_features` compiles successfully.
9. **What-If Math Verification:** Verifies simulation formula calculations match expected output variance.
10. **Multi-Horizon Rollup Queries:** Asserts all 5 dashboard views (`24h`, `1w`, `1m`, `quarterly`, and `1y`) return aggregated datasets in < 50ms with zero timeout errors.
11. **Prescriptive APTA Schema Integrity Check:** Verifies that protocol deployments resolve to valid APTA IDs, checklists map to target roles, and metrics are mathematically compliant.
12. **Materialized 1-Year Fast Store:** Validates `Analytics.predictive_passenger_volume_forecast_1y` is indexed and synced automatically via `external.trg_refresh_forecast_1y_on_event_change` trigger on scraped event changes.

---

## 7. Academic Literature References & Trigger Weights (`external.friction_weight`)

Every trigger weight in `external.friction_weight` is directly backed by published, open-access NCR transportation literature:

| Domain | Trigger Category | Weight | Academic / Transit Report Citation | Open-Access PDF Link |
| :--- | :--- | :---: | :--- | :--- |
| **academic** | **Transport Strike** | **0.90** | *Impacts of Public Transport Strikes on Commuter Mobility in Metro Manila* | [JICA Report (PDF)](https://openjicareport.jica.go.jp/pdf/11580503_01.pdf) |
| **academic** | **Class Suspension** | **0.85** | *Assessment of Class Suspension Impacts on Metro Manila Traffic (NCTS UP Diliman)* | [Abad et al., 2018 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Abad18.pdf) |
| **academic** | **Holiday** | **0.85** | *Assessment of Class Suspension and Holiday Impacts on Metro Manila Traffic (NCTS UP Diliman)* | [Abad et al., 2018 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Abad18.pdf) |
| **academic** | **School Break** | **0.85** | *Assessment of Class Suspension and School Break Impacts (NCTS UP Diliman)* | [Abad et al., 2018 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Abad18.pdf) |
| **academic** | **Online / Asynchronous Class Shift** | **0.85** | *Assessment of Remote Learning Impacts on Urban Mobility (NCTS UP Diliman)* | [Abad et al., 2018 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Abad18.pdf) |
| **academic** | **Civic Rally & Public Mobilization** | **0.75** | *Impacts of Special Mass Gatherings on Urban Commuter Networks (JICA)* | [JICA Transport Study (PDF)](https://openjicareport.jica.go.jp/pdf/11580503_01.pdf) |
| **academic** | **Major Arena Event** | **0.65** | *Event-Driven Traffic Congestion in Urban Centers (NCTS UP Diliman)* | [Fillone et al., 2005 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Fillone05.pdf) |
| **academic** | **Graduation & Commencement Rites** | **0.65** | *Special Event Congestion Analysis at Transit Terminals (NCTS UP Diliman)* | [Fillone et al., 2005 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Fillone05.pdf) |
| **academic** | **University Exam Week** | **0.20** | *Analysis of University Commuter Travel Behavior in Metro Manila (EASTS)* | [EASTS Proc. Vol 10 (PDF)](https://easts.info/on-line/proceedings/vol10/pdf/1296.pdf) |
| **academic** | **Regular Class Day** | **0.00** | *Trip Generation Characteristics of Schools in Metro Manila (NCTS UP Diliman)* | [Fillone et al., 2005 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Fillone05.pdf) |
| **lgu** | **LGU Municipal Clearing & Maintenance** | **0.00** | *LGU Road Network Maintenance Operations (NCTS UP Diliman)* | [Abad et al., 2018 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Abad18.pdf) |
| **operational** | **Code Red / Standstill** | **1.00** | *Disaster and Emergency Preparedness for Philippine Rail Lines* (JICA / DOTr) | [JICA Report (PDF)](https://openjicareport.jica.go.jp/pdf/11580503_01.pdf) |
| **operational** | **Partial Line Suspension** | **0.85** | *Vulnerability Assessment of Metro Manila Rail Transit Networks (EASTS)* | [EASTS Proc. Vol 10 (PDF)](https://easts.info/on-line/proceedings/vol10/pdf/1296.pdf) |
| **operational** | **Degraded Headway** | **0.50** | *Evaluation of Rail Transit Reliability in Metro Manila* (Fillone et al., NCTS UP Diliman) | [NCTS UP Diliman TSSP PDF](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Fillone05.pdf) |
| **operational** | **Code Green** | **0.00** | *LRTA Citizen's Charter & Service Standards* | [LRTA Portal](https://lrta.gov.ph/) |
| **pagasa** | **Typhoon (High)** | **0.95** | *Challenges of Urban Transport Development in Metro Manila (EASTS)* | [EASTS Proc. Vol 10 (PDF)](https://easts.info/on-line/proceedings/vol10/pdf/1296.pdf) |
| **pagasa** | **Torrential Rain** | **0.85** | *Analysis of Inter-City Travel Behavior in Metro Manila during Flooding* | [Abad et al., 2018 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Abad18.pdf) |
| **pagasa** | **Typhoon (Low)** | **0.70** | *Impact of Typhoon-Induced Flooding on Traffic Patterns (NCTS UP Diliman)* | [Abad et al., 2018 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Abad18.pdf) |
| **pagasa** | **Heavy Rain** | **0.65** | *Factors affecting travel behavior during flood events (NCTS UP Diliman)* | [Abad et al., 2018 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Abad18.pdf) |
| **pagasa** | **Light/Moderate Rain** | **0.35** | *Factors affecting travel behavior during flood events (NCTS UP Diliman)* | [Abad et al., 2018 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Abad18.pdf) |
| **pagasa** | **Clear / Fair** | **0.00** | *Metro Manila Urban Transportation Integration Study (JICA)* | [JICA Study (PDF)](https://openjicareport.jica.go.jp/pdf/11580503_01.pdf) |

### 🛡️ Explicit Scraped Event Cancellation & Classification Rules
- **Explicit Cancellation Rule:** An event in `external.academic_lgu_events` will **ONLY** be marked as cancelled (`is_cancelled = TRUE`) and removed from `external.events_consolidated` if there is an **actual scraped post in the database stating that it is cancelled** (`is_cancelled = TRUE` or `is_cancellation = TRUE`). In the absence of an explicit scraped cancellation post, events (such as 3-day transport strikes or multi-day advisories) **remain 100% active** (`is_cancelled = FALSE`).
- **Resilient Regex Classification:** `external.classify_event_from_text` employs generalized regular expressions to eliminate verb-tense locks (`is|are`), support hashtag variations (`#WalangPasok` via `walang\s*pasok`), accommodate general suspension phrasing (`class(es)?\s+.*suspend`, `work\s+.*suspend`), and capture online synchronous/asynchronous shifts.

*Full academic attributions and formulas are documented in [ACADEMIC_REFERENCES.md](file:///c:/Users/Jed/LRT/Analytics/ACADEMIC_REFERENCES.md).*


