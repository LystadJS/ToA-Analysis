# Run against the release databases or against fresh restores via tests/restore.sh.
source("R/mirror_sqlite.R")

check_file <- function(database,source_database) {
  pg <- connect(source_database)
  on.exit(dbDisconnect(pg))
  dest <- dbConnect(RSQLite::SQLite(),file.path("artifacts",paste0(database,".sqlite")),
                    flags=RSQLite::SQLITE_RO)
  on.exit(dbDisconnect(dest),add=TRUE)
  dbWithTransaction(pg,{
    dbExecute(pg,"SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
    verify_database(pg,dest,source_database)
  })
}
check_file("toa_us",Sys.getenv("TOA_TEST_US","toa_us"))
check_file("toa_china",Sys.getenv("TOA_TEST_CHINA","toa_china"))
