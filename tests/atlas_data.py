"""Reconcile every record in the finished atlas with the two live PostgreSQL databases."""
import base64
from collections import Counter
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


def main(path):
    snap = read_snapshot(path)
    countries = {c["iso3"]: c for c in snap["countries"]}
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
            SELECT p.iso3, sum(f.usd) AS disclosed
            FROM toa.program p JOIN toa.finance f ON p.id=f.program_id
            WHERE p.source_id='ppi' AND f.eligible_for_summary GROUP BY p.iso3
        """)
        equity = {row["iso3"]: row["disclosed"] for row in stakes}
        field = "us_equity" if provider == "USA" else "cn_equity"
        assert all(c[field] == equity.get(code) for code, c in countries.items())
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
