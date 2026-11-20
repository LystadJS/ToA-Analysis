from pathlib import Path
import hashlib, os, shutil, subprocess, tempfile, zipfile
base=Path.cwd()
art=base/'artifacts'
dst=Path('/workspace/shared/downloads')
local=art/'verified-release'
html='Trade-over-Aid-Atlas.html'
code='Trade-over-Aid-source.zip'
release='Trade-over-Aid-release.zip'
manifest='Release-SHA256SUMS'
verification='Verification.txt'
def digest(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
with tempfile.TemporaryDirectory(dir=art) as tmp:
    stage=Path(tmp)
    files={}
    for line in (dst/manifest).read_text().splitlines():
        given,name=line.split('  ',1)
        assert digest(dst/name)==given,name
        files[name]=dst/name
    commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
    subprocess.run(['git','archive','--format=zip','--prefix=ToA-Analysis/','-o',str(stage/code),commit],check=True)
    with zipfile.ZipFile(stage/code) as z:
        assert z.testzip() is None and 'ToA-Analysis/data/atlas_sources.tsv' in z.namelist()
    files[html]=art/html
    files[code]=stage/code
    data=Path('/tmp/toa-ui-final-data.log').read_text()
    browser=Path('/tmp/toa-ui-final-browser.log').read_text()
    assert 'combined scope' in data and 'Chromium desktop and offline mobile checks passed' in browser
    note=(dst/verification).read_text()
    (stage/verification).write_text(note+'\nU.S. contributor atlas and source commit '+commit+'\n'+data+browser)
    files[verification]=stage/verification
    checks={n:digest(p) for n,p in files.items()}
    (stage/manifest).write_text(''.join(f'{checks[n]}  {n}\n' for n in sorted(files)))
    files[manifest]=stage/manifest
    with zipfile.ZipFile(stage/release,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for n,p in files.items():z.write(p,n)
    with zipfile.ZipFile(stage/release) as z:
        assert set(z.namelist())==set(files)
        for n,p in files.items():
            with z.open(n) as f:assert hashlib.file_digest(f,'sha256').hexdigest()==digest(p),n
    files[release]=stage/release
    for folder in (local,dst):
        for n in (html,code,verification,manifest,release):
            with tempfile.NamedTemporaryFile(dir=folder,delete=False) as f:
                with files[n].open('rb') as src:shutil.copyfileobj(src,f)
                temp=Path(f.name)
            assert digest(temp)==digest(files[n])
            os.replace(temp,folder/n)
print('Atlas, source archive, checksums and full release published to shared downloads.')
