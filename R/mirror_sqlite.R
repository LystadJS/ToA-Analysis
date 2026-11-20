# Export the existing PostgreSQL releases. Both files are checked before publication.
source("R/common.R")

base_tables <- c("source","country","program","finance","result","context","exclusions",
                 "us_goods_trade","us_contribution","us_relationship",
                 "evaluation_program","evaluation_search","evaluation_report","evaluation_finding")
exact_fields <- list(result=c("baseline","actual","target"), context="days",
                     dated_program_results=c("baseline","actual","target"))

create_schema <- function(dest) {
  # Keep the repository's keys, constraints, indexes and reporting SQL in one place.
  ddl <- strsplit(paste(readLines("sql/schema.sql"),collapse="\n"),";",fixed=TRUE)[[1]]
  ddl <- trimws(ddl)
  views <- startsWith(ddl,"CREATE OR REPLACE VIEW")
  for (sql in ddl[!views]) {
    if (!nzchar(sql) || startsWith(sql,"CREATE SCHEMA") || startsWith(sql,"SET LOCAL")) next
    sql <- sub("ADD COLUMN IF NOT EXISTS","ADD COLUMN",sql,fixed=TRUE)
    if (startsWith(sql,"CREATE TABLE")) sql <- paste(sql,"WITHOUT ROWID")
    dbExecute(dest,sql)
  }
  for (field in c("usd","reported_amount")) {
    dbExecute(dest,sprintf("ALTER TABLE finance ADD COLUMN %s_cents INTEGER",field))
  }
  for (table in c("result","context")) {
    for (field in exact_fields[[table]]) {
      dbExecute(dest,sprintf("ALTER TABLE %s ADD COLUMN %s_decimal TEXT",table,field))
    }
  }
  for (sql in ddl[views]) {
    sql <- sub("CREATE OR REPLACE VIEW","CREATE VIEW",sql,fixed=TRUE)
    # Aggregate exact cents before converting a published total to currency units.
    sql <- gsub("sum(f.usd)","(sum(f.usd_cents)/100.0)",sql,fixed=TRUE)
    sql <- gsub("sum(coalesce(f.reported_amount,f.usd))",
                "(sum(coalesce(f.reported_amount_cents,f.usd_cents))/100.0)",sql,fixed=TRUE)
    dbExecute(dest,sql)
  }
}

