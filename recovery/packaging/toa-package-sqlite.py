from pathlib import Path
import hashlib, os, shutil, subprocess, tempfile, zipfile

root=Path.cwd()
art=root/'artifacts'
release=art/'verified-release'
downloads=Path('/workspace/shared/downloads')
full='Trade-over-Aid-release.zip'
source='Trade-over-Aid-source.zip'
small='Trade-over-Aid-SQLite.zip'
mirrors=['toa_us.sqlite','toa_china.sqlite','SQLite-SHA256SUMS']
def sha(file):
    return hashlib.file_digest(file,'sha256').hexdigest()
def checksum(path):
    with path.open('rb') as f:return sha(f)
def pack(dest,files):
    with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for name,path in files.items():z.write(path,name)
    with zipfile.ZipFile(dest) as z:
        assert z.testzip() is None
        for n,p in files.items():
            with z.open(n) as reader:assert sha(reader)==checksum(p),n
def install(path,folder):
    target=folder/path.name
    # Copy and validate in the destination filesystem before replacing a released name.
    with tempfile.NamedTemporaryFile(dir=folder,delete=False) as f:
        with path.open('rb') as src:shutil.copyfileobj(src,f)
        temp=Path(f.name)
    assert checksum(temp)==checksum(path)
    os.replace(temp,target)
with tempfile.TemporaryDirectory(dir=art) as work:
    w=Path(work)
    manifest='Release-SHA256SUMS'
    previous={}
    for line in (downloads/manifest).read_text().splitlines():
        digest,n=line.split('  ',1)
        assert checksum(downloads/n)==digest,n
        previous[n]=downloads/n
    # Keep the release's already-verified PostgreSQL backups byte for byte.
    for name in ['toa_us.dump','toa_china.dump']:
        assert checksum(art/name)==checksum(previous[name])
    commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
    subprocess.run(['git','archive','--format=zip','--prefix=ToA-Analysis/','-o',str(w/source),commit],check=True)
    with zipfile.ZipFile(w/source) as z:
        assert 'ToA-Analysis/scripts/build-sqlite.sh' in z.namelist() and z.testzip() is None
    run=Path('/tmp/toa-mirror-restored.log').read_text()
    assert '47 checks passed' in run and run.count('base rows across 7 tables and 5 reporting views')==2
    report=(downloads/'Verification.txt').read_text().replace('Release commit ','PostgreSQL evidence release commit ',1)
    (w/'Verification.txt').write_text(report+'\nSQLite mirror and source commit '+commit+'\n'+
        'Every base and view row matched both live PostgreSQL and restored release dumps.\n'+
        Path('/tmp/toa-mirror-finished.log').read_text()+Path('/tmp/toa-mirror-portable.log').read_text())
    files={**previous,source:w/source,'Verification.txt':w/'Verification.txt',**{n:art/n for n in mirrors}}
    (w/manifest).write_text(''.join(f'{checksum(files[n])}  {n}\n' for n in sorted(files)))
    pack(w/small,{n:art/n for n in mirrors})
    pack(w/full,{**files,manifest:w/manifest})
    for n in [source,'Verification.txt',*mirrors,manifest,small,full]:
        p=art/n if n in mirrors else w/n
        for directory in [release,downloads]:install(p,directory)
print('Packaged and checksum-verified both archives and standalone files.')
