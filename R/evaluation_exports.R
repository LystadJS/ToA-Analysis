# The atlas, country files and review archive share one ordered database extract.
read_evaluation_tables <- function(con) {
  query <- function(sql) as.data.table(dbGetQuery(con,sql))
  list(programs=query("SELECT * FROM toa.evaluation_program ORDER BY iso3,rank"),
       searches=query("SELECT * FROM toa.evaluation_search ORDER BY iso3,project_key,source_id"),
       reports=query("SELECT * FROM toa.evaluation_report ORDER BY iso3,project_key,published,report_id"),
       findings=query("SELECT r.iso3,r.project_key,f.* FROM toa.evaluation_finding f JOIN toa.evaluation_report r USING(report_id) ORDER BY r.iso3,r.project_key,f.report_id,f.sequence"))
}
country_evaluation_files <- function(x,iso,out) {
  fwrite(x$programs[iso3==iso],file.path(out,"evaluation_programs.csv"),scipen=999)
  results <- merge(x$reports[iso3==iso],x$findings[iso3==iso],
                   by=c("iso3","project_key","report_id"),all.x=TRUE)
  fwrite(results[order(project_key,published,sequence)],file.path(out,"evaluation_findings.csv"))
}

if (sys.nframe()==0L) {
  source("R/common.R")
  con <- connect("toa_us")
  tables <- read_evaluation_tables(con)
  dbDisconnect(con)
  out <- file.path("artifacts","evaluation-review")
  dir.create(out,recursive=TRUE,showWarnings=FALSE)
  for (name in names(tables)) fwrite(tables[[name]],file.path(out,paste0(name,".csv")))
}
