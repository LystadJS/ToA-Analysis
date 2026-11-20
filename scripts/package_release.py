#!/usr/bin/env python3
"""Package a built and validated release with the exact committed project source."""

import argparse
import csv
from hashlib import file_digest
from pathlib import Path
import subprocess
import tempfile
import zipfile


DATABASES = (
    "toa_us.dump", "toa_china.dump", "SHA256SUMS",
    "toa_us.sqlite", "toa_china.sqlite", "SQLite-SHA256SUMS",
)
BRIEF_FILES = {
    "annual_finance.csv", "bilateral_goods.csv", "brief.md", "country.pdf",
    "coverage.csv", "evaluation_findings.csv", "evaluation_programs.csv",
    "finance.csv", "programs.csv", "results.csv", "trade_context.csv",
    "us_contributions.csv", "us_relationships.csv",
}
AUDIT_FILES = (
    "Country-year-coverage.pdf", "US-spending-coverage.png",
    "chinese-payment-evidence.csv", "country-year-observations.csv",
    "kenya-register-checks.csv", "missing_commitments.csv", "missing_stakes.csv",
    "series-coverage.csv", "undated_results.csv", "us-country-year-reconciliation.csv",
    "us-greenbook-reconciliation.csv", "us-national-reconciliation.csv",
    "us-outside-registry.csv",
)
REVIEW_FILES = ("programs.csv", "searches.csv", "reports.csv", "findings.csv")


def digest(path):
    with path.open("rb") as stream:
        return file_digest(stream, "sha256").hexdigest()


def create_zip(destination, files):
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for name, path in sorted(files.items()):
            archive.write(path, name)
    with zipfile.ZipFile(destination) as archive:
        if set(archive.namelist()) != set(files) or archive.testzip() is not None:
            raise ValueError(f"Invalid archive {destination}")
        for name, path in files.items():
            with archive.open(name) as stream:
                if file_digest(stream, "sha256").hexdigest() != digest(path):
                    raise ValueError(f"Archive member differs from {path}")


def git(*args):
    return subprocess.check_output(["git", *args])


def create_source(destination, commit):
    subprocess.run(["git", "archive", "--format=zip", "--prefix=ToA-Analysis/",
                    "-o", str(destination), commit], check=True)
    entries = git("ls-tree", "-rz", commit).split(b"\0")
    expected = set()
    with zipfile.ZipFile(destination) as archive:
        for entry in filter(None, entries):
            metadata, raw_name = entry.split(b"\t", 1)
            mode, kind, oid = metadata.decode().split()
            name = "ToA-Analysis/" + raw_name.decode()
            expected.add(name)
            flags = archive.getinfo(name).external_attr >> 16
            if archive.read(name) != git("cat-file", kind, oid) or bool(flags & 0o111) != bool(int(mode, 8) & 0o111):
                raise ValueError(f"Archived source differs from {commit}: {name}")
        if {item.filename for item in archive.infolist() if not item.is_dir()} != expected:
            raise ValueError("Archived source file list differs from Git")


def package(artifacts, output, verification):
    if git("status", "--porcelain"):
        raise ValueError("Commit the feature source before packaging it")
    commit = git("rev-parse", "HEAD").decode().strip()
    for name in ("SHA256SUMS", "SQLite-SHA256SUMS"):
        subprocess.run(["sha256sum", "-c", name], cwd=artifacts, check=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent) as tmp:
        stage = Path(tmp)
        files = {name: artifacts / name for name in DATABASES + ("Trade-over-Aid-Atlas.html",)}
        files["Trade-over-Aid-coverage.html"] = artifacts / "coverage/Trade-over-Aid-coverage.html"
        for name in AUDIT_FILES:
            files[f"audit/{name}"] = artifacts / "coverage" / name
        for name in ("philippines_registration.csv", "philippines_registration.pdf"):
            files[f"audit/{name}"] = artifacts / name
        for name in REVIEW_FILES:
            files[f"evaluation-review/{name}"] = artifacts / "evaluation-review" / name
        countries = artifacts / "countries"
        with (countries / "coverage.csv").open(newline="") as stream:
            codes = {row["iso3"] for row in csv.DictReader(stream)}
        if len(codes) != 250 or {p.name for p in countries.iterdir() if p.is_dir()} != codes:
            raise ValueError("Expected exactly 250 country brief directories")
        brief_files = {name: countries / name for name in ("coverage.csv", "index.md")}
        for code in sorted(codes):
            available = {path.name for path in (countries / code).iterdir() if path.is_file()}
            if available != BRIEF_FILES:
                raise ValueError(f"Brief file list differs for {code}")
            brief_files.update({f"{code}/{name}": countries / code / name for name in available})
        briefs_zip = stage / "Trade-over-Aid-country-briefs.zip"
        create_zip(briefs_zip, brief_files)
        files[briefs_zip.name] = briefs_zip
        source_zip = stage / "Trade-over-Aid-source.zip"
        create_source(source_zip, commit)
        files[source_zip.name] = source_zip
        build_record = stage / "Verification.txt"
        build_record.write_text(f"Source commit {commit}\n\n" + verification.read_text())
        files[build_record.name] = build_record
        manifest = stage / "Release-SHA256SUMS"
        manifest.write_text("".join(f"{digest(path)}  {name}\n" for name, path in sorted(files.items())))
        files[manifest.name] = manifest
        pending = stage / output.name
        create_zip(pending, files)
        pending.replace(output)
    print(f"{digest(output)}  {output} ({output.stat().st_size:,} bytes)")


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--artifacts", type=Path, default=Path("artifacts"))
    cli.add_argument("--output", type=Path, default=Path("artifacts/Trade-over-Aid-release.zip"))
    cli.add_argument("--verification", type=Path, required=True,
                     help="Plain-text summary of actual tests run against these artifacts")
    args = cli.parse_args()
    package(args.artifacts.resolve(), args.output.resolve(), args.verification.resolve())
