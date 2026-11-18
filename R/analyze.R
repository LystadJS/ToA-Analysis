# Run through R/country.R from the repository root.
country_data <- function(db, iso) {
  conn <- connect(db)
  on.exit(dbDisconnect(conn))
  q <- function(sql) as.data.table(dbGetQuery(conn,sql,params=list(iso)))
  list(
    coverage=q("SELECT * FROM toa.country_coverage WHERE iso3=$1"),
    programs=q("SELECT p.*,s.title AS source,s.download_url AS archive FROM toa.program p
                JOIN toa.source s USING(source_id) WHERE iso3=$1 ORDER BY year DESC NULLS LAST,id"),
    finance=q("SELECT p.iso3,p.id,p.name,p.actor,p.channel,p.source_id,p.status,p.locator,
                f.measure,f.instrument,f.flow_year,f.period_ref,f.usd,f.eligible_for_summary,
                f.amount_estimated,p.project_investment_usd,p.citation,s.download_url AS archive
                FROM toa.program p JOIN toa.finance f ON p.id=f.program_id JOIN toa.source s USING(source_id)
                WHERE p.iso3=$1 ORDER BY f.flow_year DESC NULLS LAST,p.id,f.measure,f.period_ref"),
    results=q("SELECT p.name,p.source_id,p.locator,p.citation,s.download_url AS archive,r.*,
               CASE WHEN r.baseline IS NOT NULL AND coalesce(r.comparator,'=')='='
                    THEN r.actual-r.baseline END AS change_from_baseline
               FROM toa.result r JOIN toa.program p ON p.id=r.program_id JOIN toa.source s USING(source_id)
               WHERE p.iso3=$1 ORDER BY p.source_id,r.id"),
    context=q("SELECT c.*,s.publisher_url FROM toa.context c JOIN toa.source s USING(source_id)
               WHERE iso3=$1 ORDER BY source_id,year")
  )
}

series_for <- function(us, china) {
  annual <- function(f,key,metric) {
    f[source_id==key & eligible_for_summary & !is.na(flow_year),
      .(value=if (all(is.na(usd))) NA_real_ else sum(usd,na.rm=TRUE),
        known=sum(!is.na(usd)),records=.N),
      by=.(year=flow_year)][,series:=metric]
  }
  # Greenbook's 1976 fiscal year and transition quarter have different durations.
  # Keep the transition quarter in finance.csv and omit it from the annual chart.
  g <- us$finance[period_ref!="1976 transition quarter"]
  rbindlist(list(annual(g,"greenbook","U.S. economic assistance obligations"),
                 annual(us$finance,"fa","U.S. all-sector disbursements"),
                 annual(china$finance[measure=="adjusted commitment"],"gcdf","PRC adjusted official commitments"),
                 annual(china$finance[measure=="face-value commitment (CLG)"],"clg","PRC CLG face-value commitments")))
}
