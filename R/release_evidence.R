# Cash-flow records with independent currency, facility and reporting-period checks.
kenya_payments <- function() {
  refs <- fread("data/kenya_drawdowns.tsv")
  pdf <- cached("kenya_debt")
  page_text <- function(i) {
    text <- system2("pdftotext",c("-layout","-f",i,"-l",i,shQuote(pdf),"-"),stdout=TRUE)
    stopifnot(is.null(attr(text,"status")))
    text
  }
  refs[, amount := vapply(seq_len(.N),function(i) {
    line <- grep(paste0("^",facility[i],"\\s"),page_text(page[i]),value=TRUE)
    stopifnot(length(line)==1L,grepl("Exim Bank of China",line,fixed=TRUE))
    fields <- strsplit(sub(paste0("^.*\\s",currency[i],"\\s+"),"",line),"\\s+")[[1]]
    # Opening balance, principal repaid, FY drawdown, refinancing, restructuring, closing balance.
    parse_cash <- function(x) ifelse(x=="-",0,as.numeric(gsub(",","",ifelse(x=="-","0",x))))
    a <- parse_cash(fields[1:6])
    stopifnot(all(is.finite(a)),a[3]>0,abs(a[1]-a[2]+a[3]-a[4]+a[5]-a[6])<0.02)
    a[3]
  },numeric(1))]
  refs[, id := paste0("kenya-fy23-",facility)]
  sums <- refs[,.(total=sum(amount)),by=currency]
  stopifnot(abs(sums[currency=="USD",total]-44721731.99)<.01,
            abs(sums[currency=="CNY",total]-454243778.75)<.01)
  list(program=refs[,.(id,iso3="KEN",source_id="kenya_debt",name=project,actor="Exim Bank of China",
      channel="official finance",locator=paste("FY2022/23 register, PDF page",page,"facility",facility),
      year=2023L,period="Kenya FY2022/23",citation=paste0(src_url("kenya_debt"),"#page=",page),
      details="Facility drawdown in the foreign-currency statement. Reconciles to the creditor totals on PDF page 1.")],
    finance=refs[,.(program_id=id,measure="borrower-reported drawdown",instrument="China Eximbank loan",
      reported_currency=currency,reported_amount=amount,usd=fifelse(currency=="USD",amount,NA_real_),
      flow_year=2023L,period_ref="Kenya FY2022/23",period_start="2022-07-01",period_end="2023-06-30",
      eligible_for_summary=TRUE)])
}

narrative_payments <- function(projects) {
  reviewed <- fread("data/reviewed_payment_series.tsv")
  pattern <- "\\$[0-9,]+(?:\\.[0-9]+)? disbursement on [A-Z][a-z]+ [0-9]{1,2}, [0-9]{4}"
  rows <- lapply(seq_len(nrow(reviewed)),function(i) {
    ref <- reviewed[i]
    p <- projects[aid_data_record_id==ref$record]
    stopifnot(nrow(p)==1L,p$official_source_count>0)
    matches <- regmatches(p$description,gregexpr(pattern,p$description,perl=TRUE))[[1]]
    usd <- as.numeric(gsub("[,$]","",sub(" disbursement on .*","",matches)))
    dates <- as.Date(sub(".* disbursement on ","",matches),format="%B %d, %Y")
    stopifnot(length(matches)==ref$transactions,!anyNA(dates),abs(sum(usd)-ref$reported_total_usd)<.011)
    data.table(program_id=paste0("gcdf-",p$aid_data_record_id),iso3=p$recipient_iso_3,
               instrument=p$flow_type,date=dates,usd=usd)
  })
  x <- rbindlist(rows)
  stopifnot(!anyDuplicated(x,by=c("iso3","date","usd")))
  x[,.(usd=sum(usd),reported_amount=sum(usd),reported_currency="USD",measure="disbursement",
       period_start=as.character(date[1]),period_end=as.character(date[1]),eligible_for_summary=TRUE),
    by=.(program_id,instrument,flow_year=as.integer(format(date,"%Y")),period_ref=as.character(date))]
}

mcc_observations <- function(x,base) {
  # Only an actual milestone expressed as an explicit calendar date can date itself.
  date_rows <- x$UnitOfMeasure=="Date" & !is.na(x$ActualToDate) &
               grepl("^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$",x$ActualToDate)
  base[,dating_basis:="Observation date unavailable"]
  dates <- as.Date(x$ActualToDate[which(date_rows)],"%m/%d/%Y")
  stopifnot(!anyNA(dates))
  base[which(date_rows),`:=`(period_start=as.character(dates),period_end=as.character(dates),
      observed_year=as.integer(format(dates,"%Y")),dating_basis="Reported milestone date",timing_source_id="mcc",
      interpretation="Program monitoring. ActualToDate records the date of the milestone.")]
  anchors <- unique(fread(cached("mcc_calendar"))[,.(ProgramName=country,quarter)])
  # Exact compact names prevent applying first-compact dates to a second compact.
  anchors <- anchors[ProgramName %in% x$ProgramName]
  stopifnot(!anyDuplicated(anchors$ProgramName),
            all(grepl("July to September 2012",anchors$quarter,fixed=TRUE)))
  anchors[, q_anchor:=as.integer(sub(".*Quarter ([0-9]+) Results.*","\\1",quarter))]
  cols <- sprintf("ActualQ%02d",1:24)
  a <- merge(x,anchors[,.(ProgramName,q_anchor)],by="ProgramName")
  q <- melt(a,id.vars=c("IndicatorId","id","IndicatorName","Level","UnitOfMeasure","Baseline","BaselineYear",
        "EndOfProgramTarget","q_anchor"),measure.vars=cols,variable.name="quarter",value.name="reported",na.rm=TRUE)
  q <- q[!is.na(numeric_value(reported))]
  q[,serial:=2012L*4L+2L+as.integer(sub("ActualQ","",quarter))-q_anchor]
  q[,start:=as.Date(sprintf("%04d-%02d-01",serial%/%4L,3L*(serial%%4L)+1L))]
  q[,end:=as.Date(sprintf("%04d-%02d-01",(serial+1L)%/%4L,3L*((serial+1L)%%4L)+1L))-1]
  quarterly <- q[,.(id=paste0("itt-",IndicatorId,"-",quarter),program_id=id,indicator=IndicatorName,
    level=Level,unit=UnitOfMeasure,baseline=numeric_value(Baseline),baseline_text=Baseline,
    baseline_year=as.integer(BaselineYear),actual=numeric_value(reported),actual_text=reported,
    target=numeric_value(EndOfProgramTarget),target_text=EndOfProgramTarget,
    method="Quarterly program monitoring",observed_year=as.integer(format(end,"%Y")),
    period_start=as.character(start),period_end=as.character(end),timing_source_id="mcc_calendar",
    dating_basis="Reported compact quarter",interpretation=paste("ITT",IndicatorId,quarter,
      "| Quarterly actual. The target is the end-of-program target. Monitoring describes reported change; attribution requires evaluation."))]
  rbindlist(list(base,quarterly),fill=TRUE)
}
