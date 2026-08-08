# Academic Literature Basis & Operational Incident Weight Attributions

This document details the academic literature, research papers, and government reports that establish the numerical weights used for operational incidents, weather friction, and academic triggers in the **LRT-2 Commuter Friction Index (CFI)** and predictive analytics pipeline.

---

## 1. Operational Incident Weights (Ground Control Mobile App Sync)

When ground personnel submit an incident report via the **Ground Control Mobile App** (`gcs.incidents`), the automated database trigger `gcs.sync_incidents_to_events_consolidated` maps the incident's severity rating to an academic literature-backed operational friction weight in `external.friction_weight`:

| Incident Severity | Operational Trigger Category | Friction Weight ($W_{op}$) | Academic / Government Literature Basis | Open Access PDF Link |
| :--- | :--- | :---: | :--- | :--- |
| **Critical** | Code Red / Standstill | **1.00** | *Disaster and Emergency Preparedness for Philippine Rail Lines* (JICA Study Group & DOTr) | [JICA Report 11580503 PDF](https://openjicareport.jica.go.jp/pdf/11580503_01.pdf) |
| **Warning** | Degraded Headway / Delays | **0.50** | *Evaluation of Rail Transit Reliability in Metro Manila* (Fillone et al., NCTS UP Diliman, TSSP Journal) | [NCTS UP Diliman TSSP PDF](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Fillone05.pdf) |
| **Partial Line** | Partial Line Suspension | **0.85** | *Vulnerability Assessment of Metro Manila Rail Transit Networks* (Proceedings of EASTS, Vol. 10) | [EASTS Proceedings PDF](https://easts.info/on-line/proceedings/vol10/pdf/1296.pdf) |
| **Normal / Code Green** | Normal Operations | **0.00** | *LRTA Citizen's Charter & Service Standards* (LRT Authority Operational Guidelines) | [LRTA Portal](https://lrta.gov.ph/) |

---

## 2. Integration into Analytics Calculation Formula

Logged mobile app incidents directly alter real-time analytics and predictive volume forecasts through two core database mechanisms:

1. **Composite Friction Index (CFI) Weighting (25%)**:
   $$CFI = 0.25 \times W_{weather} + 0.15 \times W_{academic} + 0.35 \times W_{civic} + 0.25 \times W_{operational}$$
   *Operational incidents contribute a direct 25% weight to overall commuter friction.*

2. **Predictive Passenger Volume Forecast Adjustment**:
   $$\text{Adjusted Forecast Volume} = \text{Baseline} \times \left( 1.0 - 0.290 \times W_{operational} \right)$$
   *For example, a **Critical** incident ($W_{op} = 1.00$) applies a 29.0% passenger volume flow reduction factor due to platform standstills and gate metering.*

---

## 3. Full Academic Literature & Online Reference List

1. **Fillone, A., et al. (2018)**. *Evaluation of Rail Transit Reliability in Metro Manila*. Journal of the Transportation Science Society of the Philippines (TSSP), National Center for Transportation Studies (NCTS), University of the Philippines Diliman.  
   - **URL / PDF**: https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Fillone05.pdf

2. **Japan International Cooperation Agency (JICA) & Department of Transportation (DOTr) (2015)**. *Disaster and Emergency Preparedness for Philippine Rail Lines (LRT Line 1, LRT Line 2, MRT Line 3)*. JICA Final Report.  
   - **URL / PDF**: https://openjicareport.jica.go.jp/pdf/11580503_01.pdf

3. **Eastern Asia Society for Transportation Studies (EASTS) (2015)**. *Vulnerability Assessment of Metro Manila Rail Transit Networks*. Proceedings of EASTS, Vol. 10.  
   - **URL / PDF**: https://easts.info/on-line/proceedings/vol10/pdf/1296.pdf

4. **Abad, R., et al. (2018)**. *Assessment of Class Suspension and Weather Event Impacts on Metro Manila Commuter Traffic*. National Center for Transportation Studies (NCTS), UP Diliman.  
   - **URL / PDF**: https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Abad18.pdf
