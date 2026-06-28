# Commuter Friction Index (CFI): Concept and Mechanics

## The Core Concept: Transport Impedance
The overall concept of the Commuter Friction Index (CFI) is rooted in the idea of "transport impedance"[cite: 1]. In a dense urban transit environment, external anomalies—like severe weather, sudden class suspensions, or major university events—exert a quantifiable "friction" that disrupts normal commuter flow and alters ridership behavior[cite: 1]. 

The primary purpose of the CFI is to act as a bridge between delayed historical turnstile data and near real-time urban threats[cite: 1]. Instead of relying on qualitative observations (e.g., "it's raining heavily" or "classes are suspended"), the CFI synthesizes these chaotic, unstructured external triggers into a single, standardized numerical scale[cite: 1].

## How It Works: Mathematical Formulation
During the generation of an hourly context snapshot, the system calculates the CFI as a weighted composite of the active external dimensions currently impacting the transit network[cite: 1]. 

The mathematical formulation is:

$$CFI = (W_w \times P_{idx}) + (W_a \times A_{sw}) + (W_c \times L_{sp})$$[cite: 1]

Here is how the variables break down:
*   **$P_{idx}$ (Meteorological Friction):** This represents the baseline weather friction derived from near real-time PAGASA alerts, scaling with the severity of the tropical cyclone wind signal and recorded rainfall[cite: 1].
*   **$A_{sw}$ (Academic Surge Weight):** This variable reflects the density of active university events within the transit line's catchment area, pulled directly from academic calendars[cite: 1].
*   **$L_{sp}$ (Surge Probability Multiplier):** This is derived from local government mandates, specifically activating when official class suspensions are announced[cite: 1].
*   **$W_w, W_a, W_c$ (Algorithmic Weights):** These are the specific weights assigned to each of the three triggers above to determine their relative impact[cite: 1].

## Determining the Weights: Literature-Derived Parameter Calibration
Because historical turnstile logs (batch data) and live urban triggers (micro-batch data) process at different speeds, the system cannot perfectly synchronize them to learn the weights automatically[cite: 1]. Instead, the system uses **Literature-Derived Parameter Calibration**[cite: 1]. 

Rather than arbitrarily assigning importance, the initial weight distributions ($W$) are synthesized from established, peer-reviewed urban mobility studies that quantify exactly how much weather events and civic mandates typically impact baseline transit ridership[cite: 1]. These statistical proportions are then normalized to a sum of 1.0[cite: 1]. 

## The Operational Value
Ultimately, this mathematically rigorous index ensures that highly disparate external variables are combined into one continuous gauge[cite: 1]. By feeding this index into the predictive algorithms (like XGBoost) and displaying it on the command dashboard, transit operators gain an instantaneous, mathematically sound assessment of how much environmental resistance the transit system is currently facing[cite: 1].