#!/usr/bin/env python3
"""Download the full Diabetes 130-US Hospitals dataset (UCI id 296) into data/raw_full/ and verify SHA-256.

UCI page : https://archive.ics.uci.edu/dataset/296/diabetes+130-us+hospitals+for+years+1999-2008
Kaggle   : https://www.kaggle.com/datasets/brandao/diabetes
Licence  : Creative Commons Attribution 4.0 International (CC BY 4.0)
Citation : Strack B. et al. (2014) "Impact of HbA1c Measurement on Hospital Readmission Rates: Analysis of 70,000
           Clinical Database Patient Records", BioMed Research International, 781670.
"""
import hashlib, io, pathlib, urllib.request, zipfile

URL = "https://archive.ics.uci.edu/static/public/296/diabetes+130-us+hospitals+for+years+1999-2008.zip"
SHA256 = {
    "diabetic_data.csv": "0689e7ec031237dc63031b938805c48377748761a3b26acab621567afa24df97",
    "IDS_mapping.csv": "f1bb82b471cb34649352597572c9b1fb00bd27f77b9f5a22a03dc3eb1039749e",
}
out = pathlib.Path(__file__).resolve().parents[1] / "data" / "raw_full"
out.mkdir(parents=True, exist_ok=True)
if not all((out / f).exists() for f in SHA256):
    print("downloading", URL)
    with urllib.request.urlopen(URL, timeout=300) as r:
        z = zipfile.ZipFile(io.BytesIO(r.read()))
    for f in SHA256:
        (out / f).write_bytes(z.read(f))
bad = 0
for f, h in SHA256.items():
    got = hashlib.sha256((out / f).read_bytes()).hexdigest()
    print(f"{f:22s} {(out / f).stat().st_size:>11,d} bytes  {'OK' if got == h else 'CHECKSUM MISMATCH ' + got}")
    bad += got != h
raise SystemExit(1 if bad else 0)
