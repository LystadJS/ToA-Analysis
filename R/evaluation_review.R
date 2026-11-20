# Rank identifiable U.S. projects and financing deals, keeping each original
# measure visible. Country, sector and account aggregates cannot identify a project.
evaluation_priority <- function(us) {
  db <- merge(us$finance,us$program[,.(program_id=id,iso3,source_id,name,actor,locator,details,citation)],
              by="program_id")
  dfc <- db[source_id=="dfc" & eligible_for_summary==TRUE & usd>0]
  dfc[,ref:=sub("^Excel row [0-9]+ project ","",locator)]
  dfc[is.na(ref) | ref %in% c("","NA"),ref:=program_id]
  dfc <- dfc[order(-usd,program_id),.SD[1],by=.(iso3,ref)]
  dfc[, description:=sub("^[0-9]{5} - ","",details)]
  dfc[, display:=fifelse(grepl("^[0-9]{5} - ",details) & !is.na(details),paste(name,description,sep=" · "),name)]
  dfc <- dfc[,.(iso3,project_key=paste0("dfc:",ref),title=display,organization=actor,
    source_id,locator,year=flow_year,amount=usd,measure="Largest recorded commitment or exposure for this project number",
    search_name=fifelse(name=="Redacted" | name=="Unnamed DFC project",ref,display),citation)]
  ppi <- db[source_id=="ppi" & eligible_for_summary==TRUE & !is.na(usd) & usd>0]
  ppi <- unique(ppi,by=c("iso3","name","actor","flow_year","usd"))
  ppi <- ppi[,.(organization=paste(sort(unique(actor)),collapse="; "),
    amount=sum(usd),locator=paste(sort(unique(program_id)),collapse=", ")),by=.(iso3,title=name,year=flow_year)]
  ppi[, `:=`(project_key=paste("ppi",iso3,year,title,sep=":"),source_id="ppi",measure="Disclosed U.S. sponsor equity at financial close",search_name=title)]
  gates <- db[source_id=="gates" & usd>0,.(iso3,project_key=program_id,title=paste0(name," · ",details),
    organization=actor,source_id,locator,year=flow_year,amount=usd,measure="Grant commitment",search_name=paste(name,details),citation)]
  # A repeated export-finance authorization is not an additional project cost.
  ex <- fread("data/cache/exim-authorizations.csv",integer64="double")
  ex <- ex[Decision=="Approved" & `Deal Cancelled`=="No"]
  ex[,iso3:=to_iso(Country)]; ex[Country=="Micronesia",iso3:="FSM"]
  ex <- ex[iso3 %in% setdiff(us$country$iso3,"USA")]
  ex[,amount:=numeric_value(`Approved/Declined Amount`)]
  ex <- ex[amount>0][order(-amount,`Unique Identifier`),.SD[1],by=.(iso3,`Deal Number`)]
  party <- function(x) fifelse(is.na(x) | x %in% c("N/A","Unknown","Various",""),NA_character_,x)
  ex[,who:=fcoalesce(party(`Primary Borrower`),party(`Primary Source of Repayment (PSOR)`),party(`Primary Applicant`),`Deal Number`)]
  ex <- ex[,.(iso3,project_key=paste("exim",iso3,`Deal Number`,sep=":"),title=paste(who,fcoalesce(party(`Product Description`),"export finance"),sep=" · "),
    organization="U.S. Export-Import Bank",source_id="exim",locator=paste(`Deal Number`,`Unique Identifier`,sep=" / "),
    year=as.integer(`Fiscal Year`),amount,measure="Largest approved, noncancelled authorization for this deal",search_name=who)]
  mcc <- fread("data/cache/mcc-project-finance.csv",na.strings=c("","NA"))
  mcc <- mcc[Fund=="Compact" & CountryID %in% us$country$iso3 & !is.na(ProjectID) &
    !Project %in% c("Program Administration and Control","Monitoring and Evaluation","Not Applicable","Program Development")]
  mcc[,net:=numeric_value(Obligation)]
  mcc[,fy:=as.integer(sub("FY +","",FY))]
  mcc <- mcc[,.(amount=sum(net,na.rm=TRUE),title=Project[which.max(nchar(Project))],
    year=max(fy),activities=paste(sort(unique(Activity[!is.na(Activity) & Activity!="Not Applicable"])),collapse=" | ")),by=.(iso3=CountryID,ProjectID)]
  mcc <- mcc[amount>0,.(iso3,project_key=paste("mcc",iso3,ProjectID,sep=":"),title,
    organization="Millennium Challenge Corporation",source_id="mcc_project_costs",
    locator=paste(iso3,ProjectID,sep=" / "),year,amount,measure="Net compact project obligations in archived FY2004–13 transactions",
    search_name=paste(title,activities,sep=" | "))]
  cases <- db[source_id %in% c("ftf","moz") & measure=="program budget" & usd>0,.(iso3,project_key=program_id,title=name,organization=actor,source_id,
    locator,year=flow_year,amount=usd,measure="Reported original program budget",search_name=name,citation)]
  # The Mozambique $9m rural water activity is inside the water project.
  # Search it as a component of its parent instead of awarding it a second rank.
  cases <- cases[!(project_key=="moz-rural" & any(mcc$project_key=="mcc:MOZ:WATER SAN"))]
  # DFC describes the Acajutla 378 MW plant. The PPI record identifies
  # equity in that same facility. Keep the larger individual financing measure.
  acajutla <- "ppi:SLV:2019:Acajutla Gas-Fired Power Plant and LNG Terminal"
  if (dfc[project_key=="dfc:9000032030",.N] && ppi[project_key==acajutla,.N]) {
    stopifnot(dfc[project_key=="dfc:9000032030",amount] >= ppi[project_key==acajutla,amount])
    dfc[project_key=="dfc:9000032030",search_name:=paste(search_name, "Acajutla Gas-Fired Power Plant and LNG Terminal",sep=" | ")]
    ppi <- ppi[project_key!=acajutla]
  }
  pam <- fread(cmd="gzip -dc data/cache/pacific-aid.csv.gz", na.strings=c("","NA"))
  pam <- pam[Donor=="United States" & `Confirmation status`=="Confirmed" &
    `Spent/Committed`=="Spent" & trimws(`Transaction Type`)=="Disbursement" & !is.na(`Website Project ID`)]
  pam[,iso3:=to_iso(Recipient)]
  pam <- pam[iso3 %in% us$country$iso3]
  pam[,value:=numeric_value(`USD Current - Transaction Value`)]
  # The website ID can identify several unrelated titles. Only group a named
  # project under its ID. Broad multi-grant and sector-support pools lack that grain.
  # Peace Corps operating lines and Compact sector grants describe one named
  # program in a country. Use their disbursement transactions just once.
  pam[grepl("^(Compacts? of Free Association|U[.]S[.] Peace Corps)",`Project Title`,ignore.case=TRUE),
    `:=`(`Website Project ID`=paste0(iso3,":",fifelse(grepl("Peace Corps",`Project Title`),"PEACE","COFA")),
         `Project Title`=fifelse(grepl("Peace Corps",`Project Title`),"U.S. Peace Corps country program","Compacts of Free Association economic assistance"))]
  pam <- pam[!is.na(value) & !is.na(`Project Title`) &
    !grepl("multiple grants|unspecified|not applicable|administrative costs|administrative expenses",`Project Title`,ignore.case=TRUE)]
  pam <- pam[,.(amount=sum(value),organization=paste(sort(unique(AgencyName)),collapse=", "),
    year=max(as.integer(substr(`Final Transaction Date`,1,4))),locator=paste(sort(unique(`2023 Project Identifier`)),collapse=", ")),
    by=.(iso3,web_id=`Website Project ID`,title=trimws(`Project Title`))]
  pam <- pam[amount>0,.(iso3,project_key=paste("pam",web_id,title,sep=":"),title,organization,year,amount,
    source_id="pacific",locator,measure="Cumulative confirmed U.S. disbursements for this named Pacific Aid Map activity",search_name=title)]
  rows <- rbindlist(list(dfc,ppi,gates,ex,mcc,cases,pam),fill=TRUE)
  rows[,amount_cents:=round(amount*100)]
  rows[is.na(citation) | !nzchar(citation),citation:=us$source$download_url[match(source_id,us$source$source_id)]]
  setorder(rows,iso3,-amount_cents,project_key)
  rows[,rank:=seq_len(.N),by=iso3]
  stopifnot(!anyDuplicated(rows,by=c("iso3","project_key")),!anyNA(rows$amount_cents))
  rows[rank<=5,!"amount"]
}

