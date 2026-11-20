"""Verify that the 250 downloadable dossiers agree with the validated atlas."""
import base64
import csv
from decimal import Decimal
from pathlib import Path
import zlib
from atlas_data import read_snapshot, parse

root = Path("artifacts")
snapshot = read_snapshot(root / "Trade-over-Aid-Atlas.html")
sections = ["U.S. bilateral goods trade", "Trade agreements, preferences and initiatives",
            "U.S. agencies and organizations", "Evidence of benefit from U.S.-linked programs",
            "Financing", "Reported host-country results", "Interpretation"]


def read(folder, name):
    with (folder / name).open() as f:
        return list(csv.DictReader(f))


def number(value):
    return Decimal(value) if value else None


benefits = undated_only = 0
for code, profile in snapshot["profiles"].items():
    folder = root / "countries" / code
    review = parse(zlib.decompress(base64.b64decode(snapshot["evaluations"][code]), wbits=47))
    portfolio = read(folder,"evaluation_programs.csv")
    assert [(int(r["rank"]),r["project_key"],int(r["amount_cents"]),r["status"]) for r in portfolio] == [
        (r["rank"],r["project_key"],r["amount_cents"],r["status"]) for r in review["programs"]],code
    findings = read(folder,"evaluation_findings.csv")
    assert {(r["report_id"],int(r["sequence"]),r["indicator"],number(r["value"]),r["unit"] or None) for r in findings} == {
        (r["report_id"],r["sequence"],r["indicator"],r["value"],r["unit"]) for r in review["findings"]},code
    brief = (folder / "brief.md").read_text()
    assert [line[3:] for line in brief.splitlines() if line.startswith("## ")] == sections, code
    assert profile["trade"] in brief and profile["assessment"] in brief, code
    benefits += bool(profile["evidence"])
    undated_only += profile["undated_monitoring_only"]
    for result in profile["evidence"]:
        assert result["indicator"] in brief and result["statement"] in brief, (code,result["id"])
    actual = read(folder,"bilateral_goods.csv")
    assert [(int(r["year"]),number(r["exports_usd"]),number(r["imports_usd"])) for r in actual] == [
        (r["year"],r["exports_usd"],r["imports_usd"]) for r in profile["goods"]], code
    relations = {(r["source_id"],r["name"],r["status"]) for r in read(folder,"us_relationships.csv")}
    shown = {(r["source_id"],r["name"],r["status"]) for group in ("agreements","organizations") for r in profile[group]}
    assert shown == relations and all(name in brief for _,name,_ in relations), code
    blob = snapshot["contributors"]["scopes"][code]
    chart = parse(zlib.decompress(base64.b64decode(blob),wbits=47))["rows"]
    actual = {(r["source_id"],int(r["year"]),r["actor"],number(r["cents"]),int(r["known"]),int(r["records"]))
              for r in read(folder,"us_contributions.csv")}
    assert actual == {(r["source"],r["year"],r["actor"],r["cents"],r["known"],r["records"]) for r in chart}, code
assert len(snapshot["profiles"]) == 250
print(f"All 250 country evaluation exports match the Results page. All 250 briefs match the atlas narratives, agency register, bilateral trade, and annual contributions. "
      f"{benefits} jurisdictions have a U.S.-linked outcome or output, including {undated_only} with undated monitoring only.")
