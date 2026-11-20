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
check("MCC monitoring counts reconcile to workbook",scalar(us,"select count(*)=4737 and count(actual_text)=3299 from toa.result r join toa.program p on p.id=r.program_id where source_id='mcc' and r.id not like '%-ActualQ%'"))
check("Signed corrections retained",scalar(us,"select min(usd)<0 from toa.finance where measure='obligation'"))
check("USAID disbursement retains cents",scalar(us,"select usd=6529878.59 from toa.finance f join toa.program p on p.id=f.program_id where locator='Afghanistan/2011/Environment/Spent'"))
check("Source sector aggregates are unique",scalar(us,"select count(*)=count(distinct(iso3,year,name)) from toa.program where source_id='sector'"))
check("1976 transition quarter distinguishable",scalar(us,"select count(distinct period)=2 from toa.program where source_id='greenbook' and year=1976"))
check("Strict lower bound kept for Honduras",scalar(us,"select actual=15000000 and comparator='>' from toa.result where id='hnd-cost'"))
check("Comparison-group timing",scalar(us,"select (actual-baseline)-(114-137)=-62 and observed_year=2013 from toa.result where id='moz-time'"))
check("Project costs distinct from sponsor equity",scalar(cn,"select usd=24600000 and p.project_investment_usd>usd from toa.finance f join toa.program p on id=program_id where source_id='ppi' and iso3='KAZ' and name='Chulakkurgan Solar PV Power Plant' and actor like 'Risen%'"))
check("Undisclosed amounts stay missing through aggregation",scalar(cn,"select count(*)>0 and bool_and(reported_usd is null) from toa.finance_by_country_year where amounts_known=0"))
check("Cancelled, suspended and pledged amounts excluded from official finance summaries",scalar(cn,"select count(*)=0 from toa.finance f join toa.program p on id=program_id where p.source_id='gcdf' and p.status in ('Cancelled','Suspended','Pipeline: Pledge') and f.eligible_for_summary"))
check("Reviewed annual and cumulative disbursements kept separate",scalar(cn,"select count(*) filter(where measure='disbursement')=152 and count(*) filter(where measure='cumulative disbursement snapshot' and not eligible_for_summary)=2 from toa.finance"))
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
check("New CLG series uses nominal dollars and keeps commercial official finance identified",scalar(cn,"select count(*)=3834 and count(*) filter(where instrument like 'OFIC /%')>0 from toa.program p join toa.finance f on id=program_id where source_id='clg' and year>=2022"))
check("Single-country Afghanistan grant matches CLG source",scalar(cn,"select usd=2000000 from toa.finance where program_id='clg-AIDDATA-103729'"))
check("Reviewed private grants linked by ID and host-country purpose",scalar(us,"select count(*)=35 and count(distinct iso3)=28 and min(usd)>=1000000 from toa.program p join toa.finance f on id=program_id where source_id='gates' and channel='private philanthropy'"))
check("Risen Energy ownership evidence carried through",scalar(cn,"select count(*)>0 from toa.program where source_id='ppi' and details like '%Private Sector in record 90168%'"))
check("Current U.S. series and archived vintage cannot overlap in totals",scalar(us,"select count(*) filter(where source_id='us_sector_review' and eligible_for_summary)=65874 and count(*) filter(where source_id='fa' and eligible_for_summary)=0 from toa.finance f join toa.program p on p.id=f.program_id"))
check("Country-attributed U.S. FY24 and FY25 match source dollars",scalar(us,"select sum(usd) filter(where flow_year=2024)=42896561185 and sum(usd) filter(where flow_year=2025)=19878894683 from toa.finance f join toa.program p on p.id=f.program_id where source_id='us_sector_review'"))
check("Treasury payments reconcile separately in their native currencies",scalar(cn,"select count(*)=6 and sum(reported_amount) filter(where reported_currency='CNY')=454243778.75 and sum(usd)=44721731.99 and count(usd) filter(where reported_currency='CNY')=0 from toa.finance where measure='borrower-reported drawdown'"))
check("Cross-vintage disclosures have matching recipient, year and ID with undisclosed GCDF values", scalar(cn,"select count(*)=57 and bool_and(p.iso3=g.iso3 and p.year=g.year and f.usd is not null and gf.usd is null and not f.eligible_for_summary) from toa.finance f join toa.program p on p.id=f.program_id join toa.program g on g.id=replace(p.id,'clg-check-AIDDATA-','gcdf-') join toa.finance gf on gf.program_id=g.id and gf.measure='adjusted commitment' where f.measure='cross-vintage face-value disclosure'"))
check("Unconfirmed spending excluded from payment totals",scalar(cn,"select count(*)=769 and not bool_or(eligible_for_summary) from toa.finance where measure='source-reported spending (unconfirmed)'"))
check("Dated MCC observations distinguish quarterly values and calendar milestones",scalar(us,"select count(*) filter(where dating_basis='Reported compact quarter' and period_end>=period_start and actual is not null)=6858 and count(*) filter(where dating_basis='Reported milestone date' and period_end=period_start)=210 and count(*) filter(where dating_basis='Observation date unavailable' and observed_year is null and actual is not null)=3089 from toa.result"))
check("Philippines registration observed separately from undated summary",scalar(us,"select count(*) filter(where id='itt-73860-ActualQ20' and period_end='2016-06-30' and actual=11.67)=1 and count(*) filter(where id='itt-73860' and observed_year is null)=1 from toa.result"))
for (con in list(us,cn)) check("Sponsor disclosure subtotals retain the missing-stake denominator",scalar(con,"select sum(sponsor_records)>sum(disclosed_records) and sum(known_ownership_shares)>sum(disclosed_records) from toa.private_sponsor_coverage"))
for (con in list(us,cn)) check("Three inferred sole-sponsor stakes stay outside disclosed totals",scalar(con,"select count(*)=3 and bool_and(sponsor_ownership_pct=100 and usd is null) from toa.program p join toa.finance f on p.id=f.program_id where implied_sole_sponsor_equity_usd is not null"))
check("Currency-period view preserves Kenyan borrower currency",scalar(cn,"select count(*)=2 and sum(disclosed_records)=6 and max(disclosed_amount) filter(where currency='CNY')=454243778.75 from toa.finance_by_currency_period where source_id='kenya_debt'"))
raw_mcc <- fread("data/cache/mcc.csv",colClasses="character")
check("Moldova and Namibia quarter anchors agree with milestone dates in the indicator table",
      raw_mcc[IndicatorId=="57993",ActualQ10]=="2/27/2013" &&
      raw_mcc[IndicatorId=="73338",ActualQ10]=="2/29/2012" &&
      scalar(us,"select count(distinct iso3)=2 from toa.dated_program_results where id like '%-ActualQ10' and ((iso3='MDA' and date '2013-02-27' between period_start and period_end) or (iso3='NAM' and date '2012-02-29' between period_start and period_end))"))
dbDisconnect(us)
dbDisconnect(cn)
cat(checks,"checks passed\n")
