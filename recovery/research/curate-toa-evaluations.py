from pathlib import Path
import csv,re,json
root=Path('data')
def write(n,columns,rows):
 with (root/n).open('w',newline='') as f:
  w=csv.writer(f,delimiter='\t',lineterminator='\n');w.writerow(columns);w.writerows(rows)
records={r['id']:r for r in csv.DictReader(open('/tmp/eval-research/3ieData.evidence_records.csv'))}
rep=[];find=[];notes=[]
def report(id,code,key,evaluator,authority,scope,timing,method,summary,limitation,evidence,elig=True,url=None,source='threeie'):
 r=records[id]
 rep.append([id,code,key,'Donor or host evaluation' if elig else 'Related published evaluation',r['title'],r['year_of_publication'],evaluator,authority,scope,timing,method,summary,limitation,url or r['publication_url'],evidence,source])
def finding(id,panel,name,result,value,unit,interpretation,loc=None):
 seq=sum(row[0]==id for row in find)+1
 find.append([id,seq,panel,name,result,value,unit,interpretation,loc or 'Evaluators’ abstract, 3ie record '+id])
def note(code,key,text,lead=True):notes.append([code,key,int(lead),text])
report('6336','MOZ','mcc:MOZ:WATER SAN','Virginia Tech, Stanford University and WE Consult','The evaluation team worked with MCC and Mozambique’s Millennium Challenge Account. The original evaluation documents their respective roles.',
'Rural water point installation in Nampula, a component of the Water Supply and Sanitation Project.',
'The 2013 endline followed Phase 2 water-point installation. The final report was issued in August 2014.',
'Before-and-after comparison of 15 treatment and 23 comparison communities. The authors estimated a difference in differences.',
'The estimated reduction in a round trip to the primary water source was 62 minutes relative to comparison communities (p < 0.05).',
'The measure is the mean of community median times. The study covered selected rural communities. Its estimates cannot be applied to the entire water project.',
'Original report, evaluation design and Table 7.14. The two declines are 85 and 23 minutes.',url='https://vtechworks.lib.vt.edu/handle/10919/71300',source='moz')
for label,val in [('Treatment · baseline',161),('Treatment · follow-up',76),('Comparison · baseline',137),('Comparison · follow-up',114)]:
 finding('6336','Round trip to the primary water source',label,'Observed',val,'minutes','Mean of community median round-trip times.','Final report, Table 7.14')
finding('6336','Estimated effect','Change relative to comparison communities','Lower',-62,'minutes','Difference in differences, p < 0.05.','Final report, Table 7.14')
report('13704','ARM','mcc:ARM:IRRIG AGRI','Randall Blair, Kenneth Fortson, Joanne Lee and Anu Rangarajan','MCC lists the Water to Market farmer-training impact evaluation in its own evaluation catalogue (evaluations-armenia).',
'Farmer training under Water to Market, within the irrigated agriculture project.','Farmers were observed three years after training. The agency catalogues the 2007–2011 evaluation and the paper was published in 2020.',
'Cluster-randomized controlled trial.','Three years after training, the authors found no statistically detectable improvement in household income, consumption, higher-value crop cultivation or farming practices.',
'The available abstract gives no numerical effect sizes or confidence intervals. A statistically inconclusive estimate can include gains or losses.',
'MCC evaluation catalogue, evaluations-armenia, and 3ie record 13704, evaluators’ abstract.',url='https://doi.org/10.1086/702791')
for label in ['Household income','Household consumption','Higher-value crop cultivation','Agricultural practices']:
 finding('13704','Three years after farmer training',label,'No detectable change',None,None,'No statistically detectable improvement reported.')
report('5331','GHA','mcc:GHA:AGRI','Institute of Statistical, Social and Economic Research, University of Ghana','A participant-country research institution performed the evaluation. MCC lists the Commercial Training Activity impact evaluation in its catalogue (evaluations-ghana).',
'Farmer-based organization training and starter packs.','Follow-up interviews assessed trained farmers after their 27 contact days. Surveys ran from November 2008 to January 2011, while the wider compact was operating. The evaluation was published in 2012.',
'Randomized phase-in comparing early and late training groups.','The evaluation found higher use of improved seeds and fertilizer, and no detectable overall increase in crop yields or crop income. Crop income effects differed by zone.',
'The study assessed short-run outcomes. Starter packs included seeds and fertilizer, which complicates interpretation of the input-use increase.',
'ISSER study abstract, 3ie record 5331, and MCC catalogue entry evaluations-ghana.')
for name,res,interp in [('Crop yields overall','No detectable change','No overall impact detected.'),('Crop income overall','No detectable change','The average masks regional differences.'),('Seed and fertilizer use','Higher','The authors attribute most of the increase to the starter pack.'),('Crop income · Northern Agricultural Zone','Higher','A statistically significant increase.'),('Crop income · Southern Horticultural Belt','Lower','A statistically significant decrease.'),('Crop income · Afram Basin','No detectable change','No detectable regional effect.')]:
 finding('5331','After farmer training',name,res,None,None,interp)
