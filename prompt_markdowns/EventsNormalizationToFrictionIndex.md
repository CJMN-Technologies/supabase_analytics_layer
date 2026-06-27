### Context: Quantifying Transport Impedance
In high-density urban transit environments, external anomalies—such as severe weather, university events, and local government mandates—exert a quantifiable friction on normal commuter behavior[cite: 1]. This phenomenon is defined in modern urban mobility literature as "transport impedance"[cite: 1]. 

Because raw data pulled from external APIs (like PAGASA weather updates or LGU announcements) is unstructured and qualitative, it cannot be directly processed by the system's predictive machine learning algorithms, such as XGBoost[cite: 1]. To bridge the gap between near real-time urban threats and historical transit baselines, the system must translate these qualitative real-world events into standardized mathematical variables[cite: 1]. 

The following steps outline the logic used to normalize these chaotic urban triggers into a standardized scale (typically 0.0 to 1.0), which are then weighted and combined to calculate the system's Commuter Friction Index (CFI)[cite: 1]:

---

**Step 3a. Normalizing Meteorological Friction ($P_{idx}$)**
The system evaluates the weather severity based on predefined agency matrices[cite: 1].
* *Logic:* If `wind_signal == 0` AND `rainfall_mm < 5`, then $P_{idx} = 0.0$ (Clear weather, no friction).
* *Logic:* If `wind_signal == 1` OR `rainfall_mm > 15`, then $P_{idx} = 0.4$ (Moderate friction).
* *Logic:* If `wind_signal >= 2` OR `rainfall_mm > 40`, then $P_{idx} = 0.8$ to $1.0$ (Severe friction).

**Step 3b. Normalizing Academic Surge Weight ($A_{sw}$)**
The system counts the volume of major events (e.g., entrance exams, UAAP games, graduations) occurring within the LRT-2 catchment area for that specific day[cite: 1].
* *Logic:* If `event_count == 0`, then $A_{sw} = 0.0$.
* *Logic:* If `event_count == 1` (isolated surge), then $A_{sw} = 0.5$.
* *Logic:* If `event_count >= 3` (network-wide surge), then $A_{sw} = 1.0$.

**Step 3c. Normalizing Civic Mandates / Suspensions ($L_{sp}$)**
Because official class suspensions are typically binary declarations, this normalization utilizes direct boolean logic[cite: 1].
* *Logic:* Check keyword flags (e.g., "Suspended", "Walang Pasok").
* *Logic:* If `False` (Normal operations), then $L_{sp} = 0.0$.
* *Logic:* If `True` (Classes suspended), then $L_{sp} = 1.0$.