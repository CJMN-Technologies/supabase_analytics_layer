# Descriptive Analytics Layer Documentation

This document compiles the complete concepts, variables, formulations, and step-by-step procedures for the **Descriptive Analytics Layer** of the LRT-2 Commuter Friction Index (CFI) system.

---

# Section 1: Commuter Friction Index (CFI) Concept & Mechanics

## 1.1 The Core Concept: Transport Impedance
The overall concept of the Commuter Friction Index (CFI) is rooted in the idea of "transport impedance". In a dense urban transit environment, external anomalies—like severe weather, sudden class suspensions, or major university events—exert a quantifiable "friction" that disrupts normal commuter flow and alters ridership behavior.

The primary purpose of the CFI is to act as a bridge between delayed historical turnstile data and near real-time urban threats. Instead of relying on qualitative observations (e.g., "it's raining heavily" or "classes are suspended"), the CFI synthesizes these chaotic, unstructured external triggers into a single, standardized numerical scale.

## 1.2 How It Works: Mathematical Formulation
During the generation of an hourly context snapshot, the system calculates the CFI as a weighted composite of the active external dimensions currently impacting the transit network.

The mathematical formulation is:

$$CFI = (W_w \times P_{idx}) + (W_a \times A_{sw}) + (W_c \times L_{sp})$$

Here is how the variables break down:
*   **$P_{idx}$ (Meteorological Friction):** This represents the baseline weather friction derived from near real-time PAGASA alerts, scaling with the severity of the tropical cyclone wind signal and recorded rainfall.
*   **$A_{sw}$ (Academic Surge Weight):** This variable reflects the density of active university events within the transit line's catchment area, pulled directly from academic calendars.
*   **$L_{sp}$ (Surge Probability Multiplier):** This is derived from local government mandates, specifically activating when official class suspensions are announced.
*   **$W_w, W_a, W_c$ (Algorithmic Weights):** These are the specific weights assigned to each of the three triggers above to determine their relative impact.

## 1.3 Determining the Weights: Literature-Derived Parameter Calibration
Because historical turnstile logs (batch data) and live urban triggers (micro-batch data) process at different speeds, the system cannot perfectly synchronize them to learn the weights automatically. Instead, the system uses **Literature-Derived Parameter Calibration**.

Rather than arbitrarily assigning importance, the initial weight distributions ($W$) are synthesized from established, peer-reviewed urban mobility studies that quantify exactly how much weather events and civic mandates typically impact baseline transit ridership. These statistical proportions are then normalized to a sum of 1.0.

## 1.4 The Operational Value
Ultimately, this mathematically rigorous index ensures that highly disparate external variables are combined into one continuous gauge. By feeding this index into the predictive algorithms (like XGBoost) and displaying it on the command dashboard, transit operators gain an instantaneous, mathematically sound assessment of how much environmental resistance the transit system is currently facing.

---

# Section 2: CFI Variable Labels & Dictionaries

Below is the dictionary of the mathematical symbols and their corresponding descriptive labels as defined in the system's transport impedance framework.

### The Composite Metric
* **$CFI$**: Commuter Friction Index

### External Urban Triggers (Normalized Inputs)
* **$P_{idx}$**: Meteorological Friction (Weather Severity derived from PAGASA)
* **$A_{sw}$**: Academic Surge Weight (University Event Density)
* **$L_{sp}$**: Surge Probability Multiplier (Official Class Suspensions / LGU Mandates)

### Literature-Derived Algorithmic Weights (Multipliers)
* **$W_w$**: Algorithmic Weight for Meteorological Friction (35% or 0.35)
* **$W_a$**: Algorithmic Weight for Academic Surge (20% or 0.20)
* **$W_c$**: Algorithmic Weight for Civic Mandates (45% or 0.45)

---

# Section 3: Inflow Normalization Steps (Events to Friction Index)

## 3.1 Normalizing Meteorological Friction ($P_{idx}$)
The system evaluates the weather severity based on predefined agency matrices.
* *Logic:* If `wind_signal == 0` AND `rainfall_mm < 5`, then $P_{idx} = 0.0$ (Clear weather, no friction).
* *Logic:* If `wind_signal == 1` OR `rainfall_mm > 15`, then $P_{idx} = 0.4$ (Moderate friction).
* *Logic:* If `wind_signal >= 2` OR `rainfall_mm > 40`, then $P_{idx} = 0.8$ to $1.0$ (Severe friction).

## 3.2 Normalizing Academic Surge Weight ($A_{sw}$)
The system counts the volume of major events (e.g., entrance exams, UAAP games, graduations) occurring within the LRT-2 catchment area for that specific day.
* *Logic:* If `event_count == 0`, then $A_{sw} = 0.0$.
* *Logic:* If `event_count == 1` (isolated surge), then $A_{sw} = 0.5$.
* *Logic:* If `event_count >= 3` (network-wide surge), then $A_{sw} = 1.0$.

