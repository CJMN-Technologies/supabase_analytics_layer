-- ============================================================================
-- SQL Script: Transform 5-Year Ridership Data to Hourly
-- Calls the stored dynamic transformation procedure for each historical year.
-- ============================================================================

SELECT external.transform_ridership_table(2021) as rows_2021;
SELECT external.transform_ridership_table(2022) as rows_2022;
SELECT external.transform_ridership_table(2023) as rows_2023;
SELECT external.transform_ridership_table(2024) as rows_2024;
SELECT external.transform_ridership_table(2025) as rows_2025;
