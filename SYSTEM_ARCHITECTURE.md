# LRT-2 Decision Support System — High-Level System Architecture

A comprehensive architectural specification documenting the end-to-end topology, data flow pipelines, database schemas, and operational feedback loops across all five sub-applications in the LRT-2 Commuter Friction & Decision Support ecosystem.

---

## 1. End-to-End System Architecture Diagram

```mermaid
flowchart TB
    %% =========================================================================
    %% 1. DATA SOURCES & INGESTION TIER
    %% =========================================================================
    subgraph SOURCES["🌐 1. External & Internal Data Sources"]
        FB["Facebook Official Pages<br/>(Universities, LGUs, Student Councils)"]
        WTH["Open-Meteo Weather API<br/>(13-Station Real-Time Observations)"]
        AFCS_SRC["AFCS Ridership Datasets<br/>(Turnstile Entry/Exit Excel/CSV)"]
        PSOR_SRC["PSOR Incident Records<br/>(Internal Operational Logs)"]
    end

    %% =========================================================================
    %% 2. DATA EXTRACTION & SCRAPER PIPELINE
    %% =========================================================================
    subgraph SCRAPER["⚙️ 2. Source Layer (python-source-layer)"]
        direction TB
        PW["Playwright Stealth Scraper<br/>(DOM Expansion, Desktop Emulation)"]
        OCR["Gemini 2.0 Flash Vision<br/>(Infographic OCR & Pre-filters)"]
        WTH_PIPE["Weather Pipeline & Watchdog<br/>(Hourly Cron 5:00 AM – 10:00 PM PHT)"]
        INT_ETL["Internal Data Extractor<br/>(AFCS Turnstile & Capacity Batches)"]
    end

    FB --> PW
    PW --> OCR
    WTH --> WTH_PIPE
    AFCS_SRC --> INT_ETL
    PSOR_SRC --> INT_ETL

    %% =========================================================================
    %% 3. SUPABASE CENTRAL DATA & TRANSFORMATION ENGINE
    %% =========================================================================
    subgraph SUPABASE["🗄️ 3. Central Database & Transformation Hub (Supabase PostgreSQL)"]
        direction TB
        
        subgraph SCHEMAS["PostgreSQL Schemas"]
            EXT_SCHEMA["external Schema<br/>• academic_lgu_events<br/>• weather_current<br/>• weather_forecasts<br/>• events_consolidated<br/>• friction_weight"]
            AFCS_SCHEMA["AFCS & PSOR Schemas<br/>• ridership_hourly<br/>• student_transactions<br/>• station_platform_capacity<br/>• psor_incidents"]
            ANALYTICS_SCHEMA["Analytics Schema<br/>• predictive_model_outputs<br/>• descriptive_live_event_feed<br/>• predictive_passenger_volume_forecast (24h, 1w, 1y)<br/>• prescriptive_active_checklists<br/>• simulation_history"]
            IAM_SCHEMA["iam Schema<br/>• users (PO, CCO, GCS, SA)<br/>• roles & permissions<br/>• audit_logs & user_sessions"]
            GCS_SCHEMA["gcs Schema<br/>• shifts<br/>• incidents (photos, severity)<br/>• task_acknowledgments"]
            APTA_SCHEMA["APTA Schema<br/>• apta_protocols (01-06)<br/>• apta_protocols_tactics"]
        end

        STORAGE["Supabase Storage<br/>(incident-photos bucket)"]
        REALTIME["Supabase Realtime Engine<br/>(WebSocket Broadcast & Presence)"]
    end

    OCR -->|Scraped Events| EXT_SCHEMA
    WTH_PIPE -->|Weather Metrics| EXT_SCHEMA
    INT_ETL -->|Ridership & Platform Limits| AFCS_SCHEMA

    %% SQL Transformations & Triggers
    EXT_SCHEMA -->|classify_event_from_text<br/>& calculate_weather_friction| ANALYTICS_SCHEMA
    AFCS_SCHEMA -->|transform_ridership_hourly| ANALYTICS_SCHEMA
    APTA_SCHEMA -->|Prescriptive Rules Engine| ANALYTICS_SCHEMA

    %% =========================================================================
    %% 4. ANALYTICS & ML PIPELINE
    %% =========================================================================
    subgraph ML_LAYER["🧠 4. Machine Learning & Forecasting Layer"]
        ML_TRAIN["XGBoost & RandomForest Models<br/>(80% Train / 20% Test Split)"]
        ML_PRED["Dynamic Volume Adjuster (Bm)<br/>(Weather, Academic & Civic Shocks)"]
    end

    AFCS_SCHEMA --> ML_TRAIN
    EXT_SCHEMA --> ML_PRED
    ML_PRED --> ANALYTICS_SCHEMA

    %% =========================================================================
    %% 5. USER-FACING APPLICATIONS TIER
    %% =========================================================================
    subgraph APPS["🖥️ 5. Frontend User Applications"]
        
        subgraph IAM_APP["🔐 IAM Superadmin Portal<br/>(Next.js & Electron)"]
            IAM_UI["• User Provisioning (POxxxx, CCOxxxx, GCSxxxx)<br/>• Role & Credential Lifecycle<br/>• Immutable Audit Log Cockpit"]
        end

        subgraph DASHBOARD_APP["📊 Command Center Decision Support Dashboard<br/>(Next.js & Electron Desktop)"]
            DASH_PRED["Multi-Horizon Predictive Timeline<br/>(24h Dayparts, 1W, Quarters, 1Y)"]
            DASH_SIM["Scenario Simulator & Executive PDF<br/>(Station Diurnal Profile Engine)"]
            DASH_FEED["Urban Trigger Feed<br/>(3-Tier Severity Calibration)"]
            DASH_APTA["Prescriptive Actions Card<br/>(APTA-01 to 06 Crowd Protocols)"]
        end

        subgraph MOBILE_APP["📱 Ground Control Mobile Application<br/>(React Native & Expo)"]
            MOB_CHECK["Live APTA Prescriptive Checklists<br/>(Urgent, Warning, Normal)"]
            MOB_INC["Rapid Field Incident Reporting<br/>(Camera Capture & Evidence)"]
            MOB_SYNC["Offline-First Resilience Queue<br/>(AsyncStorage & NetInfo)"]
            MOB_SHIFT["Shift & Station Handover Logs"]
        end
    end

    %% =========================================================================
    %% 6. BIDIRECTIONAL INTERACTION FLOWS
    %% =========================================================================
    %% IAM Connections
    IAM_UI <-->|Manage Users & Audit Logs| IAM_SCHEMA
    IAM_SCHEMA -.->|Authorize Controllers| DASHBOARD_APP
    IAM_SCHEMA -.->|Authorize Ground Staff| MOBILE_APP

    %% Dashboard Connections
    ANALYTICS_SCHEMA <-->|Query Forecasts & Live Feeds| DASHBOARD_APP
    DASHBOARD_APP -->|Dispatch Prescriptive Directives| REALTIME

    %% Mobile Connections
    REALTIME -->|Push Tactical Checklists| MOBILE_APP
    MOBILE_APP -->|Upload Photos| STORAGE
    MOBILE_APP -->|Acknowledge Tasks & Shifts| GCS_SCHEMA
    MOBILE_APP -->|Submit Field Incident Reports| GCS_SCHEMA

    %% Feedback Loop: Mobile Dispatches update Dashboard
    GCS_SCHEMA -->|Incident Severity Adjusts CFI| EXT_SCHEMA
    REALTIME <-->|Broadcast Real-Time Incidents| DASH_FEED
```

