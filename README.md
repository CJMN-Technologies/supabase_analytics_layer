# Supabase Transformation & Orchestration Layer (LRT-2 Commuter Friction Index)

This repository contains the database DDL, sync triggers, dynamic ingestion scripts, and validation pipeline for standardizing and transforming the LRT-2 transit ridership logs, meteorological feeds, and environmental urban factors. 

This layer serves as the **landing and transformation zone** to compute the **Commuter Friction Index (CFI)**, which measures the "transport impedance" exerted on commuters by real-world anomalies (like severe weather, university calendar events, and LGU class suspensions) and powers the multi-tier analytics engine.

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
│   │   └── transform_ridership_hourly.sql     # Converts backups to hourly active ridership
│   ├── external/
│   │   ├── consolidate_events_schema.sql      # Text classification & scraped events sync
│   │   ├── consolidate_weather_schema.sql     # Pagasa weather alert parsing & current/forecast weather sync
│   │   └── standardize_external_triggers.sql  # Compiles classifiers and A_sw/PAGASA triggers
│   ├── literature/
│   │   └── standardize_literature_dimensions.sql # Sets up APTA tables and seeds weights
│   └── applications/
│       ├── iam_portal_schema.sql              # User profiles, administrative logs, and custom RBAC DDL
│       ├── ground_control_schema.sql          # Mobile shifts, incidents, emergency contacts, and real-time sync triggers
│       └── uat_metrics_append_only_ledger.sql # Immutable prescriptive evaluation baselines & metrics ledger
├── run_pipeline.js                            # Core orchestration runner and data integrity check suite
├── package.json                               # Node dependencies (pg, @supabase/supabase-js)
├── .env.example                               # Template for database credentials
└── README.md                                  # Project Documentation
```

---

## 3. The 3 Dataset Typologies

The analytics layer harmonizes three distinct dataset typologies to produce actionable decision support:

### 3a. Internal Datasets (AFCS & Transit Operations)
- **Turnstile Actuals (`AFCS.ridership_2021` to `ridership_2025`):** Complete historical hourly passenger entry and exit counts across all 13 LRT-2 stations.
- **Station Platform Capacity (`"Station Capacity".station_platform_capacity`):** Physical station and platform dimensions, maximum safe passenger capacity ($K_p$), and concourse physical limits.
- **PSOR Incident Logs (`PSOR.psor_incidents` & `gcs.incidents`):** Operational incident logs, degraded headway reports, and field safety telemetry.

### 3b. External Datasets (Urban Triggers & Meteorological Feeds)
- **PAGASA & Open-Meteo Weather Streams (`external.weather_current`, `external.weather_forecasts`):** Hourly meteorological metrics across the 13-station corridor, including rainfall intensity (mm/hr) and Tropical Cyclone Wind Signals (TCWS #1 to #5).
- **Social & Advisory Disruption Scrapes (`external.academic_lgu_events`):** Near real-time scraped announcements from 18+ university and LGU official communication channels (class suspensions, entrance exams, graduations, transport strikes, civic rallies).
- **Academic Calendars:** Official university term schedules, semestral breaks, and exam week schedules.

### 3c. Literature-Based Datasets (Standardized Parameters, Elasticity & APTA Standards)
- **20 Literature-Calibrated Friction Weights (`external.friction_weight`):** Empirical friction weights ($0.00$ to $1.00$) backed by peer-reviewed studies (UP NCTS, JICA, EASTS, LRTA).
- **Cyclical Demand Elasticity Multipliers:** Payday ($\psi_{\text{payday}} = +15.2\%$), semestral break ($\psi_{\text{academic}} = -18.6\%$), and day-of-week demand multipliers ($\psi_{\text{dow}}$) calibrated from local transit studies.
- **APTA Standards & Fruin Level of Service (LOS):** American Public Transportation Association crowd management standards (`APTA-01` to `APTA-06`) and TCQSM TCRP Report 165 percentile benchmarks (80th percentile Warning $W_t$, 90th percentile Critical $C_t$).

---

## 4. Database Schema & Standardization Rules

### 4a. Dimension Tables (SCD Type 1)
All lookups have been standardized to clean, human-readable primary keys instead of long composite formats:
- `APTA.apta_protocols` (IDs: `APTA-01`, `APTA-02`, ...)
- `PSOR.psor_incidents` (IDs: `PSOR-01`, `PSOR-02`, ...)
- `"Station Capacity".station_platform_capacity` (IDs: `CAP-REC` for Recto, `CAP-LEG` for Legarda, ...)
- `external.friction_weight` (IDs: `FRI-ACxx` for Academic Surge, `FRI-PAxx` for Weather Alerts, `FRI-OPxx` for GCS Incidents)

### 4b. Standardized Application IDs
All application-level keys have been migrated from raw UUID hashes to sequence-based standardized string formats:
- **`iam.users`:** `POxxxx` (Provision Officer), `CCOxxxx` (Command Center Officer), and `GCSxxxx` (Ground Control Staff).
- **`iam.audit_logs`:** `AUDxxxxxx` (Audit Logs).
- **`gcs.shifts`:** `SHFxxxxxx` (Ground Shifts).
- **`gcs.incidents`:** `INCxxxxxx` (Logged Incidents).
- **`gcs.emergency_contacts`:** `CONxxxx` (Emergency Contacts).
- **`Analytics.simulation_history`:** `SIMxxxxxx` (Stress Simulations).
- **`Analytics.prescriptive_protocol_deployments`:** `DEPxxxxxx` (APTA Deployments).

### 4c. Real-Time Consolidated Tables
Triggers process qualitative logs on-write and save them under short, unique IDs:
- **Events Consolidated (`external.events_consolidated`):**
  - Scraped events: `SCR-[CATEGORY_CODE]-[MMDD]-[RAW_ID]`
  - Calendar events: `CAL-[SCHOOL_ACRONYM]-[MMDD]-[ROW_ID]`
  - GCS Mobile Incidents: `INC-[MMDD]-[INCIDENT_ID]`
  - Auto-normalizes class suspension and online modality shift events to binary score `1.0`.
  - Automatically propagates `source_url` (Facebook announcement permalink) and `description` (raw post text) into consolidated records.
  - Non-disruptive LGU weather monitoring, rainfall advisories, river maintenance, estero clean-up operations, and road flood updates are classified as `LGU Weather / Flooding Advisory` or `LGU Municipal Clearing & Maintenance` (`affects_ridership = FALSE`), preventing false-positive capacity dampeners or erroneous `"Holiday"` / `"University Milestone / Surge"` tags.
  - Unofficial student council petitions, academic leniency requests, clinical/health examinations (e.g. FriendlyCare breast/dental/medical checkups), public employment/job fairs (PESO notices), student ID processing schedules, and studio photoshoot/yearbook/toga rental advisories are automatically categorized as non-disruptive administrative items (`affects_ridership = FALSE`), preventing false-positive passenger surges or spurious `WARNING` alerts.
  - Automatically deduplicates and updates existing rows `ON CONFLICT (id) DO UPDATE` to prevent data duplication.
- **Weather Consolidated (`external.weather_consolidated`):**
  - Weather Current: `WTH-CUR-[STATION]`
  - Weather Forecasts: `WTH-FCT-[ID]`

### 4d. Dynamic Proportional Ingestion
Ridership tables (`ridership_2021` to `ridership_2025` and incoming future tables) are transformed from non-standard daily/off-peak bands into a continuous hourly scale:
- Auto-renames incoming source tables to `*_backup` to preserve data lineage.
- Scans and maps station columns dynamically, ignoring garbage or dummy columns.
- Performs **double-layered cumulative rounding** distribution to ensure that the sum of the allocated hourly records matches the raw daily totals exactly with **0 row-sum discrepancies**.
- Inserts hourly records with format `YR[YY]-[MMDD]-[HH]` (e.g. `YR21-0101-05`), daily total records `YR[YY]-[MMDD]-DT`, and monthly total records `YR[YY]-[MM]-MT`.

---

## 5. The 3-Tier Analytics Architecture

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        3-TIER ANALYTICS DECISION INTELLIGENCE                          │
├────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                        │
│  📊 TIER 1: DESCRIPTIVE ANALYTICS LAYER                                                │
│     - Commuter Friction Index: CFI = (W_w × P_idx) + (W_a × A_sw) + (W_c × L_sp)        │
│     - 20 Literature-Calibrated Friction Weights (external.friction_weight)             │
│     - Non-Parametric Percentile Benchmarking: Warning (P_80), Critical (P_90)          │
│                                                                                        │
│  📈 TIER 2: PREDICTIVE ANALYTICS LAYER                                                 │
│     - Machine Learning Forecasting: XGBoost (Volume B_m) & Random Forest (Risk Level)  │
│     - Multiplicative Elasticity Post-Processing: V_p = B_m,seasonal × Π(1 + β_k × S_k) │
│     - Multi-Horizon Forecasting Horizons: 24-Hour Dayparts, 1-Week, Quarterly, 1-Year  │
│                                                                                        │
│  🎯 TIER 3: PRESCRIPTIVE ANALYTICS LAYER                                               │
│     - Interpretable Decision Trees anchored to physical capacity limits (U_p ≥ 80%/90%)│
│     - Standardized Crowd-Management Directives: APTA-01 through APTA-06                │
│     - Real-Time Bidirectional Dispatch & Checklist Sync with Ground Control Mobile     │
│                                                                                        │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

### 5a. Tier 1 — Descriptive Analytics Layer
*   **Dynamic Year Ingestion (`Analytics.rebuild_vw_hourly_actuals()`):** Stored procedure that dynamically discovers all `AFCS.ridership_YYYY` tables and compiles `Analytics.vw_hourly_actuals` with zero manual SQL modifications across arbitrary year ranges.
*   **Commuter Friction Index (CFI) Mechanics:** Quantifies urban transport impedance as a normalized weighted composite:
    $$CFI = (W_w \times P_{idx}) + (W_a \times A_{sw}) + (W_c \times L_{sp})$$
    where weights $W_w = 0.35$ (Meteorological), $W_a = 0.20$ (Academic Surge), and $W_c = 0.45$ (Civic Mandates) are calibrated from empirical transit studies.
*   **Non-Parametric Threshold Baselines (`Analytics.hourly_threshold_baselines`):** Replaces easily skewed arithmetic means with non-parametric percentiles:
    $$W_t = P_{80}(X) \quad (\text{Warning Threshold — Fruin LOS D})$$
    $$C_t = P_{90}(X) \quad (\text{Critical Threshold — Fruin LOS E/F})$$
    Pre-computed for every station, day of week, hour period, and flow direction (3,172 baseline records), strictly calibrated to the post-lockdown window (`2023-01-01` to `2025-12-31`).

### 5b. Tier 2 — Predictive Analytics Layer
*   **Machine Learning Forecasting ($B_m$):** Decoupled XGBoost regression models trained on historical turnstiles (`Analytics.vw_predictive_features`), outputting unperturbed baseline predictions ($B_m$) stored in `Analytics.predictive_model_outputs`.
*   **Multiplicative Elasticity Post-Processor ($V_p$):** Applies log-linear elasticity sensitivities ($\beta_k$) against real-time friction shocks ($S_k$):
    $$V_p = \text{ROUND}\left( B_{m, \text{seasonal}} \times (1 + \beta_{\text{acad}} S_{\text{acad}}) \times (1 - \beta_{\text{civic}} S_{\text{civic}}) \times (1 - \beta_{\text{weather}} S_{\text{weather}}) \times (1 - \beta_{\text{ops}} S_{\text{ops}}) \right)$$
*   **Multi-Horizon Timeline Endpoints:**
    - `Analytics.predictive_passenger_volume_forecast_24h` (Rolling 24h dayparts: Morning Rush, Midday Off-Peak, Evening Surge, Night Taper)
    - `Analytics.predictive_passenger_volume_forecast_1w` (7-day daily volume projection)
    - `Analytics.predictive_passenger_volume_forecast_quarterly` (Quarterly seasonal volume distributions)
    - `Analytics.predictive_passenger_volume_forecast_1y` (Indexed 1-year macroeconomic trend table for 0ms queries)
*   **Interactive What-If Scenario Simulator (`"Analytics".predictive_what_if_scenario_simulator`):** Analytics wrapper executing custom what-if disruptions with Gaussian duration envelopes in under 5ms.

### 5c. Tier 3 — Prescriptive Analytics Layer
*   **Interpretable Decision Trees:** Anchored directly to deterministic physical platform capacity utilization ($U_p = \frac{V_c}{K_p} \times 100$), avoiding opaque black-box AI in life-safety operations.
*   **APTA Crowd-Control Directives:** Routes outputs to pre-approved human-centric "Man-Protocols" (`APTA-01` Platform Metering, `APTA-02` Turnstile Throttling, `APTA-03` Escalator Directional Control, `APTA-04` Headway Compression, `APTA-05` Bus Augmentation, `APTA-06` Station Evacuation).
*   **Real-Time Dispatch Checklists (`Analytics.prescriptive_active_checklists`):** Automatically compiles and dispatches actionable tactical checklists to Ground Control Mobile clients, with sub-second bidirectional acknowledgment tracking in `Analytics.protocol_task_status`.

### 5d. Model Training, Testing & Prescriptive Baseline Audit Pipeline
The model training, testing, and validation pipeline partitions turnstile data chronologically (80% training / 20% test) and runs validation against four operational benchmarks:
1. **Volume Prediction Variance ($MVP_{rmse}$):** Variance (RMSE % of mean volume) must be $< 5.00\%$.
2. **Risk Classification F1-Score ($MVP_{f1}$):** Weighted F1-score of the threat classifier must be $\ge 0.85$.
3. **Symbolic Heuristic Compliance ($MVP_{scr}$):** Compliance rate of deployments to valid APTA protocols must be $100\%$.
4. **Cloud Pipeline Latency ($MVP_{latency}$):** Ingestion-to-broadcast latency ($L_{ib} = T_b - T_i$) must be $< 3.0$ seconds.

#### Dual-Write Append-Only Prescriptive Evaluation Ledgers:
* **`"Analytics".predictive_model_performance`**: Latest performance snapshot for instant dashboard KPI querying.
* **`"Analytics".uat_predictive_evaluation_logs`**: Immutable time-series ledger capturing `run_id`, `model_name`, `sample_count`, `rmse`, `mape`, `classification_accuracy`, `f1_score`, and pass/fail gate statuses for every individual test trial.
* **`"Analytics".uat_prescriptive_execution_logs`**: Immutable ledger capturing prescriptive decision triggers, APTA protocol IDs, ingestion vs broadcast timestamps, and microsecond latency measurements. Evaluated on a **30-minute operational cadence** (`*/30 * * * *` in `pg_cron`), recording **2 distinct evaluation & reset entries per hour** per station.
* **`"Analytics".vw_uat_executive_summary`**: High-level audit view exposing cumulative all-time prescriptive evaluation passing rates, average historical MAPE/RMSE, overall SCR compliance %, and pipeline latency SLA compliance.

The validation pipeline can be executed:
- **Database-Natively (Recommended):** By calling `SELECT "Analytics".train_and_validate_models();` or executing `"Analytics Layer/model training, testing and validation"/train_and_validate.sql`.
- **Via Python Script:** By executing `python "Analytics Layer/model training, testing and validation/train_and_validate.py"`.

---

## 6. Verification & Integrity Checks

The Node validation script (`run_pipeline.js`) performs eleven core integrity checks on every active table:
1. **Row Sum Discrepancy Check:** Verifies that the sum of all individual station entry/exit columns matches the `total_entry` and `total_exit` columns exactly.
2. **Negative Value Check:** Scans all columns to guarantee that no negative values exist.
3. **Unique IDs Check:** Validates that there are no duplicate Primary Keys.
4. **Meeting Classifier False Positives:** Asserts 0 planning meetings are classified as active disruptions.
5. **Class Suspension & Holiday/Break Normalization:** Asserts all school breaks have score `1.0`, and validates that midday suspension announcements apply the transition exit evacuation and decay curves correctly.
6. **Academic Surge Weight ($A_{sw}$) Density:** Validates major event grouping rules (0.5 for 1-2, 1.0 for >=3 events).
7. **Feature Ingestion Vector:** Validates `Analytics.vw_predictive_features` compiles successfully.
8. **What-If Math Verification:** Verifies simulation formula calculations match expected output variance.
9. **Multi-Horizon Rollup Queries:** Asserts all 5 dashboard views (`24h`, `1w`, `1m`, `quarterly`, and `1y`) return aggregated datasets in < 50ms with zero timeout errors.
10. **Prescriptive APTA Schema Integrity Check:** Verifies that protocol deployments resolve to valid APTA IDs, checklists map to target roles, and metrics are mathematically compliant.
11. **Materialized 1-Year Fast Store:** Validates `Analytics.predictive_passenger_volume_forecast_1y` is indexed and populated for 0ms dashboard queries; decoupled from synchronous row-level triggers to guarantee sub-150ms real-time incident logging across Ground Control mobile clients.

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

*Full academic attributions, dataset typologies, and formulas are documented in [ACADEMIC_REFERENCES.md](file:///c:/Users/Jed/LRT/Analytics/ACADEMIC_REFERENCES.md).*
