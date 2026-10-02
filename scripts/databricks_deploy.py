#!/usr/bin/env python3
"""Deploy + run the pipeline on Databricks and export the artefacts back into databricks/.

Needs env DATABRICKS_HOST (workspace URL, no path) and DATABRICKS_TOKEN. Steps (each can be skipped with --skip):
  upload   : CREATE SCHEMA/VOLUME, PUT data/raw_full/* into /Volumes/workspace/<schema>/raw/
  run      : execute every SQL statement of the generated notebook on the 'Serverless Starter Warehouse'
  compare  : row counts + key tables vs a fresh DuckDB full run -> databricks/run_outputs/duckdb_vs_databricks.json
  publish  : import notebook to /Workspace/Shared/<repo>/, create/update + PUBLISH the Lakeview dashboard,
             export notebook + dashboard JSON into databricks/
The warehouse is never stopped here (shared; auto-stop handles it). Transient API errors are retried with backoff.
"""
import argparse, base64, csv, importlib.util, json, os, pathlib, sys, time, urllib.error, urllib.parse, urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
spec = importlib.util.spec_from_file_location("project", ROOT / "scripts" / "project.py")
P = importlib.util.module_from_spec(spec); spec.loader.exec_module(P)
D = P.DBX
HOST = os.environ["DATABRICKS_HOST"].rstrip("/")
TOKEN = os.environ["DATABRICKS_TOKEN"]
WAREHOUSE_NAME = "Serverless Starter Warehouse"
SCHEMA = D["schema"]
OUT = ROOT / "databricks" / "run_outputs"


def api(method, path, body=None, raw=None, ctype="application/json", tries=8):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    for k in range(tries):
        req = urllib.request.Request(HOST + path, data=data, method=method,
                                     headers={"Authorization": "Bearer " + TOKEN, "Content-Type": ctype})
        try:
            with urllib.request.urlopen(req, timeout=900) as r:
                txt = r.read()
            return json.loads(txt) if txt else {}
        except urllib.error.HTTPError as e:
            msg = e.read().decode(errors="replace")[:600]
            if e.code in (429, 500, 502, 503, 504) and k < tries - 1:
                time.sleep(min(60, 3 * 2 ** k)); continue
            raise RuntimeError(f"{method} {path.split('?')[0]} -> {e.code}: {msg}")
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            if k < tries - 1:
                time.sleep(min(60, 3 * 2 ** k)); continue
            raise


def warehouse_id():
    for w in api("GET", "/api/2.0/sql/warehouses").get("warehouses", []):
        if w["name"] == WAREHOUSE_NAME:
            return w["id"]
    raise SystemExit("warehouse not found: " + WAREHOUSE_NAME)


WH = None


def sql(stmt, tries=6):
    body = {"warehouse_id": WH, "statement": stmt, "wait_timeout": "50s", "on_wait_timeout": "CONTINUE",
            "format": "JSON_ARRAY", "disposition": "INLINE", "catalog": "workspace", "schema": SCHEMA}
    for k in range(tries):
        r = api("POST", "/api/2.0/sql/statements", body)
        while r["status"]["state"] in ("PENDING", "RUNNING"):
            time.sleep(2); r = api("GET", f"/api/2.0/sql/statements/{r['statement_id']}")
        if r["status"]["state"] == "SUCCEEDED":
            cols = [c["name"] for c in r.get("manifest", {}).get("schema", {}).get("columns", [])]
            data = r.get("result", {}).get("data_array", []) or []
            nxt = r.get("result", {}).get("next_chunk_internal_link")
            while nxt:
                ch = api("GET", nxt); data += ch.get("data_array", []) or []; nxt = ch.get("next_chunk_internal_link")
            return cols, data
        err = json.dumps(r["status"])
        transient = any(s in err for s in ("TEMPORARILY_UNAVAILABLE", "RESOURCE_EXHAUSTED", "CONCURRENT", "429", "timeout"))
        if transient and k < tries - 1:
            time.sleep(min(60, 5 * 2 ** k)); continue
        raise RuntimeError(f"SQL failed: {err[:800]}\n{stmt[:300]}")


