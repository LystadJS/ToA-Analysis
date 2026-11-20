"""Reconcile every record in the finished atlas with the two live PostgreSQL databases."""
import base64
from collections import Counter, defaultdict
import csv
from hashlib import sha256
from decimal import Decimal
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import zlib


def parse(text):
    return json.loads(text, parse_float=Decimal)


def query(database, sql):
    command = ["psql", "-XqAt", "-v", "ON_ERROR_STOP=1", "-d", database,
               "-c", f"SELECT row_to_json(t) FROM ({sql}) t"]
    with subprocess.Popen(command, stdout=subprocess.PIPE, encoding="utf-8") as process:
        for line in process.stdout:
            yield parse(line)
        if process.wait():
            raise RuntimeError(f"Query failed in {database}")


def read_snapshot(path):
    match = re.search(r'<script id="snapshot" type="application/json">(.*?)</script>',
                      path.read_text(encoding="utf-8"), re.DOTALL)
    assert match, "No embedded database snapshot"
    return parse(match[1])


def verify_contributors(snap, countries):
    panel = snap["contributors"]
    manifest = list(csv.DictReader(Path("data/atlas_sources.tsv").open(), delimiter="\t"))
    assert [panel["source"]] == manifest
    path = Path("data/cache") / manifest[0]["file_name"]
    assert sha256(path.read_bytes()).hexdigest() == manifest[0]["sha256"]
    expected = defaultdict(lambda: [0, 0, 0])
    benchmarks = Counter()

    def add(code, source, year, actor, amount):
        for scope in (code, "ALL"):
            cell = expected[(scope, source, year, actor)]
            cell[2] += 1
            if amount is not None:
                cents = amount * 100
                assert cents == int(cents)
                cell[0] += int(cents)
                cell[1] += 1

    with path.open() as stream:
        for r in csv.DictReader(stream):
            code = "XKX" if r["Country Code"] == "CS-KM" else r["Country Code"]
            if code in countries and r["Transaction Type Name"] == "Disbursements":
                add(code, "funding_agency", int(r["Fiscal Year"]), r["Funding Agency Name"], Decimal(r["current_amount"]))
    for r in query("toa_us", """
        SELECT iso3, source_id, flow_year, actor, usd FROM toa.program p JOIN toa.finance f
        ON p.id=f.program_id WHERE eligible_for_summary AND
        ((source_id='us_sector_review' AND measure='disbursement')
         OR (source_id='greenbook' AND measure='obligation' AND period_ref<>'1976 transition quarter')
         OR (source_id='dfc' AND measure='commitment or exposure' AND flow_year IS NOT NULL)
         OR (source_id='ppi' AND measure='sponsor equity commitment')
         OR (source_id='gates' AND measure='private grant commitment'))
    """):
        if r["source_id"] == "us_sector_review":
            for scope in (r["iso3"], "ALL"):
                benchmarks[scope, r["flow_year"]] += int(r["usd"] * 100)
        else:
            add(r["iso3"], r["source_id"], r["flow_year"], r["actor"] or "Unspecified contributor", r["usd"])

    # EXIM uses the named export market and noncancelled approvals. It is a
    # separate authorization measure, including the partial FY2025.
    for r in query("toa_us", "SELECT * FROM toa.us_contribution WHERE source_id='exim'"):
        for scope in (r["iso3"], "ALL"):
            cell = expected[scope, "exim", r["year"], r["actor"]]
            cell[0] += r["cents"] or 0
            cell[1] += r["known"]
            cell[2] += r["records"]

    exim_manifest = next(r for r in snap["sources"] if r["source_id"] == "exim")
    exim_path = Path("data/cache") / exim_manifest["file_name"]
    assert sha256(exim_path.read_bytes()).hexdigest() == exim_manifest["sha256"]
    with exim_path.open(encoding="utf-8-sig", newline="") as stream:
        source_deals = {
            r["Unique Identifier"]: r for r in csv.DictReader(stream)
            if r["Decision"] == "Approved" and r["Deal Cancelled"] == "No"
        }
    observed = {}
    combined = {}
    for scope, blob in panel["scopes"].items():
        data = parse(zlib.decompress(base64.b64decode(blob), wbits=47))
        cents = Counter()
        counts = Counter()
        for row in data["exim"]:
            original = source_deals[row["id"]]
            name = next((original[field].strip() for field in (
                "Primary Borrower", "Primary Source of Repayment (PSOR)", "Primary Applicant"
            ) if original[field].strip() not in ("", "NA", "N/A", "Unknown", "Various")), original["Deal Number"])
            assert row["deal"] == original["Deal Number"] and row["name"] == name, row["id"]
            assert row["cents"] == Decimal(original["Approved/Declined Amount"].replace(",", "")) * 100
            assert row["year"] == int(original["Fiscal Year"])
            assert scope == "ALL" or row["iso3"] == scope
            target = combined if scope == "ALL" else observed
            assert row["id"] not in target
            target[row["id"]] = row
            cents[row["year"]] += row["cents"]
            counts[row["year"]] += 1
        grouped = {r["year"]: r for r in data["rows"] if r["source"] == "exim"}
        assert set(grouped) == set(counts)
        assert all((grouped[y]["cents"], grouped[y]["records"]) == (cents[y], counts[y]) for y in grouped)
    assert observed == combined and len(observed) == 11609
    print("All 11,609 named EXIM authorization records reconcile to the pinned source and contributor totals.")

    assert set(panel["scopes"]) == set(countries) | {"ALL"}
    for scope, blob in panel["scopes"].items():
        data = parse(zlib.decompress(base64.b64decode(blob), wbits=47))
        for r in data["rows"]:
            key = scope, r["source"], r["year"], r["actor"]
            amount, known, count = expected.pop(key)
            assert (r["cents"], r["known"], r["records"]) == (amount if known else None, known, count), key
        for b in data["benchmark"]:
            assert b["total_cents"] == benchmarks.pop((scope, b["year"]))
    assert not expected and not benchmarks
    print("Every contributor amount, disclosure count and comparison total matches its source for all 250 recipients and the combined scope.")


