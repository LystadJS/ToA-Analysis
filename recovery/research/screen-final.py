import csv,sqlite3,json
from pathlib import Path
c=sqlite3.connect('artifacts/toa_us.sqlite')
p=Path('data/evaluation_screening.tsv')
with p.open() as f:rows=list(csv.DictReader(f,delimiter='\t'))
review={
'mcc:BEN:ACCESSMARK':(0,'AEA trial 2552 concerns agricultural extension. The ranked project financed port works and business registration.'),
'exim:ETH:AP089513XX':(0,'The trial plans concern manufacturing workers and the indexed paper studies industrial policy. None assesses the Ethiopian Airlines aircraft authorization.'),
'pam:FSM:PEACE:':(0,'The GAO item concerns fiscal year 1968 appropriations. It does not assess outcomes of the Peace Corps activity represented in these transactions.'),
'gates-OPP19399':(0,'3ie 15107 assesses navigation to surgical care. The ranked grant supported family planning for young people in Haiti.'),
'exim:LKA:AP086903XX':(0,'3ie 6332 concerns the Dry Zone Livelihood Support and Partnership Programme. It does not identify the EXIM engineering services deal.'),
'mcc:LSO:HEALTH SEC':(0,'3ie 18980 assesses a community ART-refill protocol. The USAID studies predate the compact. These reports do not assess the financed clinics and laboratories.'),
'mcc:LSO:WTR SECTOR':(1,'IEG P108143 reviews the Metolong Dam and Water Supply operation in 2020. The accessible review covers a World Bank project. It does not isolate the outcome of MCC-financed bulk conveyance or establish a host-government evaluation.'),
'mcc:MDG:LAND TNRE':(0,'The indexed USAID policy reform report dates to 1992 and predates the Madagascar compact.'),
'exim:MOZ:AP087889XX':(0,'3ie 7719 studies an information intervention about natural gas management. It does not evaluate construction or operation under the MOZ LNG financing.'),
'gates-INV-008387':(0,'The catalogued studies address other health, agriculture and household interventions. None identifies the Lighthouse Trust grant for the national health data system.'),
'mcc:NAM:EDU':(0,'The DEC records concern the earlier ABEL education project and a USAID HIV project. Neither identifies the MCC investments reviewed here.'),
'ppi:PHL:2015:Masinloc':(0,'DEC record PN-ABK-556 dates to 1992. The Masinloc II expansion reached financial close in 2015.'),
'dfc:9000105149':(1,'DEC record PD-AAZ-069 evaluates emergency water supply in North Kordofan. The DFC legacy record has only a sector description and no date or original project identifier to corroborate the link.'),
'dfc:9000105150':(0,'The legacy finance record has no sector or date specific enough to link the indexed health and urban water studies to the funded activity.'),
'mcc:SEN:IRRIGATION':(0,'The 1986 USAID study concerns livestock and land tenure across sub-Saharan Africa and predates the Senegal compact.'),
'pam:USA-Grant-SLB-42':(1,'IEG P112613 reviews a World Bank climate and disaster resilience project. The available records do not identify the same U.S. grant or a qualifying evaluation of its outcomes.'),
'dfc:9000104886':(0,'The trial plans concern remittances and school violence. GAO-24-106232 concerns USAID oversight. None identifies the 2023 bank financing.'),
'dfc:9000105143':(0,'The 1969 DEC report covers a University of Wyoming agricultural services contract. It does not identify the fertilizer plant financing.'),
'dfc:9000105144':(0,'The DEC agricultural services report does not identify the water transport financing.'),
'dfc:9000105205':(0,'The DEC agricultural services report does not identify the debt rescheduling transaction.'),
'mcc:TZA:WTR SECTOR':(0,'The 2023 citizen engagement trial concerns a different intervention from the Lower Ruvu and Morogoro water investments.'),
'pam:USA-Grant-WSM-30':(1,'IEG P118636 reviews a World Bank economic recovery credit. The U.S. activity is described only as crisis assistance and recovery. A common intervention and qualifying evaluation could not be verified.'),
'exim:ZMB:AP088268XX':(0,'The registry record studies rural financial intermediation. It does not identify the structural metal export authorization.')}
allkeys=list(c.execute('select iso3,project_key from evaluation_program'))
for prefix,(lead,note) in review.items():
 matches=[(iso,k) for iso,k in allkeys if k.startswith(prefix)]
 assert len(matches)==1,prefix
 for iso,k in matches: rows.append(dict(iso3=iso,project_key=k,has_lead=lead,screening_note=note))
overrides={'mcc:HND:TRANSPORTN':'https://www.gao.gov/products/gao-12-631','mcc:BFA:AGRI':'https://www.socialscienceregistry.org/trials/2718','mcc:ARM:RURAL ROAD':'https://www.mathematica-mpr.com/-/media/publications/pdfs/international/armenia_rrrp_rpt.pdf','mcc:NIC:TRANSPORTN':'https://arefiles.ucdavis.edu/uploads/filer_public/ee/53/ee53709d-ffae-4b7e-9738-b76f91486d35/parada_jmp.pdf'}
for r in rows:
 k=r['project_key']
 hits=[h for a, in c.execute('select leads from evaluation_search where project_key=? and match_count>0',(k,)) for h in json.loads(a)]
 u=next((h['url'] for h in hits if h['id'].lower() in r['screening_note'].lower() and h['url'].startswith(('http:','https:'))),'')
 if not u and len(hits)==1:u=hits[0]['url']
 r['screening_url']=overrides.get(k,u)
with p.open('w',newline='') as f:
 w=csv.DictWriter(f,fieldnames=rows[0].keys(),delimiter='\t',lineterminator='\n');w.writeheader();w.writerows(rows)