report('23527','LSO','mcc:LSO:PS DEVEL','Klaus Deininger and Daniel Ayalew Ali, World Bank','3ie identifies MCC as the research funder for the Lesotho Land Administration Reform Project study.',
'Urban land titling and registry reform, within the Private Sector Development Project.',
'The compact ended in 2013. The study follows registry activity through 2019 and reports medium-term outcomes.',
'Spatial fixed effects with time-varying controls, using land-registry data and satellite imagery.',
'Titling helped women become registered co-owners. The authors attributed greater property-sale and mortgage activity to lower registration costs under a separate policy change.',
'The study separates two reforms that overlapped in time. Crediting all market activity to titling would overstate its effect.',
'3ie record 23527, research funding field and evaluators’ abstract. MCC compact calendar for Lesotho.',url='https://doi.org/10.1596/1813-9450-10043')
for name,res,interpretation in [('Female co-ownership','Higher','Titling helped give effect to the earlier legal right to co-own.'),('Land sales and mortgages','Separate reform','The study attributes market effects to a policy reducing transaction costs.'),('Registration time','Lower','Shorter registration times support the transaction-cost interpretation.')]:
 finding('23527','Land and credit markets',name,res,None,None,interpretation)
report('20118','NAM','mcc:NAM:AGRI','D. Layne Coppock and colleagues','3ie links the underlying evaluation to MCC’s official evaluation catalogue, study 138. The registered trial names the same implementer and intervention.',
'Community-Based Rangeland and Livestock Management under the Agriculture Project.',
'The trial registry records the end of the intervention in July 2014 and the end of the completed study in June 2017. The working paper appeared in 2021.',
'Randomized evaluation of communal grazing areas.','Eight of thirteen social and behavioral indices improved. Effects on rangeland health, cattle productivity and household economic outcomes were negative or statistically indistinguishable from zero.',
'The abstract groups the ecological and economic findings. It does not state a separate estimate for each, and better management practices did not establish better household outcomes.',
'3ie record 20118, primary dataset at data.mcc.gov/evaluations/index.php/catalog/138/study-description and AEA trial 2723.',url='https://doi.org/10.3386/w29469')
finding('20118','Social and behavioral outcomes','Indices with persistent improvement','Higher',8,'of 13 indices','Eight of thirteen indices showed large, persistent improvements.')
finding('20118','Economic and ecological outcomes','Rangeland, cattle and household outcomes','Negative or inconclusive',None,None,'The authors report negative or null effects across these domains.')
report('6337','NIC','mcc:NIC:RURAL DEVL','Michael R. Carter, Patricia Toledo and Emilia Tjernström','The published follow-up on this same randomized program (3ie 12695) lists MCC and USAID as research funders.',
'Rural business development services for small farmers, a component of the Rural Development Project.',
'The evaluation followed the five-year program through completion. The authors reported its results in 2012 and subsequently published post-program follow-up.',
'Randomized rollout and analysis by duration of participation.','Income in the farm activities targeted by the program rose to about 30% above baseline after two years. The evaluators found no statistically significant average effect on household living standards.',
'The 30% refers to targeted farm activities relative to baseline. It does not measure total household income or a 30% reduction in poverty.',
'3ie record 6337, evaluators’ abstract. Research sponsors are identified in follow-up record 12695.')
finding('6337','Income in targeted activities','After two years in the program','Higher',30,'percent above baseline','Approximate plateau in income from targeted activities.')
finding('6337','Household welfare','Average household living standards','No detectable change',None,None,'No statistically significant average improvement was detected.')
report('12695','NIC','mcc:NIC:RURAL DEVL','Michael R. Carter and colleagues','3ie identifies MCC and USAID as research funders.',
'Follow-up on the same rural business development intervention reported in 2012.',
'The authors explicitly report effects persisting after the program concluded.','Randomized treatment assignment, with analysis by exposure duration and household characteristics.',
'Gross farm income gains persisted and productive farm capital continued to rise after completion. Some households benefited little.',
'This paper follows the same intervention and population as the earlier report. The available abstract does not quantify the persistent average gain.',
'3ie record 12695, research funding and evaluators’ abstract.',url='https://doi.org/10.1016/j.jdeveco.2018.11.006')
for n,ex in [('Gross farm income','The estimated increase persisted.'),('Productive farm capital','The estimated effect continued to rise after the program concluded.')]:
 finding('12695','Post-program follow-up',n,'Higher',None,None,ex)