def verify_relationship_profiles(snap, countries):
    profiles = snap["profiles"]
    assert set(profiles) == set(countries)
    relationship_rows = {(r["iso3"], r["source_id"], r["name"]): r
                         for r in query("toa_us", "SELECT * FROM toa.us_relationship")}
    goods = {(r["iso3"], r["year"]): r for r in query("toa_us", """
        SELECT iso3,year,sum(imports_usd) AS imports_usd,sum(exports_usd) AS exports_usd
        FROM toa.us_goods_trade GROUP BY iso3,year
    """)}
    for code, profile in profiles.items():
        for r in profile["agreements"] + profile["organizations"]:
            expected = relationship_rows.pop((code, r["source_id"], r["name"]))
            assert r.keys() == expected.keys()
            for key in expected:
                if key == "detail" and r["source_id"] == "agoa":
                    assert r[key].startswith(expected[key])
                else:
                    assert r[key] == expected[key], (code, key, r[key], expected[key])
        for r in profile["goods"]:
            db = goods.pop((code, r["year"]))
            assert all(db[key] == r[key] for key in ("year","exports_usd","imports_usd"))
        assert profile["trade"] and profile["assessment"]
        bundle = parse(zlib.decompress(base64.b64decode(snap["bundles"][code]), wbits=47))
        results = {r["id"] for r in bundle["result"] if r["provider"] == "USA"}
        assert all(r["id"] in results and r["citation"] for r in profile["evidence"])
    assert not relationship_rows and not goods
    print("All 250 overview profiles match the U.S. relationship and bilateral goods tables; every displayed U.S. result resolves to its country record.")


def verify_evaluation_bundles(snap, countries):
    tables = {"programs": "evaluation_program", "reports":"evaluation_report", "searches":"evaluation_search",
              "findings":"evaluation_finding"}
    assert set(snap["evaluations"]) == set(countries)
    rows = {key: defaultdict(list) for key in tables}
    for key, table in tables.items():
        sql = f"SELECT * FROM toa.{table}"
        if key == "findings":
            sql = "SELECT r.iso3,r.project_key,f.* FROM toa.evaluation_finding f JOIN toa.evaluation_report r USING(report_id)"
        for r in query("toa_us",sql):
            rows[key][r["iso3"]].append(r)
    def sorted_rows(records):
        return sorted(records,key=lambda r: (r.get("project_key",""),r.get("source_id",""),r.get("report_id",""),r.get("sequence",0)))
    for code, blob in snap["evaluations"].items():
        dossier = parse(zlib.decompress(base64.b64decode(blob), wbits=47))
        for key in tables:
            assert sorted_rows(dossier[key]) == sorted_rows(rows[key][code]), (code,key)
    print("All 250 Results pages reconcile with the financing priorities, searches, reports and findings in PostgreSQL.")


