# Source-specific annual totals are deliberately kept in separate measures.
relationship_tables <- c("us_goods_trade","us_contribution","us_relationship")
relationship_sources <- function() rbindlist(lapply(c("data/atlas_sources.tsv","data/relationship_sources.tsv",
                                                      "data/relationship_local_sources.tsv"),fread))

country_goods <- function(country) {
  x <- as.data.table(readxl::read_excel("data/cache/census-country.xlsx"))
  x[,year:=as.integer(year)]
  # In the unfinished year the publisher fills unreleased months with zero.
  full_years <- x[CTY_CODE=="0015" & IDEC>0 & EDEC>0,year]
  text <- grep("^[0-9]{4} +[|]",readLines("data/cache/schedule-c.txt"),value=TRUE)
  codes <- fread(text=paste(text,collapse="\n"),sep="|",colClasses="character",header=FALSE)
  setnames(codes,c("CTY_CODE","label","iso2"))
  iso <- jsonlite::fromJSON(cached("iso"))[["3166-1"]]
  codes[,iso3:=iso$alpha_3[match(iso2,iso$alpha_2)]]
  codes[iso2=="KV",iso3:="XKX"]
  codes[iso2 %in% c("GZ","WE"),iso3:="PSE"]
  # Use contemporary Schedule C geography. Historical joint territories and
  # superseded statistical areas are not distributed to their successors.
  d <- merge(x[year %in% full_years],codes[iso3 %in% country$iso3],by="CTY_CODE")
  stopifnot(!anyDuplicated(d,by=c("CTY_CODE","year")),!anyNA(d$IYR),!anyNA(d$EYR))
  d[,.(iso3,year,census_code=CTY_CODE,exports_usd=round(EYR*1e6),
       imports_usd=round(IYR*1e6),source_id="census_goods")]
}

contribution_rows <- function(us) {
  raw <- fread("data/cache/us-funding-agency.csv",integer64="double")
  d <- raw[`Transaction Type Name`=="Disbursements"]
  stopifnot(!anyNA(d$current_amount),!anyDuplicated(d,by=c("Country Code","Fiscal Year","Funding Agency ID","Funding Account ID")))
  d[,iso3:=fifelse(`Country Code`=="CS-KM","XKX",`Country Code`)]
  agency <- d[iso3 %in% us$country$iso3,.(iso3,source_id="funding_agency",year=as.integer(`Fiscal Year`),
                                         actor=`Funding Agency Name`,amount=current_amount)]
  f <- merge(us$finance[eligible_for_summary==TRUE & !is.na(flow_year)],
             us$program[,.(program_id=id,iso3,source_id,actor)],by="program_id")
  extra <- f[(source_id=="greenbook" & measure=="obligation" & period_ref!="1976 transition quarter") |
             (source_id=="ppi" & measure=="sponsor equity commitment") |
             (source_id=="gates" & measure=="private grant commitment") |
             (source_id=="dfc" & measure=="commitment or exposure"),
             .(iso3,source_id,year=flow_year,actor,amount=usd)]
  x <- fread("data/cache/exim-authorizations.csv",integer64="double")
  stopifnot(!anyDuplicated(x[["Unique Identifier"]]))
  x <- x[Decision=="Approved" & `Deal Cancelled`=="No"]
  x[,iso3:=to_iso(Country)]
  x[Country=="Micronesia",iso3:="FSM"]
  exim <- x[iso3 %in% setdiff(us$country$iso3,"USA"),
    .(iso3,source_id="exim",year=as.integer(`Fiscal Year`),actor="Export-Import Bank of the United States",
      amount=numeric_value(`Approved/Declined Amount`))]
  d <- rbindlist(list(agency,extra,exim))
  d[is.na(actor) | !nzchar(trimws(actor)),actor:="Unspecified contributor"]
  d[,.(cents=if(all(is.na(amount))) NA_real_ else sum(round(amount*100),na.rm=TRUE),
       known=sum(!is.na(amount)),records=.N),by=.(iso3,source_id,year,actor)]
}

