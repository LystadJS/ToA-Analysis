"""Search pinned evaluation catalogues for each ranked project; a hit is a lead."""
import csv
import html
import io
import json
import re
import sys
import tarfile
import unicodedata
import zipfile
from collections import defaultdict
from pathlib import Path

CACHE = Path("data/cache")
STOP = set("""the and for of in to from with on and by grant grants project program programme
  development activity activities assistance corporation company limited ltd inc llc national
  international government ministry department bank group private services funds fund support
  financing finance financial capacity building administration control management and investment
  company sector public district construction improvement technical training technical government
  usa united states usaid mcc agency miscellaneous redacted unspecified unnamed general
  industrial commercial ltd project ssa various stage phase basic agreement monitoring evaluation
  plan government approved de la del sa cv ii per para project integrated inc corporation
  institutional industries global delivery reform limited enterprises implementation strengthen
  title key improve support information operations strategic facilities system systems institutions
  protection transfer multiple additional subsidiary americas for africa capital trust""".split())
ALIAS = {
    'CIV':['ivory coast'], 'COD':['democratic republic of the congo','congo dem rep','congo kinshasa'],
    'COG':['republic of the congo','congo rep','congo brazzaville'], 'SWZ':['swaziland'],
    'VNM':['vietnam'], 'TUR':['turkey'], 'KOR':['south korea','korea rep'],
    'PRK':['north korea'], 'LAO':['laos','lao pdr'], 'FSM':['micronesia'],
    'PSE':['west bank','gaza','palestinian territories'], 'KGZ':['kyrgyz republic'],
    'MAC':['macau'], 'MKD':['macedonia'], 'MMR':['burma'], 'TLS':['east timor'],
    'CPV':['cape verde'], 'TWN':['taiwan'], 'RUS':['russia'], 'CZE':['czech republic'],
    'SYR':['syria'], 'BRN':['brunei'], 'TON':['tonga'], 'BHS':['the bahamas']
}
SOURCES = ('threeie','usaid_dec','ieg','mcc_catalog','gao_catalog','aea_registry')

def clean(value):
    v = re.sub(r'<[^>]*>', ' ', html.unescape(value or ''))
    return ' '.join(re.findall('[a-z0-9]+',unicodedata.normalize('NFKD',v.lower()).encode('ascii','ignore').decode()))

def words(text):
    return {w for w in clean(text).split() if len(w) >= 3 and w not in STOP}

def read_tsv(path):
    with open(path,encoding='utf-8-sig') as f:
        return list(csv.DictReader(f,delimiter='\t'))

def catalogue(gao_file):
    with zipfile.ZipFile(CACHE/'3ie-evaluations.zip') as z:
        member = next(n for n in z.namelist() if n.endswith('3ieData.evidence_records.csv'))
        with z.open(member) as raw:
            rows = csv.DictReader(io.TextIOWrapper(raw,encoding='utf-8-sig'))
            geo = [k for k in rows.fieldnames if k.endswith('].country') and k.startswith('continent')]
            names = [k for k in rows.fieldnames if k.endswith('].project_name')]
            for r in rows:
                if r['product_type']!='ier': continue
                yield ('threeie',r['id'],r['title'], ' '.join(r[k] for k in names), r['abstract'],
                       ' | '.join(r[k] for k in geo if r[k]),r['publication_url'],r['year_of_publication'])
    for r in read_tsv(CACHE/'usaid-evaluation-catalog.tsv'):
        yield ('usaid_dec',r['Unique_ID'],r['Title'],r['USAID_Project_Number']+' '+r['Contract_Grant_Number'],
               r['Abstract']+' '+r['Description'],r['Descriptors_Geographic']+' | '+r['USAID_Geography'],
               r['File'] or r['URI'],r['Date_Resource_Created'])
    seen = set()
    with (CACHE/'ieg-completion-reviews.csv').open(encoding='latin-1') as f:
        for r in csv.DictReader(f):
            key = r['Project ID']+' '+r['Evaluation Type']+' '+r['Evaluation Date'][:10]
            if key in seen: continue
            seen.add(key)
            yield ('ieg',key,r['Project Name'],r['Project ID'],'',r['Country'],r['PDF'],r['Evaluation Date'])
    for r in json.loads((CACHE/'mcc-catalog.json').read_text()):
        if r.get('theme')=='Evaluation Catalog':
            yield ('mcc_catalog',r['identifier'],r['title'],'',r['description'],r['title'].split(',')[0],
                   r['distribution'][0]['accessURL'],r['modified'])
    with tarfile.open(CACHE/'aea-plan-archive.tar.gz','r:gz') as archive:
        for member in archive:
            if not re.search(r'/data/plans/plans_[0-9]{4}\.csv$',member.name):
                continue
            with archive.extractfile(member) as raw:
                for r in csv.DictReader(io.TextIOWrapper(raw,encoding='utf-8-sig')):
                    yield ('aea_registry',r['rct_id'],r['title'],'',r['abstract']+' '+r['intervention'],
                           r['countries'],r['url'],r['first_registered_on'])
    for r in read_tsv(gao_file):
        yield ('gao_catalog',r['report_id'] or r['url'],r['title'],'',r['summary'],'',r['url'],r['published'])

