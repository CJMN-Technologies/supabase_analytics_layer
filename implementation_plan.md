# Implementation Plan: Automated Ridership & Transaction Transformation Pipeline

This plan outlines the implementation of SQL scripts and a Node.js orchestration runner to automate the entire data preparation pipeline for the AFCS schema. This includes backing up, transforming the 5-year ridership tables (2021–2025) into hourly formats, and expanding the student transactions table (June 2025 – March 2026).

---

## Goal

Provide a single command/script to:
1. **Restore Ridership Backups:** Re-aggregate the current active hourly tables back into the original 5-band backup tables (`ridership_YYYY_backup`), preserving original ascending IDs and format specifications.
2. **Transform Ridership to Hourly:** Transform the backup tables into active hourly tables (`ridership_YYYY`) using empirical weights and a cumulative rounding technique that guarantees zero rounding discrepancies.
3. **Expand Student Transactions:** Recreate and expand monthly student transactions into hourly proportional rows and daily totals (restricted to June 2025 – March 2026).
4. **Validation:** Automatically verify database integrity and log status reports.

---

## User Review Required

> [!IMPORTANT]
> **Database Credentials Configuration:** The automation script will utilize a `.env` file containing the database connection string. This avoids hardcoding passwords and makes the pipeline portable across environments (development, staging, production).

> [!NOTE]
> **Double-Layered Cumulative Rounding:** In the new `transform_ridership_hourly.sql` script, we will apply a double-layered cumulative rounding strategy. This ensures that:
> 1. The sum of hourly station columns matches the hour's `total_entry` and `total_exit` columns exactly.
> 2. The sum of hourly rows matches the original band totals exactly.

---

## Proposed Changes

### Automation & Script Files

#### [NEW] [restore_ridership_backups.sql](file:///C:/Users/Jed/G11-Transformation/restore_ridership_backups.sql)
A SQL script that drops and recreates the 5 backup tables (`ridership_2021_backup` to `ridership_2025_backup`).
- **Logic:** Aggregates hourly rows in active tables back into the original 5 bands (`5-7am (OFF PEAK)`, `7-9am (AM PEAK)`, `9am-5pm (OFF PEAK)`, `5-7pm (PM PEAK)`, `7-10pm (OFF PEAK)`) by summing entries/exits chronologically.
- **Aggregates:** Renames `DAILY_TOTAL` back to `'Daily Total'`.
- **Special dates (2023):** Preserves hourly ranges (e.g. `'05:00-06:00'`) for June 2023 and Nov 1, 2023.
- **IDs:** Re-generates chronological ascending IDs matching `YR{YYYY}-{0001-to-N}`.

#### [NEW] [transform_ridership_hourly.sql](file:///C:/Users/Jed/G11-Transformation/transform_ridership_hourly.sql)
A SQL script that drops and recreates the active ridership tables, populating them with hourly rows using the EIBD weights and cumulative rounding.
- **Weights CTE:** Defines the exact empirical weights derived from Nov 1, 2023.
- **Rounding:** Enforces strict integer sum constraints so no values are lost.
- **IDs:** Assigns structured IDs: `YR{YYYY}-{YYYYMMDD}-{HH}` (hourly) and keeps original sequential IDs for `DAILY_TOTAL`.

#### [MODIFY] [expand_student_transactions.sql](file:///C:/Users/Jed/G11-Transformation/expand_student_transactions.sql)
We will align this script with the pipeline's automation runner, ensuring it executes dynamically and cleanups are handled properly.

#### [NEW] [run_pipeline.js](file:///C:/Users/Jed/G11-Transformation/run_pipeline.js)
A Node.js orchestration script that reads from a `.env` file, connects to the database via `pg`, and runs the SQL scripts in order:
1. `restore_ridership_backups.sql`
2. `transform_ridership_hourly.sql`
3. `expand_student_transactions.sql`
4. Performs verification queries and prints a success report.

#### [NEW] [.env.example](file:///C:/Users/Jed/G11-Transformation/.env.example)
A configuration template for database connection parameters.

---

## Verification Plan

We will run the following checks inside the Node.js automation runner:
1. **Row Count Validation:** Ensure each table has the expected number of hourly and aggregate rows.
2. **Sum Consistency Check:** Verify that for all active ridership and student transaction tables, `sum(stations) = total_entry/exit` for all rows.
3. **Sequential ID Check:** Verify that daily totals rise sequentially and there are no duplicate primary keys.
