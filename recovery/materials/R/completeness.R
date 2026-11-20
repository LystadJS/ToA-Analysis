# Read-only audit at the native observation date of each series.
source("R/common.R")
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
                          WHERE p.source_id='fa' AND f.measure='disbursement' GROUP BY p.iso3,f.flow_year"),
         kenya=get("SELECT p.id,p.year,p.name,f.measure,f.usd FROM toa.program p
                   JOIN toa.finance f ON p.id=f.program_id WHERE p.iso3='KEN'
                   AND (p.id='gcdf-31777' OR f.measure LIKE '%disbursement%')"))
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
published <- included(old)[,.(database_usd=sum(usd)),by=.(iso3,year)]
stopifnot(fsetequal(published,us$us_payments))
report <- included(new)[,.(sector_report_usd=sum(usd)),by=.(iso3,year)]
panel <- CJ(iso3=countries$iso3,year=seq(min(old$year,new$year),max(old$year,new$year)))
panel <- merge(merge(panel,us$us_payments,all.x=TRUE),report,all.x=TRUE)
panel[, status := fcase(is.na(database_usd) & is.na(sector_report_usd),"Neither release",
                       is.na(database_usd),"Sector file only", is.na(sector_report_usd),"Database only",
                       database_usd==sector_report_usd,"Amounts agree",sector_report_usd>database_usd,"Higher in sector file",
                       default="Lower in sector file")]
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
stopifnot(all(nation$report_world_usd==nation$report_in_registry_usd+nation$report_outside_registry_usd),
          nation[release=="country_archive",all(report_in_registry_usd==database_usd)])
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
  as.numeric(gsub(",","",fields[3],fixed=TRUE))
}
draw <- c(get_draw(summary_page[exim_row],"CNY"),get_draw(summary_page[exim_row+1L],"USD"))
loan <- cn$kenya[id=="gcdf-31777" & measure=="adjusted commitment"]
p23 <- page(23)
loan_line <- grep("^2014006_1 ",p23,value=TRUE)
stopifnot(length(loan_line)==1L,grepl("1,600,000,000.00",loan_line,fixed=TRUE),
          nrow(loan)==1L,loan$usd==1600000000,loan$year==2014,
          identical(draw,c(454243778.75,44721731.99)),!any(grepl("disbursement",cn$kenya$measure)))
kenya <- data.table(iso3="KEN",period=c("2014-05-11","FY2022/23","FY2022/23"),
  measure=c("Railway agreement, register 2014006_1","China Eximbank drawdowns","China Eximbank drawdowns"),
  currency=c("USD","CNY","USD"),national_amount=c(loan$usd,draw),database_amount=c(loan$usd,NA,NA),
  assessment=c("Agreement present: gcdf-31777","No structured Kenyan disbursement row","No structured Kenyan disbursement row"),
  pdf_page=c(23L,1L,1L))
fwrite(kenya,file.path(out,"kenya-register-checks.csv"))
# Compact rows for a standalone country-by-year matrix; the CSV retains named fields.
payload <- list(countries=countries,series=series,
  cells=unname(as.matrix(cells[,.(sid,match(iso3,countries$iso3),year,n,known,reported,zeroes,eligible)])),
  usa=unname(as.matrix(panel[,.(match(iso3,countries$iso3),year,database_usd,sector_report_usd)])),
  national=nation,kenya=kenya,sources=rbind(audit_sources,project_sources))
js <- jsonlite::toJSON(payload,na="null",digits=NA,dataframe="rows",matrix="rowmajor")
template <- read_text("audit/coverage.html")
parts <- strsplit(template,"<!-- DATA -->",fixed=TRUE)[[1]]
stopifnot(length(parts)==2L)
writeLines(paste0(parts[1],gsub("<","\\\\u003c",js,fixed=TRUE),parts[2]),
           file.path(out,"Trade-over-Aid-coverage.html"),useBytes=TRUE)
cat(nrow(countries),"countries and territories;",nrow(series),"series;",nrow(panel),
    "U.S. country-year comparisons. Treasury and same-vintage checks passed.\n")
