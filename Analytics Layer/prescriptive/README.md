# Prescriptive Analytics Layer Documentation

This document compiles the complete concepts, variables, formulations, and step-by-step procedures for the **Prescriptive Analytics Layer** (Interpretable Decision Trees) of the LRT-2 Commuter Friction Index (CFI) system.

---

# Section 1: Prescriptive Analytics Concept (Interpretable Decision Trees)

## 1.1 The Need for Mathematical Transparency
In life-safety infrastructure like the LRT-2 system, AI cannot operate as a "black box." When making decisions that dictate crowd control, station commanders must understand exactly *why* the system recommends a specific action. For this reason, the Prescriptive Layer avoids opaque algorithms in favor of highly interpretable, heuristic-trained **Decision Trees**.

## 1.2 Integration of Hard Physical Baselines
The prescriptive logic is firmly anchored to deterministic physical constraints rather than abstract probabilities. The Decision Tree maps the continuous volume forecasts and discrete threat levels against the station's maximum physical capacity thresholds. Specifically, it routes logic based on the **80% (Warning)** and **90% (Critical)** maximum platform capacity baselines to trigger tactical interventions before a breach occurs.

## 1.3 Shift to Human-Centric "Man-Protocols"
The system strictly operates as an advisory tool and does not directly manipulate LRT-2 machinery or train operations (e.g., it will not automatically alter train headways or reverse escalators). Instead, it outputs directives for human-executed ground tactics. The Decision Tree routes outputs exclusively to pre-approved, APTA-compliant protocols. These include **manual turnstile metering**, **concourse holding via human barricades**, and **localized pulse boarding** to be executed by the station personnel.

## 1.4 Decoupling System Logic from Human Execution
To ensure the system is evaluated strictly on its own architectural merit—and not on the unpredictable reaction times of ground operators—the grading metrics have been overhauled. The system is no longer judged on whether ground staff successfully prevented a breach. Instead, it is evaluated on **Symbolic Heuristic Compliance Rate (SCR)** (ensuring the AI's logic always selects a valid APTA protocol) and **Data Ingestion-to-Broadcast Latency ($L_{ib}$)** (measuring the pure cloud architecture speed from receiving a trigger to broadcasting the directive to the dashboard).

---

# Section 2: Prescriptive Variables and Mathematical Formulations

Below are the mathematical formulations and descriptive labels used to define physical thresholds, validate the heuristic logic, and measure the cloud pipeline's speed for the prescriptive mitigation strategies.

### Mathematical Formulations

**Platform Capacity Utilization ($U_p$):**
$$U_p = \left(\frac{V_c}{K_p}\right) \times 100$$

**Symbolic Heuristic Compliance Rate (SCR):**
$$SCR = \left(\frac{V_p}{T_p}\right) \times 100$$

**Data Ingestion-to-Broadcast Latency ($L_{ib}$):**
$$L_{ib} = T_b - T_i$$

### Dictionary of Variables

#### Physical Baseline Variables
* **$K_p$**: Maximum Safe Platform Capacity  
  *(The absolute physical limit of passengers a specific LRT system platform can hold safely).*
* **$V_c$**: Forecasted Passenger Volume  
  *(The numerical passenger count passed down from the predictive layer).*
* **$U_p$**: Capacity Utilization Percentage  
  *(The percentage of the platform's capacity projected to be filled. Serves as the trigger for the Decision Tree: $\ge$ 80% triggers Warning protocols, $\ge$ 90% triggers Critical protocols).*

#### Logic Validation Variables (Compliance)
* **$SCR$**: Symbolic Heuristic Compliance Rate  
  *(The percentage of system-generated responses that strictly map to a valid, pre-approved APTA standard protocol. The absolute target is 100%).*
* **$V_p$**: Valid Protocol Generations  
  *(The number of times the Decision Tree correctly outputs an approved human-centric "Man-Protocol," such as manual turnstile metering).*
* **$T_p$**: Total Prescriptive Generations  
  *(The total number of mitigation directives issued by the system during a validation test).*

#### Efficiency Validation Variables (Latency)
* **$L_{ib}$**: Data Ingestion-to-Broadcast Latency  
  *(The cloud architecture's speed, measuring the exact interval between receiving an external API trigger and broadcasting the directive to the dashboard. The target is < 3.0 seconds).*
* **$T_i$**: Time of Ingestion  
  *(The exact timestamp when the system ingests data or a simulated anomaly trigger).*
* **$T_b$**: Time of Broadcast  
  *(The exact timestamp when the actionable prescriptive directive is rendered on the operator's interface).*

---

# Section 3: Step-by-Step Procedure: Prescriptive Tactical Mitigation

The procedure below outlines how the heuristic Decision Tree translates predictive forecasts into human-executed crowd management directives while adhering to strict capacity thresholds and latency benchmarks.

### Step 1: Ingestion and Baseline Mapping
The prescriptive engine receives the forecasted passenger volume ($V_c$) from the predictive layer. The system immediately calculates the Capacity Utilization Percentage ($U_p$) by mapping this volume against the LRT system platform's Maximum Safe Platform Capacity ($K_p$).

### Step 2: Heuristic Node Traversal (Threshold Triggers)
The Decision Tree evaluates $U_p$ against hardcoded deterministic thresholds. If the utilization is projected to reach $\ge$ 80%, the logic routes to "Warning" branches. If it is projected to reach $\ge$ 90%, it routes to high-severity "Critical" branches to prevent an imminent capacity breach.

### Step 3: Tactical Protocol Selection
Upon reaching a terminal node, the Decision Tree prescribes a specific mitigation strategy. Crucially, the system does not interface with LRT system machinery. Instead, it selects a pre-approved, APTA-compliant human-centric "Man-Protocol." Directives strictly consist of actions like manual turnstile metering, establishing concourse holding areas via human barricades, or initiating localized pulse boarding.

### Step 4: System Broadcast and Latency Logging
The prescriptive directive is instantly pushed to the station commander's dashboard. To evaluate the cloud architecture's speed, the system logs the Time of Ingestion ($T_i$) of the predictive trigger and the Time of Broadcast ($T_b$) to the interface. The difference calculates the Data Ingestion-to-Broadcast Latency ($L_{ib}$), ensuring the system meets the operational target of < 3.0 seconds without being penalized by human reaction times.

### Step 5: Logic Validation (Compliance Auditing)
During system validation, every generated directive is audited to calculate the Symbolic Heuristic Compliance Rate (SCR). The system checks if the prescribed action is a valid, recognized protocol. This guarantees 100% heuristic compliance, proving the AI logic is sound regardless of how ground operators ultimately execute the instructions.