def notebook_statements():
    nb = (ROOT / "databricks" / D["notebook_file"]).read_text()
    out = []
    for cell in nb.split("\n-- COMMAND ----------\n"):
        if "-- MAGIC" in cell:
            continue
        body = "\n".join(l for l in cell.splitlines() if not l.startswith("-- Databricks notebook source"))
        for st in [s.strip() for s in body.split(";\n") if s.strip()]:
            st = st.rstrip(";").strip()
            if all(l.strip().startswith("--") or not l.strip() for l in st.splitlines()):
                continue
            out.append(st)
    return out


def upload():
    sql(f"CREATE SCHEMA IF NOT EXISTS workspace.{SCHEMA}")
    sql(f"CREATE VOLUME IF NOT EXISTS workspace.{SCHEMA}.raw")
    info = []
    for f in P.RAW_FILES:
        p = ROOT / "data" / "raw_full" / f
        t0 = time.time()
        api("PUT", f"/api/2.0/fs/files/Volumes/workspace/{SCHEMA}/raw/{urllib.parse.quote(f)}?overwrite=true",
            raw=p.read_bytes(), ctype="application/octet-stream")
        meta = api("GET", f"/api/2.0/fs/directories/Volumes/workspace/{SCHEMA}/raw/")
        size = next((c.get("file_size") for c in meta.get("contents", []) if c["name"] == f), None)
        info.append({"file": f, "local_bytes": p.stat().st_size, "volume_bytes": size, "secs": round(time.time() - t0, 1)})
        print("uploaded", info[-1], flush=True)
    return info


def run():
    log = []
    for st in notebook_statements():
        first = next(l for l in st.splitlines() if l.strip() and not l.strip().startswith("--"))
        t0 = time.time()
        cols, rows = sql(st)
        log.append({"stmt": first[:90], "secs": round(time.time() - t0, 1), "rows_returned": len(rows)})
        print(f"{log[-1]['secs']:6.1f}s  {first[:90]}", flush=True)
    return log


def compare():
    rp_spec = importlib.util.spec_from_file_location("rp", ROOT / "run_pipeline.py")
    rp = importlib.util.module_from_spec(rp_spec); rp_spec.loader.exec_module(rp)
    con, _ = rp.run_sql(ROOT / "data" / "raw_full", verbose=False)
    tables = list(D["compare_tables"])
    q = " UNION ALL ".join(f"SELECT '{t}' AS t, COUNT(*) AS n FROM {t}" for t in tables)
    _, r = sql(q); dbx = {t: int(n) for t, n in r}
    duck = {t: con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0] for t in tables}
    counts = [{"table": t, "duckdb_rows": duck[t], "databricks_rows": dbx[t], "match": duck[t] == dbx[t]} for t in tables]
    cmp = {}
    OUT.mkdir(parents=True, exist_ok=True)
    for t in D["compare_values"]:
        cols, r1 = sql(f"SELECT * FROM {t} ORDER BY ALL")
        cur = con.execute(f"SELECT * FROM {t} ORDER BY ALL"); r2 = cur.fetchall()
        diffs = []
        for a, b in zip(r1, r2):
            for c, x, y in zip(cols, a, b):
                try:
                    same = (x is None and y is None) or abs(float(x) - float(y)) <= 1e-6 * max(1, abs(float(y)))
                except (TypeError, ValueError):
                    same = str(x) == str(y)
                if not same:
                    diffs.append({"key": str(a[0]), "col": c, "databricks": x, "duckdb": str(y)})
        cmp[t] = {"rows_databricks": len(r1), "rows_duckdb": len(r2), "cell_diffs": diffs[:50], "n_cell_diffs": len(diffs)}
        with open(OUT / f"{t}.csv", "w", newline="") as f:
            w = csv.writer(f, lineterminator="\n"); w.writerow(cols); w.writerows(r1)
    res = {"row_counts": counts, "table_comparisons": cmp,
           "all_row_counts_match": all(c["match"] for c in counts)}
    (OUT / "duckdb_vs_databricks.json").write_text(json.dumps(res, indent=1) + "\n")
    for c in counts:
        print(c)
    print({k: (v["rows_databricks"], v["rows_duckdb"], v["n_cell_diffs"]) for k, v in cmp.items()})
    return res


