source("R/common.R")
source("R/evaluation_exports.R")
us <- connect(Sys.getenv("TOA_TEST_US","toa_us"))
cn <- connect(Sys.getenv("TOA_TEST_CHINA","toa_china"))
x <- read_evaluation_tables(us)
p <- x$programs
s <- x$searches
r <- x$reports
f <- x$findings
stopifnot(nrow(p)==817L,uniqueN(p$iso3)==184L,nrow(s)==nrow(p)*6L,
          nrow(p[,.(ok=identical(rank,seq_len(.N)) && all(diff(amount_cents)<=0)),by=iso3][ok==FALSE])==0L,
          all(p$amount_cents>0),all(nzchar(p$citation)),all(s[,uniqueN(source_id),by=.(iso3,project_key)]$V1==6L),
          !anyDuplicated(s,by=c("iso3","project_key","source_id")))
hits <- vapply(s$leads,function(text) length(jsonlite::fromJSON(text,simplifyVector=FALSE)),integer(1))
stopifnot(all(hits==s$match_count))
qualifying <- unique(r[eligibility=="Donor or host evaluation",.(iso3,project_key)])
stopifnot(fsetequal(p[status=="Post-completion evaluation found",.(iso3,project_key)],qualifying),
          fsetequal(qualifying[,.(iso3)],data.table(iso3=c("ARM","GHA","LSO","MOZ","NAM","NIC"))),
          nrow(r)==10L,nrow(f)==31L,all(r$report_id %in% f$report_id),
          all(f[result=="No detectable change",is.na(value)]),
          nrow(p[iso3=="ATA"])==0L,!any(p$project_key=="moz-rural"),
          nrow(p[grepl("Acajutla Gas-Fired Power Plant",project_key)])==0L)
moz <- f[report_id=="6336"][order(sequence)]$value
stopifnot(identical(as.numeric(moz),c(161,76,137,114,-62)),(moz[2]-moz[1])-(moz[4]-moz[3])==moz[5],
          f[report_id=="8060" & indicator=="Primary school enrollment",unit]=="percentage points",
          f[report_id=="20118" & !is.na(value),value]==8)
mcc <- fread("data/cache/mcc-project-finance.csv")
mcc_amount <- sum(numeric_value(mcc[CountryID=="MOZ" & Fund=="Compact" & ProjectID=="WATER SAN",Obligation]),na.rm=TRUE)
stopifnot(round(mcc_amount*100)==p[project_key=="mcc:MOZ:WATER SAN",amount_cents])
stopifnot(all(vapply(read_evaluation_tables(cn),nrow,integer(1))==0L))
cat("Verified",nrow(p),"ranked records in",uniqueN(p$iso3),"jurisdictions,",nrow(s),"catalogue searches,",
    nrow(r),"published studies and",nrow(f),"findings, with separate donor/host and unresolved classifications.\n")
dbDisconnect(us)
dbDisconnect(cn)
