-- 03_model.sql  Star schema (Spark SQL dialect)
--   facts : fact_encounter (grain: one inpatient encounter), fact_encounter_medication (encounter x prescribed drug)
--   dims  : dim_patient, dim_age_group, dim_diagnosis_group, dim_admission_type, dim_discharge_disposition,
--           dim_admission_source, dim_medication
-- The three ID lookups are seeded from IDS_mapping.csv (a stacked 3-section file that cannot be split reliably
-- with set-based SQL); 05_quality_checks.sql asserts every seed row exists verbatim in stg_ids_mapping
-- and that every id used by an encounter resolves.

CREATE OR REPLACE TABLE dim_admission_type AS
SELECT admission_type_id, description,
  CASE WHEN description IN ('NULL', 'Not Available', 'Not Mapped') THEN 'Unknown' ELSE description END AS admission_type
FROM (VALUES
  (1, 'Emergency'),
  (2, 'Urgent'),
  (3, 'Elective'),
  (4, 'Newborn'),
  (5, 'Not Available'),
  (6, 'NULL'),
  (7, 'Trauma Center'),
  (8, 'Not Mapped')
) AS t(admission_type_id, description);

CREATE OR REPLACE TABLE dim_discharge_disposition AS
SELECT discharge_disposition_id, description,
  CASE WHEN discharge_disposition_id IN (11, 19, 20, 21) THEN 'Expired'
       WHEN discharge_disposition_id IN (13, 14) THEN 'Hospice'
       WHEN discharge_disposition_id = 1 THEN 'Home'
       WHEN discharge_disposition_id IN (6, 8) THEN 'Home with health service'
       WHEN discharge_disposition_id IN (3, 4, 15, 22, 23, 24, 27, 30) THEN 'Skilled nursing / rehab / long-term care'
       WHEN discharge_disposition_id IN (2, 5, 9, 10, 12, 16, 17, 28, 29) THEN 'Other hospital / institution'
       WHEN discharge_disposition_id = 7 THEN 'Left AMA'
       ELSE 'Unknown' END AS discharge_group,
  CASE WHEN discharge_disposition_id IN (11, 13, 14, 19, 20, 21) THEN 0 ELSE 1 END AS is_readmit_eligible
FROM (VALUES
  (1, 'Discharged to home'),
  (2, 'Discharged/transferred to another short term hospital'),
  (3, 'Discharged/transferred to SNF'),
  (4, 'Discharged/transferred to ICF'),
  (5, 'Discharged/transferred to another type of inpatient care institution'),
  (6, 'Discharged/transferred to home with home health service'),
  (7, 'Left AMA'),
  (8, 'Discharged/transferred to home under care of Home IV provider'),
  (9, 'Admitted as an inpatient to this hospital'),
  (10, 'Neonate discharged to another hospital for neonatal aftercare'),
  (11, 'Expired'),
  (12, 'Still patient or expected to return for outpatient services'),
  (13, 'Hospice / home'),
  (14, 'Hospice / medical facility'),
  (15, 'Discharged/transferred within this institution to Medicare approved swing bed'),
  (16, 'Discharged/transferred/referred another institution for outpatient services'),
  (17, 'Discharged/transferred/referred to this institution for outpatient services'),
  (18, 'NULL'),
  (19, 'Expired at home. Medicaid only, hospice.'),
  (20, 'Expired in a medical facility. Medicaid only, hospice.'),
  (21, 'Expired, place unknown. Medicaid only, hospice.'),
  (22, 'Discharged/transferred to another rehab fac including rehab units of a hospital .'),
  (23, 'Discharged/transferred to a long term care hospital.'),
  (24, 'Discharged/transferred to a nursing facility certified under Medicaid but not certified under Medicare.'),
  (25, 'Not Mapped'),
  (26, 'Unknown/Invalid'),
  (30, 'Discharged/transferred to another Type of Health Care Institution not Defined Elsewhere'),
  (27, 'Discharged/transferred to a federal health care facility.'),
  (28, 'Discharged/transferred/referred to a psychiatric hospital of psychiatric distinct part unit of a hospital'),
  (29, 'Discharged/transferred to a Critical Access Hospital (CAH).')
) AS t(discharge_disposition_id, description);

CREATE OR REPLACE TABLE dim_admission_source AS
SELECT admission_source_id, description,
  CASE WHEN admission_source_id IN (1, 2, 3) THEN 'Referral'
       WHEN admission_source_id = 7 THEN 'Emergency room'
       WHEN admission_source_id IN (4, 5, 6, 10, 18, 19, 22, 25, 26) THEN 'Transfer'
       WHEN admission_source_id IN (9, 15, 17, 20, 21) THEN 'Unknown'
       ELSE 'Other' END AS admission_source_group
