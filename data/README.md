# Data

| Folder | Content | In git? |
|---|---|---|
| `raw/` | **Reproducible sample**: `diabetic_data.csv` (153 encounters, original 50 columns, values verbatim) + full `IDS_mapping.csv` | yes |
| `raw_full/` | Full UCI files (~18.3 MB) - `python scripts/download_full_data.py` | no (`.gitignore`) |
| `clean/`, `clean_full/` | Cleaned + star-schema CSVs written by `run_pipeline.py` | no (regenerate) |

## Source
* **Diabetes 130-US Hospitals for Years 1999-2008**, UCI ML Repository #296 (Kaggle mirror: `brandao/diabetes`).
* Licence **CC BY 4.0**. Citation: Strack B., DeShazo J.P., Gennings C., et al. (2014) *Impact of HbA1c Measurement on Hospital Readmission Rates*, BioMed Research International, 781670.
* Mirror used: `https://archive.ics.uci.edu/static/public/296/diabetes+130-us+hospitals+for+years+1999-2008.zip` (SHA-256 of both CSVs pinned in `scripts/download_full_data.py`).

## Sample rule (`scripts/make_sample.py`, deterministic)
`CAST(encounter_id AS BIGINT) % 691 = 7` -> **153 encounters** (0.15 %). The sample is for running the pipeline end to end,
not for insight: **all numbers in `results/` come from the FULL 101,766-row file**.

## Missing-value conventions in the source
`?` = missing (race, weight, payer_code, medical_specialty, diag_*); `None` in `A1Cresult` / `max_glu_serum` = test not performed;
`Unknown/Invalid` gender (3 rows). `readmitted`: `<30` = readmitted within 30 days, `>30` = later readmission, `NO` = none recorded.
