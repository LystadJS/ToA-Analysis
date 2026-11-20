source("R/common.R")
source("R/analyze.R")
source("R/visualize.R")
source("R/country_profile.R")
source("R/evaluation_exports.R")
profile_db <- connect("toa_us")
profile_table <- function(table) as.data.table(dbGetQuery(profile_db,paste0("SELECT * FROM toa.",table)))
goods <- profile_table("us_goods_trade")
relations <- profile_table("us_relationship")
contributions <- profile_table("us_contribution")
evaluations <- read_evaluation_tables(profile_db)
dbDisconnect(profile_db)
write_brief <- function(iso) {
  us <- country_data("toa_us",iso)
  cn <- country_data("toa_china",iso)
  if (!nrow(us$coverage)) stop("Unknown ISO3 or XKX country code")
  out <- file.path("artifacts","countries",iso)
  dir.create(out,recursive=TRUE,showWarnings=FALSE)
  combine <- function(slot) rbindlist(list(USA=us[[slot]],CHN=cn[[slot]]),idcol="provider")
  for (slot in c("coverage","programs","finance","results")) {
    fwrite(combine(slot),file.path(out,paste0(slot,".csv")))
  }
  country_evaluation_files(evaluations,iso,out)
  fwrite(us$context,file.path(out,"trade_context.csv"))
  series <- series_for(us,cn)
  fwrite(series[order(series,year)],file.path(out,"annual_finance.csv"))
  plot_country(series,us$context,us$coverage$name,file.path(out,"country.pdf"))
  profile <- country_profile(us$coverage$name,iso,goods[iso3==iso],relations[iso3==iso],us$results)
  fwrite(profile$goods,file.path(out,"bilateral_goods.csv"))
  fwrite(relations[iso3==iso][order(kind,name,source_id)],file.path(out,"us_relationships.csv"))
  fwrite(contributions[iso3==iso][order(source_id,year,actor)],file.path(out,"us_contributions.csv"))
  fmt <- function(x) format(x,big.mark=",",scientific=FALSE,trim=TRUE,digits=12)
  lines <- c(paste("#",us$coverage$name,"| Development finance and trade"),"",
    "Amounts are current U.S. dollars unless a source currency is shown. Reporting windows differ by source. The last fiscal year in a snapshot may be incomplete. Country allocations can fund implementing partners.",
    "",profile_markdown(profile),"## Financing", "")
  for (label in unique(series$series)) {
    available <- series[series==label & !is.na(value)][order(-year)]
    if (nrow(available)) {
      z <- available[1]
      lines <- c(lines,sprintf("- %s in %s amounted to $%s across %s of %s records with disclosed amounts.",
                      label,z$year,fmt(round(z$value,2)),z$known,z$records))
    }
  }
  if (!nrow(series) || all(is.na(series$value))) lines <- c(lines,"The selected public series contain no annual amount for this country.")
  for (donor in c("USA","CHN")) {
    d <- if(donor=="USA") us else cn
    source_keys <- if (donor=="USA") "dfc" else c("gcdf","clg")
    projects <- d$finance[source_id %in% source_keys & eligible_for_summary & !is.na(usd) &
                          measure %in% c("adjusted commitment","face-value commitment (CLG)","commitment or exposure") & !is.na(flow_year) & name!="Redacted"][order(-flow_year,id)]
    if (nrow(projects)) {
      z <- projects[1]
      link <- if (!is.na(z$citation) && startsWith(z$citation,"http")) z$citation else z$archive
      lines <- c(lines,sprintf("- **%s** (%s). The recorded %s was $%s. [Source record](%s)",
                               z$name,z$flow_year,z$measure,fmt(z$usd),link))
    }
    philanthropy <- d$finance[source_id=="gates"]
    if (nrow(philanthropy)) lines <- c(lines,sprintf("- %d reviewed Gates Foundation grants to local grantees total $%s in commitments. [Example grant](%s)",
             nrow(philanthropy),fmt(sum(philanthropy$usd)),philanthropy$citation[1]))
    payments <- d$finance[measure=="borrower-reported drawdown",
      .(amount=sum(reported_amount),facilities=.N,citation=citation[1]),by=.(period_ref,reported_currency)]
    for (j in seq_len(nrow(payments))) {
      z <- payments[j]
      lines <- c(lines,sprintf("- The Treasury recorded %s %s drawn on %d China Eximbank facilities in %s. [Debt register](%s)",
        z$reported_currency,fmt(z$amount),z$facilities,z$period_ref,z$citation))
    }
    aiddata <- d$finance[source_id=="gcdf" & measure=="disbursement"]
    if(nrow(aiddata)) lines <- c(lines,sprintf("- AidData reports %d dated payment observations, %d–%d. Coverage varies by facility. [Funding records](finance.csv)",
      nrow(aiddata),min(aiddata$flow_year),max(aiddata$flow_year)))
    f <- d$finance[source_id=="ppi"]
    if (nrow(f)) lines <- c(lines,sprintf("- %s sponsor equity at financial close: %s across %d of %d listed stakes with dollar disclosures. Ownership percentages are available for %d. Coverage includes state-owned sponsors. [PPI workbook](%s)",
      donor,if(all(is.na(f$usd))) "undisclosed" else paste0("$",fmt(sum(f$usd,na.rm=TRUE))),sum(!is.na(f$usd)),nrow(f),sum(!is.na(f$sponsor_ownership_pct)),f$archive[1]))
    implied <- f[!is.na(implied_sole_sponsor_equity_usd)]
    if(nrow(implied)) lines <- c(lines,sprintf("- The workbook reports 100%% ownership by a sole named sponsor and project equity for %d additional stake(s). The implied equity is $%s, shown separately from directly disclosed stakes. [PPI workbook](%s)",
      nrow(implied),fmt(sum(implied$implied_sole_sponsor_equity_usd)),implied$archive[1]))
    disclosed <- f[!is.na(usd)][order(-flow_year,id)]
    if (nrow(disclosed)) {
      z <- disclosed[1]
      lines <- c(lines,sprintf("- %s had a disclosed equity commitment of $%s in %s (%d). [PPI workbook](%s)",
                               z$actor,fmt(z$usd),z$name,z$flow_year,z$archive))
    }
  }
  lines <- c(lines,"","[Annual series](annual_finance.csv) · [Funding amounts and citations](finance.csv) · [Participation and project status](programs.csv)",
             "", "## Reported host-country results", "")
  # Lead with evaluated studies and direct trade measures. Include the full evidence table for every country.
  r <- combine("results")
  reported <- r[!is.na(actual) & source_id!="agoa" & (source_id!="mcc" | !is.na(observed_year)) & level %in% c("Outcome","Output")]
  priority <- c("Difference in differences","Program report","Reported before/after","Reported operational output","Quarterly program monitoring","Program monitoring")
  reported[,rank:=match(method,priority)]
  reported[,topic:=grepl("trade|customs|export|market|transport|road|time to connect",indicator,ignore.case=TRUE)]
  reported <- unique(reported[order(rank,-topic,level,-observed_year,-period_end,id)],by=c("provider","program_id","indicator","unit"))
  if (!nrow(reported)) lines <- c(lines,"No project result meets the briefing criteria. The results extract includes any undated monitoring snapshots.")
  for (i in head(seq_len(nrow(reported)),6)) {
    z <- reported[i]
    actual <- paste0(if (!is.na(z$comparator) && z$comparator==">") "more than " else "",fmt(z$actual))
    comparison <- if (is.na(z$baseline)) "" else paste0(" Baseline ",fmt(z$baseline),".")
    url <- if (!is.na(z$citation) && nzchar(z$citation)) z$citation else z$archive
    lines <- c(lines,"",sprintf("- **%s.** %s reported %s %s.%s %s [%s, %s](%s)",
         z$indicator,z$name,actual,z$unit,comparison,paste(if(!is.na(z$period_end)) paste("Period ending",z$period_end,".") else if(!is.na(z$observed_year)) paste("Observed in",z$observed_year,".") else "Observation year unreported.",z$interpretation),z$method,z$locator,url))
  }
  a <- us$results[source_id=="agoa" & !is.na(actual)][order(-observed_year)]
  if (nrow(a)) lines <- c(lines,"",sprintf("In %d, U.S. imports from this country claiming AGOA preferences were valued at $%s. Customs values measure preference use. [USITC-derived series](%s)",a$observed_year[1],fmt(a$actual[1]),a$archive[1]))
  priorities <- evaluations$programs[iso3==iso][order(rank)]
  lines <- c(lines,"","### Post-completion evaluation review","")
  if (!nrow(priorities)) {
    lines <- c(lines,"No individually priced U.S.-linked program or deal qualified for ranking in the collected sources.")
  } else {
    for (i in seq_len(nrow(priorities))) {
      item <- priorities[i]
      lines <- c(lines, sprintf("%d. **%s** · $%s. %s. %s. [Financing source](%s)",
        item$rank,item$title,formatC(item$amount_cents/100,format="f",digits=2,big.mark=","),
        item$measure,sub("[.]$","",item$status),item$citation))
      for (j in which(evaluations$reports$iso3==iso & evaluations$reports$project_key==item$project_key)) {
        study <- evaluations$reports[j]
        lines <- c(lines,sprintf("   - %s. %s [Published study](%s)",
          study$eligibility,study$summary,study$url))
      }
    }
  }
  lines <- c(lines,"","[Ranked programs and financing records](evaluation_programs.csv) · [Study findings](evaluation_findings.csv)",
             "","[All indicators, baselines, targets, changes and evidence methods](results.csv)",
    "", "## Interpretation", "",
    "Monitoring and reported before/after changes can reflect other reforms and economic conditions. Country-level logistics observations provide context. A comparison-group estimate applies to its evaluated population. Results do not estimate the effect of joining Trade over Aid.",
    "", "[Finance and logistics charts](country.pdf) · [Country logistics observations](trade_context.csv)")
  writeLines(lines,file.path(out,"brief.md"))
  cat("Wrote",out,"\n")
  invisible(TRUE)
}
args <- commandArgs(trailingOnly=TRUE)
if (length(args)!=1L || !grepl("^[A-Za-z]{3}$",args[1])) stop("Usage: Rscript R/country.R ISO3|ALL")
if (toupper(args[1])=="ALL") {
  conn <- connect("toa_us")
  codes <- dbGetQuery(conn,"SELECT iso3 FROM toa.country ORDER BY iso3")$iso3
  dbDisconnect(conn)
  jobs <- suppressWarnings(as.integer(Sys.getenv("TOA_BRIEF_JOBS","1")))
  if (is.na(jobs) || jobs < 1L) stop("TOA_BRIEF_JOBS must be a positive integer")
  completed <- if (jobs==1L) lapply(codes,write_brief) else
    parallel::mclapply(codes,write_brief,mc.cores=jobs)
  if (!all(vapply(completed,function(x) !is.null(x) && !inherits(x,"try-error"),logical(1))))
    stop("A country brief failed to build")
  coverage <- rbindlist(lapply(codes,function(code) fread(file.path("artifacts","countries",code,"coverage.csv"))))
  fwrite(coverage,"artifacts/countries/coverage.csv")
  listing <- unique(coverage[,.(iso3,name)])[order(name)]
  writeLines(c("# Country evidence briefs","",
               "Each country folder contains a briefing, charts and the underlying records. Coverage counts include reported zeros, missing dollar amounts and source-coded statuses.",
               "","[Coverage by provider](coverage.csv)","",
               sprintf("- [%s (%s)](%s/brief.md)",listing$name,listing$iso3,listing$iso3)),
             "artifacts/countries/index.md")
} else {
  write_brief(toupper(args[1]))
}
