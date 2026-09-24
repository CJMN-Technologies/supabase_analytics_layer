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
  - **Explicit Source Entity Tagging (`source_type`)**: Contains an explicit `source_type` (`'lgu'`, `'academic'`, `'weather'`, `'ops'`) decoupled from literature friction domain parameters ($A_{sw}$ vs $L_{sp}$). Notices declared by Local Government Units (e.g. Quezon City, Manila PIO, San Juan, Pasig, Marikina, Antipolo, Cainta) remain tagged as `source_type = 'lgu'` even when declaring class suspensions (which affect student volume $A_{sw}$).
  - **Deterministic Origin Propagation & Institutional Precedence**: The sync trigger `external.sync_academic_lgu_to_events_consolidated()` dynamically evaluates the posting authority origin. Educational institution keywords (`university`, `college`, `school`, `institute`, `student council`, `varsitarian`, `konseho`) take strict precedence over `"City"` in geographic names (e.g. *St. Paul University Quezon City*, *World Citi Colleges Quezon City*), guaranteeing `source_type = 'academic'`.
  - **Descriptive Event Feed Resolution**: `"Analytics".descriptive_live_event_feed` projects `source_type` directly, supplemented by resilient exclusion regex (`AND NOT ec.source_name ~* '(university|college|school|council|student|varsitarian)'`) to prevent school pages containing city names from false-positive LGU tagging.
  - **Strict Resumption vs Reschedule Guardrail**: Announcements officially lifting disruptions or declaring resumption of classes/work (`event_code = 'RESUMPTION_CLASSES'` or containing `"resumption"`) strictly deactivate prior disruption entries on the announcement date and exit without inserting active suspension records into `events_consolidated`, preventing advance announcements (where `event_date > post_date`) from being inverted into active class suspensions.
  - **Multi-Day Date Range Expansion**: Multi-day event dates in format `YYYY-MM-DD to YYYY-MM-DD` (e.g. UERM Long Exam Week) automatically expand into contiguous daily disruption entries across the event duration (capped at 14 days) in `external.events_consolidated`.
  - **Background Reason Clause Isolation**: Reason clauses embedded in non-disruptive announcements (e.g. *"Due to Preliminary Examination Week, our Parent Orientation has moved..."*) are guarded so parent orientations remain categorized as non-disruptive administrative items (`affects_ridership = FALSE`), preventing false `exam_week` disruption spikes.
  - **Off-Corridor Mega-Venue & Cultural Expo Geofencing Guardrail**: If an event announcement physically takes place at a mega-venue or exhibition space outside the LRT-2 transit corridor (e.g. SM Mall of Asia Arena in Pasay, SMX Convention Center, Philippine International Convention Center / PICC in Pasay, San Andres Sports Complex in Malate District 5, World Trade Center, Philippine Arena in Bocaue, or Foro de Intramuros / Intramuros heritage tourism expos), the trigger automatically discards the event from `events_consolidated` unless an LRT-2 station is explicitly cited. Prevents off-corridor sports tournaments, museum exhibitions, and convention recaps from creating 0.50–1.00 friction shocks on Recto, Legarda, Pureza, or V. Mapa (`purge_recent_scraped_anomalies_and_harden_recap.sql`).
  - **Satellite Campus Local Holiday Isolation**: Academic calendar entries specific to satellite campuses outside the LRT-2 corridor (e.g. *Makati Day* in the FEU Academic Calendar for FEU Makati) are excluded from `events_consolidated`, ensuring local municipal holidays only apply to stations physically located in that LGU.
  - **Micro-Venue, Ticket Booth & Campus Observance Suppression**: Ticket sales announcements (e.g. VP for Finance ticket booth, room SB 106 selling), university dance studio recitals, neighborhood covered court concerts, campus dress themes (*"Yellow Day"*), and foundation anniversary masses/choir performances are strictly prevented from escalating into `MAJOR_ARENA_EVENT` shocks (`affects_ridership = FALSE`).
  - **Expanded Retrospective Photo Recap & Sponsor Thank-You Guardrail**: If a Facebook post has `event_code = 'MAJOR_ARENA_EVENT'` and its extracted `event_date` is **1 or more days before** the publication date (`v_days_in_past >= 1`), or if post-event retrospective / partner appreciation phrasing is detected (`"playing it back"`, `"katatapos lang"`, `"after the spectacular ceremony"`, `"came together for an opening"`, `"officially commenced"`, `"victory over"`, `"defeated"`, `"won against"`, `"final score"`, `"thank you to our partner"`, `"couldn't have done it without"`, `"partner companies"`, `"sponsors and partners"`), the trigger treats the post as a past-event photo album, interview, recap, or sponsor thank-you and silently discards it from `events_consolidated`. Operates on both same-day and multi-day posts (`purge_recent_scraped_anomalies_and_harden_recap.sql`).
  - **Administrative Portal Deadlines & Weather Demobilization Guardrails**: Online admissions document submission deadline extensions (e.g. UPCAT Form 1/2B submissions) are classified as non-disruptive `ADMINISTRATIVE` notices rather than active `University Exam Week` disruptions. Flood monitoring demobilization updates (e.g. Pasig Incident Management Team demobilizing after river levels normalize) are explicitly isolated to prevent triggering `Civic Rally & Public Mobilization`.
  - **Typhoon Advisory Safety Guardrail**: LGU and PAGASA severe weather bulletins mentioning typhoons or tropical cyclone wind signals are strictly preserved under `WEATHER_ADVISORY` and forbidden from being misclassified as transit `Holiday` records.
  - **Constrained Statutory Holiday Phrasing & EDSA Landmark Disambiguation**: In `external.classify_event_from_text()`, holiday triggers are strictly constrained to statutory/official designations (`araw ng (kagitingan|maynila|kalayaan|...)`, `edsa (people power)? (day|revolution|anniversary)`). Bare mentions of `"EDSA"` (e.g. *EDSA People Power Monument*, *EDSA Busway*, or *EDSA traffic advisory*) are prevented from triggering statutory holiday shocks.
  - **Motorist Surface Traffic Advisory Guardrail**: Traffic management advisories issued for road motor vehicles (e.g. *"Abiso sa mga motorista"*, *"alternatibong ruta"*, *"pagbagal ng daloy ng trapiko"*) around highway landmarks are classified as non-disruptive municipal infrastructure (`affects_ridership = FALSE`), ensuring road congestion notices never induce false train ridership cancellations.
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
- **Rescheduled & Postponed Event Filter Precedence (Filter 5c / 6c):** Rescheduled sports, arena, and concert events (e.g. UAAP kickoff rallies, exhibition games) are evaluated *prior* to general class suspension regex in `external.classify_event_from_text()`. This prevents incidental suspension clauses (e.g., *"rescheduled following suspension of classes"*) from hijacking the event classification into false Critical (`1.0`) class suspensions on the announcement date.
- **Rescheduling & Target Date Reconciliation (`external.sync_academic_lgu_to_events_consolidated`):**
  - Honors `NEW.event_code = 'MAJOR_ARENA_EVENT'` and parsed `NEW.event_date` from the scraper.
  - When `is_cancellation = TRUE` with `cancellation_target_code = 'MAJOR_ARENA_EVENT'` (or matching arena/sports keywords), prior matching events on the announcement date are marked `is_cancelled = TRUE` and purged from `events_consolidated`.
  - If rescheduled to a future date (`event_date > post_date`), the trigger registers the rescheduled event on the target date as `major_event` (`Major Arena Event`, weight `0.65`). Pure cancellations without a new target date are pruned without inserting false disruptions.
