-- ============================================================================
-- Migration: Event Name Enrichment & Literature-Backed Severity Calibration
-- Sub-application: Analytics (Transformation & Descriptive Layer)
-- Target Tables: external.academic_lgu_events, external.events_consolidated, Analytics views
-- Zero-Deletion Guarantee: 2,728 records preserved 100%
-- ============================================================================

-- 1. Backfill specific, contextual event names in external.academic_lgu_events
UPDATE external.academic_lgu_events SET event_name = '455th Manila Founding Anniversary (Araw ng Maynila)' 
WHERE id IN ('external_academic_0001', 'external_academic_0002');

UPDATE external.academic_lgu_events SET event_name = 'Class & Office Suspension (Manila City LGU Advisory)' 
WHERE id = 'external_academic_0004';

UPDATE external.academic_lgu_events SET event_name = 'Ateneo Sanggunian General Assembly & Student Council Call' 
WHERE id = 'external_academic_0005';

UPDATE external.academic_lgu_events SET event_name = 'UST Central Student Council Executive Applications' 
WHERE id = 'external_academic_0006';

UPDATE external.academic_lgu_events SET event_name = 'Nationwide Transport Strike (MANIBELA Advisory)' 
WHERE id IN ('external_academic_0007', 'external_academic_0008', 'external_lgu_0036');

UPDATE external.academic_lgu_events SET event_name = 'FEU Commencement Exercises (Day 3 Session)' 
WHERE id = 'external_academic_0009';

UPDATE external.academic_lgu_events SET event_name = 'UERM Class Suspension & President Office Advisory' 
WHERE id = 'external_academic_0010';

UPDATE external.academic_lgu_events SET event_name = 'FEU Tatak Tamaraw Freshmen Welcoming & Orientation' 
WHERE id IN ('external_academic_0011', 'external_academic_0012', 'external_academic_0013', 'external_academic_0015', 'external_academic_0016', 'external_academic_0017');

UPDATE external.academic_lgu_events SET event_name = 'UE Student Council Online Class Modality Request' 
WHERE id = 'external_academic_0014';

UPDATE external.academic_lgu_events SET event_name = 'Ninoy Aquino Day & National Heroes Day Commemoration' 
WHERE id = 'external_academic_0018';

UPDATE external.academic_lgu_events SET event_name = 'TIP Cubao Class Suspension (Habagat & Monsoon Advisory)' 
WHERE id IN ('external_academic_0019', 'external_academic_0020', 'external_academic_0025', 'external_academic_0026');

UPDATE external.academic_lgu_events SET event_name = 'NCR Work & Class Suspension (Office of the President Malacañang)' 
WHERE id IN ('external_academic_0021', 'external_lgu_0056', 'external_lgu_0057', 'external_lgu_0058');

UPDATE external.academic_lgu_events SET event_name = 'FEU Academic Advisory (Monsoon Weather Precautions)' 
WHERE id IN ('external_academic_0022', 'external_lgu_0062');

UPDATE external.academic_lgu_events SET event_name = 'Ateneo Special Work & Remote Learning Arrangement' 
WHERE id IN ('external_academic_0023', 'external_lgu_0063');

UPDATE external.academic_lgu_events SET event_name = 'Manila City LGU Onsite Class Suspension' 
WHERE id IN ('external_academic_0024', 'external_lgu_0009', 'external_lgu_0030', 'external_lgu_0064');

UPDATE external.academic_lgu_events SET event_name = 'UERM Onsite Class Suspension & Examination Reschedule' 
WHERE id IN ('external_academic_0027', 'external_academic_0028');

UPDATE external.academic_lgu_events SET event_name = 'PUP Academic Year Student Guide & Room Advisory' 
WHERE id = 'external_academic_0044';

UPDATE external.academic_lgu_events SET event_name = 'QC LGU Road Network Repair & Drainage Maintenance' 
WHERE id = 'external_lgu_0006';

UPDATE external.academic_lgu_events SET event_name = 'St. Paul University QC Academic Year Opening Preparation' 
WHERE id = 'external_lgu_0007';

UPDATE external.academic_lgu_events SET event_name = 'DepEd Manila Beginning of School Year Orientation' 
WHERE id = 'external_lgu_0008';

UPDATE external.academic_lgu_events SET event_name = 'Quezon City Moderate to Heavy Rainfall Advisory' 
WHERE id IN ('external_lgu_0010', 'external_lgu_0011', 'external_lgu_0012', 'external_lgu_0013', 'external_lgu_0014', 'external_lgu_0015', 'external_lgu_0033', 'external_lgu_0034', 'external_lgu_0035', 'external_lgu_0047', 'external_lgu_0049', 'external_lgu_0052', 'external_lgu_0055');

