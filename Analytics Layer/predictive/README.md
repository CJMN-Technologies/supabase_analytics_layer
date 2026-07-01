# Predictive Analytics Layer Documentation

This document compiles the complete concepts, variables, formulations, and step-by-step procedures for the **Predictive Analytics Layer** (XGBoost & Random Forest) of the LRT-2 Commuter Friction Index (CFI) system.

---

# Section 1: Predictive Analytics Concept (XGBoost & Random Forest)

## 1.1 The Dual-Model Architecture
The Predictive Layer of the Decision Support System utilizes a dual-model machine learning architecture to forecast commuter surges. Relying on a single model is insufficient for life-safety infrastructure; therefore, the system separates continuous volume forecasting from discrete threat classification.

## 1.2 XGBoost Regression (Volume Forecasting & Simulation)
To predict the exact numerical passenger volume, the system uses **Extreme Gradient Boosting (XGBoost)**. XGBoost excels at identifying non-linear patterns in historical tabular data (e.g., time of day, seasonality, academic events). 

Furthermore, XGBoost powers the **Interactive "What-If" Simulation Engine**. Operators can inject theoretical stressors (like a sudden class suspension), allowing the model to calculate a new **Simulated Forecasted Peak** and determine the **Forecasted Peak Variance** from the baseline.

## 1.3 Random Forest Classification (Threat Level Categorization)
While XGBoost predicts *how many* passengers will arrive, a **Random Forest Classifier** determines the *severity* of that volume. Optimized for "Maximum Recall," this model classifies the incoming surge into discrete threat levels (Normal, Warning, Critical). In transit safety, prioritizing recall ensures the system minimizes false negatives (missing a critical surge), even if it occasionally issues a false positive (a false alarm).

## 1.4 Operational Validation
To guarantee the system meets Minimum Viable Performance (MVP) standards, the baseline forecasts are continuously audited against actual turnstile data using the **Mean Absolute Percentage Error (MAPE)**, strictly penalizing the model for missing massive surges.

---

# Section 2: Predictive Variables and Mathematical Formulations

Below are the mathematical formulations and descriptive labels for the predictive regression validation and scenario simulation variance.

### Mathematical Formulations

**Forecasted Peak Variance ($P_v$):**
$$P_v = \left(\frac{F_s - B_m}{B_m}\right) \times 100$$

**Mean Absolute Percentage Error (MAPE):**
$$M = \frac{100}{n}\sum_{i=1}^{n}\left|\frac{A_i - F_i}{A_i}\right|$$

### Dictionary of Variables

#### Scenario Simulation Variables
* **$P_v$**: Forecasted Peak Variance  
  *(The percentage shift or operational shock between the normal baseline forecast and the stressed simulation).*
* **$B_m$**: Baseline Mean Forecast  
  *(The normal passenger volume predicted by XGBoost strictly using historical temporal data).*
* **$F_s$**: Simulated Forecasted Peak  
  *(The new predicted passenger volume generated when hypothetical stressors are applied to the model).*

#### Validation & Error Variables (MAPE)
* **$M$**: Mean Absolute Percentage Error (MAPE)  
  *(The average percentage discrepancy between the system's predictions and the actual ground truth).*
* **$n$**: Number of Observations  
  *(The total count of forecasting instances being evaluated).*
* **$A_i$**: Actual Volume  
  *(The true, recorded passenger count pulled from the AFCS turnstile logs post-event).*
* **$F_i$**: Forecasted Volume  
  *(The passenger count initially predicted by the XGBoost regression model).*

#### Classification Labels (Random Forest)
* **Normal**: Expected volume is operating below the 80th percentile historical baseline.
* **Warning**: Expected volume exceeds the 80th percentile Warning Threshold ($W_t$).
* **Critical**: Expected volume exceeds the 90th percentile Critical Threshold ($C_t$), indicating severe life-safety risk.

---

# Section 3: Step-by-Step Procedure: Predictive Forecasting & Simulation

The following pipeline outlines how the system's dual-model architecture processes data to forecast transit volumes, classify threat levels, and simulate stress scenarios.

### Step 1: Feature Engineering & Ingestion
The predictive engine ingests the static historical AFCS turnstile data and temporal features (time of day, day of week, seasonality). In parallel, the API layer pulls near real-time environmental data (PAGASA, LGU mandates) to dynamically calculate the Commuter Friction Index (CFI).

### Step 2: Baseline Volume Forecasting (XGBoost)
The **XGBoost Regression** model analyzes the ingested historical and temporal features to predict the continuous numerical passenger volume for the upcoming time horizons (e.g., forecasting 1,500 passengers for Recto Station at 4:00 PM). This establishes the **Baseline Mean Forecast ($B_m$)**.

### Step 3: Dynamic Contextual Adjustment (Applying CFI)
Instead of confusing the machine learning model with real-time data it was never trained on, the system uses the CFI score as a **Post-Processing Modifier**. It mathematically adjusts the XGBoost baseline forecast ($B_m$) up or down based on current transit impedance (e.g., sudden heavy rain), producing a context-aware volume projection.

### Step 4: Threat Level Categorization (Random Forest)
The **Random Forest Classifier** evaluates this adjusted data to assign a discrete safety category (Normal, Warning, or Critical) to the forecasted period. This model is deliberately biased towards Maximum Recall to ensure high-risk surges are never overlooked or misclassified.

### Step 5: "What-If" Scenario Simulation
If a command center operator wishes to stress-test the network, they input hypothetical triggers into the dashboard simulator (e.g., "Simulate a Signal No. 2 Typhoon and Manila class suspension at 5:00 PM"). The system recalculates the CFI and applies it to the baseline to produce a **Simulated Forecasted Peak ($F_s$)**. It then calculates the **Forecasted Peak Variance ($P_v$)**, displaying the exact percentage shift to the operator.

### Step 6: Continuous Auditing & Validation
Once the forecasted hour passes, the system retrieves the *actual* turnstile counts ($A_i$) from the database. It calculates the **Mean Absolute Percentage Error (MAPE)** to evaluate the model's operational accuracy. If the error exceeds acceptable thresholds, the system flags the algorithms for recalibration.
