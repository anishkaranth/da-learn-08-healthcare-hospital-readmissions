-- 05_quality_checks.sql  Data-quality evidence (Spark SQL dialect)

CREATE OR REPLACE TABLE dq_row_counts AS
SELECT 'encounters' AS entity,
       (SELECT COUNT(*) FROM stg_encounters) AS raw_rows,
       (SELECT COUNT(DISTINCT encounter_id) FROM stg_encounters) AS distinct_keys,
       (SELECT COUNT(*) FROM cln_encounters) AS clean_rows,
       'encounter_id' AS grain
UNION ALL SELECT 'encounter_medications', NULL, NULL, (SELECT COUNT(*) FROM cln_encounter_medications), 'encounter x prescribed drug'
UNION ALL SELECT 'fact_encounter', NULL, NULL, (SELECT COUNT(*) FROM fact_encounter), 'encounter'
UNION ALL SELECT 'fact_encounter_medication', NULL, NULL, (SELECT COUNT(*) FROM fact_encounter_medication), 'encounter x drug'
UNION ALL SELECT 'dim_patient', NULL, NULL, (SELECT COUNT(*) FROM dim_patient), 'patient_nbr'
UNION ALL SELECT 'dim_age_group', NULL, NULL, (SELECT COUNT(*) FROM dim_age_group), 'age decade'
UNION ALL SELECT 'dim_diagnosis_group', NULL, NULL, (SELECT COUNT(*) FROM dim_diagnosis_group), 'ICD-9 group'
UNION ALL SELECT 'dim_admission_type', NULL, NULL, (SELECT COUNT(*) FROM dim_admission_type), 'admission_type_id'
UNION ALL SELECT 'dim_discharge_disposition', NULL, NULL, (SELECT COUNT(*) FROM dim_discharge_disposition), 'discharge_disposition_id'
UNION ALL SELECT 'dim_admission_source', NULL, NULL, (SELECT COUNT(*) FROM dim_admission_source), 'admission_source_id'
UNION ALL SELECT 'dim_medication', NULL, NULL, (SELECT COUNT(*) FROM dim_medication), 'drug';

CREATE OR REPLACE TABLE dq_null_rates AS
SELECT 'encounters' AS entity, 'weight' AS column_name,
  (SELECT ROUND(100.0 * SUM(CASE WHEN weight = '?' THEN 1 ELSE 0 END) / COUNT(*), 2) FROM stg_encounters) AS raw_missing_pct,
  (SELECT ROUND(100.0 * SUM(dq_missing_weight) / COUNT(*), 2) FROM cln_encounters) AS clean_null_pct,
  'kept as NULL (97% missing - not used for analysis)' AS treatment
