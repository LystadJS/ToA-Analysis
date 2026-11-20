# Trade flows are written from the partner's perspective. This same text and
# evidence are used in the offline atlas and the downloadable country brief.
country_profile <- function(name,code,goods,relationships,results) {
  money <- function(x) paste0("$",format(round(x),big.mark=",",scientific=FALSE,trim=TRUE))
  series <- goods[,.(imports_usd=sum(imports_usd),exports_usd=sum(exports_usd)),by=year][order(-year)]
  trade <- if(code=="USA") "The United States is the reporting economy in this bilateral goods series." else
    "The Census extract has no matched, complete calendar year for this jurisdiction."
  if(nrow(series)) {
    z <- series[1]
    trade <- sprintf("In %d, the United States imported %s in goods from %s and exported %s in goods to it. Two-way goods trade totaled %s.",
                     z$year,money(z$imports_usd),name,money(z$exports_usd),money(z$imports_usd+z$exports_usd))
    previous <- series[year==z$year-1]
    if(nrow(previous) && sum(previous$imports_usd,previous$exports_usd)>0) {
      change <- 100*(sum(z$imports_usd,z$exports_usd)/sum(previous$imports_usd,previous$exports_usd)-1)
      trade <- paste(trade,sprintf("That was %.1f%% %s than in %d.",abs(change),if(change<0) "lower" else "higher",previous$year))
    }
  }
  agreements <- relationships[kind %in% c("Initiative","Trade agreement","Trade preference")][order(kind,name)]
  organizations <- relationships[!kind %in% agreements$kind][order(kind,name)]
  r <- results[(!is.na(actual)) & level %in% c("Outcome","Output") &
                 (source_id!="mcc" | !is.na(observed_year))]
  r[,evidence_order:=fcase(method=="Difference in differences",1L,method=="Program report",2L,
    level=="Outcome",3L,default=4L)]
  r <- head(unique(r[order(evidence_order,-observed_year,-period_end,id)],by=c("program_id","indicator","unit")),3)
  evidence <- r[,.(id,indicator,method,project=name,locator,source_id,observed_year,
    statement=paste0(ifelse(!is.na(comparator) & comparator==">","More than ",""),
      format(actual,big.mark=",",trim=TRUE,scientific=FALSE,digits=10)," ",unit,
      fifelse(!is.na(baseline),paste0(" (baseline ",format(baseline,big.mark=",",trim=TRUE,scientific=FALSE,digits=10),")"),""),
      fifelse(!is.na(observed_year),paste0(" in ",observed_year)," · observation year unreported")),
    interpretation,citation=fcoalesce(citation,archive))]
  assessment <- if (!nrow(evidence)) "No qualifying U.S.-linked outcome or output was found in the reviewed sources. The benefit to this participant is unknown." else
    if(any(evidence$method=="Difference in differences")) "A comparison-group evaluation estimates a change for the studied population. Its scope is the evaluated intervention." else
    "The source reports a result for a U.S.-linked program. Monitoring and before-and-after observations alone cannot establish how much the program caused."
  list(trade=trade,goods=series,agreements=agreements,organizations=organizations,
       evidence=evidence,assessment=assessment)
}

profile_markdown <- function(profile) {
  render <- function(rows) {
    if(!nrow(rows)) return("No organizational relationship documented in these sources.")
    vapply(seq_len(nrow(rows)),function(i) {
      r <- rows[i]
      years <- na.omit(unique(c(r$first_year,r$last_year)))
      sprintf("- **%s** · %s%s. %s [Source](%s)",r$name,r$status,
              if(length(years)) paste0(" (",paste(years,collapse="–"),")") else "",r$detail,r$citation)
    },character(1))
  }
  rows <- profile$evidence
  evidence <- vapply(seq_len(nrow(rows)),function(i) {
    r <- rows[i]
    sprintf("- **%s** · %s. %s. %s [%s, %s](%s)",r$indicator,r$statement,r$project,r$interpretation,r$method,r$locator,r$citation)
  },character(1))
  c("## U.S. bilateral goods trade","",profile$trade,
    "Calendar years, current U.S. dollars. Services are outside this series. [U.S. Census Bureau](https://www.census.gov/foreign-trade/balance/country.xlsx) · [Annual country values](bilateral_goods.csv)","",
    "## Trade agreements, preferences and initiatives","",render(profile$agreements),
    if(!any(profile$agreements$kind=="Trade agreement")) "No comprehensive U.S. free trade agreement is listed for this jurisdiction in the through-2025 inventory.",
    "", "## U.S. agencies and organizations","",render(profile$organizations),
    "", "[Annual contributions by organization and measure](us_contributions.csv) · [Relationship records](us_relationships.csv)",
    "", "## Evidence of benefit from U.S.-linked programs","",profile$assessment,"",evidence,
    "", "The USUN roster supplies no measure of the impact of joining Trade over Aid.","")
}
