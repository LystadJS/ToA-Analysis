# Build a country-partitioned snapshot for the offline HTML atlas.
source("R/common.R")
source("R/fonts.R")
source("R/atlas_contributors.R")
source("R/country_profile.R")
source("R/evaluation_exports.R")
dir.create("artifacts/atlas-build", recursive=TRUE, showWarnings=FALSE)
writeLines(web_fonts_css(),"artifacts/atlas-build/fonts.css",useBytes=TRUE)
read_release <- function(database) {
  con <- connect(database)
  on.exit(dbDisconnect(con))
  dbWithTransaction(con, {
    dbExecute(con,"SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
    read <- function(query) as.data.table(dbGetQuery(con,query))
    list(country=read("SELECT * FROM toa.country ORDER BY iso3"),
         source=read("SELECT * FROM toa.source ORDER BY source_id"),
         program=read("SELECT * FROM toa.program ORDER BY iso3, year DESC NULLS LAST, id"),
         finance=read("SELECT p.iso3,f.* FROM toa.finance f JOIN toa.program p ON p.id=f.program_id ORDER BY p.iso3,f.flow_year DESC NULLS LAST,f.program_id,f.measure,f.period_ref"),
         result=read("SELECT p.iso3,r.* FROM toa.result r JOIN toa.program p ON p.id=r.program_id ORDER BY p.iso3,r.id"),
         context=read("SELECT * FROM toa.context ORDER BY iso3,source_id,year"),
         exclusions=read("SELECT * FROM toa.exclusions ORDER BY source_id,reason,label"))
  })
}
us <- read_release("toa_us")
cn <- read_release("toa_china")
stopifnot(identical(us$country,cn$country),identical(us$context,cn$context))
sources <- unique(rbind(us$source,cn$source))
stopifnot(!anyDuplicated(sources$source_id))
json <- function(x) jsonlite::toJSON(x,auto_unbox=TRUE,na="null",null="null",digits=NA)
# Compress each country independently so selecting one never parses the other 249 dossiers.
db <- connect("toa_us")
load_rows <- function(table) as.data.table(dbGetQuery(db,paste("SELECT * FROM toa.",table,sep="")))
us$contribution <- load_rows("us_contribution")
goods <- load_rows("us_goods_trade")
relationships <- load_rows("us_relationship")
evaluations <- read_evaluation_tables(db)
dbDisconnect(db)
us_results <- merge(us$result,us$program[,.(program_id=id,source_id,name,locator,citation)],by="program_id")
us_results[us$source,on="source_id",archive:=i.download_url]
profiles <- list()
bundles <- list()
review_bundles <- list()
countries <- copy(us$country)
for (code in countries$iso3) {
  profiles[[code]] <- country_profile(countries[iso3==code,name],code,goods[iso3==code],
      relationships[iso3==code],us_results[iso3==code])
  review <- lapply(evaluations,function(x) x[iso3==code])
  review_bundles[[code]] <- jsonlite::base64_enc(memCompress(charToRaw(enc2utf8(as.character(json(review)))),type="gzip"))
  tables <- list()
  for (tab in c("program","finance","result")) {
    tables[[tab]] <- rbindlist(list(USA=us[[tab]][iso3==code], CHN=cn[[tab]][iso3==code]),idcol="provider")
  }
  tables$context <- us$context[iso3==code]
  bundles[[code]] <- jsonlite::base64_enc(memCompress(charToRaw(enc2utf8(as.character(json(tables)))),type="gzip"))
}
countries[, us := tabulate(match(us$program$iso3,iso3),nbins=.N)]
countries[, cn := tabulate(match(cn$program$iso3,iso3),nbins=.N)]
sponsor_equity <- function(release) {
  sponsor_ids <- release$program[source_id=="ppi", id]
  release$finance[program_id %in% sponsor_ids & eligible_for_summary,
                  .(disclosed=if(all(is.na(usd))) NA_real_ else sum(usd,na.rm=TRUE), complete=all(!is.na(usd))), by=iso3]
}
us_sponsors <- sponsor_equity(us)
cn_sponsors <- sponsor_equity(cn)
countries[us_sponsors, `:=`(us_equity=i.disclosed,us_equity_complete=i.complete), on="iso3"]
countries[cn_sponsors, `:=`(cn_equity=i.disclosed,cn_equity_complete=i.complete), on="iso3"]
stopifnot(sum(countries$us)==nrow(us$program),sum(countries$cn)==nrow(cn$program))
exclusions <- rbindlist(list(USA=us$exclusions, CHN=cn$exclusions), idcol="provider")
writeLines(json(list(countries=countries,sources=sources,exclusions=exclusions,profiles=profiles,bundles=bundles,evaluations=review_bundles,reviewed_countries=as.list(sort(unique(evaluations$reports[eligibility=="Donor or host evaluation",iso3]))),contributors=atlas_contributors(us))),
           "artifacts/atlas-build/snapshot.json", useBytes=TRUE)
cat(nrow(countries),"countries;",sum(countries$us),"U.S. and",sum(countries$cn),"PRC program records\n")
