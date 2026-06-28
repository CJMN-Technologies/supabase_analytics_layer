-- ============================================================================
-- SQL Script: Re-standardize Internal Dimensions (Station Capacity & PSOR)
-- Classification: Internal Dataset (PSOR, Station Capacity)
-- ============================================================================

DO $$
BEGIN
  -- PSOR
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'PSOR' AND table_name = 'psor_incidents')
     AND NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'PSOR' AND table_name = 'psor_incidents_backup') THEN
     ALTER TABLE "PSOR".psor_incidents RENAME TO psor_incidents_backup;
  END IF;

  -- Station Capacity
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'Station Capacity' AND table_name = 'station_platform_capacity')
     AND NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'Station Capacity' AND table_name = 'station_platform_capacity_backup') THEN
     ALTER TABLE "Station Capacity".station_platform_capacity RENAME TO station_platform_capacity_backup;
  END IF;
END $$;

DROP TABLE IF EXISTS "PSOR".psor_incidents;
CREATE TABLE "PSOR".psor_incidents (
    id text PRIMARY KEY,
    category text NOT NULL,
    specific_incident_transgression text NOT NULL,
    load_timestamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

DROP TABLE IF EXISTS "Station Capacity".station_platform_capacity;
CREATE TABLE "Station Capacity".station_platform_capacity (
    id text PRIMARY KEY,
    station_name text NOT NULL,
    platform_design text NOT NULL,
    directional_usable_area_m2 numeric,
    directional_platform_limit_pax integer,
    total_concourse_limit_pax integer,
    total_station_limit_pax integer,
    load_timestamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

INSERT INTO "PSOR".psor_incidents (id, category, specific_incident_transgression, load_timestamp)
SELECT 
  'PSOR-' || LPAD((row_number() OVER (ORDER BY load_timestamp, specific_incident_transgression))::text, 2, '0') as id,
  category, specific_incident_transgression, load_timestamp
FROM "PSOR".psor_incidents_backup;

INSERT INTO "Station Capacity".station_platform_capacity (id, station_name, platform_design, directional_usable_area_m2, directional_platform_limit_pax, total_concourse_limit_pax, total_station_limit_pax, load_timestamp)
SELECT 
  CASE UPPER(TRIM(station_name))
    WHEN 'RECTO' THEN 'CAP-REC'
    WHEN 'LEGARDA' THEN 'CAP-LEG'
    WHEN 'PUREZA' THEN 'CAP-PUR'
    WHEN 'V. MAPA' THEN 'CAP-VMA'
    WHEN 'J. RUIZ' THEN 'CAP-JRU'
    WHEN 'GILMORE' THEN 'CAP-GIL'
    WHEN 'BETTY GO-BELMONTE' THEN 'CAP-BET'
    WHEN 'ARANETA CENTER-CUBAO' THEN 'CAP-CUB'
    WHEN 'ANONAS' THEN 'CAP-ANO'
    WHEN 'KATIPUNAN' THEN 'CAP-KAT'
    WHEN 'SANTOLAN' THEN 'CAP-SAN'
    WHEN 'MARIKINA-PASIG' THEN 'CAP-MAR'
    WHEN 'ANTIPOLO' THEN 'CAP-ANT'
    ELSE 'CAP-' || UPPER(LEFT(REPLACE(station_name, ' ', ''), 3))
  END as id,
  station_name, platform_design, directional_usable_area_m2, directional_platform_limit_pax, total_concourse_limit_pax, total_station_limit_pax, load_timestamp
FROM "Station Capacity".station_platform_capacity_backup;