---

## 2. Sub-Application Breakdown & Responsibilities

| Sub-Application | Path | Primary Tech Stack | Core Responsibilities |
|---|---|---|---|
| **1. Source Layer** | `Scraper/` (`python-source-layer`) | Python 3.12, Playwright, BeautifulSoup, Gemini 2.0 Flash | • Scrapes official Facebook academic/LGU announcements.<br>• Extracts text from advisory infographics via Gemini Vision OCR.<br>• Fetches hourly Open-Meteo weather observations and 7-day forecasts.<br>• Executes internal AFCS turnstile ETL batches. |
| **2. Transformation & ML Layer** | `Analytics/` (`supabase_analytics_layer`) | PostgreSQL PL/pgSQL, Python 3.10, XGBoost, Scikit-learn | • Standardizes raw inputs into the Commuter Friction Index (CFI).<br>• Runs classification functions (`classify_event_from_text`).<br>• Trains volume prediction models ($B_m$) and computes headroom.<br>• Compiles prescriptive crowd-control checklists against APTA standards. |
| **3. Decision Support Dashboard** | `Command Center Dashboard/` | Next.js 16.2, Electron 31, TailwindCSS, Recharts | • Mission-control interface for transit controllers.<br>• Visualizes 24h, 1w, quarterly, and 1y predictive passenger volumes.<br>• Runs what-if simulations with realistic diurnal curves.<br>• Exports printable A4 executive PDF reports.<br>• Dispatches APTA crowd management checklists. |
| **4. Ground Control Mobile** | `Ground Control Mobile/` | React Native 0.81, Expo 54, NativeWind | • Field client for station safety officers and platform personnel.<br>• Displays prioritized real-time APTA checklists (Urgent / Warning / Normal).<br>• Enables rapid incident reporting with camera evidence capture.<br>• Provides offline mutation queuing (`useOfflineSync`). |
| **5. IAM Superadmin Portal** | `Identity Access and Management Portal/` | Next.js 16.2, Electron, TailwindCSS, Radix UI | • Single source of truth for user authentication and authorization.<br>• Enforces Role-Based Access Control (`SAxxxx`, `POxxxx`, `CCOxxxx`, `GCSxxxx`).<br>• Immutably records administrative actions in `iam.audit_logs`. |

