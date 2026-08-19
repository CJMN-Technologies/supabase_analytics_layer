# Model Training, Testing, and Validation Documentation

This document compiles the complete concepts, variables, formulations, and step-by-step procedures for the **Model Training, Testing, and Validation** of the LRT-2 Commuter Friction Index (CFI) system.

---

# Section 1: Model Training, Testing, and Validation Concept

## 1.1 Strict Chronological Data Partitioning
To ensure the machine learning models learn genuine forecasting rather than mere pattern memorization, the methodology strictly prohibits random data splitting. The data is partitioned chronologically using a Time-Series Cross-Validation approach. Specifically, an 80/20 chronological split is mandated—the algorithms are trained on the earlier 80% of historical LRT system turnstile data and tested purely on the subsequent 20%. This prevents "data leakage" (the model learning from future events) and ensures the models are tested on their true extrapolative forecasting capabilities.

## 1.2 Decoupled Validation Phases
To accurately isolate and evaluate system performance, the validation methodology is explicitly decoupled into two distinct testing phases that mirror the system's pipeline:
1. **Predictive Accuracy:** Evaluates the mathematical forecasting engine (the continuous volume predictions of XGBoost and the discrete risk classification of the Random Forest).
2. **Prescriptive Validation:** Evaluates the decision-making logic of the heuristic Decision Trees and the data-broadcast speed of the cloud pipeline.

## 1.3 Simulated Scenario Injection (UAT)
Live operational stress testing—which historically relied on Command Center staff logging physical reaction times during real-world anomalies—has been completely removed to eliminate human interference from the system's grading. Instead, User Acceptance Testing (UAT) is conducted via **Simulated Scenario Injection**. In a controlled sandbox environment, historical anomaly datasets (e.g., past severe weather alerts or sudden class suspensions) are fed into the pipeline. This safely and mathematically verifies both the predictive accuracy and the prescriptive logic.

## 1.4 Minimum Viable Performance Benchmarks
To be deemed production-ready for the client, the LRT-2 Decision Support System (LRT2 DSS) must achieve or exceed the following concrete Minimum Viable Performance (MVP) passing grades during the simulation phase:
* **Volume Prediction (XGBoost):** RMSE < 5% variance.
* **Risk Classification (Random Forest):** Weighted F1-Score $\ge$ 0.85.
* **Heuristic Compliance (Decision Tree):** SCR = 100%.
* **System Latency (Cloud Pipeline):** $L_{ib}$ < 3.0 seconds.

---

# Section 2: Variables and Mathematical Formulations

Below are the mathematical formulations and descriptive labels used to partition the data, evaluate the decoupled predictive and prescriptive phases, and benchmark the system against the strict Minimum Viable Performance (MVP) targets for the LRT system.

### Mathematical Formulations

**Root Mean Squared Error (RMSE) [Predictive - Regression]:**
$$RMSE = \sqrt{\frac{1}{n}\sum_{i=1}^{n}(y_i - \hat{y}_i)^2}$$

**Weighted F1-Score [Predictive - Classification]:**
$$F1 = 2 \times \frac{Precision \times Recall}{Precision + Recall}$$

**Symbolic Heuristic Compliance Rate (SCR) [Prescriptive - Logic]:**
$$SCR = \left(\frac{V_p}{T_p}\right) \times 100$$

**Data Ingestion-to-Broadcast Latency [Prescriptive - Pipeline]:**
$$L_{ib} = T_b - T_i$$

### Dictionary of Variables

#### 1. Data Partitioning Variables
* **$D_{train}$**: Training Dataset  
  *(The chronologically earlier 80% of the historical turnstile data used strictly to train the models).*
* **$D_{test}$**: Testing Dataset  
  *(The subsequent 20% of unseen chronological data used strictly to test extrapolative forecasting capabilities).*

#### 2. Predictive Accuracy Variables
* **$RMSE$**: Root Mean Squared Error  
  *(The standard deviation of prediction errors for the XGBoost volume forecasts).*
* **$y_i$**: Actual True Value  
  *(The verified, historical passenger volume recorded).*
* **$\hat{y}_i$**: Predicted Value  
  *(The continuous numerical volume predicted by the XGBoost algorithm).*
