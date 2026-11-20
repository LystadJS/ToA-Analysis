from pathlib import Path
import hashlib, os, shutil, subprocess, tempfile, zipfile

root = Path.cwd()
art = root/"artifacts"
shared = Path("/workspace/shared/downloads")
local = art/"verified-release"
manifest = "Release-SHA256SUMS"
bundle = "Trade-over-Aid-release.zip"

def digest(path):
    with path.open("rb") as f:
        return hashlib.file_digest(f,"sha256").hexdigest()

def write_zip(path,paths):
    with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for name,file in sorted(paths.items()):
            z.write(file,name)
    with zipfile.ZipFile(path) as z:
        assert set(z.namelist())==set(paths)
        for name,file in paths.items():
            with z.open(name) as src: assert hashlib.file_digest(src,"sha256").hexdigest()==digest(file),name

with tempfile.TemporaryDirectory(dir=art) as tmp:
    stage=Path(tmp)
    parts={}
    for line in (shared/manifest).read_text().splitlines():
        sha,name=line.split("  ",1)
        assert digest(shared/name)==sha,name
        parts[name]=shared/name
    commit=subprocess.check_output(["git","rev-parse","HEAD"], text=True).strip()
    name="Trade-over-Aid-source.zip"
    subprocess.run(["git","archive","--format=zip","--prefix=ToA-Analysis/","-o",str(stage/name),commit],check=True)
    with zipfile.ZipFile(stage/name) as z:
        assert z.testzip() is None and "ToA-Analysis/data/usun_roster.tsv" in z.namelist()
    parts[name]=stage/name
    for name in ("Trade-over-Aid-Atlas.html","toa_us.dump","toa_china.dump","toa_us.sqlite","toa_china.sqlite","SHA256SUMS","SQLite-SHA256SUMS"):
        parts[name]=art/name
    parts["Trade-over-Aid-coverage.html"]=art/"coverage/Trade-over-Aid-coverage.html"
    name="Trade-over-Aid-country-briefs.zip"
    country=art/"countries"
    files={str(p.relative_to(country)):p for p in country.rglob("*") if p.is_file()}
    assert len(files)==250*11+2,len(files)
    write_zip(stage/name,files)
    parts[name]=stage/name
    name="Trade-over-Aid-audit-evidence.zip"
    extras={f'sources/{f}':root/'data'/f for f in ['relationship_sources.tsv','relationship_local_sources.tsv','atlas_sources.tsv','us_fta_partners.tsv','us_free_association.tsv','usun_roster.tsv']}
    extra_dir=stage/'audit'
    with zipfile.ZipFile(shared/name) as z: z.extractall(extra_dir)
    files={str(p.relative_to(extra_dir)):p for p in extra_dir.rglob("*") if p.is_file()}
    files.update(extras)
    files['Coverage.md']=root/'docs/Coverage.md'
    files['figures/US-spending-coverage.png']=art/'coverage/US-spending-coverage.png'
    write_zip(stage/name,files)
    parts[name]=stage/name
    sqlite="Trade-over-Aid-SQLite.zip"
    write_zip(stage/sqlite,{n:parts[n] for n in ("toa_us.sqlite","toa_china.sqlite","SQLite-SHA256SUMS")})
    summary=["Country relationships release "+commit, ""]
    for log,checks in [
        ('data-final',["All 250 overview profiles","250 country dossiers"]),
        ('brief-qa',["All 250 briefs","23 jurisdictions"]),
        ('browser-final',["Chromium desktop"]),('audit-release',["6250","all 250 jurisdictions"]),
        ('coverage-ui',["Offline Chromium"]),('print',["All 250 country PDFs"]),
        ('restored-final',["47 checks passed","11,609 EXIM","342546 base rows","52864 base rows"])]:
        output=Path('/tmp/relations-'+log+'.log').read_text()
        assert all(q in output for q in checks),(log,checks)
        summary.extend([l for l in output.splitlines() if len(l)>16 and not l.startswith("PASS ")])
    summary.extend(["", "The USUN roster is the user-supplied transcription of 19 November 2026. The live page returned HTTP 403.",
                    "Both archived EXIM copies have identical analysis fields across all 51,753 source identifiers. The reports include 11,609 noncancelled approved authorizations assigned to named foreign markets."])
    (stage/'Verification.txt').write_text('\n'.join(summary)+'\n')
    parts['Verification.txt']=stage/'Verification.txt'
    (stage/manifest).write_text(''.join(f'{digest(file)}  {name}\n' for name,file in sorted(parts.items())))
    parts[manifest]=stage/manifest
    write_zip(stage/bundle,parts)
    parts[bundle]=stage/bundle
    parts[sqlite]=stage/sqlite
    for dest in (local,shared):
        for name,src in parts.items():
            if src==shared/name: continue
            with tempfile.NamedTemporaryFile(dir=dest,delete=False) as f, src.open('rb') as original:
                shutil.copyfileobj(original,f)
                temp=Path(f.name)
            assert digest(temp)==digest(src)
            os.replace(temp,dest/name)
        for hashes in ('SHA256SUMS','SQLite-SHA256SUMS',manifest):
            subprocess.run(['sha256sum','--quiet','-c',hashes],check=True,cwd=dest)
print('Packaged and checksum-verified the atlas, all 250 country bundles, restored PostgreSQL backups, SQLite mirrors, audit, and source release.')
