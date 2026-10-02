#!/usr/bin/env python3
"""Render SVG charts (pure vector shapes, no raster) from the KPI tables exported by run_pipeline.py."""
import csv, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import svgcharts as S


def rd(t, name):
    with open(pathlib.Path(t) / f"{name}.csv", newline="") as f:
        return list(csv.DictReader(f))


def f(x):
    return float(x) if x not in ("", None) else 0.0


def panels(t):
    k = rd(t, "a_kpi_headline")[0]
    base = f(k["readmit_30d_pct"])
    sub = f"overall 30-day rate {base:.2f}% (eligible encounters)"
    age = sorted(rd(t, "a_readmit_by_age"), key=lambda r: f(r["age_mid"]))
    diag = sorted(rd(t, "a_readmit_by_diagnosis"), key=lambda r: -f(r["readmit_30d_pct"]))
    diag = [r for r in diag if r["primary_diagnosis_group"] != "Missing"]
    los = sorted(rd(t, "a_readmit_by_los"), key=lambda r: f(r["los_days"]))
    med = sorted(rd(t, "a_readmit_by_medication"), key=lambda r: -f(r["readmit_30d_pct"]))
    prior = sorted(rd(t, "a_readmit_by_prior_inpatient"), key=lambda r: r["prior_inpatient_band"])
    disch = sorted(rd(t, "a_readmit_by_discharge"), key=lambda r: -f(r["readmit_30d_pct"]))
    ins = {r["insulin_status"]: r for r in rd(t, "a_readmit_by_insulin")}
    ins = [ins[s] for s in ("No", "Steady", "Up", "Down") if s in ins]
    return [
        ("readmit_by_age", S.vbar("30-day readmission by age group", [r["age_group"] for r in age],
                                  [f(r["readmit_30d_pct"]) for r in age], "{:.1f}%", sub, ylabel="30-day readmit %")),
        ("readmit_by_diagnosis", S.hbar("By primary diagnosis group (ICD-9)", [r["primary_diagnosis_group"] for r in diag],
                                        [f(r["readmit_30d_pct"]) for r in diag], "{:.1f}%", sub, color=S.PALETTE[1],
                                        notes=[f"n={int(f(r['encounters'])):,}" for r in diag])),
        ("readmit_by_los", S.line("30-day readmission by length of stay", [r["los_days"] for r in los],
                                  [("30-day readmit %", [f(r["readmit_30d_pct"]) for r in los])], "{:.1f}", sub,
                                  ylabel="30-day readmit %", xlabel="Days in hospital", every=1)),
        ("readmit_by_medication", S.hbar("When each drug is prescribed (>=500 encounters)", [r["medication"] for r in med],
                                         [f(r["readmit_30d_pct"]) for r in med], "{:.1f}%", sub, color=S.PALETTE[2],
                                         notes=[f"n={int(f(r['encounters_prescribed'])):,}" for r in med])),
        ("readmit_by_prior_inpatient", S.vbar("By inpatient visits in the prior year", [r["prior_inpatient_band"] for r in prior],
                                              [f(r["readmit_30d_pct"]) for r in prior], "{:.1f}%", sub, color=S.PALETTE[4],
                                              notes=[f"n={int(f(r['encounters'])):,}" for r in prior], ylabel="30-day readmit %")),
        ("readmit_by_discharge", S.hbar("By discharge destination (all encounters)", [r["discharge_group"] for r in disch],
                                        [f(r["readmit_30d_pct"]) for r in disch], "{:.1f}%", "expired / hospice shown for completeness",
                                        color=S.PALETTE[0], notes=[f"n={int(f(r['encounters'])):,}" for r in disch])),
        ("readmit_by_insulin", S.vbar("By insulin dose status", [r["insulin_status"] for r in ins],
                                      [f(r["readmit_30d_pct"]) for r in ins], "{:.1f}%", sub, color=S.PALETTE[5],
                                      notes=[f"n={int(f(r['encounters'])):,}" for r in ins], ylabel="30-day readmit %")),
    ], k


def make_all(tables, out):
    out = pathlib.Path(out); out.mkdir(parents=True, exist_ok=True)
    ps, k = panels(tables)
    for name, p in ps:
        S.save(p, out / f"{name}.svg")
    cards = [("Encounters", f"{int(f(k['encounters_total'])):,}"), ("Patients", f"{int(f(k['patients_total'])):,}"),
             ("30-day readmit", f"{f(k['readmit_30d_pct']):.2f}%"), ("Any readmit", f"{f(k['readmit_any_pct']):.2f}%"),
             ("Avg LOS", f"{f(k['avg_los_days']):.2f} d"), ("On insulin", f"{f(k['on_insulin_pct']):.1f}%"),
             ("HbA1c tested", f"{f(k['a1c_tested_pct']):.1f}%")]
    S.dashboard(out / "dashboard.svg", "Diabetes 130-US hospitals: 30-day readmission dashboard",
                "Rendered from results/tables (SQL on DuckDB, full data). Rates on readmission-eligible encounters.",
                cards, [p for n, p in ps if n != "readmit_by_insulin"], cols=2)
    print("charts ->", out, sorted(p.name for p in out.glob("*.svg")))


if __name__ == "__main__":
    root = pathlib.Path(__file__).resolve().parents[1]
    make_all(root / "results/tables", root / "results/charts")