---

## 3. Detailed Data Flow & Operational Feedback Loops

```mermaid
sequenceDiagram
    autonumber
    actor Officer as Ground Control Staff (Mobile)
    participant Mobile as Ground Control App
    participant Storage as Supabase Storage
    participant DB as Supabase PostgreSQL
    participant Realtime as Supabase Realtime
    participant Dashboard as Command Center Dashboard
    actor Controller as Command Center Officer

    %% Incident Escalation Flow
    Note over Officer, Mobile: Field Incident Occurs (e.g. Concourse Overcrowding)
    Officer->>Mobile: Capture photo & submit incident report
    Mobile->>Storage: Upload photo to "incident-photos" bucket
    Storage-->>Mobile: Return public photo URL
    Mobile->>DB: Insert into gcs.incidents (Severity: Critical/Warning)
    DB->>DB: Trigger updates external.events_consolidated (CFI recalculated)
    DB->>Realtime: Broadcast gcs_incidents_feed event
    Realtime->>Dashboard: Instant notification in Urban Trigger Feed

    %% Prescriptive Action & Task Dispatch Flow
    Note over Controller, Dashboard: Controller Evaluates Prescriptive Recommendation
    Dashboard->>DB: Evaluate "Analytics".prescriptive_action_recommendations
    Controller->>Dashboard: Acknowledge & dispatch APTA protocol (e.g. APTA-02 Faregate Throttling)
    Dashboard->>Realtime: Broadcast to "apta_prescriptive_dispatch" channel
    Realtime->>Mobile: Push updated tactical checklist to station staff
    Officer->>Mobile: Check off completed task (e.g. Inflow gate restricted)
    Mobile->>DB: Record in gcs.task_acknowledgments
    DB->>Realtime: Broadcast task completion
    Realtime->>Dashboard: Live checklist progress updates to 100%
```

---

## 4. PostgreSQL Schema & Data Dictionary

```mermaid
erDiagram
    %% IAM Schema
    iam_users ||--o{ iam_audit_logs : generates
    iam_users ||--o{ gcs_shifts : executes
    iam_users ||--o{ gcs_task_acknowledgments : acknowledges

    %% GCS Schema
    gcs_incidents }o--|| external_events_consolidated : propagates_to
    gcs_task_acknowledgments }o--|| apta_protocols : implements

    %% APTA Schema
    apta_protocols ||--|{ apta_protocols_tactics : contains

    %% External Schema
    external_academic_lgu_events ||--o{ external_events_consolidated : transforms_into
    external_weather_current ||--o{ external_weather_consolidated : syncs_to
    external_friction_weight ||--o{ external_events_consolidated : provides_weights

    %% Analytics Schema
    afcs_ridership_hourly ||--o{ analytics_predictive_model_outputs : trains
    external_events_consolidated ||--o{ analytics_predictive_model_outputs : adjusts_volume
    analytics_predictive_model_outputs ||--o{ analytics_forecast_views : exposes

    iam_users {
        string user_id PK "POxxxx, CCOxxxx, GCSxxxx, SAxxxx"
        string username
        string role "Super Admin, Provisioning Officer, etc."
        string station_assignment
        string status "active, suspended, deactivated"
    }

    gcs_incidents {
        string id PK "INCxxxxxx"
        string station_name
        string incident_type
        string severity "critical, warning, low"
        string photo_url
        numeric duration_hours
        string status "active, resolved"
    }

    external_events_consolidated {
        string id PK
        string station
        date event_date
        string event_name
        string event_category "class_suspension, major_event, etc."
        numeric normalized_score "0.0 to 1.0"
    }

    apta_protocols {
        string id PK "APTA-01 to APTA-06"
        string name
        string trigger_condition
        string alert_level "Urgent, Warning, Normal"
    }
```

---

## 5. Security & Isolation Matrix

| Boundary | Mechanism | Enforcement Layer |
|---|---|---|
| **User Authentication** | Supabase Auth + JWT Tokens | API Gateway & App Route Guards |
| **Role Authorization** | RBAC bitmasks stored in `iam.roles` | PostgreSQL Row-Level Security (RLS) & UI Guards |
| **Audit Immutability** | Append-only table (`iam.audit_logs`) | Revoked `UPDATE`/`DELETE` permissions |
| **Scraper Rate Limits** | Partitioned cookie pools & delay throttling | Playwright worker processes |
| **Offline Resilience** | FIFO queue in local storage (`AsyncStorage`) | `useOfflineSync` NetInfo reconnection hook |
| **Photo Upload Integrity** | Isolated bucket (`incident-photos`) | Supabase Storage RLS policies |
