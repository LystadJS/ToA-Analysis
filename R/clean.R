# Return one release at a time. Source row numbers refer to the checksum-pinned files.
clean_release <- function(provider) {
  iso <- jsonlite::fromJSON(cached("iso"))[["3166-1"]]
  country <- rbind(data.table(iso3=iso$alpha_3, name=iso$name, code_system="ISO 3166-1"),
                   data.table(iso3="XKX", name="Kosovo", code_system="user assigned"))
  programs <- list()
  money <- list()
  results <- list()
  excluded <- list()

  retain <- function(x, source, label, code) {
    keep <- code %in% country$iso3
    if (any(!keep)) {
      excluded[[source]] <<- data.table(label=fifelse(is.na(label[!keep]), "(missing)", label[!keep]))[
        , .(n=.N), by=label][, `:=`(source_id=source, reason="Outside current country concordance")]
    }
    x[, iso3 := code]
    x[keep]
  }
  finance <- function(p, amount, measure, instrument, eligible=TRUE, estimated=NA_character_) {
    data.table(program_id=p$id, measure=measure, instrument=instrument, usd=as.numeric(amount),
               flow_year=p$year, period_ref=fcoalesce(p$period,"Undated"), eligible_for_summary=eligible,
               amount_estimated=estimated)
  }
  if (provider == "USA") {
    x <- sheet("greenbook",6)
    setnames(x,c("fy","region","label","category","group","agency","account","usd","constant"))
    x[, row := .I+7L]
    x <- x[category=="Economic"]
    x <- retain(x,"greenbook",x$label,to_iso(x$label))
    p <- x[, .(id=paste0("gb-",row), iso3, source_id="greenbook", locator=paste("Excel row",row),
               name=account, actor=agency, channel="government", sector=group, year=as.integer(as.numeric(fy)),
               period=fifelse(fy=="1976.9","1976 transition quarter",paste0("FY",fy)))]
    programs$greenbook <- p
    money$greenbook <- finance(p,as.numeric(x$usd),"obligation","economic assistance account")

    x <- fread(cached("fa"))[`Transaction Type Name`=="Disbursements"]
    x[, row_key := paste(`Country Code`,`Fiscal Year`,sep="/")]
    code <- fifelse(x[["Country Code"]]=="CS-KM","XKX",x[["Country Code"]])
    x <- retain(x,"fa",x[["Country Name"]],code)
    p <- x[, .(id=paste0("fa-",row_key),iso3,source_id="fa",locator=row_key,
               name="All reported U.S. foreign assistance",actor="U.S. government",
               channel="government",sector="All sectors including military",year=as.integer(substr(`Fiscal Year`,1,4)),
               period=paste0("FY",`Fiscal Year`))]
    programs$fa <- p
    money$fa <- finance(p,x$current_amount,"disbursement","country total")

    x <- fread(cached("sector"),sep="\t")[Aidtype=="Spent" & Category!="Total" & FiscalYear<=2013]
    x[, row := .I]
    x <- retain(x,"sector",x$OperatingUnit,fifelse(x$OperatingUnit=="Kosovo","XKX",x$iso_alpha3))
    p <- x[, .(id=paste0("sector-",iso3,"-",FiscalYear,"-",Category,"-",row),iso3,source_id="sector",
               locator=paste(OperatingUnit,FiscalYear,Category,Aidtype,sep="/"),name=Category,actor="USAID",
               channel="government",sector=Category,year=FiscalYear,period=paste0("FY",FiscalYear))]
    programs$sector <- p
    money$sector <- finance(p,x$AnnualSectorSpent,"disbursement","USAID sector")

    x <- sheet("dfc")
    x[, summary_ok := !duplicated(x) & !duplicated(x,fromLast=TRUE)]
    x[, row := .I+1L]
    x <- retain(x,"dfc",x$Country,to_iso(x$Country))[iso3!="USA"]
    p <- x[, .(id=paste0("dfc-",row),iso3,source_id="dfc",locator=paste("Excel row",row,"project",`Project Number`),
               name=fcoalesce(`Project Name`,"Unnamed DFC project"),actor="U.S. International Development Finance Corporation",
               channel="government",sector=`NAICS Sector`,status="Active portfolio snapshot",
               year=as.integer(`Fiscal Year`),period=fifelse(is.na(`Fiscal Year`),NA_character_,paste0("FY",`Fiscal Year`)),
               details=`Project Description`,citation=`Project Profile URL`)]
    programs$dfc <- p
    money$dfc <- finance(p,numeric_value(x$Committed),"commitment or exposure",x[["Project Type"]],x$summary_ok)

    x <- fread("data/cache/mcc.csv",colClasses="character",na.strings=c("","NA"))
    x <- retain(x,"mcc",x$CountryName,to_iso(x$CountryName))
    # Keep one program record per compact/project. Subgroups remain separate indicators.
    x[, ProjectName := fcoalesce(ProjectName,"Program-level indicators")]
    x[, id := paste("mcc",iso3,ProgramName,ProjectName,sep="/")]
    programs$mcc <- unique(x[,.(id,iso3,source_id="mcc",locator=paste(ProgramName,ProjectName,sep="/"),
         name=paste(ProgramName,ProjectName,sep=" — "),actor="Millennium Challenge Corporation",channel="government")])
    results$mcc <- x[, .(id=paste0("itt-",IndicatorId),program_id=id,indicator=IndicatorName,level=Level,
                         unit=UnitOfMeasure,baseline=numeric_value(Baseline),baseline_year=as.integer(BaselineYear),
                         actual=numeric_value(ActualToDate),baseline_text=Baseline,target_text=EndOfProgramTarget,actual_text=ActualToDate,target=numeric_value(EndOfProgramTarget),
                         method="Program monitoring",interpretation=paste("ITT",IndicatorId,Classification,
                                 fcoalesce(ActivityName,""),"| Actual to date. Reporting end date unspecified."))]
    x <- fread(cached("agoa"))
    x <- retain(x,"agoa",x$country,x$iso3)
    programs$agoa <- x[,.(id=paste("agoa",iso3,year,sep="-"),iso3,source_id="agoa",locator=paste(iso3,year),
            name="African Growth and Opportunity Act",actor="U.S. government",channel="trade preference",
            sector="Market access",year,period=paste0("CY",year),status=paste("Source eligibility",eligible))]
    results$agoa <- x[,.(id=paste0("claim-",iso3,"-",year),program_id=programs$agoa$id,
         indicator="U.S. imports claiming AGOA (D-only)",level="Preference use",unit="current USD",
         actual=agoa_claimed_imports_usd,observed_year=year,method="Customs records",
         interpretation="Customs value of imports claiming the preference. Incremental exports and welfare effects require a counterfactual.")]
    selected <- fread("data/gates_recipients.tsv")
    grants <- fread(cached("gates"),skip="GRANT ID")
    x <- merge(selected,grants,by.x="grant_id",by.y="GRANT ID")
    stopifnot(nrow(x)==nrow(selected), all(x$iso3==to_iso(x[["GRANTEE COUNTRY"]])),
              all(x[["AMOUNT COMMITTED"]]>=1e6))
    p <- x[,.(id=paste0("gates-",grant_id),iso3,source_id="gates",locator=grant_id,
              name=paste("Grant to",GRANTEE),actor="Gates Foundation",channel="private philanthropy",
              sector=TOPIC,year=as.integer(substr(`DATE COMMITTED`,1,4)),period=`DATE COMMITTED`,
              details=PURPOSE,citation=paste0("https://www.gatesfoundation.org/about/committed-grants/",
                  substr(`DATE COMMITTED`,1,4),"/",substr(`DATE COMMITTED`,6,7),"/",tolower(grant_id)))]
    programs$gates <- p
    money$gates <- finance(p,x[["AMOUNT COMMITTED"]],"private grant commitment","foundation grant")
    programs$cases <- fread("data/case_programs.tsv",na.strings="")
    results$cases <- fread("data/case_results.tsv",na.strings="")
    money$cases <- data.table(program_id=c("ftf-ner","moz-rural"),measure="program budget",
            flow_year=c(2018L,2007L),period_ref=c("Compact implemented 2018–2024","2007 compact"),
            instrument=c("compact envelope","original activity budget"),usd=c(442e6,9e6),eligible_for_summary=FALSE)
  } else {
    e <- new.env()
    load(cached("gcdf"),envir=e)
    x <- as.data.table(e$gcdf3_dataset)
    x <- retain(x,"gcdf",x$recipient,x$recipient_iso_3)
    p <- x[,.(id=paste0("gcdf-",aid_data_record_id),iso3,source_id="gcdf",
              locator=as.character(aid_data_record_id),name=title,actor=funding_agencies,
              channel="official finance",sector=sector_name,status,year=commitment_year,period=paste0("CY",commitment_year),
              details=description,citation=paste0("https://china.aiddata.org/projects/",aid_data_record_id,"/"))]
    programs$gcdf <- p
    money$gcdf <- finance(p,x$adjusted_amount_nominal_usd,
              fifelse(x$status=="Pipeline: Pledge","pledge","adjusted commitment"),x$flow_type,
              x$recommended_for_aggregates=="Yes",x$amount_estimated)
    d <- fread("data/gcdf_disbursements.tsv")
    d[,program_id := paste0("gcdf-",record)]
    money$draw <- d[,.(program_id,measure,flow_year=year,period_ref,instrument=x$flow_type[match(record,x$aid_data_record_id)],
                       usd,eligible_for_summary=measure=="disbursement")]
    d <- fread("data/gcdf_results.tsv")
    results$gcdf <- d[,.(id=paste0("route-",record),program_id=paste0("gcdf-",record),indicator,
                        level=fifelse(unit=="kWh","Output","Outcome"),unit,baseline,actual,comparator,observed_year,
                        method=fifelse(unit=="kWh","Reported operational output","Reported before/after"),
                        interpretation=paste(note,"Recorded project completion year:",x$completion_year[match(record,x$aid_data_record_id)]))]
    # Independent 2022–23 extract from the later, wider CLG release. Use nominal amount only.
    x <- fread(cached("clg"))[year %in% 2022:2023]
    x <- retain(x,"clg",x$country_raw,x$country_iso3)
    p <- x[,.(id=paste0("clg-",record_id),iso3,source_id="clg",locator=record_id,
              name=project_title,actor=funder_or_investor,channel="official finance",sector,status,year,
              period=paste0("CY",year),details=paste(flow_class,intent,funder_type,sep=" | "),
              citation=paste0("https://china.aiddata.org/projects/",sub("AIDDATA-","",record_id),"/"))]
    programs$clg <- p
    money$clg <- finance(p,x$amount_nominal_usd_mn*1e6,
              fifelse(x$status=="Pipeline: Pledge","pledge (CLG)","face-value commitment (CLG)"),
              paste(x$flow_class,x$flow_type,sep=" / "),x$recommended_for_aggregates=="Yes")
  }
  x <- sheet("ppi")
  x[, row := .I+1L]
  origin <- if (provider=="USA") "United States" else "China"
  x <- x[InvestmentYear==`Financial closure year` & grepl(origin,`Sponsors Country`,fixed=TRUE)]
  x <- retain(x,"ppi",x$Country,to_iso(x$Country))[iso3!=provider]
  # World Bank puts one sponsor and one country on each workbook line. Company names may contain commas.
  pieces <- function(s) strsplit(s,",\\s*(?:_x000d_|[\r\n])\\s*",perl=TRUE)
  sponsors <- pieces(x$Sponsors)
  origins <- pieces(x[["Sponsors Country"]])
  stopifnot(identical(lengths(sponsors),lengths(origins)))
  x <- x[rep(seq_len(nrow(x)),lengths(sponsors))]
  x[, `:=`(sponsor=trimws(unlist(sponsors)), origin_name=trimws(unlist(origins)), position=seq_len(.N)), by=NULL]
  x <- x[origin_name==origin]
  # A named stakeholder's directly disclosed USD equity in millions; never allocate total project investment.
  equity <- regmatches(x$sponsor,regexec("\\(\\$([0-9,.]+)\\s*/",x$sponsor))
  amount <- vapply(equity,function(v) if(length(v)) numeric_value(v[2])*1e6 else NA_real_,numeric(1))
  p <- x[, .(id=paste("ppi",row,position,sep="-"),iso3,source_id="ppi",
             locator=paste("CustomQuery row",row,sponsor),name=`Project name`,actor=sub(" \\([^()]*\\)\\s*$","",sponsor),
             channel="private participation in infrastructure",sector=`Primary sector`,status=`Project status`,
             year=as.integer(InvestmentYear),period=paste0("CY",InvestmentYear),
             project_investment_usd=numeric_value(TotalInvestment)*1e6,
             details=paste("Reported sponsor origin",origin_name,"|",sponsor,"|",`Type of PPI`,"|",Subsector))]
  p[actor=="Risen Energy Co., Ltd" & provider=="CHN",
    details:=paste(details,"| AidData classifies the named sponsor as Chinese Private Sector in record 90168. Ownership classification is sourced separately from PPI.")]
  programs$ppi <- p
  money$ppi <- finance(p,amount,"sponsor equity commitment","sponsor equity")

  context <- rbindlist(lapply(c("export","import"),function(key) {
    x <- fread(cached(key))
    x <- retain(x,key,x[["Country Name"]],x[["Country Code"]])
    x[,.(iso3,source_id=key,year=Year,days=Value)]
  }))
  p <- rbindlist(programs,fill=TRUE)
  r <- rbindlist(results,fill=TRUE)
  sources <- registry[source_id %in% c("iso",p$source_id,context$source_id)]
  list(source=sources,country=country,program=p,finance=rbindlist(money,fill=TRUE),
       result=r,context=context,exclusions=rbindlist(excluded))
}