def main(path):
    snap = read_snapshot(path)
    countries = {c["iso3"]: c for c in snap["countries"]}
    verify_evaluation_bundles(snap, countries)
    verify_contributors(snap, countries)
    verify_relationship_profiles(snap, countries)
    sources = {s["source_id"]: s for s in snap["sources"]}
    tables = {"program": ("id",), "finance": ("program_id", "measure", "period_ref"),
              "result": ("id",), "context": ("iso3", "source_id", "year")}
    rows = {name: {} for name in tables}
    assert set(countries) == set(snap["bundles"])
    for code, blob in snap["bundles"].items():
        data = parse(zlib.decompress(base64.b64decode(blob), wbits=47))
        assert set(data) == set(tables)
        donors = Counter(row["provider"] for row in data["program"])
        assert (countries[code]["us"], countries[code]["cn"]) == (donors["USA"], donors["CHN"])
        for table, keys in tables.items():
            for row in data[table]:
                assert row["iso3"] == code
                key = (row.pop("provider", None), *(row[k] for k in keys))
                assert key not in rows[table], (table, key)
                rows[table][key] = row

    queries = {
        "program": "SELECT * FROM toa.program",
        "finance": "SELECT p.iso3, f.* FROM toa.finance f JOIN toa.program p ON p.id=f.program_id",
        "result": "SELECT p.iso3, r.* FROM toa.result r JOIN toa.program p ON p.id=r.program_id",
        "context": "SELECT * FROM toa.context",
    }
    all_sources = set()
    counts = Counter()
    for provider, database in [("USA", "toa_us"), ("CHN", "toa_china")]:
        registry = list(query(database, "SELECT * FROM toa.country"))
        assert set(countries) == {r["iso3"] for r in registry}
        for row in registry:
            assert all(countries[row["iso3"]][k] == v for k, v in row.items())
        stakes = query(database, """
            SELECT p.iso3, sum(f.usd) AS disclosed, bool_and(f.usd IS NOT NULL) AS complete
            FROM toa.program p JOIN toa.finance f ON p.id=f.program_id
            WHERE p.source_id='ppi' AND f.eligible_for_summary GROUP BY p.iso3
        """)
        stakes = list(stakes)
        equity = {row["iso3"]: row["disclosed"] for row in stakes}
        complete = {row["iso3"]: row["complete"] for row in stakes}
        field = "us_equity" if provider == "USA" else "cn_equity"
        assert all(c[field] == equity.get(code) for code, c in countries.items())
        assert all(c[field + "_complete"] == complete.get(code) for code, c in countries.items())
        for row in query(database, "SELECT * FROM toa.source"):
            all_sources.add(row["source_id"])
            assert sources[row["source_id"]] == row
        expected = list(query(database, "SELECT * FROM toa.exclusions ORDER BY source_id,reason,label"))
        assert [dict(provider=provider, **r) for r in expected] == [
            r for r in snap["exclusions"] if r["provider"] == provider
        ]
        for table, keys in tables.items():
            for row in query(database, queries[table]):
                key = (None if table == "context" else provider, *(row[k] for k in keys))
                actual = rows[table][key]
                if row != actual:
                    mismatch = {k: (v, actual.get(k)) for k, v in row.items() if v != actual.get(k)}
                    # R and browser charts use double precision for measured indicators and days.
                    # Every financial amount, key, source field and missing value must match exactly.
                    for field, (database_value, browser_value) in mismatch.items():
                        assert field in {"baseline", "actual", "target", "days"} and (
                            isinstance(database_value, (Decimal, int)) and
                            isinstance(browser_value, (Decimal, int)) and
                            math.isclose(database_value, browser_value, rel_tol=5e-15)
                        ), (database, table, key, field, database_value, browser_value)
                    assert set(actual) == set(row)
                counts[table] += 1
    assert all_sources == set(sources)
    for table, index in rows.items():
        assert counts[table] == len(index) * (2 if table == "context" else 1)
    print(f"{len(countries)} country dossiers reconcile with PostgreSQL, including all "
          + ", ".join(f"{len(index):,} {table} records" for table, index in rows.items())
          + f", {len(sources)} sources and {len(snap['exclusions'])} country-matching exclusions.")


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "artifacts/Trade-over-Aid-Atlas.html"))