def publish():
    folder = f"/Workspace/Shared/{P.NAME}"
    nb_path = f"{folder}/{D['notebook_file'].rsplit('.', 1)[0]}"
    api("POST", "/api/2.0/workspace/mkdirs", {"path": folder})
    api("POST", "/api/2.0/workspace/import", {"path": nb_path, "format": "SOURCE", "language": "SQL", "overwrite": True,
        "content": base64.b64encode((ROOT / "databricks" / D["notebook_file"]).read_bytes()).decode()})
    ser = (ROOT / "databricks" / D["dashboard_file"]).read_text()
    name = D["dashboard_name"]
    existing, tok = [], None
    while True:
        q = "/api/2.0/lakeview/dashboards?page_size=200" + (f"&page_token={tok}" if tok else "")
        r = api("GET", q)
        existing += [d for d in r.get("dashboards", []) if d.get("display_name") == name and d.get("lifecycle_state") != "TRASHED"]
        tok = r.get("next_page_token")
        if not tok:
            break
    if existing:
        d = api("PATCH", f"/api/2.0/lakeview/dashboards/{existing[0]['dashboard_id']}",
                {"display_name": name, "serialized_dashboard": ser, "warehouse_id": WH})
    else:
        d = api("POST", "/api/2.0/lakeview/dashboards",
                {"display_name": name, "parent_path": folder, "serialized_dashboard": ser, "warehouse_id": WH})
    did = d["dashboard_id"]
    pub = api("POST", f"/api/2.0/lakeview/dashboards/{did}/published", {"warehouse_id": WH, "embed_credentials": True})
    got = api("GET", f"/api/2.0/lakeview/dashboards/{did}/published")
    # export back
    exp = api("GET", f"/api/2.0/workspace/export?path={urllib.parse.quote(nb_path)}&format=SOURCE")
    (ROOT / "databricks" / D["notebook_file"]).write_bytes(base64.b64decode(exp["content"]))
    full = api("GET", f"/api/2.0/lakeview/dashboards/{did}")
    (ROOT / "databricks" / D["dashboard_file"]).write_text(json.dumps(json.loads(full["serialized_dashboard"]), indent=1) + "\n")
    info = {"dashboard_name": name, "dashboard_path": full.get("path"), "published": bool(got.get("revision_create_time")),
            "published_at_utc": got.get("revision_create_time"), "notebook_path": nb_path, "folder": folder}
    print(info)
    return info


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--skip", nargs="*", default=[]); a = ap.parse_args()
    WH = warehouse_id()
    OUT.mkdir(parents=True, exist_ok=True)
    runf = OUT / "databricks_run.json"
    state = json.loads(runf.read_text()) if runf.exists() else {}
    state["warehouse"] = WAREHOUSE_NAME
    state["schema"] = f"workspace.{SCHEMA}"
    if "upload" not in a.skip:
        state["upload"] = upload()
    if "run" not in a.skip:
        t0 = time.time(); state["statements"] = run(); state["run_secs"] = round(time.time() - t0, 1)
        state["run_finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    if "compare" not in a.skip:
        c = compare(); state["all_row_counts_match"] = c["all_row_counts_match"]
        state["row_counts"] = {x["table"]: x["databricks_rows"] for x in c["row_counts"]}
        cols, r = sql("SELECT * FROM dq_assertions ORDER BY check_name")
        state["assertions"] = [dict(zip(cols, x)) for x in r]
    if "publish" not in a.skip:
        state["dashboard"] = publish()
    runf.write_text(json.dumps(state, indent=1) + "\n")
