source("R/common.R")
source("R/analyze.R")
source("R/visualize.R")
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
  fwrite(us$context,file.path(out,"trade_context.csv"))
  series <- series_for(us,cn)
  fwrite(series[order(series,year)],file.path(out,"annual_finance.csv"))
  plot_country(series,us$context,us$coverage$name,file.path(out,"country.pdf"))
  fmt <- function(x) format(x,big.mark=",",scientific=FALSE,trim=TRUE,digits=12)
  lines <- c(paste("#",us$coverage$name,"| Development finance and trade"),"",
    "Amounts are current U.S. dollars. Reporting windows differ by source. The last fiscal year in a snapshot may be incomplete. Country allocations can fund implementing partners.",
    "", "## Financing", "")
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
                          measure!="disbursement" & !is.na(flow_year) & name!="Redacted"][order(-flow_year,id)]
    if (nrow(projects)) {
      z <- projects[1]
      link <- if (!is.na(z$citation) && startsWith(z$citation,"http")) z$citation else z$archive
      lines <- c(lines,sprintf("- **%s** (%s). The recorded %s was $%s. [Source record](%s)",
                               z$name,z$flow_year,z$measure,fmt(z$usd),link))
    }
    philanthropy <- d$finance[source_id=="gates"]
    if (nrow(philanthropy)) lines <- c(lines,sprintf("- The reviewed Gates Foundation grant to a local organization was $%s (%s). The stated purpose names this country. [Grant record](%s)",
             fmt(philanthropy$usd[1]),philanthropy$period_ref[1],philanthropy$citation[1]))
    f <- d$finance[source_id=="ppi"]
    if (nrow(f)) lines <- c(lines,sprintf("- %s sponsors appear in %d infrastructure sponsor records. Disclosed equity amounts are available for %d. Project-wide investment is listed separately in the finance extract.",
                           donor,nrow(f),sum(!is.na(f$usd))))
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
  reported <- r[!is.na(actual) & source_id!="agoa" & level %in% c("Outcome","Output")]
  priority <- c("Difference in differences","Program report","Reported before/after","Reported operational output","Program monitoring")
  reported[,rank:=match(method,priority)]
  reported[,topic:=grepl("trade|customs|export|market|transport|road|time to connect",indicator,ignore.case=TRUE)]
  reported <- reported[order(rank,-topic,level,id)]
  if (!nrow(reported)) lines <- c(lines,"These releases contain no numeric project outcome or output for this country.")
  for (i in head(seq_len(nrow(reported)),6)) {
    z <- reported[i]
    actual <- paste0(if (!is.na(z$comparator) && z$comparator==">") "more than " else "",fmt(z$actual))
    comparison <- if (is.na(z$baseline)) "" else paste0(" Baseline ",fmt(z$baseline),".")
    url <- if (!is.na(z$citation) && nzchar(z$citation)) z$citation else z$archive
    lines <- c(lines,"",sprintf("- **%s.** %s reported %s %s.%s %s [%s, %s](%s)",
         z$indicator,z$name,actual,z$unit,comparison,z$interpretation,z$method,z$locator,url))
  }
  a <- us$results[source_id=="agoa" & !is.na(actual)][order(-observed_year)]
  if (nrow(a)) lines <- c(lines,"",sprintf("In %d, U.S. imports from this country claiming AGOA preferences were valued at $%s. Customs values measure preference use. [USITC-derived series](%s)",a$observed_year[1],fmt(a$actual[1]),a$archive[1]))
  lines <- c(lines,"","[All indicators, baselines, targets, changes and evidence methods](results.csv)",
    "", "## Interpretation", "",
    "Monitoring and reported before/after changes can reflect other reforms and economic conditions. Country-level logistics observations provide context. A comparison-group estimate applies to its evaluated population. Results do not estimate the effect of joining Trade over Aid.",
    "", "[Finance and logistics charts](country.pdf) · [Country logistics observations](trade_context.csv)")
  writeLines(lines,file.path(out,"brief.md"))
  cat("Wrote",out,"\n")
}
args <- commandArgs(trailingOnly=TRUE)
if (length(args)!=1L || !grepl("^[A-Za-z]{3}$",args[1])) stop("Usage: Rscript R/country.R ISO3|ALL")
if (toupper(args[1])=="ALL") {
  conn <- connect("toa_us")
  codes <- dbGetQuery(conn,"SELECT iso3 FROM toa.country ORDER BY iso3")$iso3
  dbDisconnect(conn)
  invisible(lapply(codes,write_brief))
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