* **$F1$**: F1-Score (Weighted)  
  *(The harmonic mean of Precision and Recall, calculated across all threat level classes by the Random Forest model to account for class imbalances in surge events).*

#### 3. Prescriptive Validation Variables
* **$SCR$**: Symbolic Heuristic Compliance Rate  
  *(The percentage of system-generated responses that strictly map to valid, pre-approved APTA standard protocols. The target is 100%).*
* **$V_p$**: Valid Protocol Generations  
  *(The number of times the Decision Tree correctly outputs an approved human-centric "Man-Protocol").*
* **$T_p$**: Total Prescriptive Generations  
  *(The total number of mitigation directives issued during the simulated test).*
* **$L_{ib}$**: Data Ingestion-to-Broadcast Latency  
  *(The exact processing speed from receiving an external trigger to rendering the directive on the dashboard).*

#### 4. Minimum Viable Performance (MVP) Targets
* **$MVP_{rmse}$**: < 5% variance *(The maximum acceptable error margin for XGBoost volume predictions).*
* **$MVP_{f1}$**: $\ge$ 0.85 *(The minimum acceptable Weighted F1-Score for Random Forest risk classification).*
* **$MVP_{scr}$**: 100% *(The mandatory heuristic compliance rate for the Decision Tree logic).*
* **$MVP_{latency}$**: < 3.0 seconds *(The maximum allowable latency for the cloud pipeline).*

---

# Section 3: Step-by-Step Procedure: Model Training, Testing, and Validation

The following procedure outlines the decoupled pipeline used to partition data, train the predictive engine, and rigorously validate the system's prescriptive logic and cloud speed against strict operational benchmarks.

### Step 1: Chronological Data Partitioning
The engine ingests the historical AFCS turnstile logs and applies a strict Time-Series Cross-Validation split to prevent data leakage. The data is partitioned chronologically: the older 80% serves as the training dataset ($D_{train}$), while the most recent 20% is strictly withheld as the testing dataset ($D_{test}$) to evaluate the models' true extrapolative forecasting capabilities.

### Step 2: Predictive Engine Training
The $D_{train}$ dataset, along with temporal features, is fed into the predictive models. The **XGBoost** algorithm maps non-linear relationships to forecast continuous passenger volumes, while the **Random Forest** algorithm builds classification boundaries to categorize discrete threat levels (Normal, Warning, Critical) based on the LRT system's capacity thresholds.

### Step 3: Phase 1 Validation (Predictive Accuracy Testing)
The models are exposed to the unseen $D_{test}$ dataset. The system evaluates their forecasting accuracy mathematically:
* It calculates the **RMSE** for the XGBoost volume predictions, ensuring the error variance remains $< 5\%$.
* It calculates the **Weighted F1-Score** for the Random Forest classification, ensuring a balance of precision and recall with a score $\ge 0.85$.

### Step 4: Phase 2 Validation (Simulated Scenario Injection)
To validate the prescriptive logic without relying on unpredictable human operations, the testing shifts to User Acceptance Testing (UAT) via **Simulated Scenario Injection**. The system is fed historical anomaly datasets (e.g., severe weather events or sudden class suspensions) in a controlled sandbox environment. The Decision Tree processes these simulated surges to generate tactical "Man-Protocols."

### Step 5: Heuristic Compliance and Latency Certification
During the simulation, the system audits the outputs of the Prescriptive Layer and the speed of the cloud architecture:
* **Compliance:** The system calculates the Symbolic Heuristic Compliance Rate (SCR) by verifying that every generated directive is a valid, APTA-compliant human tactic (Target: $100\%$).
* **Speed:** The system logs the Time of Ingestion ($T_i$) and the Time of Broadcast ($T_b$) to calculate the Data Ingestion-to-Broadcast Latency ($L_{ib}$), ensuring the cloud pipeline operates at $< 3.0$ seconds.

If the system clears all four Minimum Viable Performance (MVP) benchmarks ($MVP_{rmse}$, $MVP_{f1}$, $MVP_{scr}$, $MVP_{latency}$), it is mathematically certified as production-ready for the LRT system.
