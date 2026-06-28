-- ============================================================================
-- SQL Script: Re-standardize Literature Dimensions (APTA & Friction Weights)
-- Classification: Urban Literature Data (APTA, Friction Weight Table)
-- ============================================================================

DO $$
BEGIN
  -- APTA
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'APTA' AND table_name = 'apta_protocols')
     AND NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'APTA' AND table_name = 'apta_protocols_backup') THEN
     ALTER TABLE "APTA".apta_protocols RENAME TO apta_protocols_backup;
  END IF;

  -- external.friction_weight
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'external' AND table_name = 'friction_weight')
     AND NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'external' AND table_name = 'friction_weight_backup') THEN
     ALTER TABLE "external".friction_weight RENAME TO friction_weight_backup;
  END IF;
END $$;

DROP TABLE IF EXISTS "APTA".apta_protocols;
CREATE TABLE "APTA".apta_protocols (
    id text PRIMARY KEY,
    apta_standard_code text NOT NULL,
    official_document_title text NOT NULL,
    scope_relevance_to_surge_management text NOT NULL,
    human_centric_ground_tactics text NOT NULL,
    open_access_link_source text NOT NULL,
    load_timestamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

DROP TABLE IF EXISTS "external".friction_weight;
CREATE TABLE "external".friction_weight (
    id text PRIMARY KEY,
    friction_domain text NOT NULL,
    trigger_category text NOT NULL,
    specific_condition_api_input text NOT NULL,
    friction_weight numeric NOT NULL CHECK (friction_weight >= 0 AND friction_weight <= 1),
    ncr_literature_source_basis text NOT NULL,
    open_access_link text NOT NULL,
    load_timestamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

INSERT INTO "APTA".apta_protocols (id, apta_standard_code, official_document_title, scope_relevance_to_surge_management, human_centric_ground_tactics, open_access_link_source, load_timestamp)
SELECT 
  'APTA-' || LPAD((row_number() OVER (ORDER BY load_timestamp, apta_standard_code))::text, 2, '0') as id,
  apta_standard_code, official_document_title, scope_relevance_to_surge_management, human_centric_ground_tactics, open_access_link_source, load_timestamp
FROM "APTA".apta_protocols_backup;

INSERT INTO "external".friction_weight (id, friction_domain, trigger_category, specific_condition_api_input, friction_weight, ncr_literature_source_basis, open_access_link, load_timestamp)
SELECT 
  'FRI-' || 
  CASE LOWER(friction_domain)
    WHEN 'academic' THEN 'AC'
    WHEN 'pagasa' THEN 'PA'
    WHEN 'operational' THEN 'OP'
    ELSE 'XX'
  END || 
  LPAD((row_number() OVER (PARTITION BY friction_domain ORDER BY load_timestamp, trigger_category))::text, 2, '0') as id,
  friction_domain, trigger_category, specific_condition_api_input, friction_weight, ncr_literature_source_basis, open_access_link, load_timestamp
FROM "external".friction_weight_backup;

-- Seed School Break trigger category into friction_weight and friction_weight_backup if they do not exist
INSERT INTO "external".friction_weight (id, friction_domain, trigger_category, specific_condition_api_input, friction_weight, ncr_literature_source_basis, open_access_link, load_timestamp)
VALUES (
    'FRI-AC06',
    'academic',
    'School Break',
    'Semestral/Christmas/Summer Break',
    0.85,
    'Assessment of Class Suspension and School Break Impacts on Metro Manila Traffic (NCTS)',
    'https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Abad18.pdf',
    now()
)
ON CONFLICT (id) DO UPDATE SET
    trigger_category = EXCLUDED.trigger_category,
    specific_condition_api_input = EXCLUDED.specific_condition_api_input,
    friction_weight = EXCLUDED.friction_weight,
    ncr_literature_source_basis = EXCLUDED.ncr_literature_source_basis,
    open_access_link = EXCLUDED.open_access_link;

INSERT INTO "external".friction_weight_backup (id, friction_domain, trigger_category, specific_condition_api_input, friction_weight, ncr_literature_source_basis, open_access_link, load_timestamp)
VALUES (
    'FRI-AC06',
    'academic',
    'School Break',
    'Semestral/Christmas/Summer Break',
    0.85,
    'Assessment of Class Suspension and School Break Impacts on Metro Manila Traffic (NCTS)',
    'https://ncts.upd.edu.ph/tssp/wp-content/uploads/2018/08/Abad18.pdf',
    now()
)
ON CONFLICT (id) DO UPDATE SET
    trigger_category = EXCLUDED.trigger_category,
    specific_condition_api_input = EXCLUDED.specific_condition_api_input,
    friction_weight = EXCLUDED.friction_weight,
    ncr_literature_source_basis = EXCLUDED.ncr_literature_source_basis,
    open_access_link = EXCLUDED.open_access_link;

-- Rename Mid-Day Class Suspension to Class Suspension / Holiday in friction_weight and friction_weight_backup
UPDATE "external".friction_weight 
SET trigger_category = 'Class Suspension / Holiday'
WHERE trigger_category = 'Mid-Day Class Suspension';

UPDATE "external".friction_weight_backup 
SET trigger_category = 'Class Suspension / Holiday'
WHERE trigger_category = 'Mid-Day Class Suspension';
