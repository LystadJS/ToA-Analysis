# Attribution comes from the funding file. The sector vintage supplies a separate benchmark.
atlas_contributors <- function(us) {
  manifest <- fread("data/atlas_sources.tsv")
  raw <- fread(file.path("data/cache",manifest$file_name),integer64="double")
  agency <- raw[`Transaction Type Name`=="Disbursements"]
  stopifnot(!anyNA(agency$current_amount),
            !anyDuplicated(agency,by=c("Country Code","Fiscal Year","Funding Agency ID","Funding Account ID")))
  agency[,iso3:=fifelse(`Country Code`=="CS-KM","XKX",`Country Code`)]
  agency <- agency[iso3 %in% us$country$iso3,
    .(iso3,year=as.integer(`Fiscal Year`),source="funding_agency",
      actor=`Funding Agency Name`,usd=current_amount)]
  financing <- merge(us$finance[eligible_for_summary==TRUE],
      us$program[,.(program_id=id,source=source_id,actor)],by="program_id")
  benchmark <- financing[source=="us_sector_review" & measure=="disbursement",
                         .(total_cents=sum(round(usd*100))),by=.(iso3,year=flow_year)]
  rows <- rbindlist(list(agency,financing[
    (source=="greenbook" & measure=="obligation" & period_ref!="1976 transition quarter") |
    (source=="ppi" & measure=="sponsor equity commitment") |
    (source=="gates" & measure=="private grant commitment"),.(iso3,year=flow_year,source,actor,usd)]))
  stopifnot(!anyNA(rows$year))
  rows[is.na(actor) | !nzchar(trimws(actor)), actor:="Unspecified contributor"]
  rows[,cents:=round(usd*100)]
  summarize <- function(x,by_fields) x[,.(cents=if(all(is.na(cents))) NA_real_ else sum(cents,na.rm=TRUE),
                                          known=sum(!is.na(cents)),records=.N),by=by_fields]
  by_country <- summarize(rows,c("iso3","source","year","actor"))
  overall <- summarize(rows,c("source","year","actor"))[,iso3:="ALL"]
  all_rows <- rbindlist(list(by_country,overall),use.names=TRUE)
  annual <- rbindlist(list(benchmark,benchmark[,.(total_cents=sum(total_cents)),by=year][,iso3:="ALL"]),use.names=TRUE)
  bundle <- function(code) {
    values <- list(rows=all_rows[iso3==code,.(source,year,actor,cents,known,records)][order(source,year,actor)],
                   benchmark=annual[iso3==code,.(year,total_cents)][order(year)])
    jsonlite::base64_enc(memCompress(charToRaw(enc2utf8(as.character(json(values)))),type="gzip"))
  }
  codes <- c(us$country$iso3,"ALL")
  list(source=as.list(manifest[1]),scopes=setNames(lapply(codes,bundle),codes))
}
