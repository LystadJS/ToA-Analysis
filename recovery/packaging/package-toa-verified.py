from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
from collections import Counter
from hashlib import sha256
import csv,json,os,shutil,subprocess
root=Path.cwd()
a=root/'artifacts'
out=Path('/workspace/shared/downloads')
staging=a/'verified-release'
staging.mkdir(exist_ok=True)
def command(args):
    return subprocess.check_output(args,text=True)
def scalar_rows(db,sql):
    return json.loads(command(['psql','-XAt','-v','ON_ERROR_STOP=1','-d',db,'-c','SELECT json_agg(x) FROM ('+sql+') x']))
def pack(name,files,strings=None):
    target=staging/name
    with ZipFile(target,'w',ZIP_DEFLATED,compresslevel=6) as z:
        for file,arc in files:z.write(file,str(arc))
        for arc,content in (strings or {}).items():z.writestr(arc,content)
    with ZipFile(target) as z:assert z.testzip() is None, name
countries=a/'countries'
expected={}
for provider,db in [('USA','toa_us'),('CHN','toa_china')]:
    for kind,query in {'programs':'select iso3,count(*) n from toa.program group by 1','finance':'select p.iso3,count(*) n from toa.finance f join toa.program p on p.id=f.program_id group by 1','results':'select p.iso3,count(*) n from toa.result r join toa.program p on p.id=r.program_id group by 1'}.items():
        expected[kind,provider]={x['iso3']:x['n'] for x in scalar_rows(db,query)}
dirs=sorted(p for p in countries.iterdir() if p.is_dir())
assert len(dirs)==250
for folder in dirs:
    for kind in ('programs','finance','results'):
        with (folder/(kind+'.csv')).open() as file: actual=Counter(r['provider'] for r in csv.DictReader(file))
        assert all(actual[p]==expected[kind,p].get(folder.name,0) for p in ('USA','CHN')), (folder,kind,actual)
    assert (folder/'country.pdf').read_bytes().startswith(b'%PDF')
    assert (folder/'brief.md').read_text().startswith('# ')
assert '2025 amounted to $121,259,455' in (countries/'HND/brief.md').read_text()
assert '454,243,778.75' in (countries/'KEN/brief.md').read_text()
pack('Trade-over-Aid-country-briefs.zip',[(p,p.relative_to(countries)) for p in sorted(countries.rglob('*')) if p.is_file()])
for file in ['toa_us.dump','toa_china.dump','Trade-over-Aid-Atlas.html','philippines_registration.pdf','SHA256SUMS']:
    shutil.copyfile(a/file,staging/file)
coverage=a/'coverage'
for file in ['Trade-over-Aid-coverage.html','Country-year-coverage.pdf','US-spending-coverage.png']:
    shutil.copyfile(coverage/file,staging/file)
commit=command(['git','rev-parse','HEAD']).strip()
subprocess.run(['git','archive','--format=zip','--prefix=ToA-Analysis/','-o',str(staging/'Trade-over-Aid-source.zip'),commit],check=True)
with ZipFile(staging/'Trade-over-Aid-source.zip') as z:assert z.testzip() is None
checks='\n'.join(Path('/tmp/'+n).read_text().strip().splitlines()[-1] for n in ['priority-verify-done.log','priority-restore-done.log','priority-atlas-data-final.log','priority-atlas-browser-final.log','priority-coverage-done.log','priority-coverage-browser-done.log'])
readme='Release commit '+commit+'\n\nDatabase integration / restored copies / HTML reconciliation / offline browser / country-year audit / offline audit browser\n'+checks+'\nCountry CSVs for all 250 jurisdictions checked against each provider database by country and table.\n'
files=[(p,'tables/'+p.name) for p in sorted(coverage.glob('*.csv'))]
files += [(a/'philippines_registration.csv','tables/philippines_registration.csv'),(root/'docs/Coverage.md','Coverage.md'),(root/'docs/Evidence.md','Evidence.md'),(root/'data/sources.tsv','sources/database_sources.tsv'),(root/'data/audit_sources.tsv','sources/audit_sources.tsv'),(root/'data/cache/mcc-calendars.csv','sources/mcc-calendars.csv'),(root/'data/cache/kenya-debt-fy2022-23.pdf','sources/kenya-debt-fy2022-23.pdf'),(coverage/'US-spending-coverage.png','figures/US-spending-coverage.png')]
pack('Trade-over-Aid-audit-evidence.zip',files,{'verification.txt':readme})
(staging/'Verification.txt').write_text(readme)
releases=sorted(p for p in staging.iterdir() if p.is_file() and p.name not in {'Trade-over-Aid-release.zip','Release-SHA256SUMS'})
(staging/'Release-SHA256SUMS').write_text(''.join(sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in releases))
pack('Trade-over-Aid-release.zip',[(p,p.name) for p in releases+[staging/'Release-SHA256SUMS']])
for p in staging.iterdir():
    tmp=out/(p.name+'.tmp')
    shutil.copyfile(p,tmp)
    os.replace(tmp,out/p.name)
print('Published validated country files, atlas, coverage, sources, reports and PostgreSQL dumps in shared downloads.')
