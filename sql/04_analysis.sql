-- 04_analysis.sql  Business KPIs (Spark SQL dialect)
-- Readmission rates are computed on READMISSION-ELIGIBLE encounters (discharges to expired / hospice excluded),
-- 30-day rate = readmitted '<30' ; any-readmission rate = '<30' or '>30'.

CREATE OR REPLACE TABLE a_kpi_headline AS
SELECT
  COUNT(*)                                                                    AS encounters_total,
  COUNT(DISTINCT patient_nbr)                                                 AS patients_total,
  SUM(is_readmit_eligible)                                                    AS eligible_encounters,
  SUM(CASE WHEN is_readmit_eligible = 1 THEN readmit_30d_flag ELSE 0 END)     AS readmits_30d,
  ROUND(100.0 * SUM(CASE WHEN is_readmit_eligible = 1 THEN readmit_30d_flag ELSE 0 END) / SUM(is_readmit_eligible), 2) AS readmit_30d_pct,
  ROUND(100.0 * SUM(CASE WHEN is_readmit_eligible = 1 THEN readmit_any_flag ELSE 0 END) / SUM(is_readmit_eligible), 2) AS readmit_any_pct,
  ROUND(100.0 * SUM(readmit_30d_flag) / COUNT(*), 2)                          AS readmit_30d_pct_all_encounters,
  ROUND(100.0 * SUM(CASE WHEN is_readmit_eligible = 1 AND is_first_encounter = 1 THEN readmit_30d_flag ELSE 0 END)
        / SUM(CASE WHEN is_readmit_eligible = 1 AND is_first_encounter = 1 THEN 1 ELSE 0 END), 2) AS readmit_30d_pct_first_encounter,
  ROUND(AVG(time_in_hospital), 2)                                             AS avg_los_days,
  ROUND(AVG(num_medications), 2)                                              AS avg_num_medications,
  ROUND(AVG(num_lab_procedures), 2)                                           AS avg_num_lab_procedures,
  ROUND(100.0 * SUM(med_change_flag) / COUNT(*), 2)                           AS med_change_pct,
  ROUND(100.0 * SUM(diabetes_med_flag) / COUNT(*), 2)                         AS on_diabetes_med_pct,
  ROUND(100.0 * SUM(insulin_flag) / COUNT(*), 2)                              AS on_insulin_pct,
  ROUND(100.0 * SUM(CASE WHEN a1c_result <> 'Not measured' THEN 1 ELSE 0 END) / COUNT(*), 2) AS a1c_tested_pct,
  ROUND(100.0 * SUM(CASE WHEN number_inpatient > 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS prior_inpatient_pct
FROM fact_encounter;

-- Q1 readmission by age group
CREATE OR REPLACE TABLE a_readmit_by_age AS
SELECT a.age_group, a.age_mid,
       COUNT(*) AS encounters,
       SUM(f.readmit_30d_flag) AS readmits_30d,
       ROUND(100.0 * AVG(f.readmit_30d_flag), 2) AS readmit_30d_pct,
       ROUND(100.0 * AVG(f.readmit_any_flag), 2) AS readmit_any_pct,
       ROUND(AVG(f.time_in_hospital), 2) AS avg_los_days
FROM fact_encounter f JOIN dim_age_group a ON f.age_key = a.age_key
WHERE f.is_readmit_eligible = 1
GROUP BY a.age_group, a.age_mid;

-- Q2 readmission by primary diagnosis group (ICD-9 chapters)
CREATE OR REPLACE TABLE a_readmit_by_diagnosis AS
SELECT d.diag_group AS primary_diagnosis_group,
       COUNT(*) AS encounters,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS share_pct,
       SUM(f.readmit_30d_flag) AS readmits_30d,
       ROUND(100.0 * AVG(f.readmit_30d_flag), 2) AS readmit_30d_pct,
       ROUND(100.0 * AVG(f.readmit_any_flag), 2) AS readmit_any_pct,
       ROUND(AVG(f.time_in_hospital), 2) AS avg_los_days
FROM fact_encounter f JOIN dim_diagnosis_group d ON f.primary_diag_group_key = d.diag_group_key
WHERE f.is_readmit_eligible = 1
GROUP BY d.diag_group;

-- Q2b top 15 primary ICD-9 codes by volume
CREATE OR REPLACE TABLE a_readmit_top_diag_codes AS
SELECT diag_1, encounters, readmit_30d_pct FROM (
  SELECT diag_1, COUNT(*) AS encounters, ROUND(100.0 * AVG(readmit_30d_flag), 2) AS readmit_30d_pct,
         ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC, diag_1) AS rk
  FROM fact_encounter WHERE is_readmit_eligible = 1 AND diag_1 IS NOT NULL
  GROUP BY diag_1) t
WHERE rk <= 15;

-- Q3 readmission by length of stay (days 1-14) and band
CREATE OR REPLACE TABLE a_readmit_by_los AS
SELECT time_in_hospital AS los_days, los_band,
       COUNT(*) AS encounters,
       SUM(readmit_30d_flag) AS readmits_30d,
       ROUND(100.0 * AVG(readmit_30d_flag), 2) AS readmit_30d_pct,
       ROUND(100.0 * AVG(readmit_any_flag), 2) AS readmit_any_pct
FROM fact_encounter WHERE is_readmit_eligible = 1
GROUP BY time_in_hospital, los_band;

CREATE OR REPLACE TABLE a_readmit_by_los_band AS
SELECT los_band, COUNT(*) AS encounters, SUM(readmit_30d_flag) AS readmits_30d,
       ROUND(100.0 * AVG(readmit_30d_flag), 2) AS readmit_30d_pct,
       ROUND(AVG(num_medications), 2) AS avg_num_medications
FROM fact_encounter WHERE is_readmit_eligible = 1
GROUP BY los_band;

-- Q4 medications: readmission among encounters where each drug was prescribed (>= 500 encounters)
CREATE OR REPLACE TABLE a_readmit_by_medication AS
SELECT dm.medication, dm.drug_class,
       COUNT(*) AS encounters_prescribed,
       SUM(CASE WHEN m.dose_status IN ('Up', 'Down') THEN 1 ELSE 0 END) AS encounters_dose_changed,
       SUM(m.readmit_30d_flag) AS readmits_30d,
       ROUND(100.0 * AVG(m.readmit_30d_flag), 2) AS readmit_30d_pct
FROM fact_encounter_medication m JOIN dim_medication dm ON m.medication_key = dm.medication_key
WHERE m.is_readmit_eligible = 1
GROUP BY dm.medication, dm.drug_class
HAVING COUNT(*) >= 500;

-- Q4b insulin dose status, medication change and number of diabetes drugs
CREATE OR REPLACE TABLE a_readmit_by_insulin AS
SELECT insulin_status, COUNT(*) AS encounters, ROUND(100.0 * AVG(readmit_30d_flag), 2) AS readmit_30d_pct
FROM fact_encounter WHERE is_readmit_eligible = 1 GROUP BY insulin_status;

CREATE OR REPLACE TABLE a_readmit_by_med_change AS
SELECT CASE WHEN diabetes_med_flag = 1 THEN 'On diabetes med' ELSE 'No diabetes med' END AS diabetes_med,
       CASE WHEN med_change_flag = 1 THEN 'Changed' ELSE 'Not changed' END AS med_change,
       COUNT(*) AS encounters, ROUND(100.0 * AVG(readmit_30d_flag), 2) AS readmit_30d_pct
FROM fact_encounter WHERE is_readmit_eligible = 1 GROUP BY 1, 2;

CREATE OR REPLACE TABLE a_readmit_by_n_meds AS
SELECT CASE WHEN n_diabetes_meds >= 3 THEN '3+' ELSE CAST(n_diabetes_meds AS STRING) END AS n_diabetes_meds,
       COUNT(*) AS encounters, ROUND(100.0 * AVG(readmit_30d_flag), 2) AS readmit_30d_pct
FROM fact_encounter WHERE is_readmit_eligible = 1 GROUP BY 1;

-- Q5 other drivers: prior inpatient visits, HbA1c test, discharge destination, admission type
CREATE OR REPLACE TABLE a_readmit_by_prior_inpatient AS
SELECT prior_inpatient_band, COUNT(*) AS encounters, SUM(readmit_30d_flag) AS readmits_30d,
       ROUND(100.0 * AVG(readmit_30d_flag), 2) AS readmit_30d_pct
FROM fact_encounter WHERE is_readmit_eligible = 1 GROUP BY prior_inpatient_band;

CREATE OR REPLACE TABLE a_readmit_by_a1c AS
SELECT a1c_result, COUNT(*) AS encounters, ROUND(100.0 * AVG(readmit_30d_flag), 2) AS readmit_30d_pct,
       ROUND(100.0 * AVG(med_change_flag), 2) AS med_change_pct
FROM fact_encounter WHERE is_readmit_eligible = 1 GROUP BY a1c_result;

CREATE OR REPLACE TABLE a_readmit_by_discharge AS
SELECT d.discharge_group, COUNT(*) AS encounters, SUM(f.readmit_30d_flag) AS readmits_30d,
       ROUND(100.0 * AVG(f.readmit_30d_flag), 2) AS readmit_30d_pct
FROM fact_encounter f JOIN dim_discharge_disposition d ON f.discharge_disposition_id = d.discharge_disposition_id
GROUP BY d.discharge_group;

CREATE OR REPLACE TABLE a_readmit_by_admission_type AS
SELECT t.admission_type, COUNT(*) AS encounters, ROUND(100.0 * AVG(f.readmit_30d_flag), 2) AS readmit_30d_pct
FROM fact_encounter f JOIN dim_admission_type t ON f.admission_type_id = t.admission_type_id
WHERE f.is_readmit_eligible = 1 GROUP BY t.admission_type;

-- Q6 patients: repeat users drive volume
CREATE OR REPLACE TABLE a_patient_utilisation AS
SELECT CASE WHEN n_encounters >= 5 THEN '5+' ELSE CAST(n_encounters AS STRING) END AS encounters_per_patient,
       COUNT(*) AS patients, SUM(n_encounters) AS encounters,
       ROUND(100.0 * SUM(n_encounters) / SUM(SUM(n_encounters)) OVER (), 2) AS encounter_share_pct
FROM dim_patient GROUP BY 1;
