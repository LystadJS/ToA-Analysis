# Rank identifiable U.S. projects and financing deals, keeping each original
# measure visible. Country, sector and account aggregates cannot identify a project.
evaluation_priority <- function(us) {
  db <- merge(us$finance,us$program[,.(program_id=id,iso3,source_id,name,actor,locator,details,citation)],
              by="program_id")
  dfc <- db[source_id=="dfc" & eligible_for_summary==TRUE & usd>0]
  dfc[,ref:=sub("^Excel row [0-9]+ project ","",locator)]
  dfc[is.na(ref) | ref %in% c("","NA"),ref:=program_id]
  dfc <- dfc[order(-usd,program_id),.SD[1],by=.(iso3,ref)]
  dfc <- dfc[,.(iso3,project_key=paste0("dfc:",ref),title=name,organization=actor,
    source_id,locator,year=flow_year,amount=usd,measure="Largest recorded commitment or exposure for this project number",
    search_name=fifelse(name=="Redacted" | name=="Unnamed DFC project",ref,name),citation)]
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
  cases <- cases[!(project_key=="moz-rural" & any(mcc$project_key=="mcc:MOZ:WTR SUPPL"))]
  rows <- rbindlist(list(dfc,ppi,gates,ex,mcc,cases),fill=TRUE)
  rows[,amount_cents:=round(amount*100)]
  rows[is.na(citation) | !nzchar(citation),citation:=us$source$download_url[match(source_id,us$source$source_id)]]
  setorder(rows,iso3,-amount_cents,project_key)
  rows[,rank:=seq_len(.N),by=iso3]
  stopifnot(!anyDuplicated(rows,by=c("iso3","project_key")),!anyNA(rows$amount_cents))
  rows[rank<=5,!"amount"]
}
