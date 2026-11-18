source("R/common.R")
source("R/clean.R")

load_database <- function(provider, database) {
  release <- clean_release(provider)
  conn <- connect(database)
  on.exit(dbDisconnect(conn))
  sql <- paste(readLines("sql/schema.sql"), collapse="\n")
  dbWithTransaction(conn, {
    dbExecute(conn,"SELECT pg_advisory_xact_lock(73650211)")
    for (statement in strsplit(sql,";",fixed=TRUE)[[1]]) {
      if (nzchar(trimws(statement))) dbExecute(conn,statement)
    }
    # A failed import rolls back the whole provider release to its previous state.
    tables <- names(release)
    dbExecute(conn,paste("TRUNCATE",paste(dbQuoteIdentifier(conn,tables),collapse=", ")))
    for (tab in tables) {
      dbAppendTable(conn,Id(schema="toa",table=tab),as.data.frame(release[[tab]]))
    }
  })
  cat(database, paste(names(release), vapply(release,nrow,integer(1)), collapse=" | "), "\n")
}
load_database("USA","toa_us")
load_database("CHN","toa_china")