evaluation_tables <- c("evaluation_program","evaluation_search","evaluation_report","evaluation_finding")
build_evaluation_review <- function(us) {
  us$source <- unique(rbind(us$source,registry[source_id=="pacific"],fread("data/evaluation_sources.tsv")),by="source_id")
  p <- evaluation_priority(us)
  aliases <- fread("data/evaluation_aliases.tsv")
  p[aliases,on="project_key",search_name:=paste(search_name,i.aliases,sep=" | ")]
  scratch <- tempfile("evaluation-")
  dir.create(scratch)
  on.exit(unlink(scratch,recursive=TRUE))
  files <- file.path(scratch,c("priorities.tsv","countries.tsv","gao.tsv","search.tsv"))
  fwrite(p,files[1],sep="\t")
  fwrite(us$country,files[2],sep="\t")
  gao <- as.data.table(readRDS("data/cache/gao-reports.rds"))
  fwrite(gao[,.(report_id,title,summary,published,url)],files[3],sep="\t")
  result <- system2("python3",c("scripts/search_evaluations.py",shQuote(files)))
  if (result!=0L) stop("Evaluation catalogue search failed")
  searches <- as.data.table(read.delim(files[4],colClasses=c("character","character","character","integer","character"),
                                        na.strings=character(),check.names=FALSE))
  stopifnot(all(vapply(unique(searches$leads),jsonlite::validate,logical(1))))
  searches[,review_as_of:=as.Date("2026-11-19")]
  reports <- fread("data/evaluation_reports.tsv",na.strings="")
  findings <- fread("data/evaluation_findings.tsv",na.strings="")
  reviews <- fread("data/evaluation_screening.tsv",na.strings="")
  p[,status:="No qualifying evaluation found in the sources searched"]
  p[,screening_note:=fifelse(title %in% c("Redacted","Unnamed DFC project"),
    "The financier withholds the project name. Only the disclosed financing identifier could be searched.",NA_character_)]
  p[,screening_url:=NA_character_]
  p[reviews,on=.(iso3,project_key),`:=`(screening_note=i.screening_note,screening_url=i.screening_url)]
  p[reviews[has_lead==0],on=.(iso3,project_key),status:="No qualifying evaluation found in the sources searched"]
  p[reviews[has_lead==1],on=.(iso3,project_key),status:="Related records found; qualifying evaluation unverified"]
  p[reports[eligibility=="Related published evaluation"],on=.(iso3,project_key),status:="Published evaluation found; donor or host role unverified"]
  p[reports[eligibility=="Donor or host evaluation"],on=.(iso3,project_key),status:="Post-completion evaluation found"]
  stopifnot(nrow(searches)==6L*nrow(p),all(reviews$project_key %in% p$project_key),
            all(reports$project_key %in% p$project_key),all(findings$report_id %in% reports$report_id))
  us$evaluation_program <- p
  us$evaluation_search <- searches
  us$evaluation_report <- reports
  us$evaluation_finding <- findings
  us
}
