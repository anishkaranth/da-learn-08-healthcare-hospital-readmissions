# Results - full Diabetes 130-US hospitals dataset (101,763 clean encounters)

Run: `python run_pipeline.py --source full` on DuckDB 1.5.6 (Python 3.13), 2026-10-02. Every number is copied from
`results/tables/*.csv` / `metrics.json` of that run; the Databricks run produced identical values (0 cell differences).
Readmission rates use the 99,340 **readmission-eligible** encounters (expired / hospice discharges excluded).

![dashboard](charts/dashboard.svg)

## Headline KPIs
| KPI | Value |
|---|---|
| Encounters (clean) / patients | 101,763 / 71,515 |
| Eligible encounters | 99,340 |
| 30-day readmissions | 11,314 -> **11.39 %** |
| Any readmission (<30 or >30) | **47.13 %** |
| 30-day rate, first encounter per patient only | 8.97 % |
| 30-day rate, all encounters (no exclusion) | 11.16 % |
| Avg length of stay | 4.40 days |
| Avg medications / lab procedures per encounter | 16.02 / 43.10 |
| Diabetes medication changed during stay | 46.19 % |
| On any diabetes medication / on insulin | 77.0 % / 53.44 % |
| HbA1c measured | 16.72 % |
| Encounters with >= 1 inpatient visit in prior year | 33.54 % |

## Readmission by the requested dimensions
| Age group | 0-10 | 10-20 | 20-30 | 30-40 | 40-50 | 50-60 | 60-70 | 70-80 | 80-90 | 90-100 |
|---|---|---|---|---|---|---|---|---|---|---|
| 30-day % | 1.88 | 5.8 | **14.31** | 11.26 | 10.66 | 9.77 | 11.3 | 12.06 | 12.57 | 11.9 |
| Encounters | 160 | 690 | 1,649 | 3,764 | 9,607 | 17,060 | 22,058 | 25,329 | 16,434 | 2,589 |

| Primary diagnosis | Encounters | Share | 30-day % | Any % |
|---|---|---|---|---|
| Diabetes (250.xx) | 8,661 | 8.72 % | **13.1** | 51.39 |
| Injury | 6,851 | 6.9 % | 12.41 | 45.0 |
| Circulatory | 29,680 | 29.88 % | 11.69 | 48.16 |
| Other | 17,793 | 17.91 % | 11.68 | 46.86 |
| Genitourinary | 5,002 | 5.04 % | 11.04 | 45.3 |
| Neoplasms | 3,131 | 3.15 % | 10.89 | 36.28 |
| Digestive | 9,333 | 9.4 % | 10.82 | 46.83 |
| Respiratory | 13,934 | 14.03 % | 10.06 | 49.72 |
| Musculoskeletal | 4,935 | 4.97 % | 9.54 | 39.33 |

| Length of stay | 1-2 days | 3-4 days | 5-7 days | 8-14 days |
|---|---|---|---|---|
| Encounters | 30,713 | 31,116 | 22,800 | 14,711 |
| 30-day % | 9.33 | 11.33 | 12.67 | **13.85** |
| Avg medications | 11.86 | 15.05 | 18.44 | 22.72 |

| Medication (prescribed, >= 500 enc.) | Encounters | 30-day % |
|---|---|---|
| repaglinide | 1,518 | 13.5 |
| insulin | 52,964 | 12.42 |
| nateglinide | 689 | 11.61 |
| glipizide | 12,530 | 11.54 |
| glyburide-metformin | 698 | 11.17 |
| glyburide | 10,523 | 10.72 |
| pioglitazone | 7,254 | 10.64 |
| rosiglitazone | 6,303 | 10.53 |
| glimepiride | 5,122 | 10.35 |
| metformin | 19,843 | **9.77** |

Insulin dose: No 10.21 % (46,376) - Steady 11.37 % - Up 13.33 % - **Down 14.22 %** (11,908).
Number of diabetes drugs: 0 -> 9.87 %, 1 -> 12.58 %, 2 -> 10.85 %, 3+ -> 10.42 %. Med changed 12.02 % vs on-med-not-changed 11.56 %.

## Other drivers
* **Prior inpatient visits:** 0 -> 8.59 % (66,242), 1 -> 13.25 %, 2 -> 17.93 %, **3+ -> 26.4 %** (6,814).
* **Discharge destination** (all encounters): other hospital / institution 18.57 %, SNF / rehab / LTC 16.0 %, Left AMA 14.45 %, home with health service 12.71 %, home 9.3 %, hospice 5.58 %, expired 0 %.
* **HbA1c:** not measured 11.69 % vs >8 9.94 %, >7 10.15 %, normal 9.77 % - testing goes with lower readmission (Strack et al.'s finding).
* **Admission type:** emergency 11.83 %, urgent 11.35 %, elective 10.49 %.
* **Utilisation:** 54,742 patients (76.5 %) had one stay; 1,590 patients with 5+ stays account for 10.3 % of encounters.

## Data quality
| Entity | Raw | Clean | Notes |
|---|---|---|---|
| encounters | 101,766 | 101,763 | 0 duplicate ids; 3 Unknown/Invalid gender dropped |
| encounter x drug | - | 120,050 | prescribed (Steady/Up/Down) only |
| dim_patient | - | 71,515 | attributes from first encounter |
| small dims | - | age 10, diagnosis 10, admission type 8, discharge 30, admission source 25, medication 23 | lookups seeded from IDS_mapping.csv and verified verbatim |

Missing (raw '?'): weight 96.86 %, medical_specialty 49.08 %, payer_code 39.56 %, race 2.23 %, diag_1 0.02 %. HbA1c 'None' 83.28 %.
Flags: 2,423 expired/hospice (excluded from rates), 430 num_medications outliers (kept), 1,645 V/E primary codes.
**All 12 assertions in `dq_assertions` PASS** on DuckDB and Databricks.

## Charts (SVG, pure vector)
`charts/dashboard.svg` (KPI cards + 6 panels) and `readmit_by_age.svg`, `readmit_by_diagnosis.svg`, `readmit_by_los.svg`,
`readmit_by_medication.svg`, `readmit_by_prior_inpatient.svg`, `readmit_by_discharge.svg`, `readmit_by_insulin.svg`.

## Files
* `metrics.json` - KPIs, data-quality stats (row counts, null rates, issues, assertions), list of analysis tables, engine + timings
* `JSON.shot` - headline snapshot + run config (valid JSON)
* `tables/` - every `a_*` and `dq_*` table as CSV
* `sample/` - `metrics.json` + `JSON.shot` from the 153-encounter sample (pipeline check only)
