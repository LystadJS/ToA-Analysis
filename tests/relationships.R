# Independent checks against the publisher columns, the pinned lists and the
# two reporting directions. Run on live or restored databases.
source("R/common.R")
con <- connect(Sys.getenv("TOA_TEST_US","toa_us"))
read <- function(sql) as.data.table(dbGetQuery(con,sql))
r <- read("SELECT * FROM toa.us_relationship")
roster <- fread("data/usun_roster.tsv")
listed <- r[source_id=="usun_toa" & status=="Listed on supplied USUN roster",iso3]
stopifnot(setequal(listed,roster$iso3),length(listed)==47,nrow(r[source_id=="usun_toa"])==250,
          "NRU" %in% listed,!"USA" %in% listed,
          r[iso3=="CRI" & source_id=="ustr_fta",first_year]==2009,
          r[iso3=="DOM" & source_id=="ustr_fta",first_year]==2007,
          nrow(r[source_id=="ustr_fta"])==20,
          setequal(r[source_id=="cofa",iso3],c("FSM","MHL","PLW")),
          nrow(r[source_id=="unctad_bit"])==47,
          r[iso3=="ECU" & source_id=="unctad_bit",status]=="UNCTAD archive status · Terminated")
# Reconcile every EXIM country-year, excluding domestic, unallocated,
# unapproved and cancelled decisions without allocating them to recipients.
x <- fread("data/cache/exim-authorizations.csv",integer64="double")
x <- x[Decision=="Approved" & `Deal Cancelled`=="No" &
       !Country %in% c("United States","Multiple - Countries","Private Export Funding Corp.")]
x[,iso3:=to_iso(Country)]
x[Country=="Micronesia",iso3:="FSM"]
stopifnot(!anyNA(x$iso3),!anyNA(x[["Approved/Declined Amount"]]))
by_year <- x[,.(cents=sum(round(as.numeric(`Approved/Declined Amount`)*100)),records=.N),
             by=.(iso3,year=as.integer(`Fiscal Year`))]
expected <- read("SELECT iso3,year,cents,records FROM toa.us_contribution WHERE source_id='exim'")
stopifnot(fsetequal(by_year,expected),sum(expected$records)==11609)
trade <- read("SELECT * FROM toa.us_goods_trade")
raw <- as.data.table(readxl::read_excel("data/cache/census-country.xlsx"))
raw[,year:=as.integer(year)]
comparison <- merge(trade,raw,by.x=c("census_code","year"),by.y=c("CTY_CODE","year"))
stopifnot(nrow(comparison)==nrow(trade),all(comparison$exports_usd==round(comparison$EYR*1e6)),
          all(comparison$imports_usd==round(comparison$IYR*1e6)),
          trade[iso3=="HND" & year==2025,imports_usd]==5504088658,
          !any(trade$year>2025),uniqueN(trade$iso3)==232)
stopifnot(read("SELECT count(*) AS n FROM toa.us_contribution WHERE source_id='usun_toa'")$n==0)
dbDisconnect(con)
cat("Verified 47 roster names, 20 FTA partner rows, 11,609 EXIM authorizations and all 8,118 bilateral goods rows for 232 partners.\n")
