-- 02_cleaning.sql  (Spark SQL dialect; runs on DuckDB via 00_duckdb_compat.sql shims)
-- Grain: one row per inpatient encounter (encounter_id).
-- Steps: '?' / 'None' / 'Unknown/Invalid' -> NULL  -> TRY_CAST types  -> standardise categories
--        -> dedupe on encounter_id -> ICD-9 diagnosis groups (Strack et al. 2014) -> length-of-stay & age bands
--        -> medication counts -> readmission flags + eligibility (expired / hospice excluded)
--        -> outlier flags (Q3 + 3*IQR) -> integrity filters.

CREATE OR REPLACE TABLE cln_encounters AS
WITH typed AS (
  SELECT
    TRY_CAST(encounter_id AS BIGINT)                                   AS encounter_id,
    TRY_CAST(patient_nbr AS BIGINT)                                    AS patient_nbr,
    CASE WHEN trim(race) IN ('?', '') THEN NULL
         WHEN trim(race) = 'AfricanAmerican' THEN 'African American'
         ELSE trim(race) END                                           AS race,
    CASE WHEN trim(gender) IN ('Male', 'Female') THEN trim(gender) ELSE NULL END AS gender,
    CASE WHEN trim(age) LIKE '[%)' THEN replace(replace(trim(age), '[', ''), ')', '') ELSE NULL END AS age_group,
    CASE WHEN trim(weight) IN ('?', '') THEN NULL ELSE replace(replace(trim(weight), '[', ''), ')', '') END AS weight_band,
    TRY_CAST(admission_type_id AS INT)                                 AS admission_type_id,
    TRY_CAST(discharge_disposition_id AS INT)                          AS discharge_disposition_id,
    TRY_CAST(admission_source_id AS INT)                               AS admission_source_id,
    TRY_CAST(time_in_hospital AS INT)                                  AS time_in_hospital,
    CASE WHEN trim(payer_code) IN ('?', '') THEN NULL ELSE trim(payer_code) END AS payer_code,
    CASE WHEN trim(medical_specialty) IN ('?', '') THEN NULL ELSE trim(medical_specialty) END AS medical_specialty,
    TRY_CAST(num_lab_procedures AS INT)                                AS num_lab_procedures,
    TRY_CAST(num_procedures AS INT)                                    AS num_procedures,
    TRY_CAST(num_medications AS INT)                                   AS num_medications,
    TRY_CAST(number_outpatient AS INT)                                 AS number_outpatient,
    TRY_CAST(number_emergency AS INT)                                  AS number_emergency,
    TRY_CAST(number_inpatient AS INT)                                  AS number_inpatient,
    CASE WHEN trim(diag_1) IN ('?', '') THEN NULL ELSE trim(diag_1) END AS diag_1,
    CASE WHEN trim(diag_2) IN ('?', '') THEN NULL ELSE trim(diag_2) END AS diag_2,
    CASE WHEN trim(diag_3) IN ('?', '') THEN NULL ELSE trim(diag_3) END AS diag_3,
    TRY_CAST(diag_1 AS DOUBLE)                                         AS diag_1_num,   -- NULL for V / E codes
    TRY_CAST(diag_2 AS DOUBLE)                                         AS diag_2_num,
    TRY_CAST(diag_3 AS DOUBLE)                                         AS diag_3_num,
    TRY_CAST(number_diagnoses AS INT)                                  AS number_diagnoses,
    CASE WHEN trim(max_glu_serum) IN ('None', '?', '') THEN 'Not measured' ELSE trim(max_glu_serum) END AS max_glu_serum,
    CASE WHEN trim(A1Cresult) IN ('None', '?', '') THEN 'Not measured' ELSE trim(A1Cresult) END AS a1c_result,
    CASE WHEN trim(metformin) IN ('No', 'Steady', 'Up', 'Down') THEN trim(metformin) ELSE NULL END AS med_metformin,
    CASE WHEN trim(repaglinide) IN ('No', 'Steady', 'Up', 'Down') THEN trim(repaglinide) ELSE NULL END AS med_repaglinide,
    CASE WHEN trim(nateglinide) IN ('No', 'Steady', 'Up', 'Down') THEN trim(nateglinide) ELSE NULL END AS med_nateglinide,
    CASE WHEN trim(chlorpropamide) IN ('No', 'Steady', 'Up', 'Down') THEN trim(chlorpropamide) ELSE NULL END AS med_chlorpropamide,
    CASE WHEN trim(glimepiride) IN ('No', 'Steady', 'Up', 'Down') THEN trim(glimepiride) ELSE NULL END AS med_glimepiride,
    CASE WHEN trim(acetohexamide) IN ('No', 'Steady', 'Up', 'Down') THEN trim(acetohexamide) ELSE NULL END AS med_acetohexamide,
    CASE WHEN trim(glipizide) IN ('No', 'Steady', 'Up', 'Down') THEN trim(glipizide) ELSE NULL END AS med_glipizide,
    CASE WHEN trim(glyburide) IN ('No', 'Steady', 'Up', 'Down') THEN trim(glyburide) ELSE NULL END AS med_glyburide,
    CASE WHEN trim(tolbutamide) IN ('No', 'Steady', 'Up', 'Down') THEN trim(tolbutamide) ELSE NULL END AS med_tolbutamide,
    CASE WHEN trim(pioglitazone) IN ('No', 'Steady', 'Up', 'Down') THEN trim(pioglitazone) ELSE NULL END AS med_pioglitazone,
    CASE WHEN trim(rosiglitazone) IN ('No', 'Steady', 'Up', 'Down') THEN trim(rosiglitazone) ELSE NULL END AS med_rosiglitazone,
    CASE WHEN trim(acarbose) IN ('No', 'Steady', 'Up', 'Down') THEN trim(acarbose) ELSE NULL END AS med_acarbose,
    CASE WHEN trim(miglitol) IN ('No', 'Steady', 'Up', 'Down') THEN trim(miglitol) ELSE NULL END AS med_miglitol,
    CASE WHEN trim(troglitazone) IN ('No', 'Steady', 'Up', 'Down') THEN trim(troglitazone) ELSE NULL END AS med_troglitazone,
    CASE WHEN trim(tolazamide) IN ('No', 'Steady', 'Up', 'Down') THEN trim(tolazamide) ELSE NULL END AS med_tolazamide,
    CASE WHEN trim(examide) IN ('No', 'Steady', 'Up', 'Down') THEN trim(examide) ELSE NULL END AS med_examide,
    CASE WHEN trim(citoglipton) IN ('No', 'Steady', 'Up', 'Down') THEN trim(citoglipton) ELSE NULL END AS med_citoglipton,
    CASE WHEN trim(insulin) IN ('No', 'Steady', 'Up', 'Down') THEN trim(insulin) ELSE NULL END AS med_insulin,
    CASE WHEN trim(glyburide_metformin) IN ('No', 'Steady', 'Up', 'Down') THEN trim(glyburide_metformin) ELSE NULL END AS med_glyburide_metformin,
    CASE WHEN trim(glipizide_metformin) IN ('No', 'Steady', 'Up', 'Down') THEN trim(glipizide_metformin) ELSE NULL END AS med_glipizide_metformin,
    CASE WHEN trim(glimepiride_pioglitazone) IN ('No', 'Steady', 'Up', 'Down') THEN trim(glimepiride_pioglitazone) ELSE NULL END AS med_glimepiride_pioglitazone,
    CASE WHEN trim(metformin_rosiglitazone) IN ('No', 'Steady', 'Up', 'Down') THEN trim(metformin_rosiglitazone) ELSE NULL END AS med_metformin_rosiglitazone,
    CASE WHEN trim(metformin_pioglitazone) IN ('No', 'Steady', 'Up', 'Down') THEN trim(metformin_pioglitazone) ELSE NULL END AS med_metformin_pioglitazone,
    CASE WHEN trim(change) = 'Ch' THEN 1 WHEN trim(change) = 'No' THEN 0 ELSE NULL END AS med_change_flag,
    CASE WHEN trim(diabetesMed) = 'Yes' THEN 1 WHEN trim(diabetesMed) = 'No' THEN 0 ELSE NULL END AS diabetes_med_flag,
    CASE WHEN trim(readmitted) IN ('<30', '>30', 'NO') THEN trim(readmitted) ELSE NULL END AS readmitted
  FROM stg_encounters
), ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY encounter_id ORDER BY patient_nbr) AS rn
  FROM typed
  WHERE encounter_id IS NOT NULL
), first_enc AS (
  SELECT encounter_id, ROW_NUMBER() OVER (PARTITION BY patient_nbr ORDER BY encounter_id) AS patient_encounter_seq
  FROM ranked WHERE rn = 1
), bounds AS (
  SELECT
    percentile_approx(CAST(num_medications AS DOUBLE), 0.25)    AS med_q1,
    percentile_approx(CAST(num_medications AS DOUBLE), 0.75)    AS med_q3,
    percentile_approx(CAST(num_lab_procedures AS DOUBLE), 0.25) AS lab_q1,
    percentile_approx(CAST(num_lab_procedures AS DOUBLE), 0.75) AS lab_q3
  FROM ranked WHERE rn = 1
), enriched AS (
  SELECT r.*, f.patient_encounter_seq,
    CASE
    WHEN r.diag_1 IS NULL THEN 'Missing'
    WHEN r.diag_1 LIKE 'V%' OR r.diag_1 LIKE 'E%' THEN 'Other'
    WHEN r.diag_1 LIKE '250%' THEN 'Diabetes'
    WHEN (r.diag_1_num >= 390 AND r.diag_1_num < 460) OR floor(r.diag_1_num) = 785 THEN 'Circulatory'
    WHEN (r.diag_1_num >= 460 AND r.diag_1_num < 520) OR floor(r.diag_1_num) = 786 THEN 'Respiratory'
    WHEN (r.diag_1_num >= 520 AND r.diag_1_num < 580) OR floor(r.diag_1_num) = 787 THEN 'Digestive'
    WHEN (r.diag_1_num >= 580 AND r.diag_1_num < 630) OR floor(r.diag_1_num) = 788 THEN 'Genitourinary'
    WHEN r.diag_1_num >= 800 AND r.diag_1_num < 1000 THEN 'Injury'
    WHEN r.diag_1_num >= 710 AND r.diag_1_num < 740 THEN 'Musculoskeletal'
    WHEN r.diag_1_num >= 140 AND r.diag_1_num < 240 THEN 'Neoplasms'
    ELSE 'Other' END AS diag_1_group,
    CASE
    WHEN r.diag_2 IS NULL THEN 'Missing'
    WHEN r.diag_2 LIKE 'V%' OR r.diag_2 LIKE 'E%' THEN 'Other'
    WHEN r.diag_2 LIKE '250%' THEN 'Diabetes'
    WHEN (r.diag_2_num >= 390 AND r.diag_2_num < 460) OR floor(r.diag_2_num) = 785 THEN 'Circulatory'
    WHEN (r.diag_2_num >= 460 AND r.diag_2_num < 520) OR floor(r.diag_2_num) = 786 THEN 'Respiratory'
    WHEN (r.diag_2_num >= 520 AND r.diag_2_num < 580) OR floor(r.diag_2_num) = 787 THEN 'Digestive'
    WHEN (r.diag_2_num >= 580 AND r.diag_2_num < 630) OR floor(r.diag_2_num) = 788 THEN 'Genitourinary'
    WHEN r.diag_2_num >= 800 AND r.diag_2_num < 1000 THEN 'Injury'
    WHEN r.diag_2_num >= 710 AND r.diag_2_num < 740 THEN 'Musculoskeletal'
    WHEN r.diag_2_num >= 140 AND r.diag_2_num < 240 THEN 'Neoplasms'
    ELSE 'Other' END AS diag_2_group,
    CASE
    WHEN r.diag_3 IS NULL THEN 'Missing'
    WHEN r.diag_3 LIKE 'V%' OR r.diag_3 LIKE 'E%' THEN 'Other'
    WHEN r.diag_3 LIKE '250%' THEN 'Diabetes'
    WHEN (r.diag_3_num >= 390 AND r.diag_3_num < 460) OR floor(r.diag_3_num) = 785 THEN 'Circulatory'
    WHEN (r.diag_3_num >= 460 AND r.diag_3_num < 520) OR floor(r.diag_3_num) = 786 THEN 'Respiratory'
    WHEN (r.diag_3_num >= 520 AND r.diag_3_num < 580) OR floor(r.diag_3_num) = 787 THEN 'Digestive'
    WHEN (r.diag_3_num >= 580 AND r.diag_3_num < 630) OR floor(r.diag_3_num) = 788 THEN 'Genitourinary'
    WHEN r.diag_3_num >= 800 AND r.diag_3_num < 1000 THEN 'Injury'
    WHEN r.diag_3_num >= 710 AND r.diag_3_num < 740 THEN 'Musculoskeletal'
    WHEN r.diag_3_num >= 140 AND r.diag_3_num < 240 THEN 'Neoplasms'
    ELSE 'Other' END AS diag_3_group,
    (CASE WHEN med_metformin IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_repaglinide IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_nateglinide IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_chlorpropamide IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_glimepiride IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_acetohexamide IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_glipizide IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_glyburide IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_tolbutamide IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_pioglitazone IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_rosiglitazone IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_acarbose IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_miglitol IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_troglitazone IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_tolazamide IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_examide IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_citoglipton IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_insulin IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_glyburide_metformin IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_glipizide_metformin IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_glimepiride_pioglitazone IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_metformin_rosiglitazone IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_metformin_pioglitazone IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END) AS n_diabetes_meds,
    (CASE WHEN med_metformin IN ('Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_repaglinide IN ('Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_nateglinide IN ('Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_chlorpropamide IN ('Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_glimepiride IN ('Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_acetohexamide IN ('Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_glipizide IN ('Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_glyburide IN ('Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_tolbutamide IN ('Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_pioglitazone IN ('Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_rosiglitazone IN ('Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_acarbose IN ('Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_miglitol IN ('Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_troglitazone IN ('Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_tolazamide IN ('Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_examide IN ('Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_citoglipton IN ('Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_insulin IN ('Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_glyburide_metformin IN ('Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_glipizide_metformin IN ('Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_glimepiride_pioglitazone IN ('Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_metformin_rosiglitazone IN ('Up', 'Down') THEN 1 ELSE 0 END + CASE WHEN med_metformin_pioglitazone IN ('Up', 'Down') THEN 1 ELSE 0 END) AS n_meds_changed
  FROM ranked r JOIN first_enc f ON r.encounter_id = f.encounter_id
  WHERE r.rn = 1
)
SELECT
  r.encounter_id,
  r.patient_nbr,
  r.patient_encounter_seq,
  CASE WHEN r.patient_encounter_seq = 1 THEN 1 ELSE 0 END             AS is_first_encounter,
  r.race,
  r.gender,
  r.age_group,
  CAST(split_part(r.age_group, '-', 1) AS INT) + 5                     AS age_mid,
  r.weight_band,
  r.admission_type_id,
  r.discharge_disposition_id,
  r.admission_source_id,
  r.time_in_hospital,
  CASE WHEN r.time_in_hospital <= 2 THEN '01: 1-2 days'
       WHEN r.time_in_hospital <= 4 THEN '02: 3-4 days'
       WHEN r.time_in_hospital <= 7 THEN '03: 5-7 days'
       ELSE '04: 8-14 days' END                                       AS los_band,
  r.payer_code,
  r.medical_specialty,
  r.num_lab_procedures,
  r.num_procedures,
  r.num_medications,
  r.number_outpatient,
  r.number_emergency,
  r.number_inpatient,
  CASE WHEN r.number_inpatient = 0 THEN '0' WHEN r.number_inpatient = 1 THEN '1'
       WHEN r.number_inpatient = 2 THEN '2' ELSE '3+' END            AS prior_inpatient_band,
  r.number_outpatient + r.number_emergency + r.number_inpatient       AS prior_visits_total,
  r.diag_1, r.diag_2, r.diag_3,
  r.diag_1_group, r.diag_2_group, r.diag_3_group,
  r.number_diagnoses,
  r.max_glu_serum,
  r.a1c_result,
  r.med_metformin,
  r.med_repaglinide,
  r.med_nateglinide,
  r.med_chlorpropamide,
  r.med_glimepiride,
  r.med_acetohexamide,
  r.med_glipizide,
  r.med_glyburide,
  r.med_tolbutamide,
  r.med_pioglitazone,
  r.med_rosiglitazone,
  r.med_acarbose,
  r.med_miglitol,
  r.med_troglitazone,
  r.med_tolazamide,
  r.med_examide,
  r.med_citoglipton,
  r.med_insulin,
  r.med_glyburide_metformin,
  r.med_glipizide_metformin,
  r.med_glimepiride_pioglitazone,
  r.med_metformin_rosiglitazone,
  r.med_metformin_pioglitazone,
  r.n_diabetes_meds,
  r.n_meds_changed,
  r.med_change_flag,
  r.diabetes_med_flag,
  CASE WHEN r.med_insulin IN ('Steady', 'Up', 'Down') THEN 1 ELSE 0 END AS insulin_flag,
  r.readmitted,
  CASE WHEN r.readmitted = '<30' THEN 1 ELSE 0 END                    AS readmit_30d_flag,
  CASE WHEN r.readmitted IN ('<30', '>30') THEN 1 ELSE 0 END          AS readmit_any_flag,
  -- 11 = Expired, 13/14 = Hospice, 19/20/21 = Expired (Medicaid hospice): cannot be readmitted -> excluded from rates
  CASE WHEN r.discharge_disposition_id IN (11, 13, 14, 19, 20, 21) THEN 0 ELSE 1 END AS is_readmit_eligible,
  -- outlier flags (kept, flagged)
  CASE WHEN r.num_medications > b.med_q3 + 3 * (b.med_q3 - b.med_q1) THEN 1 ELSE 0 END AS is_num_meds_outlier,
  CASE WHEN r.num_lab_procedures > b.lab_q3 + 3 * (b.lab_q3 - b.lab_q1) THEN 1 ELSE 0 END AS is_num_labs_outlier,
  CASE WHEN r.weight_band IS NULL THEN 1 ELSE 0 END                   AS dq_missing_weight,
  CASE WHEN r.race IS NULL THEN 1 ELSE 0 END                          AS dq_missing_race
FROM enriched r CROSS JOIN bounds b
WHERE r.patient_nbr IS NOT NULL
  AND r.readmitted IS NOT NULL
  AND r.gender IS NOT NULL
  AND r.age_group IS NOT NULL
  AND r.time_in_hospital BETWEEN 1 AND 14
  AND r.admission_type_id IS NOT NULL
  AND r.discharge_disposition_id IS NOT NULL
  AND r.admission_source_id IS NOT NULL;

-- Long medication table: one row per encounter x prescribed diabetes drug (status Steady / Up / Down)
CREATE OR REPLACE TABLE cln_encounter_medications AS
SELECT encounter_id, 'metformin' AS medication, med_metformin AS dose_status FROM cln_encounters WHERE med_metformin IN ('Steady', 'Up', 'Down')
UNION ALL
SELECT encounter_id, 'repaglinide' AS medication, med_repaglinide AS dose_status FROM cln_encounters WHERE med_repaglinide IN ('Steady', 'Up', 'Down')
UNION ALL
SELECT encounter_id, 'nateglinide' AS medication, med_nateglinide AS dose_status FROM cln_encounters WHERE med_nateglinide IN ('Steady', 'Up', 'Down')
UNION ALL
SELECT encounter_id, 'chlorpropamide' AS medication, med_chlorpropamide AS dose_status FROM cln_encounters WHERE med_chlorpropamide IN ('Steady', 'Up', 'Down')
UNION ALL
SELECT encounter_id, 'glimepiride' AS medication, med_glimepiride AS dose_status FROM cln_encounters WHERE med_glimepiride IN ('Steady', 'Up', 'Down')
UNION ALL
SELECT encounter_id, 'acetohexamide' AS medication, med_acetohexamide AS dose_status FROM cln_encounters WHERE med_acetohexamide IN ('Steady', 'Up', 'Down')
UNION ALL
SELECT encounter_id, 'glipizide' AS medication, med_glipizide AS dose_status FROM cln_encounters WHERE med_glipizide IN ('Steady', 'Up', 'Down')
UNION ALL
SELECT encounter_id, 'glyburide' AS medication, med_glyburide AS dose_status FROM cln_encounters WHERE med_glyburide IN ('Steady', 'Up', 'Down')
UNION ALL
SELECT encounter_id, 'tolbutamide' AS medication, med_tolbutamide AS dose_status FROM cln_encounters WHERE med_tolbutamide IN ('Steady', 'Up', 'Down')
UNION ALL
SELECT encounter_id, 'pioglitazone' AS medication, med_pioglitazone AS dose_status FROM cln_encounters WHERE med_pioglitazone IN ('Steady', 'Up', 'Down')
UNION ALL
SELECT encounter_id, 'rosiglitazone' AS medication, med_rosiglitazone AS dose_status FROM cln_encounters WHERE med_rosiglitazone IN ('Steady', 'Up', 'Down')
UNION ALL
SELECT encounter_id, 'acarbose' AS medication, med_acarbose AS dose_status FROM cln_encounters WHERE med_acarbose IN ('Steady', 'Up', 'Down')
UNION ALL
SELECT encounter_id, 'miglitol' AS medication, med_miglitol AS dose_status FROM cln_encounters WHERE med_miglitol IN ('Steady', 'Up', 'Down')
UNION ALL
SELECT encounter_id, 'troglitazone' AS medication, med_troglitazone AS dose_status FROM cln_encounters WHERE med_troglitazone IN ('Steady', 'Up', 'Down')
UNION ALL
SELECT encounter_id, 'tolazamide' AS medication, med_tolazamide AS dose_status FROM cln_encounters WHERE med_tolazamide IN ('Steady', 'Up', 'Down')
UNION ALL
SELECT encounter_id, 'examide' AS medication, med_examide AS dose_status FROM cln_encounters WHERE med_examide IN ('Steady', 'Up', 'Down')
UNION ALL
SELECT encounter_id, 'citoglipton' AS medication, med_citoglipton AS dose_status FROM cln_encounters WHERE med_citoglipton IN ('Steady', 'Up', 'Down')
UNION ALL
SELECT encounter_id, 'insulin' AS medication, med_insulin AS dose_status FROM cln_encounters WHERE med_insulin IN ('Steady', 'Up', 'Down')
UNION ALL
SELECT encounter_id, 'glyburide_metformin' AS medication, med_glyburide_metformin AS dose_status FROM cln_encounters WHERE med_glyburide_metformin IN ('Steady', 'Up', 'Down')
UNION ALL
SELECT encounter_id, 'glipizide_metformin' AS medication, med_glipizide_metformin AS dose_status FROM cln_encounters WHERE med_glipizide_metformin IN ('Steady', 'Up', 'Down')
UNION ALL
SELECT encounter_id, 'glimepiride_pioglitazone' AS medication, med_glimepiride_pioglitazone AS dose_status FROM cln_encounters WHERE med_glimepiride_pioglitazone IN ('Steady', 'Up', 'Down')
UNION ALL
SELECT encounter_id, 'metformin_rosiglitazone' AS medication, med_metformin_rosiglitazone AS dose_status FROM cln_encounters WHERE med_metformin_rosiglitazone IN ('Steady', 'Up', 'Down')
UNION ALL
SELECT encounter_id, 'metformin_pioglitazone' AS medication, med_metformin_pioglitazone AS dose_status FROM cln_encounters WHERE med_metformin_pioglitazone IN ('Steady', 'Up', 'Down');
