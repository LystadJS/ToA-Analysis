import hashlib
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path.cwd()
art = root / "artifacts"
shared = Path("/workspace/shared/downloads")
manifest = "Release-SHA256SUMS"
release = "Trade-over-Aid-release.zip"
verification = "Verification.txt"
code = "Trade-over-Aid-source.zip"
briefs = "Trade-over-Aid-country-briefs.zip"
audit = "Trade-over-Aid-audit-evidence.zip"

def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def update_archive(name, patches):
    with ZipFile(shared / name) as old, ZipFile(stage / name, "w", ZIP_DEFLATED) as new:
        assert set(patches) <= set(old.namelist())
        for member in old.namelist():
            if member in patches:
                new.write(patches[member], member)
            else:
                new.writestr(member, old.read(member))
    with ZipFile(stage / name) as new, ZipFile(shared / name) as old:
        assert new.testzip() is None
        assert new.namelist() == old.namelist()
        for member in new.namelist():
            if member in patches:
                assert new.read(member) == patches[member].read_bytes(), member
            else:
                assert new.read(member) == old.read(member), member

with tempfile.TemporaryDirectory(dir=art) as tmp:
    stage = Path(tmp)
    files = {}
    for line in (shared / manifest).read_text().splitlines():
        checksum, name = line.split("  ",1)
        assert digest(shared / name) == checksum
        files[name] = shared / name
    visuals = [art / "Trade-over-Aid-Atlas.html", art / "philippines_registration.pdf",
               *(art / "coverage" / name for name in ("Trade-over-Aid-coverage.html","Country-year-coverage.pdf","US-spending-coverage.png"))]
    files.update({path.name: path for path in visuals})
    country_plots = {f"{f.parent.name}/country.pdf": f for f in (art / "countries").glob("???/country.pdf")}
    assert len(country_plots) == 250
    update_archive(briefs, country_plots)
    update_archive(audit, {"figures/US-spending-coverage.png": files["US-spending-coverage.png"]})
    commit = subprocess.check_output(["git","rev-parse","HEAD"],text=True).strip()
    subprocess.run(["git","archive","--format=zip","--prefix=ToA-Analysis/","-o",str(stage / code),commit],check=True)
    with ZipFile(stage / code) as repo:
        assert repo.testzip() is None
        assert "ToA-Analysis/R/plot_theme.R" in repo.namelist()
        assert len([n for n in repo.namelist() if n.endswith(".ttf")]) == 3
    summary = ["Visualization release and source commit "+commit]
    for log, phrase in [
        ("print", "All 250 country PDFs"), ("atlas-browser","Chromium desktop"),
        ("coverage-browser","Offline Chromium checks passed"), ("data","250 country dossiers"),
        ("audit","all 250 jurisdictions")]:
        output = Path("/tmp/toa-theme-"+log+".log").read_text()
        assert phrase in output, log
        summary.extend(line for line in output.strip().splitlines() if len(line)>15)
    (stage / verification).write_text((shared / verification).read_text()+"\n"+"\n".join(summary)+"\n")
    for name in (audit,briefs,code,verification):
        files[name] = stage / name
    checks = {name: digest(source) for name,source in files.items()}
    (stage / manifest).write_text("".join(f"{value}  {name}\n" for name,value in sorted(checks.items())))
    files[manifest] = stage / manifest
    with ZipFile(stage / release, "w", ZIP_DEFLATED, compresslevel=6) as combined:
        for name,source in files.items():
            combined.write(source,name)
    with ZipFile(stage / release) as combined:
        assert set(combined.namelist()) == set(files)
        for name,source in files.items():
            with combined.open(name) as f:
                assert hashlib.file_digest(f,"sha256").hexdigest() == digest(source),name
    files[release] = stage / release
    for destination in (art / "verified-release", shared):
        for name, source in files.items():
            if source.parent == shared: continue
            with tempfile.NamedTemporaryFile(dir=destination, delete=False) as f:
                with source.open("rb") as part:
                    shutil.copyfileobj(part, f)
                temp = Path(f.name)
            assert digest(temp) == digest(source)
            os.replace(temp,destination / name)
        subprocess.run(["sha256sum","--quiet","--check",manifest],cwd=destination,check=True)
print("Verified both release directories and every member of the complete release. All 250 bundled country figures match the generated PDFs.")
