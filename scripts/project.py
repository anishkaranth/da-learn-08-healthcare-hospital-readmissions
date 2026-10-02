"""Project-specific settings used by run_pipeline.py, build_databricks.py and databricks_deploy.py."""
NAME = "da-learn-08-healthcare-hospital-readmissions"
DATASET = ("Diabetes 130-US Hospitals for Years 1999-2008 (UCI ML Repository id 296; Kaggle: brandao/diabetes; CC BY 4.0)")
RAW_FILES = ["diabetic_data.csv", "IDS_mapping.csv"]
STAR = ["fact_encounter", "fact_encounter_medication", "dim_patient", "dim_age_group", "dim_diagnosis_group",
        "dim_admission_type", "dim_discharge_disposition", "dim_admission_source", "dim_medication"]
CLEAN = ["cln_encounters"]
METRIC_TABLES = ["a_readmit_by_age", "a_readmit_by_diagnosis", "a_readmit_by_los_band", "a_readmit_by_medication",
                 "a_readmit_by_prior_inpatient", "a_readmit_by_a1c", "a_readmit_by_discharge", "a_readmit_by_med_change",
                 "a_readmit_by_insulin", "a_readmit_by_n_meds", "a_readmit_by_admission_type", "a_patient_utilisation"]



def build_shot(q, kpi):
    """Headline snapshot written to results/JSON.shot."""
    keys = ["encounters_total", "patients_total", "eligible_encounters", "readmits_30d", "readmit_30d_pct", "readmit_any_pct",
            "readmit_30d_pct_first_encounter", "avg_los_days", "avg_num_medications", "med_change_pct", "on_insulin_pct",
            "a1c_tested_pct", "prior_inpatient_pct"]
    return {
        "config": {"sql_dialect": "Spark/Databricks SQL (+ DuckDB shim in sql/00)",
                   "readmission_definition": "readmitted '<30' -> readmit_30d_flag = 1 (any = '<30' or '>30')",
                   "rate_denominator": "readmission-eligible encounters (discharge to expired / hospice excluded)",
                   "outlier_rule": "num_medications / num_lab_procedures > Q3 + 3*IQR (flagged, kept)",
                   "sample_rule": "CAST(encounter_id AS BIGINT) % 691 = 7 (data/raw, 153 encounters)"},
        "headline": {k: kpi[k] for k in keys},
        "readmit_30d_pct_by_age": {r["age_group"]: r["readmit_30d_pct"] for r in q("SELECT * FROM a_readmit_by_age ORDER BY age_mid")},
        "readmit_30d_pct_by_los_band": {r["los_band"]: r["readmit_30d_pct"] for r in q("SELECT * FROM a_readmit_by_los_band ORDER BY los_band")},
        "readmit_30d_pct_by_prior_inpatient": {r["prior_inpatient_band"]: r["readmit_30d_pct"] for r in q("SELECT * FROM a_readmit_by_prior_inpatient ORDER BY 1")},
        "top_diagnosis_groups": q("SELECT primary_diagnosis_group, encounters, readmit_30d_pct FROM a_readmit_by_diagnosis ORDER BY encounters DESC LIMIT 5"),
        "medications_by_readmit_30d_pct": q("SELECT medication, encounters_prescribed, readmit_30d_pct FROM a_readmit_by_medication ORDER BY readmit_30d_pct DESC"),
    }


DBX = {
    "schema": "da_learn_08",
    "title": "Hospital readmissions (Diabetes 130-US hospitals)",
    "notebook_file": "readmissions_pipeline_notebook.sql",
    "dashboard_file": "readmissions_dashboard.lvdash.json",
    "dashboard_name": "da-learn-08 Hospital readmissions",
    # staging table -> (file in volume, extra read_files options, select list)
    "staging": {"stg_encounters": ("diabetic_data.csv", None, """* EXCEPT (`glyburide-metformin`, `glipizide-metformin`, `glimepiride-pioglitazone`, `metformin-rosiglitazone`, `metformin-pioglitazone`),
       `glyburide-metformin` AS glyburide_metformin,
       `glipizide-metformin` AS glipizide_metformin,
       `glimepiride-pioglitazone` AS glimepiride_pioglitazone,
       `metformin-rosiglitazone` AS metformin_rosiglitazone,
       `metformin-pioglitazone` AS metformin_pioglitazone"""),
                "stg_ids_mapping": ("IDS_mapping.csv", None, None)},
    "compare_tables": ["stg_encounters", "stg_ids_mapping", "cln_encounters", "cln_encounter_medications", "fact_encounter",
                       "fact_encounter_medication", "dim_patient", "dim_age_group", "dim_diagnosis_group", "dim_admission_type",
                       "dim_discharge_disposition", "dim_admission_source", "dim_medication"],
    "compare_values": ["a_kpi_headline", "a_readmit_by_age", "a_readmit_by_diagnosis", "a_readmit_by_los_band",
                       "a_readmit_by_medication", "a_readmit_by_prior_inpatient", "dq_issues", "dq_assertions"],
}