UNION ALL SELECT 'encounters', 'payer_code',
  (SELECT ROUND(100.0 * SUM(CASE WHEN payer_code = '?' THEN 1 ELSE 0 END) / COUNT(*), 2) FROM stg_encounters),
  (SELECT ROUND(100.0 * SUM(CASE WHEN payer_code IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) FROM cln_encounters),
  'kept as NULL'
UNION ALL SELECT 'encounters', 'medical_specialty',
  (SELECT ROUND(100.0 * SUM(CASE WHEN medical_specialty = '?' THEN 1 ELSE 0 END) / COUNT(*), 2) FROM stg_encounters),
  (SELECT ROUND(100.0 * SUM(CASE WHEN medical_specialty IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) FROM cln_encounters),
  'kept as NULL'
UNION ALL SELECT 'encounters', 'race',
  (SELECT ROUND(100.0 * SUM(CASE WHEN race = '?' THEN 1 ELSE 0 END) / COUNT(*), 2) FROM stg_encounters),
  (SELECT ROUND(100.0 * SUM(dq_missing_race) / COUNT(*), 2) FROM cln_encounters),
  'kept as NULL'
UNION ALL SELECT 'encounters', 'diag_1',
  (SELECT ROUND(100.0 * SUM(CASE WHEN diag_1 = '?' THEN 1 ELSE 0 END) / COUNT(*), 2) FROM stg_encounters),
  (SELECT ROUND(100.0 * SUM(CASE WHEN diag_1 IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) FROM cln_encounters),
  'NULL -> diagnosis group Missing'
UNION ALL SELECT 'encounters', 'A1Cresult',
  (SELECT ROUND(100.0 * SUM(CASE WHEN A1Cresult = 'None' THEN 1 ELSE 0 END) / COUNT(*), 2) FROM stg_encounters),
  (SELECT ROUND(100.0 * SUM(CASE WHEN a1c_result = 'Not measured' THEN 1 ELSE 0 END) / COUNT(*), 2) FROM cln_encounters),
  '''None'' means test not done -> category Not measured';

CREATE OR REPLACE TABLE dq_issues AS
SELECT 'encounters: duplicate encounter_id (extras dropped)' AS check_name,
       (SELECT COUNT(*) - COUNT(DISTINCT encounter_id) FROM stg_encounters) AS affected_rows
UNION ALL SELECT 'encounters: gender Unknown/Invalid (dropped)',
       (SELECT COUNT(*) FROM stg_encounters WHERE gender NOT IN ('Male', 'Female'))
UNION ALL SELECT 'encounters: rows dropped in cleaning',
       (SELECT COUNT(*) FROM stg_encounters) - (SELECT COUNT(*) FROM cln_encounters)
UNION ALL SELECT 'encounters: expired / hospice discharge (excluded from readmission rates)',
       (SELECT COUNT(*) FROM cln_encounters WHERE is_readmit_eligible = 0)
UNION ALL SELECT 'encounters: repeat encounters of the same patient',
       (SELECT COUNT(*) FROM cln_encounters WHERE is_first_encounter = 0)
UNION ALL SELECT 'encounters: num_medications outlier (> Q3 + 3*IQR, kept)', (SELECT SUM(is_num_meds_outlier) FROM cln_encounters)
UNION ALL SELECT 'encounters: num_lab_procedures outlier (> Q3 + 3*IQR, kept)', (SELECT SUM(is_num_labs_outlier) FROM cln_encounters)
UNION ALL SELECT 'encounters: diag_1 is a V/E supplementary code', (SELECT COUNT(*) FROM cln_encounters WHERE diag_1 LIKE 'V%' OR diag_1 LIKE 'E%')
UNION ALL SELECT 'encounters: discharge id not in IDS_mapping', (SELECT COUNT(*) FROM cln_encounters WHERE discharge_disposition_id NOT IN (SELECT discharge_disposition_id FROM dim_discharge_disposition))
UNION ALL SELECT 'encounters: patients with > 1 encounter', (SELECT COUNT(*) FROM dim_patient WHERE n_encounters > 1);

CREATE OR REPLACE TABLE dq_assertions AS
WITH c AS (
  SELECT 'fact_encounter.encounter_id unique' AS check_name,
         (SELECT COUNT(*) - COUNT(DISTINCT encounter_id) FROM fact_encounter) AS failed_rows
  UNION ALL SELECT 'fact_encounter rows = cln_encounters rows',
         (SELECT ABS((SELECT COUNT(*) FROM fact_encounter) - (SELECT COUNT(*) FROM cln_encounters)))
  UNION ALL SELECT 'fact_encounter.patient_nbr -> dim_patient',
         (SELECT COUNT(*) FROM fact_encounter WHERE patient_nbr NOT IN (SELECT patient_nbr FROM dim_patient))
  UNION ALL SELECT 'fact_encounter.admission_type_id -> dim_admission_type',
         (SELECT COUNT(*) FROM fact_encounter WHERE admission_type_id NOT IN (SELECT admission_type_id FROM dim_admission_type))
  UNION ALL SELECT 'fact_encounter.discharge_disposition_id -> dim_discharge_disposition',
         (SELECT COUNT(*) FROM fact_encounter WHERE discharge_disposition_id NOT IN (SELECT discharge_disposition_id FROM dim_discharge_disposition))
  UNION ALL SELECT 'fact_encounter.admission_source_id -> dim_admission_source',
         (SELECT COUNT(*) FROM fact_encounter WHERE admission_source_id NOT IN (SELECT admission_source_id FROM dim_admission_source))
  UNION ALL SELECT 'fact_encounter_medication.medication_key -> dim_medication',
         (SELECT COUNT(*) FROM fact_encounter_medication WHERE medication_key NOT IN (SELECT medication_key FROM dim_medication))
  UNION ALL SELECT 'seeded lookup rows exist verbatim in IDS_mapping.csv',
         (SELECT COUNT(*) FROM (
            SELECT CAST(admission_type_id AS STRING) AS id, description FROM dim_admission_type
            UNION ALL SELECT CAST(discharge_disposition_id AS STRING), description FROM dim_discharge_disposition
            UNION ALL SELECT CAST(admission_source_id AS STRING), description FROM dim_admission_source) s
          WHERE NOT EXISTS (SELECT 1 FROM stg_ids_mapping m
                            WHERE trim(m.admission_type_id) = s.id AND trim(m.description) = s.description))
  UNION ALL SELECT 'readmitted in {<30, >30, NO}',
         (SELECT COUNT(*) FROM fact_encounter WHERE readmitted NOT IN ('<30', '>30', 'NO'))
  UNION ALL SELECT 'time_in_hospital between 1 and 14',
         (SELECT COUNT(*) FROM fact_encounter WHERE time_in_hospital NOT BETWEEN 1 AND 14)
  UNION ALL SELECT 'readmit_30d_flag <= readmit_any_flag',
         (SELECT COUNT(*) FROM fact_encounter WHERE readmit_30d_flag > readmit_any_flag)
  UNION ALL SELECT 'non-negative visit / medication counts',
         (SELECT COUNT(*) FROM fact_encounter WHERE num_medications < 0 OR number_inpatient < 0 OR number_emergency < 0 OR number_outpatient < 0)
)
SELECT check_name, failed_rows, CASE WHEN failed_rows = 0 THEN 'PASS' ELSE 'FAIL' END AS status FROM c;
