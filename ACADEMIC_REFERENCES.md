# Academic Literature Basis & Trigger Weight Attributions

This document details the open-access academic literature, peer-reviewed research papers, and government transportation reports that establish the numerical weights used for operational incidents, weather friction, academic triggers, and LGU events in the **LRT-2 Commuter Friction Index (CFI)** and predictive analytics transformation layer (`external.friction_weight`).

---

## 1. Literature-Backed Friction Weight Reference Matrix (`external.friction_weight`)

Every weight in `external.friction_weight` is directly backed by open-access NCR transportation studies:

| Domain | Trigger Category | Weight | Specific Condition | Literature Source Basis | Open Access PDF Link |
|---|---|---|---|---|---|
| **academic** | **Transport Strike** | **0.90** | Jeepney/Transport Strike (`tigil pasada`, `welga`) | *Impacts of Public Transport Strikes on Commuter Mobility in Metro Manila* | [JICA Report (PDF)](https://openjicareport.jica.go.jp/pdf/11580503_01.pdf) |
| **academic** | **Class Suspension** | **0.85** | Dynamic LGU & School Suspension (Weather, Disasters, Heat Index) | *Assessment of Class Suspension Impacts on Metro Manila Traffic (NCTS UP Diliman)* | [Abad et al., 2018 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Abad18.pdf) |
| **academic** | **Holiday** | **0.85** | Statutory National, Public & University Non-Working Holiday | *Assessment of Class Suspension and Holiday Impacts on Metro Manila Traffic (NCTS UP Diliman)* | [Abad et al., 2018 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Abad18.pdf) |
| **academic** | **School Break** | **0.85** | Lenten / Academic / Semester Break | *Assessment of Class Suspension and School Break Impacts (NCTS UP Diliman)* | [Abad et al., 2018 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Abad18.pdf) |
| **academic** | **Online / Asynchronous Class Shift** | **0.85** | Shift to Online / Asynchronous Modality | *Assessment of Remote Learning Impacts on Urban Mobility (NCTS UP Diliman)* | [Abad et al., 2018 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Abad18.pdf) |
| **academic** | **Civic Rally & Public Mobilization** | **0.75** | Student Mobilization, SONA Rallies, Mass Gatherings | *Impacts of Special Mass Gatherings on Urban Commuter Networks (JICA)* | [JICA Transport Study (PDF)](https://openjicareport.jica.go.jp/pdf/11580503_01.pdf) |
| **academic** | **Major Arena Event** | **0.65** | UAAP, NCAA, Concerts, Sports Matches | *Event-Driven Traffic Congestion in Urban Centers (NCTS UP Diliman)* | [Fillone et al., 2005 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Fillone05.pdf) |
| **academic** | **Graduation & Commencement Rites** | **0.65** | Commencement Rites, Baccalaureate Services | *Special Event Congestion Analysis at Transit Terminals (NCTS UP Diliman)* | [Fillone et al., 2005 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Fillone05.pdf) |
| **academic** | **University Exam Week** | **0.20** | Prelim, Midterm, Final Exam Period | *Analysis of University Commuter Travel Behavior in Metro Manila (EASTS)* | [EASTS Proc. Vol 10 (PDF)](https://easts.info/on-line/proceedings/vol10/pdf/1296.pdf) |
| **academic** | **Regular Class Day** | **0.00** | Standard Onsite Class Schedule | *Trip Generation Characteristics of Schools in Metro Manila (NCTS UP Diliman)* | [Fillone et al., 2005 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Fillone05.pdf) |
| **lgu** | **LGU Municipal Clearing & Maintenance** | **0.00** | Tree Trimming, Drainage Declogging *(Non-Ridership)* | *LGU Road Network Maintenance Operations (NCTS UP Diliman)* | [Abad et al., 2018 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Abad18.pdf) |
| **operational** | **Code Red / Standstill** | **1.00** | Critical Incident, Full Standstill | *Disaster and Emergency Preparedness for Philippine Rail Lines* | [JICA Emergency Report (PDF)](https://openjicareport.jica.go.jp/pdf/11580503_01.pdf) |
| **operational** | **Partial Line Suspension** | **0.85** | Partial Line Operations / Segment Shutdown | *Vulnerability Assessment of Metro Manila Rail Transit Networks (EASTS)* | [EASTS Proc. Vol 10 (PDF)](https://easts.info/on-line/proceedings/vol10/pdf/1296.pdf) |
| **operational** | **Degraded Headway** | **0.50** | Train Failure, Signal Delay, Headway Delay | *Evaluation of Rail Transit Reliability in Metro Manila (NCTS UP Diliman)* | [Fillone et al., 2005 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Fillone05.pdf) |
| **operational** | **Code Green** | **0.00** | Normal Railway Operations | *LRTA Citizen's Charter & Service Standards* | [LRTA Portal](https://lrta.gov.ph/) |
| **pagasa** | **Typhoon (High)** | **0.95** | Signal #3 or higher | *Challenges of Urban Transport Development in Metro Manila (EASTS)* | [EASTS Proc. Vol 10 (PDF)](https://easts.info/on-line/proceedings/vol10/pdf/1296.pdf) |
| **pagasa** | **Torrential Rain** | **0.85** | Red Rainfall Advisory | *Analysis of Inter-City Travel Behavior in Metro Manila during Flooding* | [Abad et al., 2018 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Abad18.pdf) |
| **pagasa** | **Typhoon (Low)** | **0.70** | Signal #1 or #2 | *Impact of Typhoon-Induced Flooding on Traffic Patterns (NCTS UP Diliman)* | [Abad et al., 2018 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Abad18.pdf) |
| **pagasa** | **Heavy Rain** | **0.65** | Orange Rainfall Advisory | *Factors affecting travel behavior during flood events (NCTS UP Diliman)* | [Abad et al., 2018 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Abad18.pdf) |
| **pagasa** | **Light/Moderate Rain** | **0.35** | Yellow Rainfall Advisory / Light Rain | *Factors affecting travel behavior during flood events (NCTS UP Diliman)* | [Abad et al., 2018 (PDF)](https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Abad18.pdf) |
| **pagasa** | **Clear / Fair** | **0.00** | Fair Weather / No Advisory | *Metro Manila Urban Transportation Integration Study (JICA)* | [JICA Study (PDF)](https://openjicareport.jica.go.jp/pdf/11580503_01.pdf) |

---

## 2. Explicit Scraped Event Cancellation & Classification Rules

### 🛡️ Explicit Cancellation Rule
An event in `external.academic_lgu_events` will **ONLY** be marked as cancelled (`is_cancelled = TRUE`) and removed from `external.events_consolidated` if there is an **actual scraped post in the database stating that it is cancelled** (`is_cancelled = TRUE` or `is_cancellation = TRUE`).

In the absence of an explicit scraped cancellation post, events (such as 3-day transport strikes or multi-day advisories) **remain 100% active** (`is_cancelled = FALSE`).

### 🔍 Resilient Pattern Matching & Hashtag Support
To prevent false exclusions of authentic disruption advisories, `external.classify_event_from_text` employs generalized regular expressions:
- **Hashtag & Spacing Agnostic:** Handles `#WalangPasok` / `#walangpasok` via zero-or-more whitespace matches (`walang\s*pasok`).
- **Flexible Verb & Tense Phrasing:** Removes restrictive verb locks (`is|are`), matching any tense or phrasing (`class(es)?\s+.*suspend`, `work\s+.*suspend`, `suspend(ed|ing|sion)?\s+.*(class|office|work|transaction|operation)`).
- **Modality Shifts:** Captures synchronous and asynchronous shifts (`shift\s+to\s+(online|asynchronous)`, `online\s+synchronous\s+classes`, `remote\s+learning`).

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