FROM (VALUES
  (1, 'Physician Referral'),
  (2, 'Clinic Referral'),
  (3, 'HMO Referral'),
  (4, 'Transfer from a hospital'),
  (5, 'Transfer from a Skilled Nursing Facility (SNF)'),
  (6, 'Transfer from another health care facility'),
  (7, 'Emergency Room'),
  (8, 'Court/Law Enforcement'),
  (9, 'Not Available'),
  (10, 'Transfer from critial access hospital'),
  (11, 'Normal Delivery'),
  (12, 'Premature Delivery'),
  (13, 'Sick Baby'),
  (14, 'Extramural Birth'),
  (15, 'Not Available'),
  (17, 'NULL'),
  (18, 'Transfer From Another Home Health Agency'),
  (19, 'Readmission to Same Home Health Agency'),
  (20, 'Not Mapped'),
  (21, 'Unknown/Invalid'),
  (22, 'Transfer from hospital inpt/same fac reslt in a sep claim'),
  (23, 'Born inside this hospital'),
  (24, 'Born outside this hospital'),
  (25, 'Transfer from Ambulatory Surgery Center'),
  (26, 'Transfer from Hospice')
) AS t(admission_source_id, description);

CREATE OR REPLACE TABLE dim_medication AS
SELECT medication_key, medication, drug_class
FROM (VALUES
  (1, 'metformin', 'Biguanide'),
  (2, 'repaglinide', 'Meglitinide'),
  (3, 'nateglinide', 'Meglitinide'),
  (4, 'chlorpropamide', 'Sulfonylurea'),
  (5, 'glimepiride', 'Sulfonylurea'),
  (6, 'acetohexamide', 'Sulfonylurea'),
  (7, 'glipizide', 'Sulfonylurea'),
  (8, 'glyburide', 'Sulfonylurea'),
  (9, 'tolbutamide', 'Sulfonylurea'),
  (10, 'pioglitazone', 'Thiazolidinedione'),
  (11, 'rosiglitazone', 'Thiazolidinedione'),
  (12, 'acarbose', 'Alpha-glucosidase inhibitor'),
  (13, 'miglitol', 'Alpha-glucosidase inhibitor'),
  (14, 'troglitazone', 'Thiazolidinedione'),
  (15, 'tolazamide', 'Sulfonylurea'),
  (16, 'examide', 'Other (examide)'),
  (17, 'citoglipton', 'Other (citoglipton)'),
  (18, 'insulin', 'Insulin'),
  (19, 'glyburide_metformin', 'Combination'),
  (20, 'glipizide_metformin', 'Combination'),
  (21, 'glimepiride_pioglitazone', 'Combination'),
  (22, 'metformin_rosiglitazone', 'Combination'),
  (23, 'metformin_pioglitazone', 'Combination')
) AS t(medication_key, medication, drug_class);

CREATE OR REPLACE TABLE dim_age_group AS
SELECT CAST(ROW_NUMBER() OVER (ORDER BY age_mid) AS INT) AS age_key, age_group, age_mid
FROM (SELECT DISTINCT age_group, age_mid FROM cln_encounters) a;

CREATE OR REPLACE TABLE dim_diagnosis_group AS
SELECT CAST(ROW_NUMBER() OVER (ORDER BY diag_group) AS INT) AS diag_group_key, diag_group
FROM (SELECT diag_1_group AS diag_group FROM cln_encounters
      UNION SELECT diag_2_group FROM cln_encounters
      UNION SELECT diag_3_group FROM cln_encounters) d;

-- Patient attributes are taken from the patient's first encounter (lowest encounter_id)
CREATE OR REPLACE TABLE dim_patient AS
SELECT patient_nbr, race, gender, age_group AS first_age_group, n_encounters
FROM (
  SELECT patient_nbr, race, gender, age_group,
         COUNT(*) OVER (PARTITION BY patient_nbr) AS n_encounters,
         ROW_NUMBER() OVER (PARTITION BY patient_nbr ORDER BY encounter_id) AS rn
  FROM cln_encounters
) p WHERE rn = 1;

CREATE OR REPLACE TABLE fact_encounter AS
SELECT
  e.encounter_id,
  e.patient_nbr,
  a.age_key,
  d1.diag_group_key AS primary_diag_group_key,
  d2.diag_group_key AS secondary_diag_group_key,
  e.admission_type_id,
  e.discharge_disposition_id,
  e.admission_source_id,
  e.patient_encounter_seq,
  e.is_first_encounter,
  e.payer_code,
  e.medical_specialty,
  e.diag_1,
  e.time_in_hospital,
  e.los_band,
  e.num_lab_procedures,
  e.num_procedures,
  e.num_medications,
  e.number_outpatient,
  e.number_emergency,
  e.number_inpatient,
  e.prior_inpatient_band,
  e.number_diagnoses,
  e.max_glu_serum,
  e.a1c_result,
  e.n_diabetes_meds,
  e.n_meds_changed,
  e.med_change_flag,
  e.diabetes_med_flag,
  e.insulin_flag,
  e.med_insulin AS insulin_status,
  e.readmitted,
  e.readmit_30d_flag,
  e.readmit_any_flag,
  e.is_readmit_eligible,
  e.is_num_meds_outlier,
  e.is_num_labs_outlier
FROM cln_encounters e
JOIN dim_age_group a ON e.age_group = a.age_group
JOIN dim_diagnosis_group d1 ON e.diag_1_group = d1.diag_group
JOIN dim_diagnosis_group d2 ON e.diag_2_group = d2.diag_group;

CREATE OR REPLACE TABLE fact_encounter_medication AS
SELECT m.encounter_id, dm.medication_key, m.dose_status,
       f.readmit_30d_flag, f.readmit_any_flag, f.is_readmit_eligible
FROM cln_encounter_medications m
JOIN dim_medication dm ON m.medication = dm.medication
JOIN fact_encounter f ON m.encounter_id = f.encounter_id;
