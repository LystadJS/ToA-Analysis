library(DBI)
library(RPostgres)
library(data.table)

connect <- function(database) dbConnect(Postgres(), dbname = database, bigint = "numeric")
registry <- fread("data/sources.tsv")
cached <- function(key) file.path("data/cache", registry[source_id == key, file_name])
sheet <- function(key, skip = 0L) {
  as.data.table(readxl::read_excel(cached(key), skip = skip, col_types = "text"))
}
src_url <- function(key) registry[source_id == key, download_url]
to_iso <- function(label) {
  labels <- unique(label)
  overrides <- c("Kosovo"="XKX", "China (Hong Kong)"="HKG", "China (Taiwan)"="TWN",
                 "China (P.R.C.)"="CHN", "West Bank/Gaza"="PSE")
  codes <- countrycode::countrycode(labels, "country.name", "iso3c", custom_match=overrides, warn=FALSE)
  regional <- grepl("regional|not specified|former|worldwide|redacted", labels, ignore.case=TRUE)
  codes[regional] <- NA_character_
  codes[match(label,labels)]
}
numeric_value <- function(x) {
  s <- trimws(gsub(",", "", sub("^'", "", as.character(x)), fixed=TRUE))
  allowed <- grepl("^[+-]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)([eE][+-]?[0-9]+)?$", s)
  s[!allowed] <- NA_character_
  as.numeric(s)
}
