
if (sys.nframe()==0L) {
  source("R/common.R")
  con <- connect("toa_us")
  tables <- read_evaluation_tables(con)
  dbDisconnect(con)
  out <- file.path("artifacts","evaluation-review")
  dir.create(out,recursive=TRUE,showWarnings=FALSE)
  for (name in names(tables)) fwrite(tables[[name]],file.path(out,paste0(name,".csv")))
}
