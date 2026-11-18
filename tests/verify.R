# Integration checks against both populated PostgreSQL databases and pinned source records.
source("R/common.R")
source("R/analyze.R")
us <- connect(Sys.getenv("TOA_TEST_US","toa_us"))
cn <- connect(Sys.getenv("TOA_TEST_CHINA","toa_china"))
scalar <- function(con,sql) dbGetQuery(con,sql)[[1]][1]
checks <- 0L
check <- function(title,ok) {
  if (!isTRUE(ok)) stop(title,call.=FALSE)
  checks <<- checks+1L
  cat("PASS",title,"\n")
}
for (conn in list(us,cn)) {
  check("ISO universe and Kosovo", scalar(conn,"select count(*)=250 and count(*) filter(where code_system='ISO 3166-1')=249 from toa.country"))
  check("Empty coverage survives", scalar(conn,"select program_records=0 from toa.country_coverage where iso3='ATA'"))
  check("Sources have pinned hashes", scalar(conn,"select bool_and(sha256 ~ '^[0-9a-f]{64}$') from toa.source"))
  check("No orphaned program references",scalar(conn,"select count(*)=0 from toa.program p left join toa.country c using(iso3) left join toa.source s using(source_id) where c.name is null or s.title is null"))
  check("Logistics observations have unique country/indicator/year keys",scalar(conn,"select count(*)=1279 and count(*)=count(distinct (iso3,source_id,year)) from toa.context"))
  check("Unknown equity kept null",scalar(conn,"select count(*)>0 from toa.finance f join toa.program p on id=program_id where source_id='ppi' and usd is null"))
  check("Provider finance totals exclude context and trade values",scalar(conn,"select count(*)=0 from toa.finance_by_country_year where source_id in ('import','export','agoa')"))
}
check("Both country dimensions match",identical(dbGetQuery(us,"select * from toa.country order by iso3"),dbGetQuery(cn,"select * from toa.country order by iso3")))
check("MCC monitoring counts reconcile to workbook",scalar(us,"select count(*)=4737 and count(actual_text)=3299 from toa.result r join toa.program p on p.id=r.program_id where source_id='mcc'"))
check("Signed corrections retained",scalar(us,"select min(usd)<0 from toa.finance where measure='obligation'"))
check("USAID disbursement retains cents",scalar(us,"select usd=6529878.59 from toa.finance f join toa.program p on p.id=f.program_id where locator='Afghanistan/2011/Environment/Spent'"))
check("Source sector aggregates are unique",scalar(us,"select count(*)=count(distinct(iso3,year,name)) from toa.program where source_id='sector'"))
check("1976 transition quarter distinguishable",scalar(us,"select count(distinct period)=2 from toa.program where source_id='greenbook' and year=1976"))
check("Strict lower bound kept for Honduras",scalar(us,"select actual=15000000 and comparator='>' from toa.result where id='hnd-cost'"))
check("Comparison-group timing",scalar(us,"select (actual-baseline)-(114-137)=-62 and observed_year=2013 from toa.result where id='moz-time'"))
check("Project costs distinct from sponsor equity",scalar(cn,"select usd=24600000 and p.project_investment_usd>usd from toa.finance f join toa.program p on id=program_id where source_id='ppi' and iso3='KAZ' and name='Chulakkurgan Solar PV Power Plant' and actor like 'Risen%'"))
check("Undisclosed amounts stay missing through aggregation",scalar(cn,"select count(*)>0 and bool_and(reported_usd is null) from toa.finance_by_country_year where amounts_known=0"))
check("Cancelled, suspended and pledged amounts excluded from official finance summaries",scalar(cn,"select count(*)=0 from toa.finance f join toa.program p on id=program_id where p.source_id='gcdf' and p.status in ('Cancelled','Suspended','Pipeline: Pledge') and f.eligible_for_summary"))
check("Reviewed annual and cumulative disbursements kept separate",scalar(cn,"select count(*) filter(where measure='disbursement')=11 and count(*) filter(where measure='cumulative disbursement snapshot' and not eligible_for_summary)=2 from toa.finance"))
# Reconcile complete eligible country-level totals, independently using the source's own aggregate flag.
e <- new.env()
load(cached("gcdf"), envir=e)
x <- e$gcdf3_dataset
codes <- dbGetQuery(cn,"select iso3 from toa.country")$iso3
ok <- x$recommended_for_aggregates=="Yes" & x$recipient_iso_3 %in% codes
agg <- dbGetQuery(cn,"select count(*) as n,count(usd) as known,sum(usd) as total from toa.finance where measure='adjusted commitment' and eligible_for_summary")
check("AidData eligible count and known amount coverage reconcile",agg$n==sum(ok) && agg$known==sum(ok & !is.na(x$adjusted_amount_nominal_usd)))
check("AidData stock-adjusted nominal amount reconciles to cents per record", abs(agg$total-sum(round(x$adjusted_amount_nominal_usd[ok],2),na.rm=TRUE)) < 2)
x <- fread(cached("fa"),integer64="double")
code <- fifelse(x[["Country Code"]]=="CS-KM","XKX",x[["Country Code"]])
ok <- code %in% codes & x[["Transaction Type Name"]]=="Disbursements"
check("U.S. country disbursement release reconciles",sum(x$current_amount[ok])==scalar(us,"select sum(usd) from toa.finance f join toa.program p on p.id=f.program_id where source_id='fa'"))
check("AGOA panel reconciles to D-only source claims",sum(fread(cached("agoa"))$agoa_claimed_imports_usd,na.rm=TRUE)==scalar(us,"select sum(actual) from toa.result where level='Preference use'"))
check("New CLG series uses nominal dollars and keeps commercial official finance identified",scalar(cn,"select count(*)=3834 and count(*) filter(where instrument like 'OFIC /%')>0 from toa.program p join toa.finance f on id=program_id where source_id='clg'"))
check("Single-country Afghanistan grant matches CLG source",scalar(cn,"select usd=2000000 from toa.finance where program_id='clg-AIDDATA-103729'"))
check("Reviewed private grants linked by ID and host-country purpose",scalar(us,"select count(*)=12 and min(usd)>=1000000 from toa.program p join toa.finance f on id=program_id where source_id='gates' and channel='private philanthropy'"))
check("Risen Energy ownership evidence carried through",scalar(cn,"select count(*)>0 from toa.program where source_id='ppi' and details like '%Private Sector in record 90168%'"))
dbDisconnect(us)
dbDisconnect(cn)
cat(checks,"checks passed\n")
