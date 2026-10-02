# Power BI build guide

> A `.pbix` cannot be produced on the Linux box this project was built on (Power BI Desktop is Windows-only and has no
> headless authoring mode), so this folder is a **kit**: data + model + measures + layout spec. Build time ~45 min.

1. **Get the data.** `powerbi/data/` holds the star schema built from the **153-encounter repo sample** (small enough for git).
   For the full 101,763 encounters run `pip install -r requirements.txt && python scripts/download_full_data.py && python run_pipeline.py --source full`
   and load `data/clean_full/star/*.csv` instead (same columns).
2. **Load.** Power BI Desktop -> *Get data -> Text/CSV* for the 9 files (2 facts + 7 dims). Set types per `model.md`. Locale: English (United States).
3. **Model.** Create the 9 relationships in `model.md` (secondary diagnosis inactive; medication bridge both directions). Hide keys/flags.
4. **Measures.** Create a table `_Measures` and paste each measure from `measures.dax`; format % measures as Percentage (2 dp).
5. **Pages.** Build the 3 pages in `dashboard_spec.md`; compare against `results/charts/dashboard.svg`.
6. **Validate** with the full data: Encounters 101,763; Readmit 30d % 11.39 %; Readmit Any % 47.13 %; Avg LOS 4.40.
   With the sample CSVs compare against `results/sample/JSON.shot`.
7. Save as `hospital_readmissions.pbix` (not committed - binary).