report('8060','BFA','mcc:BFA:SCHOOL','Harounan Kazianga, Leigh Linden, Ali Protik and Matt Sloan','The study identifies the Burkinabè Ministry of Education as implementer and MCC and the national government as program funders. The accessible record does not identify the commissioner of this research.',
'BRIGHT school expansion, including the second phase.','The study measures outcomes six years into the intervention after schools were upgraded from three classrooms to six.',
'Regression discontinuity comparing villages on either side of the selection threshold.',
'Enrollment was 15.5 percentage points higher and test scores were 0.29 standard deviations higher. The estimates cover exposure to the phased BRIGHT program.',
'An incremental Phase 2 effect cannot be isolated from the reported overall estimates. The research sponsor could not be verified.',
'3ie record 8060, evaluators’ abstract, named implementing agency and program funding fields.',False)
finding('8060','Enrollment after six years','Primary school enrollment','Higher',15.5,'percentage points','Difference in enrollment between program and comparison villages.')
finding('8060','Learning after six years','Standardized test score','Higher',0.29,'standard deviations','Standardized difference on the test-score scale.')
report('19120','BFA','mcc:BFA:SCHOOL','Nicholas Ingwersen and colleagues','3ie lists the U.S. National Institute of Child Health and Human Development as a research funder. Direct commissioning by MCC, USAID or the Burkina Faso government was unverified.',
'Ten-year follow-up in villages selected for the two-phase BRIGHT school program.',
'Primary-school-age children, older youths and young adults were assessed ten years after the program began.',
'Regression discontinuity around the village selection threshold.',
'Children in selected villages attended school more and scored higher on tests. Among women old enough to have completed secondary school, marriage and childbearing occurred later.',
'Findings refer to the phased program in selected villages. The available abstract does not isolate the contribution of Phase 2.',
'3ie record 19120, research funder and evaluators’ abstract.',False,url='https://doi.org/10.3386/w25994')
for label,obs in [('School attendance','Increased for primary-school-age children.'),('Test scores','Increased for primary-school-age children.'),('Age at marriage and childbearing','Women old enough to have completed secondary school delayed both.')]:
 finding('19120','Ten-year follow-up',label,'Higher',None,None,obs)
# Study confirmed, exact donor/host commissioning and complete findings unavailable.
note('ARM','mcc:ARM:RURAL ROAD','Mathematica’s 2015 Evaluation of a Rural Road Rehabilitation Project in Armenia is indexed as 3ie 21710. The available entry has no abstract and does not name the research sponsor. No effect estimate was recoverable.')
note('SLV','mcc:SLV:PROD DEVEL','3ie 5867 indexes a 2014 three-year handicrafts evaluation, but links to a differently titled one-year report. MCC’s archived entry is interim. The 15% income figure in the abstract is a target. The final effect and commissioning of that edition remain unverified.')
note('PHL','mcc:PHL:COMDEV GRT','MCC’s KALAHI-CIDSS entry and AEA trial 171 identify the Philippine government program. The 2015 report in 3ie 13138 is interim, and the older World Bank synthesis concerns an earlier phase.')
note('NIC','mcc:NIC:TRANSPORTN','3ie 21351 studies a rehabilitated road to León. The accessible metadata leaves research funding unspecified and does not confirm the exact financed road segment.')
note('BFA','mcc:BFA:AGRI','AEA trial 2718 identifies MCC’s Di irrigation perimeter and its 2014 completion. The registry entry is a study plan and lists no resulting paper.')
note('TZA','mcc:TZA:TRSPRT STR','3ie 21526 concerns a broader 2,500 km Tanzanian road program. The accessible record does not isolate the roads financed under this compact.')
note('HND','mcc:HND:TRANSPORTN','GAO-12-631 reviews MCC transport investments in seven countries. The accessible index does not establish project-level findings for Highway CA-5. The Honduras farmer-training impact evaluation covers a different project.')
for c in ('FSM','MHL','PLW'):note(c,'pam:'+c+':COFA:Compacts of Free Association economic assistance','GAO-22-104436 examined the planned expiration of economic assistance and projected funding after 2023. It was published before that funding period ended.')
write('evaluation_reports.tsv','report_id iso3 project_key eligibility title published evaluator authority scope timing method summary limitation url evidence source_id'.split(),rep)
write('evaluation_findings.tsv','report_id sequence panel indicator result value unit interpretation locator'.split(),find)
write('evaluation_screening.tsv','iso3 project_key has_lead screening_note'.split(),notes)
