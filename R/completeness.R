# Read-only audit at the native observation date of each series.
source("R/common.R")
source("R/fonts.R")
out <- "artifacts/coverage"
dir.create(out, recursive=TRUE, showWarnings=FALSE)
read_text <- function(path) paste(readLines(path, warn=FALSE), collapse="\n")
profile_sql <- read_text("audit/profile.sql")
release <- function(name) {
  con <- connect(name)
  on.exit(dbDisconnect(con))
  dbWithTransaction(con, {
    dbExecute(con,"SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
    get <- function(sql) as.data.table(dbGetQuery(con,sql))
    list(countries=get("SELECT iso3,name FROM toa.country ORDER BY iso3"),
         cells=get(profile_sql),
         context=get("SELECT 'Context' AS kind, source_id, 'Survey lead time' AS series, iso3, year,
                     count(*) AS n, count(days) AS known, count(days) AS reported,
                     count(*) FILTER (WHERE days=0) AS zeroes, NULL::bigint AS eligible
                     FROM toa.context GROUP BY source_id,iso3,year ORDER BY source_id,iso3,year"),
         us_payments=get("SELECT p.iso3, f.flow_year AS year, sum(f.usd) AS database_usd
                          FROM toa.program p JOIN toa.finance f ON p.id=f.program_id
                          WHERE p.source_id='us_sector_review' AND f.eligible_for_summary GROUP BY p.iso3,f.flow_year"),
         archive=get("SELECT p.iso3,f.flow_year AS year,sum(f.usd) AS previous_database_usd
                     FROM toa.program p JOIN toa.finance f ON p.id=f.program_id
                     WHERE p.source_id='fa' GROUP BY p.iso3,f.flow_year"),
         economic=get("SELECT f.period_ref AS period,sum(f.usd) AS database_economic_usd
                       FROM toa.program p JOIN toa.finance f ON p.id=f.program_id
                       WHERE p.source_id='greenbook' GROUP BY f.period_ref"),
         undated_results=get("SELECT p.iso3,p.source_id,p.name,r.id,r.indicator,r.actual,r.actual_text,
                     r.unit,r.method,r.dating_basis,p.citation,p.locator FROM toa.program p JOIN toa.result r ON p.id=r.program_id
                     WHERE r.observed_year IS NULL AND (r.actual IS NOT NULL OR r.actual_text IS NOT NULL) ORDER BY p.iso3,r.id"),
         missing_stakes=get("SELECT iso3,p.year,p.id,p.name,p.actor,p.sponsor_ownership_pct,p.implied_sole_sponsor_equity_usd,
                     p.project_investment_usd,p.locator,s.download_url
                     FROM toa.program p JOIN toa.finance f ON p.id=f.program_id JOIN toa.source s USING(source_id)
                     WHERE p.source_id='ppi' AND f.usd IS NULL ORDER BY p.project_investment_usd DESC NULLS LAST,p.id"),
         missing_commitments=get("SELECT g.iso3,g.year,g.id,g.name,gf.measure,gf.instrument,g.citation,g.locator,
                     c.id AS related_disclosure_id,cf.usd AS related_face_value_usd
                     FROM toa.finance gf JOIN toa.program g ON g.id=gf.program_id
                     LEFT JOIN toa.program c ON c.id=replace(g.id,'gcdf-','clg-check-AIDDATA-') AND c.id LIKE 'clg-check-%'
                     LEFT JOIN toa.finance cf ON cf.program_id=c.id
                     WHERE gf.measure IN ('adjusted commitment','face-value commitment (CLG)') AND gf.eligible_for_summary AND gf.usd IS NULL
                     ORDER BY cf.usd DESC NULLS LAST,g.iso3,g.year,g.id"),
         payments=get("SELECT p.iso3,p.source_id,p.id,p.name,p.actor,f.measure,f.flow_year,f.period_ref,
                     f.period_start,f.period_end,coalesce(f.reported_currency,'USD') AS currency,
                     coalesce(f.reported_amount,f.usd) AS amount,p.locator,p.citation,
                     CASE WHEN p.source_id='kenya_debt' THEN 'Borrower register, reconciled to creditor totals'
                          ELSE 'AidData project narrative' END AS evidence
                     FROM toa.program p JOIN toa.finance f ON p.id=f.program_id
                     WHERE p.source_id IN ('kenya_debt','gcdf') AND f.measure IN ('disbursement','borrower-reported drawdown')
                     ORDER BY p.iso3,f.flow_year,p.id,f.period_ref"),
         kenya=get("SELECT p.id,p.year,p.name,f.measure,f.usd,f.reported_amount,f.reported_currency FROM toa.program p
                   JOIN toa.finance f ON p.id=f.program_id WHERE p.iso3='KEN'
                   AND (p.id='gcdf-31777' OR f.measure='borrower-reported drawdown')"))
  })
}
us <- release("toa_us")
cn <- release("toa_china")
stopifnot(identical(us$countries,cn$countries),identical(us$context,cn$context))
countries <- us$countries
cells <- rbindlist(list(USA=us$cells,CHN=cn$cells,Shared=us$context),idcol="provider")
idx <- c("provider","kind","source_id","series","iso3","year")
setorderv(cells,idx)
stopifnot(!anyDuplicated(cells,by=idx), all(cells$iso3 %in% countries$iso3),
          all(cells$n>=cells$reported & cells$reported>=cells$known))
fwrite(cells,file.path(out,"country-year-observations.csv"))
series <- cells[, .(records=sum(n), numeric_or_present=sum(known), reported=sum(reported),
                    undated=sum(n[is.na(year)]), countries=uniqueN(iso3),
                    first_year=if(any(!is.na(year)))min(year,na.rm=TRUE) else NA_integer_,
                    last_year=if(any(!is.na(year)))max(year,na.rm=TRUE) else NA_integer_),
                by=.(provider,kind,source_id,series)]
series[, sid := .I]
cells <- merge(cells, series[,.(provider,kind,source_id,series,sid)],
               by=c("provider","kind","source_id","series"))
fwrite(series,file.path(out,"series-coverage.csv"))

# Reconcile the pinned country release separately from cross-vintage differences.
audit_sources <- fread("data/audit_sources.tsv")
project_sources <- registry[source_id %in% unique(cells$source_id)]
read_disb <- function(path) {
  x <- fread(path,integer64="double")[`Transaction Type Name`=="Disbursements"]
  stopifnot(!anyNA(x$current_amount))
  x[, .(iso3=fifelse(`Country Code`=="CS-KM","XKX",`Country Code`), label=`Country Name`,
        year=as.integer(`Fiscal Year`),usd=current_amount,sector=if("US Sector ID" %in% names(x)) x[["US Sector ID"]] else NA_integer_)]
}
old <- read_disb(cached("fa"))
new <- read_disb(file.path("data/cache",audit_sources[source_id=="us_sector_review",file_name]))
stopifnot(!anyDuplicated(old,by=c("iso3","year")), !anyDuplicated(new,by=c("iso3","year","sector")))
included <- function(x) x[iso3 %in% countries$iso3]
published <- included(old)[,.(previous_database_usd=sum(usd)),by=.(iso3,year)]
stopifnot(fsetequal(published,us$archive))
report <- included(new)[,.(sector_report_usd=sum(usd)),by=.(iso3,year)]
panel <- CJ(iso3=countries$iso3,year=seq(min(old$year,new$year),max(old$year,new$year)))
stopifnot(fsetequal(report,us$us_payments[,.(iso3,year,sector_report_usd=database_usd)]))
panel <- Reduce(function(a,b) merge(a,b,by=c("iso3","year"),all.x=TRUE),list(panel,us$us_payments,report,us$archive))
status_for <- function(database_usd,sector_report_usd) fcase(is.na(database_usd) & is.na(sector_report_usd),"Neither release",
                       is.na(database_usd),"Sector file only", is.na(sector_report_usd),"Database only",
                       database_usd==sector_report_usd,"Amounts agree",sector_report_usd>database_usd,"Higher in sector file",
                       default="Lower in sector file")
panel[, status := status_for(database_usd,sector_report_usd)]
panel[, previous_status := status_for(previous_database_usd,sector_report_usd)]
# Signed dollar differences are defined only where both country-year observations exist.
panel[, difference_usd := sector_report_usd-database_usd]
fwrite(merge(countries,panel,by="iso3"),file.path(out,"us-country-year-reconciliation.csv"))
national <- function(x) {
  x[,.(report_world_usd=sum(usd),report_in_registry_usd=sum(usd[iso3 %in% countries$iso3]),
       report_outside_registry_usd=sum(usd[!iso3 %in% countries$iso3]),
       registry_countries=uniqueN(iso3[iso3 %in% countries$iso3])),by=year]
}
nation <- rbindlist(list(country_archive=national(old),sector_archive=national(new)),idcol="release")
nation <- merge(nation,us$us_payments[,.(database_usd=sum(database_usd)),by=year],by="year",all.x=TRUE)
nation <- merge(nation,us$archive[,.(previous_database_usd=sum(previous_database_usd)),by=year],by="year",all.x=TRUE)
stopifnot(all(nation$report_world_usd==nation$report_in_registry_usd+nation$report_outside_registry_usd),
          nation[release=="sector_archive",all(report_in_registry_usd==database_usd)],
          nation[release=="country_archive",all(report_in_registry_usd==previous_database_usd)])
setorder(nation,release,year)
fwrite(nation,file.path(out,"us-national-reconciliation.csv"))
unmapped <- rbindlist(list(country_archive=old,sector_archive=new),idcol="release")[
  !iso3 %in% countries$iso3, .(usd=sum(usd),n=.N),by=.(release,year,source_code=iso3,label)]
fwrite(unmapped,file.path(out,"us-outside-registry.csv"))

# Assert the report transcription against the original Treasury PDF, using the
# header's column C (drawdowns) and table row's currency, never the debt stock.
pdf <- file.path("data/cache",audit_sources[source_id=="kenya_debt",file_name])
page <- function(i) {
  text <- system2("pdftotext",c("-layout","-f",i,"-l",i,shQuote(pdf),"-"),stdout=TRUE)
  stopifnot(is.null(attr(text,"status")))
  text
}
summary_page <- page(1)
exim_row <- grep("^Exim Bank of China\\s+CNY",summary_page)
stopifnot(length(exim_row)==1L, any(grepl("DRAW DOWNS",summary_page,fixed=TRUE)))
get_draw <- function(line,currency) {
  fields <- strsplit(trimws(sub(paste0("^.*?\\b",currency,"\\s+"),"",line,perl=TRUE)),"\\s+")[[1]]
  if(fields[3]=="-") return(0)
  as.numeric(gsub(",","",fields[3],fixed=TRUE))
}
draw <- c(get_draw(summary_page[exim_row],"CNY"),get_draw(summary_page[exim_row+1L],"USD"))
loan <- cn$kenya[id=="gcdf-31777" & measure=="adjusted commitment"]
p23 <- page(23)
loan_line <- grep("^2014006_1 ",p23,value=TRUE)
stopifnot(length(loan_line)==1L,get_draw(loan_line,"USD")==0,grepl("1,600,000,000.00",loan_line,fixed=TRUE),
          nrow(loan)==1L,loan$usd==1600000000,loan$year==2014,
          identical(draw,c(454243778.75,44721731.99)))
by_currency <- cn$kenya[measure=="borrower-reported drawdown",.(amount=sum(reported_amount)),by=reported_currency]
database_draw <- by_currency$amount[match(c("CNY","USD"),by_currency$reported_currency)]
stopifnot(identical(draw,database_draw))
kenya <- data.table(iso3="KEN",period=c("2014-05-11","FY2022/23","FY2022/23"),
  measure=c("Railway agreement, register 2014006_1","China Eximbank drawdowns","China Eximbank drawdowns"),
  currency=c("USD","CNY","USD"),national_amount=c(loan$usd,draw),database_amount=c(loan$usd,database_draw),
  assessment=c("Agreement present: gcdf-31777","Reconciled facility drawdowns","Reconciled facility drawdowns"),
  pdf_page=c(23L,1L,1L))
fwrite(kenya,file.path(out,"kenya-register-checks.csv"))
for (kind in c("undated_results","missing_stakes"))
  fwrite(rbindlist(list(USA=us[[kind]],CHN=cn[[kind]]),idcol="provider"),file.path(out,paste0(kind,".csv")))
fwrite(cn$payments,file.path(out,"chinese-payment-evidence.csv"))
fwrite(cn$missing_commitments,file.path(out,"missing_commitments.csv"))
greenbook <- sheet("greenbook",6)
setnames(greenbook,c("fy","region","label","category","group","agency","account","usd","constant"))
greenbook[, period:=fifelse(fy=="1976.9","1976 transition quarter",paste0("FY",fy))]
greenbook[, usd:=as.numeric(usd)]
greenbook[, iso3:=to_iso(label)]
greenbook <- greenbook[!is.na(fy), .(report_all_usd=sum(usd,na.rm=TRUE),
  report_unmapped_economic_usd=sum(usd[category=="Economic" & !iso3 %in% countries$iso3],na.rm=TRUE),
  report_all_military_usd=sum(usd[category=="Military"],na.rm=TRUE)),by=period]
greenbook <- merge(greenbook,us$economic,by="period",all.x=TRUE)
greenbook[is.na(database_economic_usd), database_economic_usd:=0]
stopifnot(all(greenbook$report_all_usd==greenbook$database_economic_usd+greenbook$report_unmapped_economic_usd+greenbook$report_all_military_usd))
fwrite(greenbook,file.path(out,"us-greenbook-reconciliation.csv"))

# Compact rows for a standalone country-by-year matrix; the CSV retains named fields.
payload <- list(countries=countries,series=series,
  cells=unname(as.matrix(cells[,.(sid,match(iso3,countries$iso3),year,n,known,reported,zeroes,eligible)])),
  usa=unname(as.matrix(panel[,.(match(iso3,countries$iso3),year,database_usd,sector_report_usd,previous_database_usd)])),
  national=nation,greenbook=greenbook,kenya=kenya,sources=unique(rbind(audit_sources,project_sources),by="source_id"))
js <- jsonlite::toJSON(payload,na="null",digits=NA,dataframe="rows",matrix="rowmajor")
template <- read_text("audit/coverage.html")
template <- paste(strsplit(template,"/* TOA_FONTS */",fixed=TRUE)[[1]],collapse=web_fonts_css())
template <- paste(strsplit(template,"/* COVERAGE_JS */",fixed=TRUE)[[1]], collapse=read_text("audit/coverage.js"))
parts <- strsplit(template,"<!-- DATA -->",fixed=TRUE)[[1]]
stopifnot(length(parts)==2L)
writeLines(paste0(parts[1],gsub("<","\\u003c",js,fixed=TRUE),parts[2]),
           file.path(out,"Trade-over-Aid-coverage.html"),useBytes=TRUE)
cat(nrow(countries),"countries and territories;",nrow(series),"series;",nrow(panel),
    "U.S. country-year comparisons. Treasury and same-vintage checks passed.\n")