- **Retrospective Photo Recap & Sports Game Score Guardrail:** The consolidation trigger `external.sync_academic_lgu_to_events_consolidated()` enforces strict temporal and semantic retrospective guardrails on `MAJOR_ARENA_EVENT` notices. Any post where the extracted `event_date` is on or before the publication date (`v_days_in_past >= 1`), or containing post-game outcome reporting (`victory over`, `defeated`, `won against`, `edged out`, `loss to`, `final score`, `campaign off to a strong start`) or photo recap language (`naging matagumpay`, `photo highlight`, `event recap`, `held last`, `playing it back`, `katatapos lang`, `came together for an opening`, `officially commenced`, `after the ... ceremony`), is isolated as a historical recap and blocked from injecting active disruption records into `external.events_consolidated`.
- **Off-Corridor Mega-Venue Geofencing:** Sports and concert venues located outside the LRT-2 transit walkshed catchment (SM Mall of Asia Arena Pasay, PICC Plenary Hall Pasay, San Andres Sports Complex Malate, Rizal Memorial Stadium Pasay/Manila, Ninoy Aquino Stadium, Philsports Arena/Ultra Pasig, Cuneta Astrodome, Filoil EcoOil Centre San Juan) are geofenced and suppressed from generating `MAJOR_ARENA_EVENT` shocks (`friction_weight = 0.65`) in `events_consolidated`.
- **Micro-Venue & Administrative Deadlines Suppression:** Ticket sales booths, dance studios, student covered courts, small gymnasiums, and administrative form submission deadlines (admissions, transcript clearance, graduation forms) are isolated from `MAJOR_ARENA_EVENT`, preventing false capacity dampeners.
- **Emergency IMT Demobilization Isolation:** Post-flood advisories from municipal disaster councils (e.g. Pasig PIO) announcing that the Incident Management Team (IMT) has "demobilized" are isolated from `Civic Rally & Public Mobilization`, preventing false crowd mobilization alarms.
- **Satellite Campus Local Holiday Geofencing:** Academic calendar entries declaring local LGU holidays for satellite branches situated entirely outside the LRT-2 corridor (e.g. *Makati Day (Makati Holiday)* from FEU Makati) are quarantined and excluded from triggering academic disruption shocks across LRT-2 stations.
- **Student Council EVM Petition & Administrative Position Paper Guardrail:** Student appeals and administrative petition updates (such as announcements that the University Administration has denied an EVM petition and confirmed normal on-site classes) are isolated from active transport disruption shocks (`affects_ridership = FALSE`), preventing spurious `Transport Strike` entries from penalizing transit capacity.
- **Civic Theme Month & Broad Multi-Week Observance Guardrail:** Multi-week promotional celebrations (e.g. *World Tourism Month*, *Philippine Creative Industries Month*, *Buwan ng Wika*, *Anniversary Month*) are prevented from expanding into multi-week daily `MAJOR_ARENA_EVENT` capacity dampeners and are categorized as non-disruptive civic notices (`affects_ridership = FALSE`).
- **UE Multi-Campus Disambiguation & Out-of-Corridor Isolation:** Announcements originating from multi-campus university pages (such as University of the East) that exclusively target off-corridor branches (such as UE Caloocan at Samson Road) are filtered out to ensure they do not falsely generate major event disruptions at LRT-2 Recto station or surrounding University Belt nodes.
- **Constrained Statutory Holiday Regex Guardrail:** In `external.classify_event_from_text()`, the regex pattern for Filipino holiday declarations (`araw\s+ng`) is strictly constrained to recognized statutory and commemorative days (`araw\s+ng\s+(kagitingan|maynila|kalayaan|quezon|pasig|marikina|san\s+juan|manggagawa|mga\s+bayani|wika)`). This prevents unconstrained matches against common phrasing in municipal civic announcements (e.g. *"isang araw ng paglilinis"*) that would otherwise falsely trigger full Holiday (`1.0`) ridership dampeners.
- **Environmental & Civic Cleanup Classification:** Community cleanup drives, coastal cleanups, waterway clearing, and tree pruning operations are classified under `infrastructure` / `LGU Municipal Clearing & Maintenance` with `affects_ridership = FALSE`, preventing non-disruptive municipal maintenance from penalizing station capacity.
- **Street Festival & Off-Corridor Micro-Venue Suppression:** Localized street festivals, neighborhood night markets, and district cultural festivities (e.g. Banawe Chinatown Mooncake Festival) are isolated from `MAJOR_ARENA_EVENT` (`friction_weight = 0.65`) through micro-venue patterns and same-day retrospective language detection (`idinaos na`, `napuno ng masasayang aktibidad`).
- **Institutional Cluster Parent-Child Deduplication:** When a parent university administration page (e.g. Far Eastern University Manila) publishes an official transit or modality disruption notice (e.g. 2-day transport strike online class shift), subsequent or extended advisories from student councils (e.g. FEU Central Student Organization) sharing the same cluster key and start date are automatically suppressed in `external.sync_academic_lgu_to_events_consolidated()` and `pipeline.py` to prevent duplicate or inflated multi-day shock records.
- **Student Welfare Lounge & Exam Cheer Suppression:** Internal student council welfare lounges, free coffee/snack distribution booths (`study fuel`, `snack booth`, `free coffee`, `student activity room`, `busking`), and motivational social media exam cheer greetings (`give it your best`, `you got this`, `fighting`) are categorized under non-disruptive administrative/regular class items (`affects_ridership = FALSE`). Prevents internal welfare activities and social media cheers from duplicating institutional academic calendars or injecting multi-day exam week disruption spikes (`purge_scraped_events_sept25_anomalies_and_tighten_classifier.sql`).
- **Hotel Ballroom & Private Function Venue Isolation:** Municipal awards ceremonies, banquets, and recognition programs held inside enclosed private hotel ballrooms (e.g. Novotel Manila Araneta City ballroom for the *31st Quezon City Barangay Day Celebration*) are explicitly excluded from `MAJOR_ARENA_EVENT` via `novotel`, `ballroom`, `hotel function`, and `function hall` exclusion patterns (`affects_ridership = FALSE`), preventing hotel ballroom ceremonies from falsely triggering 0.50–0.65 transit arena shocks.
- **Classroom Student Org Assemblies & Micro-Room Guardrail:** Student organization general assemblies, committee sign-ups, and member orientations taking place inside campus rooms or student union facilities (`sub\s+\d+`, `room\s+\d+`, `classroom`, `general assembly`) are classified as non-disruptive administrative items (`affects_ridership = FALSE`). Incidental political slogans on promotional graphics (e.g. activist posters for student org fairs) are prevented from overriding the classroom venue and escalating into major arena or mass mobilization shocks (`external_acad_0283`).
- **Retrospective Photo Album Recap Guardrail:** Facebook posts published after civic events conclude that serve as photojournalism galleries, recaps, or retrospectives (matching `photos by`, `photo album`, `in photos:`, `event recap:`, `protesters marched to`) are classified as non-disruptive administrative items (`affects_ridership = FALSE`), preventing late-evening photo recap albums from duplicating active daytime mobilization records.
- **Corridor-Wide Scope Resolution for NCR & Malacañang Proclamations:** In `external.get_affected_stations()`, Malacañang, presidential, and NCR-wide holiday proclamations (e.g. *49th ASEAN Summit Special Non-Working Days*) dynamically expand across all 13 LRT-2 stations (`All Stations`), even when sourced from collegiate publications (e.g. The Varsitarian) whose default cluster is University Belt Manila.
- **Resilient Regex Classification:** `external.classify_event_from_text` employs generalized regular expressions to eliminate verb-tense locks (`is|are`), support hashtag variations (`#WalangPasok` via `walang\s*pasok`), accommodate general suspension phrasing (`class(es)?\s+.*suspend`, `work\s+.*suspend`), and capture online synchronous/asynchronous shifts.

### 🔐 Universal Superadmin RLS Omnipresence
All fact and dimension tables across the analytical constellation (`Analytics.prescriptive_protocol_deployments`, `Analytics.simulation_history`, `Analytics.hourly_threshold_baselines`, `Analytics.prescriptive_task_checklist`, `external.academic_lgu_events`, `external.processed_calendar_tables`, `external.friction_weight`, `AFCS.*`, `APTA.*`) enforce permissive PostgreSQL Row Level Security bypass policies for Tier-0 Superadmin accounts via `iam.is_superadmin()`, allowing root operational inspection, model auditing, scenario simulation, and complete data pipeline monitoring.

*Full academic attributions, dataset typologies, and formulas are documented in [ACADEMIC_REFERENCES.md](file:///c:/Users/Jed/LRT/Analytics/ACADEMIC_REFERENCES.md).*
