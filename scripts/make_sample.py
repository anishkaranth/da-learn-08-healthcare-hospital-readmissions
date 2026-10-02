#!/usr/bin/env python3
"""Build the reproducible raw subset in data/raw/ from data/raw_full/.

Rule (deterministic, no randomness): keep encounters where CAST(encounter_id AS BIGINT) % 691 = 7
(153 of 101,766 encounters, ~0.15 %). Values are copied verbatim as strings (cleaning happens in sql/02).
IDS_mapping.csv (2.5 KB lookup file) is copied in full (CRLF line endings normalised to LF).
"""
import pathlib, duckdb

ROOT = pathlib.Path(__file__).resolve().parents[1]
FULL, OUT = ROOT / "data/raw_full", ROOT / "data/raw"
OUT.mkdir(parents=True, exist_ok=True)
con = duckdb.connect()
con.execute(f"""
COPY (
  SELECT * FROM read_csv('{(FULL / "diabetic_data.csv").as_posix()}', header = true, all_varchar = true)
  WHERE CAST(encounter_id AS BIGINT) % 691 = 7
  ORDER BY CAST(encounter_id AS BIGINT)
) TO '{(OUT / "diabetic_data.csv").as_posix()}' (HEADER, DELIMITER ',')
""")
# copied with CRLF -> LF line endings (git-friendly); content otherwise unchanged
(OUT / "IDS_mapping.csv").write_bytes((FULL / "IDS_mapping.csv").read_bytes().replace(b"\r\n", b"\n"))
n = con.execute(f"SELECT COUNT(*) FROM read_csv('{(OUT / 'diabetic_data.csv').as_posix()}', all_varchar = true)").fetchone()[0]
print("diabetic_data.csv sample rows:", n)