def dashboard_def(q):
    """Lakeview dashboard: 2 KPI counters + 6 charts = 8 visuals. q(table) -> fully-qualified name."""
    from lakeview import ds, text, counter, chart, page, PCT, NUM
    datasets = [
        ds("kpi", "Headline KPIs", f"SELECT encounters_total, patients_total, readmit_30d_pct / 100 AS readmit_30d_rate, "
           f"readmit_any_pct / 100 AS readmit_any_rate, avg_los_days FROM {q('a_kpi_headline')}"),
        ds("age", "By age", f"SELECT age_group, age_mid, encounters, readmit_30d_pct FROM {q('a_readmit_by_age')} ORDER BY age_mid"),
        ds("diag", "By diagnosis", f"SELECT primary_diagnosis_group, encounters, readmit_30d_pct FROM {q('a_readmit_by_diagnosis')} ORDER BY readmit_30d_pct DESC"),
        ds("los", "By length of stay", f"SELECT los_days, encounters, readmit_30d_pct FROM {q('a_readmit_by_los')} ORDER BY los_days"),
        ds("med", "By medication", f"SELECT medication, encounters_prescribed, readmit_30d_pct FROM {q('a_readmit_by_medication')} ORDER BY readmit_30d_pct DESC"),
        ds("prior", "By prior inpatient visits", f"SELECT prior_inpatient_band, encounters, readmit_30d_pct FROM {q('a_readmit_by_prior_inpatient')} ORDER BY prior_inpatient_band"),
        ds("disch", "By discharge destination", f"SELECT discharge_group, encounters, readmit_30d_pct FROM {q('a_readmit_by_discharge')} ORDER BY readmit_30d_pct DESC"),
    ]
    p1 = [text("t1", "## Diabetes 130-US hospitals: 30-day readmissions (full data, 101,763 encounters)", 0, 0),
          counter("k_enc", "kpi", "encounters_total", "Encounters", NUM, 0, 1, 2, 2),
          counter("k_rate", "kpi", "readmit_30d_rate", "30-day readmission rate", PCT, 2, 1, 2, 2),
          text("k_note", "Rates use readmission-eligible encounters (expired / hospice excluded). Source: UCI id 296, CC BY 4.0. Tables in workspace.da_learn_08.", 4, 1, 2, 2),
          chart("c_age", "bar", "age", ("age_group", "Age group"), ("readmit_30d_pct", "30-day readmit %"), "30-day readmission by age", {"x": 0, "y": 3, "width": 3, "height": 6}),
          chart("c_diag", "bar", "diag", ("primary_diagnosis_group", "Primary diagnosis"), ("readmit_30d_pct", "30-day readmit %"), "By primary diagnosis group", {"x": 3, "y": 3, "width": 3, "height": 6}, horizontal=True),
          chart("c_los", "line", "los", ("los_days", "Length of stay (days)"), ("readmit_30d_pct", "30-day readmit %"), "By length of stay", {"x": 0, "y": 9, "width": 6, "height": 5}, xs="quantitative")]
    p2 = [text("t2", "## Drivers: medications, prior utilisation, discharge destination", 0, 0),
          chart("c_med", "bar", "med", ("medication", "Medication"), ("readmit_30d_pct", "30-day readmit %"), "Readmission when drug prescribed (>=500 encounters)", {"x": 0, "y": 1, "width": 6, "height": 5}),
          chart("c_prior", "bar", "prior", ("prior_inpatient_band", "Inpatient visits in prior year"), ("readmit_30d_pct", "30-day readmit %"), "By prior inpatient visits", {"x": 0, "y": 6, "width": 3, "height": 5}),
          chart("c_disch", "bar", "disch", ("discharge_group", "Discharge destination"), ("readmit_30d_pct", "30-day readmit %"), "By discharge destination", {"x": 3, "y": 6, "width": 3, "height": 5}, horizontal=True)]
    return {"datasets": datasets, "pages": [page("overview", "Overview", p1), page("drivers", "Drivers", p2)]}