columns_in <- function(pg) {
  as.data.table(dbGetQuery(pg,"SELECT c.table_name,c.column_name,c.data_type,c.numeric_scale,t.table_type
    FROM information_schema.columns c JOIN information_schema.tables t USING(table_schema,table_name)
    WHERE c.table_schema='toa' ORDER BY c.table_name,c.ordinal_position"))
}

copy_table <- function(pg,dest,table,definition) {
  # Numeric text crosses DBI without an intermediate conversion to an R double.
  fields <- definition[, fcase(data_type %in% c("numeric","date"),paste0(column_name,"::text"),
                               data_type=="boolean",paste0(column_name,"::integer"),
                               default=column_name)]
  projection <- paste(fields,"AS",definition$column_name)
  if (table=="finance") {
    for (field in c("usd","reported_amount")) {
      projection <- c(projection,sprintf("(%s*100)::bigint::text AS %s_cents",field,field))
    }
  }
  cursor <- dbSendQuery(pg,sprintf("SELECT %s FROM toa.%s",paste(projection,collapse=","),table))
  on.exit(dbClearResult(cursor))
  repeat {
    rows <- dbFetch(cursor,n=8192)
    if (!nrow(rows)) break
    for (field in exact_fields[[table]]) rows[[paste0(field,"_decimal")]] <- rows[[field]]
    dbAppendTable(dest,table,rows)
  }
}

verify_relation <- function(pg,dest,table,definition) {
  # Compare multisets of full rows. Character projections preserve NULLs, dates,
  # Booleans and decimal scales through both drivers, including a genuine zero.
  pg_expr <- definition$column_name
  sqlite_expr <- definition$column_name
  for (i in seq_len(nrow(definition))) {
    field <- definition$column_name[i]
    type <- definition$data_type[i]
    if (type=="boolean") pg_expr[i] <- paste0(field,"::integer")
    if (field %in% exact_fields[[table]]) {
      sqlite_expr[i] <- paste0(field,"_decimal")
      bad <- sprintf("SELECT count(*) FROM %s WHERE %s IS NOT CAST(%s_decimal AS NUMERIC)",
                     table,field,field)
      stopifnot(dbGetQuery(dest,bad)[[1]]==0)
    } else if (type=="numeric") {
      scale <- definition$numeric_scale[i]
      if (is.na(scale)) {
        # Only these view aggregates are unbounded numeric currency columns.
        stopifnot(field %in% c("reported_usd","disclosed_sponsor_equity_usd","disclosed_amount"))
        scale <- 2L
      }
      pg_expr[i] <- sprintf("round(%s,%d)",field,scale)
      sqlite_expr[i] <- sprintf("CASE WHEN %s IS NOT NULL THEN printf('%%.%df',%s) END",field,scale,field)
    }
  }
  projection <- function(expr,fields) paste(sprintf("CAST(%s AS TEXT) AS %s",expr,fields),collapse=",")
  pg_sql <- projection(pg_expr,definition$column_name)
  sqlite_sql <- projection(sqlite_expr,definition$column_name)
  if (table=="finance") {
    for (field in c("usd","reported_amount")) {
      pg_sql <- paste0(pg_sql,sprintf(",(%s*100)::bigint::text AS %s_cents",field,field))
      sqlite_sql <- paste0(sqlite_sql,sprintf(",CAST(%s_cents AS TEXT) AS %s_cents",field,field))
    }
  }
  expected <- as.data.table(dbGetQuery(pg,sprintf("SELECT %s FROM toa.%s",pg_sql,table)))
  actual <- as.data.table(dbGetQuery(dest,paste("SELECT",sqlite_sql,"FROM",table)))
  # SQLite infers logical for expression columns containing only NULLs.
  for (field in names(actual)[vapply(actual,is.logical,logical(1))]) {
    set(actual,j=field,value=as.character(actual[[field]]))
  }
  if (!fsetequal(expected,actual,all=TRUE)) stop("SQLite rows differ from PostgreSQL in ",table)
  nrow(actual)
}

verify_database <- function(pg,dest,database,meta=columns_in(pg)) {
  objects <- dbGetQuery(dest,"SELECT name FROM sqlite_schema WHERE type IN ('table','view')")
  stopifnot(setequal(unique(meta$table_name),objects$name),
            identical(dbGetQuery(dest,"PRAGMA integrity_check")[[1]],"ok"),
            nrow(dbGetQuery(dest,"PRAGMA foreign_key_check"))==0L)
  counts <- vapply(unique(meta$table_name),function(table) {
    verify_relation(pg,dest,table,meta[table_name==table])
  },integer(1))
  cat(database,"verified",sum(counts[base_tables]),"base rows across",length(base_tables),
      "tables and",sum(!names(counts) %in% base_tables),"reporting views\n")
}

export_database <- function(database,path) {
  pg <- connect(database)
  on.exit(dbDisconnect(pg))
  dest <- dbConnect(RSQLite::SQLite(),dbname=path)
  on.exit(dbDisconnect(dest),add=TRUE)
  dbExecute(dest,"PRAGMA foreign_keys=ON")
  dbWithTransaction(pg, {
    dbExecute(pg,"SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
    meta <- columns_in(pg)
    stopifnot(setequal(meta[table_type=="BASE TABLE",table_name],base_tables))
    dbWithTransaction(dest, {
      create_schema(dest)
      for (table in base_tables) copy_table(pg,dest,table,meta[table_name==table])
    })
    verify_database(pg,dest,database,meta)
  })
}

publish <- function() {
  dir.create("artifacts",showWarnings=FALSE)
  staging <- tempfile("sqlite-",tmpdir="artifacts")
  stopifnot(dir.create(staging))
  on.exit(unlink(staging,recursive=TRUE))
  databases <- c("toa_us","toa_china")
  files <- paste0(databases,".sqlite")
  for (i in seq_along(files)) export_database(databases[i],file.path(staging,files[i]))
  # Stage the manifest with the checked files. Each rename is on the same filesystem.
  hashes <- system2("sha256sum",file.path(staging,files),stdout=TRUE)
  stopifnot(is.null(attr(hashes,"status")),length(hashes)==length(files))
  manifest <- "SQLite-SHA256SUMS"
  writeLines(paste(sub(" .*","",hashes),files,sep="  "),file.path(staging,manifest))
  for (file in c(files,manifest)) {
    if (!file.rename(file.path(staging,file),file.path("artifacts",file))) stop("Could not publish ",file)
  }
}
if (sys.nframe()==0L) publish()
