# Power BI model

## Tables (from `powerbi/data/`, sample-sized: the 153-encounter repo subset; regenerate full with `--source full` -> `data/clean_full/star/`)
| Table | Grain | Key columns |
|---|---|---|
| `fact_encounter` | one inpatient encounter | `encounter_id` (unique), `patient_nbr`, `age_key`, `primary_diag_group_key`, `secondary_diag_group_key`, `admission_type_id`, `discharge_disposition_id`, `admission_source_id` |
| `fact_encounter_medication` | encounter x prescribed diabetes drug | `encounter_id`, `medication_key`, `dose_status` (Steady / Up / Down) |
| `dim_patient` | patient | `patient_nbr`, race, gender, first_age_group, n_encounters |
| `dim_age_group` | age decade | `age_key`, age_group, age_mid |
| `dim_diagnosis_group` | ICD-9 chapter group | `diag_group_key`, diag_group |
| `dim_admission_type` | admission type id | `admission_type_id`, description, admission_type |
| `dim_discharge_disposition` | discharge id | `discharge_disposition_id`, description, discharge_group, is_readmit_eligible |
| `dim_admission_source` | admission source id | `admission_source_id`, description, admission_source_group |
| `dim_medication` | drug (23) | `medication_key`, medication, drug_class |

## Relationships (*:1, single direction unless noted)
1. `fact_encounter[patient_nbr]` -> `dim_patient[patient_nbr]`
2. `fact_encounter[age_key]` -> `dim_age_group[age_key]`
3. `fact_encounter[primary_diag_group_key]` -> `dim_diagnosis_group[diag_group_key]` (active)
4. `fact_encounter[secondary_diag_group_key]` -> `dim_diagnosis_group[diag_group_key]` (**inactive**; use `USERELATIONSHIP`)
5. `fact_encounter[admission_type_id]` -> `dim_admission_type[admission_type_id]`
6. `fact_encounter[discharge_disposition_id]` -> `dim_discharge_disposition[discharge_disposition_id]`
7. `fact_encounter[admission_source_id]` -> `dim_admission_source[admission_source_id]`
8. `fact_encounter_medication[medication_key]` -> `dim_medication[medication_key]`
9. `fact_encounter_medication[encounter_id]` -> `fact_encounter[encounter_id]` (*:1, **both directions** so encounter slicers filter drugs)

## Data types
* ids / keys / flags / counts / days: Whole number; `age_mid`: Whole number
* `los_band`, `prior_inpatient_band`, `a1c_result`, `max_glu_serum`, `readmitted`, labels: Text (sort `los_band` alphabetically - the `01:` prefixes keep order)
* No calendar date in the source (1999-2008 encounters are de-identified) -> no date table.

Hide keys, `is_*` flags and outlier flags from report view.
