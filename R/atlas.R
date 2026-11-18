# Build a country-partitioned snapshot for the offline HTML atlas.
source("R/common.R")
dir.create("artifacts/atlas-build", recursive=TRUE, showWarnings=FALSE)
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
bundles <- list()
countries <- copy(us$country)
for (code in countries$iso3) {
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
  release$finance[program_id %in% sponsor_ids & eligible_for_summary & !is.na(usd),
                  .(disclosed=sum(usd)), by=iso3]
}
us_sponsors <- sponsor_equity(us)
cn_sponsors <- sponsor_equity(cn)
countries[us_sponsors, us_equity := i.disclosed, on="iso3"]
countries[cn_sponsors, cn_equity := i.disclosed, on="iso3"]
stopifnot(sum(countries$us)==nrow(us$program),sum(countries$cn)==nrow(cn$program))
exclusions <- rbindlist(list(USA=us$exclusions, CHN=cn$exclusions), idcol="provider")
writeLines(json(list(countries=countries,sources=sources,exclusions=exclusions,bundles=bundles)),
           "artifacts/atlas-build/snapshot.json", useBytes=TRUE)
cat(nrow(countries),"countries;",sum(countries$us),"U.S. and",sum(countries$cn),"PRC program records\n")
