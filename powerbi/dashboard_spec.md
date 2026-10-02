# Dashboard specification (3 pages)

Validate against full-data SQL (`results/metrics.json`): Encounters **101,763**, Patients **71,515**, 30-day readmission **11.39 %**,
any readmission **47.13 %**, avg LOS **4.40 days**. On the sample CSVs here expect the values in `results/sample/JSON.shot`.

## Page 1 - Executive overview
* KPI cards: Encounters, Patients, Readmit 30d %, Readmit Any %, Avg LOS (days), On Insulin %
* Column: Readmit 30d % by `dim_age_group[age_group]` (sort by `age_mid`)
* Bar: Readmit 30d % by `dim_diagnosis_group[diag_group]` with data labels + Encounters as tooltip
* Line: Readmit 30d % by `fact_encounter[time_in_hospital]` (1-14 days)

## Page 2 - Clinical drivers
* Bar: Drug Readmit 30d % by `dim_medication[medication]` (visual filter Drug Encounters >= 500 on full data)
* Column: Readmit 30d % by `fact_encounter[insulin_status]` (No / Steady / Up / Down)
* Column: Readmit 30d % by `fact_encounter[prior_inpatient_band]`
* Clustered column: Readmit 30d % by `a1c_result` x `med_change_flag`

## Page 3 - Discharge & utilisation
* Bar: Readmit 30d % by `dim_discharge_disposition[discharge_group]` (remove the is_readmit_eligible filter in the measure for this one or show Encounters)
* Matrix: `dim_admission_type[admission_type]` x `los_band`, values Readmit 30d % with conditional formatting on `Readmit 30d vs Overall (pp)`
* Column: patients by `dim_patient[n_encounters]` (1, 2, 3, 4, 5+)
* Slicers: `dim_patient[gender]`, `dim_patient[race]`, `dim_age_group[age_group]`
