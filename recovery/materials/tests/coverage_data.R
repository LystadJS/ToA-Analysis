# Independent release checks for the embedded matrix and its report reconciliations.
source("R/common.R")
out <- "artifacts/coverage"
html <- paste(readLines(file.path(out,"Trade-over-Aid-coverage.html"),warn=FALSE),collapse="\n")
payload <- strsplit(strsplit(html,'<script id="data" type="application/json">',fixed=TRUE)[[1]][2],
                    '</script>',fixed=TRUE)[[1]][1]
d <- jsonlite::fromJSON(payload)
stopifnot(nrow(d$countries)==250L,!anyDuplicated(d$countries$iso3))
m <- as.data.table(d$cells)
setnames(m,c("sid","country","year","n","known","reported","zeroes","eligible"))
m[,iso3:=d$countries$iso3[country]]
m[, country:=NULL]
m <- merge(as.data.table(d$series)[,.(sid,provider,kind,source_id,series)],m,by="sid")
m[,sid:=NULL]
csv <- fread(file.path(out,"country-year-observations.csv"))
stopifnot(fsetequal(m,csv),sum(m$n[m$kind=="Context"])==1279)
for (provider_name in c("USA","CHN")) {
  con <- connect(if(provider_name=="USA") "toa_us" else "toa_china")
  for (category in c(Funding="finance",Programs="program",Results="result")) {
    kind_name <- switch(category,finance="Funding",program="Programs",result="Results")
    count <- dbGetQuery(con,paste0("SELECT count(*) AS n FROM toa.",category))$n
    stopifnot(m[provider==provider_name & kind==kind_name,sum(n)]==count)
  }
  dbDisconnect(con)
}
outcomes <- m[source_id=="mcc" & kind=="Results"]
stopifnot(all(is.na(outcomes$year)),sum(outcomes$n)==4737,sum(outcomes$known)==3089,sum(outcomes$reported)==3299)
stopifnot(m[source_id=="ppi" & kind=="Funding" & provider=="USA",sum(known)]==80,
          m[source_id=="ppi" & kind=="Funding" & provider=="CHN",sum(known)]==52,
          m[provider=="CHN" & series=="disbursement" & kind=="Funding",sum(n)]==11,
          m[provider=="CHN" & series=="disbursement" & kind=="Funding",uniqueN(iso3)]==4,
          m[series=="disbursement" & kind=="Funding" & iso3=="KEN" & provider=="CHN",.N]==0)
usa <- as.data.table(d$usa)
setnames(usa,c("country","year","database_usd","sector_report_usd"))
usa[,iso3:=d$countries$iso3[country]]
panel <- fread(file.path(out,"us-country-year-reconciliation.csv"),integer64="double")
stopifnot(nrow(usa)==250L*25L,!anyDuplicated(usa,by=c("iso3","year")),
          fsetequal(usa[,.(iso3,year,database_usd,sector_report_usd)],panel[,.(iso3,year,database_usd,sector_report_usd)]),
          panel[year==2024,sum(database_usd,na.rm=TRUE)]==5919082291,
          panel[year==2024,sum(sector_report_usd,na.rm=TRUE)]==42896561185,
          panel[year==2024 & status=="Sector file only",sum(sector_report_usd)]==168103368,
          panel[year==2024 & status=="Sector file only",.N]==52,
          panel[year==2025 & !is.na(sector_report_usd),.N]==173,
          all(is.na(panel[is.na(database_usd) | is.na(sector_report_usd),difference_usd])))
nat <- as.data.table(d$national)
scope <- fread(file.path(out,"us-outside-registry.csv"),integer64="double")
check <- merge(nat,scope[,.(unmapped=sum(usd)),by=.(release,year)],by=c("release","year"))
stopifnot(nrow(check)==nrow(nat),all(check$unmapped==check$report_outside_registry_usd))
g <- as.data.table(d$greenbook)
stopifnot(nrow(g)==76,all(g$report_all_usd==g$database_economic_usd+g$report_unmapped_economic_usd+g$report_all_military_usd),
          g[period=="FY2020",database_economic_usd]==25293693021,
          nrow(d$kenya)==3,identical(d$kenya$pdf_page,c(23L,1L,1L)))
cat("Embedded HTML, exported cells and database counts reconcile for all 250 jurisdictions and 41 series. National and recipient report checks passed.\n")