## 3.3 Normalizing Civic Mandates / Suspensions ($L_{sp}$)
Because official class suspensions are typically binary declarations, this normalization utilizes direct boolean logic.
* *Logic:* Check keyword flags (e.g., "Suspended", "Walang Pasok").
* *Logic:* If `False` (Normal operations), then $L_{sp} = 0.0$.
* *Logic:* If `True` (Classes suspended), then $L_{sp} = 1.0$.

---

# Section 4: Threshold Benchmarking via Percentiles

## 4.1 The Problem with Traditional Averages
In standard transit operations, historical baselines are often established using simple arithmetic means (averages). However, in high-density, highly volatile environments like LRT-2—which is heavily impacted by sudden student commuter surges, weather suspensions, and university events—using the mean is mathematically inadequate. Simple averages are easily skewed by extreme statistical outliers. If a massive crowd surge happens on a Tuesday, the average for all Tuesdays is artificially dragged upward, resulting in a distorted baseline that triggers false alarms or delayed responses.

## 4.2 The Solution: Non-Parametric Percentiles
To resolve this, the Decision Support System (DSS) abandons simple averages in favor of **non-parametric statistical percentiles** (specifically the 80th and 90th percentiles).

Percentiles are resistant to extreme outliers. By benchmarking capacity thresholds against the historical distribution of passenger volume, the system mathematically shields its baseline from being distorted by the extreme statistical noise of past crowd surges.

## 4.3 Operational Value
Instead of comparing a live crowd to an "average" crowd, the system compares it to the frequency distribution of past crowds.
* The **80th Percentile** establishes a "Warning" state, meaning the current volume is higher than 80% of historical observations for that specific time context.
* The **90th Percentile** establishes a "Critical" state, representing severe overcrowding that exceeds 90% of historical norms, justifying the immediate execution of prescriptive tactical automation (such as throttling turnstiles).

---

# Section 5: Threshold Benchmarking Variables

Below is the mathematical formulation and the descriptive labels for the variables used to establish capacity baselines within the system.

### Mathematical Formulation
$$W_t = P_{80}(X)$$
$$C_t = P_{90}(X)$$

### Dictionary of Variables
* **$X$**: Historical Passenger Volume Distribution  
  *(The aggregated dataset of continuous numerical passenger turnstile logs for a specific temporal or spatial context, e.g., Legarda Station on Friday at 5:00 PM).*
* **$P_{80}$**: The 80th Percentile  
  *(The statistical value below which 80% of the historical passenger volume observations fall).*
* **$P_{90}$**: The 90th Percentile  
  *(The statistical value below which 90% of the historical passenger volume observations fall).*
* **$W_t$**: Warning Threshold  
  *(The calculated baseline limit that, when breached, indicates an elevated but manageable commuter density).*
* **$C_t$**: Critical Threshold  
  *(The calculated baseline limit that, when breached, indicates severe overcrowding and life-safety risks, requiring immediate prescriptive mitigation).*

---

# Section 6: Step-by-Step Procedure: Establishing Threshold Benchmarks

The procedure below outlines how the system transforms raw historical turnstile data into operational threshold limits using percentile benchmarking.

### Step 1: Historical Data Aggregation
The system ingests the raw, historical Automated Fare Collection System (AFCS) logs from the database. This dataset contains millions of continuous passenger volume records spanning the 5-year historical baseline.

### Step 2: Contextual Grouping and Distribution Modeling ($X$)
Because a baseline for 7:00 AM cannot be applied to 12:00 PM, the system groups the historical data into specific temporal and topological segments (e.g., historical volumes for "Recto Station," "Mondays," "07:00 - 08:00"). This segmented dataset becomes the **Historical Passenger Volume Distribution ($X$)**.

### Step 3: Calculating the Warning Threshold ($W_t$)
The analytics engine applies a statistical percentile function to the sorted distribution $X$. It isolates the **80th percentile ($P_{80}$)**. The resulting numerical volume becomes the **Warning Threshold ($W_t$)**.
* *Outcome:* The system now knows the exact passenger count that separates normal operations from the top 20% of historically busy hours.

### Step 4: Calculating the Critical Threshold ($C_t$)
The engine then calculates the **90th percentile ($P_{90}$)** of the same distribution $X$. This higher numerical volume is set as the **Critical Threshold ($C_t$)**.
* *Outcome:* The system identifies the absolute peak volume metric, representing the top 10% of historically extreme crowd surges.

### Step 5: Operational Deployment
These calculated thresholds ($W_t$ and $C_t$) are stored as static operational baselines for each station and hour. When the Predictive layer (XGBoost) forecasts an upcoming volume, or the live monitoring dashboard ingests real-time data, the numbers are instantly compared against these benchmarks to trigger the appropriate visual indicators (Amber for Warning, Red for Critical) and prescriptive tactical alerts.