build_relationships <- function(us) {
  sources <- relationship_sources()
  local <- fread("data/relationship_local_sources.tsv")
  for (i in seq_len(nrow(local))) {
    hash <- system2("sha256sum",file.path("data",local$file_name[i]),stdout=TRUE)
    stopifnot(sub(" .*","",hash)==local$sha256[i])
  }
  us$source <- rbindlist(list(us$source,sources))[!duplicated(source_id)]
  fund <- contribution_rows(us)
  kinds <- c(funding_agency="Funding agency",greenbook="Historical assistance agency",dfc="Development finance",
             exim="Export credit",ppi="Infrastructure sponsor",gates="Philanthropy")
  roles <- c(funding_agency="Recipient allocation in federal disbursement accounts",
    greenbook="Economic assistance obligations recorded",dfc="Project in DFC portfolio",
    exim="Destination of approved export finance",ppi="Listed infrastructure sponsor",gates="Local grant commitment")
  role_details <- c(funding_agency="Net payments attributed to this recipient can fund implementing partners.",
    greenbook="Greenbook economic obligations, including predecessor agencies where identified.",
    dfc="Active-project snapshot. The reported instrument can be financing or insurance exposure.",
    exim="Approved, noncancelled authorizations to the named market. U.S. exporters or lenders can receive the proceeds. FY2025 ends in Q3.",
    ppi="A listed U.S. sponsor has a stake in a project at financial close. Disclosures vary.",
    gates="Reviewed Foundation grant commitments to locally identified grantees.")
  org <- fund[,.(first_year=min(year),last_year=max(year)),by=.(iso3,source_id,name=actor)]
  org[, `:=`(kind=unname(kinds[source_id]),status=unname(roles[source_id]),detail=unname(role_details[source_id]))]
  org[,citation:=us$source$publisher_url[match(source_id,us$source$source_id)]]
  # Include undated portfolio projects and retain MCC program names as searchable evidence.
  dfc <- us$program[source_id=="dfc",.(iso3,source_id,name=actor,kind="Development finance",
    status=roles[["dfc"]],detail=role_details[["dfc"]],citation=src_url("dfc"))]
  org <- rbindlist(list(org,unique(dfc)[!org,on=.(iso3,source_id,name)]),fill=TRUE)
  mcc <- us$program[source_id=="mcc",.(detail=paste(sort(unique(sub(" — .*","",name))),collapse="; ")),by=iso3]
  mcc[, `:=`(source_id="mcc",name="Millennium Challenge Corporation",kind="Development program",
             status="Program monitored by MCC",citation=src_url("mcc"))]
  agoa <- us$program[source_id=="agoa"][order(year),.(first_year=min(year),last_year=max(year),
    status=paste0("Eligibility in ",last(year),": ",sub("Source eligibility ","",last(status))),
    detail="Unilateral trade preference. Country-year eligibility and U.S. imports claiming the preference appear in the program and results records."),by=iso3]
  agoa[, `:=`(name="African Growth and Opportunity Act (AGOA)",kind="Trade preference",source_id="agoa",citation=src_url("agoa"))]
  fta <- fread("data/us_fta_partners.tsv")
  fta <- fta[,.(iso3,source_id="ustr_fta",name=agreement,kind="Trade agreement",status="Party to agreement through 2025",
                first_year=entry_year,detail="Year of entry into force for this partner. The inventory covers comprehensive U.S. free trade agreements.",citation)]
  compact <- fread("data/us_free_association.tsv")[,.(iso3,source_id="cofa",name="Compact of Free Association",
    kind="Compact",status="Sovereign state in free association with the United States",first_year=entry_year,
    detail=paste("The compact governs the bilateral relationship, including economic assistance.",statute),citation)]
  bits <- fread("data/cache/unctad-bit.csv",select=c("Party1","Party2","Treaty type","Status",
                                                      "Date of signature","Date of entry into force","name"))
  bits <- bits[`Treaty type`=="Bilateral Investment Treaties" &
               (Party1=="United States of America" | Party2=="United States of America")]
  bits[,iso3:=to_iso(fifelse(Party1=="United States of America",Party2,Party1))]
  stopifnot(!anyNA(bits$iso3))
  bits <- bits[,.(iso3,source_id="unctad_bit",name,kind="Investment treaty",
    status=paste("UNCTAD archive status ·",Status),
    first_year=as.integer(substr(`Date of signature`,7,10)),
    detail=paste0("First year shown is signature. ",
      fifelse(is.na(`Date of entry into force`) | !nzchar(`Date of entry into force`),"",
              paste0("Entry into force in the source: ",`Date of entry into force`,". ")),
      "Status is from the archived inventory and may have changed."),
    citation=sources[source_id=="unctad_bit",download_url])]
  roster <- fread("data/usun_roster.tsv")
  stopifnot(nrow(roster)>0,!anyDuplicated(roster$iso3),all(roster$iso3 %in% us$country$iso3),
            all(fta$iso3 %in% us$country$iso3),!anyDuplicated(fta$iso3))
  toa <- us$country[,.(iso3,source_id="usun_toa",name="Trade over Aid",kind="Initiative",
    status=fifelse(iso3 %in% roster$iso3,"Listed on supplied USUN roster","Not listed on supplied USUN roster"),
    detail="USUN roster transcribed 19 November 2026. It identifies participation only. Joining dates, contributions and outcomes are unreported.",
    citation="https://usun.usmission.gov/trade-over-aid/")]
  us$us_relationship <- rbindlist(list(org,mcc,agoa,fta,toa,bits,compact),fill=TRUE)
  us$us_goods_trade <- country_goods(us$country)
  us$us_contribution <- fund
  us
}
