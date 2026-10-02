-- 01_staging.sql
-- Land the raw CSVs as all-STRING staging tables (no type inference). {{RAW_DIR}} is substituted by run_pipeline.py.
-- DuckDB : read_csv(path, header = true, all_varchar = true)
-- Databricks (databricks/readmissions_pipeline_notebook.sql):
--   read_files('/Volumes/workspace/da_learn_08/raw/<file>', format => 'csv', header => true, inferColumnTypes => false)
-- diabetic_data.csv : one row per inpatient encounter (101,766 rows x 50 columns), '?' = missing
-- IDS_mapping.csv   : three stacked lookup tables (admission type / discharge disposition / admission source)
-- The 5 combination-drug columns contain '-' in their names; they are renamed to snake_case here so that
-- 02-05 use plain identifiers on both engines (Databricks uses `backticks`, DuckDB "double quotes").
CREATE OR REPLACE TABLE stg_encounters AS
SELECT * EXCLUDE ("glyburide-metformin", "glipizide-metformin", "glimepiride-pioglitazone", "metformin-rosiglitazone", "metformin-pioglitazone"),
       "glyburide-metformin" AS glyburide_metformin,
       "glipizide-metformin" AS glipizide_metformin,
       "glimepiride-pioglitazone" AS glimepiride_pioglitazone,
       "metformin-rosiglitazone" AS metformin_rosiglitazone,
       "metformin-pioglitazone" AS metformin_pioglitazone
FROM read_csv('{{RAW_DIR}}/diabetic_data.csv', header = true, all_varchar = true);

CREATE OR REPLACE TABLE stg_ids_mapping AS
SELECT * FROM read_csv('{{RAW_DIR}}/IDS_mapping.csv', header = true, all_varchar = true, null_padding = true);
