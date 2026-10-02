# Databricks package

The full pipeline ran on the **Serverless Starter Warehouse** (Unity Catalog) on 2026-10-02 and a Lakeview (AI/BI)
dashboard was **published** over the resulting tables. The warehouse is shared and left to auto-stop.

| Object | Workspace location |
|---|---|
| Raw CSVs (full) | UC volume `/Volumes/workspace/da_learn_08/raw/` |
| Tables (stg_*, cln_*, fact_*, dim_*, a_*, dq_*) | `workspace.da_learn_08` |
| Notebook | `/Workspace/Shared/da-learn-08-healthcare-hospital-readmissions/readmissions_pipeline_notebook` |
| Dashboard (published) | **da-learn-08 Hospital readmissions** (`/Shared/da-learn-08-healthcare-hospital-readmissions/`) |

## DuckDB vs Databricks
All **13 tables have identical row counts** (stg_encounters 101,766; cln/fact_encounter 101,763; encounter x drug 120,050;
dim_patient 71,515; ...). `a_kpi_headline`, `a_readmit_by_age/diagnosis/los_band/medication/prior_inpatient`, `dq_issues`
and `dq_assertions` have **0 cell differences**; 12 / 12 assertions PASS. Evidence: `run_outputs/duckdb_vs_databricks.json`,
`run_outputs/databricks_run.json` (upload sizes, 45 statements with timings, published dashboard path).

## Files here
| File | What it is |
|---|---|
| `readmissions_pipeline_notebook.sql` | Notebook exported from the workspace (generated from `sql/` by `scripts/build_databricks.py`) |
| `readmissions_dashboard.lvdash.json` | Dashboard exported from the workspace: 2 pages, 2 counters + 6 charts (age, diagnosis, LOS line, medication, prior inpatient, discharge) |
| `run_outputs/` | Tables queried back from Databricks + comparison JSON |

## Re-run it yourself
* Automated: `export DATABRICKS_HOST=https://<workspace-host> DATABRICKS_TOKEN=<pat>` then `python scripts/databricks_deploy.py`
  (creates schema + volume, uploads `data/raw_full/*`, runs every notebook statement with retry/backoff, compares with DuckDB,
  imports the notebook, creates/updates and publishes the dashboard, exports both back here).
* Manual: `CREATE SCHEMA IF NOT EXISTS workspace.da_learn_08; CREATE VOLUME IF NOT EXISTS workspace.da_learn_08.raw;` -> upload the
  two CSVs -> *Import* the notebook -> attach a SQL warehouse -> *Run all* -> Dashboards -> *Import* the `.lvdash.json` -> *Publish*.

## Dialect notes
| Topic | DuckDB run | Databricks |
|---|---|---|
| CSV load | `read_csv(..., all_varchar = true)`; hyphenated columns renamed with `"..."` + `EXCLUDE` | `read_files(..., inferColumnTypes => false)`; renamed with backticks + `EXCEPT` |
| `percentile_approx` | exact (`quantile_cont` shim) | approximate (no visible effect on outlier counts here) |
| `VALUES ... AS t(cols)` seeds, window functions, `TRY_CAST`, `split_part` | same | same |