UPDATE external.academic_lgu_events SET event_name = 'QC LGU Joint Infrastructure Audit & Inspection' 
WHERE id IN ('external_lgu_0017', 'external_lgu_0018');

UPDATE external.academic_lgu_events SET event_name = 'Manila City Disaster Risk Monitoring & River Inspection' 
WHERE id IN ('external_lgu_0019', 'external_lgu_0020', 'external_lgu_0051');

UPDATE external.academic_lgu_events SET event_name = 'Super Typhoon Inday (Signal #1 Weather Advisory)' 
WHERE id IN ('external_lgu_0021', 'external_lgu_0022', 'external_lgu_0023', 'external_lgu_0073');

UPDATE external.academic_lgu_events SET event_name = 'QC LGU District 2 Free Legal Consultation & Community Service' 
WHERE id IN ('external_lgu_0024', 'external_lgu_0025');

UPDATE external.academic_lgu_events SET event_name = 'St. Paul University QC Afternoon Class Suspension' 
WHERE id IN ('external_lgu_0026', 'external_lgu_0028', 'external_lgu_0029');

UPDATE external.academic_lgu_events SET event_name = 'QC LGU Waste Management & City Sanitation Drive' 
WHERE id = 'external_lgu_0027';

UPDATE external.academic_lgu_events SET event_name = 'QC LGU West Philippine Sea Forum & Civic Gathering' 
WHERE id = 'external_lgu_0032';

UPDATE external.academic_lgu_events SET event_name = 'Manila Water Emergency Pipe Repair & Supply Advisory' 
WHERE id = 'external_lgu_0037';

UPDATE external.academic_lgu_events SET event_name = 'Quezon City Class Suspension (5th SONA Advisory)' 
WHERE id IN ('external_lgu_0038', 'external_lgu_0039');

UPDATE external.academic_lgu_events SET event_name = 'QC Youth Community Mural Project & Art Event' 
WHERE id = 'external_lgu_0040';

UPDATE external.academic_lgu_events SET event_name = 'QC Weekly Civic Highlights & Community Briefing' 
WHERE id IN ('external_lgu_0041', 'external_lgu_0042');

UPDATE external.academic_lgu_events SET event_name = 'Manila City Dept. of Environment Cleanup Operation' 
WHERE id = 'external_lgu_0043';

UPDATE external.academic_lgu_events SET event_name = 'Marikina City LGU Drainage Declogging & Maintenance' 
WHERE id IN ('external_lgu_0044', 'external_lgu_0045');

UPDATE external.academic_lgu_events SET event_name = 'Pasig City New Public Infrastructure Inauguration' 
WHERE id = 'external_lgu_0046';

UPDATE external.academic_lgu_events SET event_name = 'QC LGU Community Holy Mass & Civic Gathering' 
WHERE id = 'external_lgu_0048';

UPDATE external.academic_lgu_events SET event_name = 'Tropical Depression Luis Weather Advisory' 
WHERE id = 'external_lgu_0050';

UPDATE external.academic_lgu_events SET event_name = 'Southwest Monsoon (Habagat) Weather Advisory' 
WHERE id IN ('external_lgu_0053', 'external_lgu_0060', 'external_lgu_0061', 'external_lgu_0065');

UPDATE external.academic_lgu_events SET event_name = 'Manila City Sanitation & Clean Community Service' 
WHERE id = 'external_lgu_0054';

UPDATE external.academic_lgu_events SET event_name = 'Tropical Storm Maymay & Habagat Rainfall Advisory' 
WHERE id = 'external_lgu_0059';

UPDATE external.academic_lgu_events SET event_name = 'UST Central Student Council Red Rainfall Warning Advisory' 
WHERE id = 'external_lgu_0066';

UPDATE external.academic_lgu_events SET event_name = 'QC LGU Monsoon Road Condition & Passability Status' 
WHERE id = 'external_lgu_0067';

UPDATE external.academic_lgu_events SET event_name = 'San Beda Student Relief Drive (Habagat Relief)' 
WHERE id = 'external_lgu_0075';

UPDATE external.academic_lgu_events SET event_name = 'PUP Freshmen Welcoming Assembly & Convocation' 
WHERE id = 'external_lgu_0076';

-- 2. Synchronize external.events_consolidated from updated external.academic_lgu_events
UPDATE external.events_consolidated ec
SET event_name = ale.event_name
FROM external.academic_lgu_events ale
WHERE ec.source_id = ale.id
  AND ale.event_name IS NOT NULL
  AND ec.event_name = 'Class Suspension / Holiday';

