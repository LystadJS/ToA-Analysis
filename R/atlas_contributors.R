# Keep authorization rows distinct from the top-deal ranking, which deduplicates renewals.
atlas_exim_authorizations <- function(country) {
  x <- fread("data/cache/exim-authorizations.csv",integer64="double")
  x <- x[Decision=="Approved" & `Deal Cancelled`=="No"]
  x[,iso3:=to_iso(Country)]
  x[Country=="Micronesia",iso3:="FSM"]
  x <- x[iso3 %in% setdiff(country$iso3,"USA")]
  csv_text <- function(value) trimws(gsub('""','"',value,fixed=TRUE))
  party <- function(value) {
    value <- csv_text(value)
    fifelse(is.na(value) | value %in% c("NA","N/A","Unknown","Various",""),NA_character_,value)
  }
  d <- x[,.(iso3,year=as.integer(`Fiscal Year`),deal=`Deal Number`,id=`Unique Identifier`,
            name=fcoalesce(party(`Primary Borrower`),party(`Primary Source of Repayment (PSOR)`),
                           party(`Primary Applicant`),`Deal Number`),
            product=csv_text(`Product Description`),cents=round(numeric_value(`Approved/Declined Amount`)*100))]
  stopifnot(!anyDuplicated(d$id),!anyNA(d$cents))
  setorder(d,year,-cents,iso3,deal,id)
  d
}

# Attribution comes from the funding file. The sector vintage supplies a separate benchmark.
atlas_contributors <- function(us) {
  manifest <- fread("data/atlas_sources.tsv")
  by_country <- copy(us$contribution)
  setnames(by_country,"source_id","source")
  overall <- by_country[,.(cents=if(all(is.na(cents))) NA_real_ else sum(cents,na.rm=TRUE),
                           known=sum(known),records=sum(records)),by=.(source,year,actor)][,iso3:="ALL"]
  all_rows <- rbindlist(list(by_country,overall),use.names=TRUE)
  sector <- us$program[source_id=="us_sector_review",id]
  benchmark <- us$finance[eligible_for_summary==TRUE & program_id %in% sector & measure=="disbursement",
                          .(total_cents=sum(round(usd*100))),by=.(iso3,year=flow_year)]
  annual <- rbindlist(list(benchmark,benchmark[,.(total_cents=sum(total_cents)),by=year][,iso3:="ALL"]),use.names=TRUE)
  exim <- atlas_exim_authorizations(us$country)
  exim_totals <- exim[,.(cents=sum(cents),records=.N),by=.(iso3,year)]
  stopifnot(fsetequal(exim_totals,us$contribution[source_id=="exim",.(iso3,year,cents,records=as.integer(records))]))
  bundle <- function(code) {
    values <- list(rows=all_rows[iso3==code,.(source,year,actor,cents,known,records)][order(source,year,actor)],
                   benchmark=annual[iso3==code,.(year,total_cents)][order(year)],
                   exim=if(code=="ALL") exim else exim[iso3==code])
    jsonlite::base64_enc(memCompress(charToRaw(enc2utf8(as.character(json(values)))),type="gzip"))
  }
  codes <- c(us$country$iso3,"ALL")
  list(source=as.list(manifest[1]),scopes=setNames(lapply(codes,bundle),codes))
}