def search(portfolio, countries, gao_file, output):
    projects = read_tsv(portfolio)
    country_alias = {}
    for r in read_tsv(countries):
        code,name=r['iso3'],r['name']
        variants=[name]+ALIAS.get(code,[])
        if code not in ('COD','COG','KOR','PRK','VIR','VGB'): variants.append(name.split(',')[0])
        country_alias[code]={clean(v) for v in variants if len(clean(v))>=3}
    # Currency and timing are intentionally absent from textual similarity.
    # Each published report requires an independent, documented scope review.
    projects_by_country=defaultdict(list)
    for p in projects:
        terms=words(p['search_name']+' '+p['title'])
        country_words=words(' '.join(country_alias[p['iso3']]))
        terms -= country_words
        ids = {clean(p['locator'].split(' / ')[0])} if p['source_id']=='exim' else set()
        if p['source_id'] in ('dfc','gates'): ids.add(clean(p['project_key'].split(':')[-1].replace('gates-','')))
        phrases=[clean(x) for x in p['search_name'].split(' | ') if len(x)<130 and len(words(x))>=2]
        projects_by_country[p['iso3']].append((p,terms,ids,phrases))
    synonyms=defaultdict(set)
    for code in projects_by_country:
        for a in country_alias[code]: synonyms[a].add(code)
    pattern=re.compile(r'\b(?:'+'|'.join(re.escape(a) for a in sorted(synonyms,key=len,reverse=True))+r')\b')
    hits=defaultdict(dict)
    for source,ident,title,names,abstract,geo,url,published in catalogue(gao_file):
        if not ident or not title: continue
        descriptor=clean(title+' '+names)
        text=descriptor+' '+clean(abstract)
        geography=clean(geo)
        # If geographic indexing gives no recognized country, look in the report.
        codes={c for a in pattern.findall(geography) for c in synonyms[a]}
        if not codes: codes={c for a in pattern.findall(text) for c in synonyms[a]}
        if not codes: continue
        years=re.findall(r'\b(?:19|20)[0-9]{2}\b',published or '')
        src_year=int(years[0]) if years else None
        primary=words(descriptor)
        body=words(text)
        for code in codes:
            for p,terms,ids,phrases in projects_by_country[code]:
                if src_year and p['source_id'] in ('exim','dfc','gates') and p['year'].isdigit() and src_year < int(p['year']) and source!='aea_registry':
                    continue
                a=terms & primary
                b=terms & body
                ident_match=any(len(i)>=5 and (' '+i+' ') in (' '+text+' ') for i in ids)
                score=len(a)*3+len(b-a)
                exact=any((' '+phrase+' ') in (' '+text+' ') for phrase in phrases)
                specific=(len(a)>=2 and (len(b)>=3 or len(terms)<=4)) or (len(a)>=1 and len(b)>=4)
                if ident_match or exact or specific:
                    key=(code,p['project_key'],source)
                    hit=(score + 20*ident_match + 10*exact,title,url,published)
                    if ident not in hits[key] or hit>hits[key][ident]: hits[key][ident]=hit
    with open(output,'w',newline='',encoding='utf-8') as f:
        w=csv.writer(f,delimiter='\t'); w.writerow(['iso3','project_key','source_id','match_count','leads'])
        for p in projects:
            for src in SOURCES:
                candidates=hits[p['iso3'],p['project_key'],src]
                best=sorted(candidates,key=lambda k:(-candidates[k][0],k))
                leads=[dict(id=k,title=candidates[k][1],url=candidates[k][2],date=candidates[k][3]) for k in best]
                w.writerow([p['iso3'],p['project_key'],src,len(candidates),json.dumps(leads,ensure_ascii=False)])
if __name__=='__main__':
    search(*sys.argv[1:])