-- 3. Update any remaining generic event names in events_consolidated
UPDATE external.events_consolidated
SET event_name = CASE
    WHEN description ILIKE '%455th%' THEN '455th Manila Founding Anniversary (Araw ng Maynila)'
    WHEN description ILIKE '%Ninoy Aquino%' THEN 'Ninoy Aquino Day & National Heroes Day Commemoration'
    WHEN description ILIKE '%Inday%' THEN 'Super Typhoon Inday (Signal #1 Advisory)'
    WHEN description ILIKE '%Habagat%' THEN 'Class Suspension due to Southwest Monsoon (Habagat)'
    WHEN description ILIKE '%MANIBELA%' OR description ILIKE '%strike%' THEN 'Nationwide Transport Strike (MANIBELA Advisory)'
    WHEN description ILIKE '%SONA%' THEN 'Quezon City Class Suspension (SONA Advisory)'
    ELSE 'Academic & LGU Advisory Notice'
END
WHERE event_name = 'Class Suspension / Holiday';

-- 4. Recreate Analytics.descriptive_live_event_feed view with 3-tier severity calibration
CREATE OR REPLACE VIEW "Analytics"."descriptive_live_event_feed" AS
 SELECT weather_current.id AS trigger_id,
    'weather'::text AS source_type,
    'Open-Meteo Weather Service'::text AS source,
    (((((((('Station: '::text || weather_current.station) || ' - Temp: '::text) || weather_current.temperature) || '°C, Rain: '::text) || weather_current.rainfall_mm) || 'mm ('::text) || COALESCE(NULLIF(weather_current.computed_rainfall_level, 'None'::text), 'Normal'::text)) || ')'::text) AS message,
        CASE
            WHEN weather_current.rainfall_mm >= 30.0 
              OR weather_current.computed_rainfall_level = 'Red' 
              OR weather_current.wind_speed >= 62.0 
              THEN 'critical'::text
            WHEN weather_current.rainfall_mm >= 7.5 
              OR weather_current.computed_rainfall_level IN ('Orange', 'Yellow') 
              OR weather_current.wind_speed >= 39.0 
              THEN 'warning'::text
            ELSE 'low'::text
        END AS urgency,
    weather_current.station AS station_name,
    'https://open-meteo.com'::text AS source_url,
    'Station live weather metrics via Open-Meteo API'::text AS description
   FROM external.weather_current
  WHERE (((weather_current.observed_at AT TIME ZONE 'Asia/Manila'::text))::date = ((CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila'::text))::date)
UNION ALL
 SELECT min(ec.id) AS trigger_id,
        CASE
            WHEN ((ec.event_category = 'lgu'::text) OR (ec.friction_domain = 'lgu'::text)) THEN 'lgu'::text
            ELSE 'academic'::text
        END AS source_type,
    string_agg(DISTINCT ec.source_name, ' / '::text) AS source,
    ((('Station: '::text || string_agg(DISTINCT ec.station, ', '::text)) || ' - '::text) || COALESCE(ec.event_name, 'Event Notice'::text)) AS message,
    max(COALESCE(ec.announcement_time, ec.updated_at)) AS "time",
        CASE
            -- Tier 1 (CRITICAL, Red): Normalized Score >= 0.80 or explicit physical disruptions
            WHEN ((lower(COALESCE(ec.event_name, ''::text)) ~* '(suspension|walang pasok|red alert|tigil pasada|strike|monsoon|typhoon)') 
                  OR (max(ec.normalized_score) >= 0.80)) THEN 'critical'::text
            -- Tier 2 (WARNING, Amber): Normalized Score between 0.45 and 0.79 or large crowd surges
            WHEN ((max(ec.normalized_score) >= 0.45) 
                  OR (lower(COALESCE(ec.event_name, ''::text)) ~* '(arena|concert|heavy rain|flood|commencement|graduation|rally)')) THEN 'warning'::text
            -- Tier 3 (INFORMATIONAL, Sky-Blue): Routine calendar milestones, exams, orientations, registrations
            ELSE 'low'::text
        END AS urgency,
    string_agg(DISTINCT ec.station, ', '::text) AS station_name,
    max(ec.source_url) AS source_url,
    max(ec.description) AS description
   FROM external.events_consolidated ec
  WHERE (ec.event_date = ((CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila'::text))::date)
  GROUP BY ec.event_date, ec.event_category, ec.friction_domain, ec.event_name;
