
evaluation_tables <- c("evaluation_program","evaluation_search","evaluation_report","evaluation_finding")
build_evaluation_review <- function(us) {
  us$source <- rbind(us$source,fread("data/evaluation_sources.tsv"))
  p <- evaluation_priority(us)
  scratch <- tempfile("evaluation-")
  dir.create(scratch)
  on.exit(unlink(scratch,recursive=TRUE))
  files <- file.path(scratch,c("priorities.tsv","countries.tsv","gao.tsv","search.tsv"))
  fwrite(p,files[1],sep="\t")
  fwrite(us$country,files[2],sep="\t")
  gao <- as.data.table(readRDS("data/cache/gao-reports.rds"))
  fwrite(gao[,.(report_id,title,summary,published,url)],files[3],sep="\t")
  result <- system2("python3",c("scripts/search_evaluations.py",shQuote(files)))
  if (result!=0L) stop("Evaluation catalogue search failed")
  searches <- fread(files[4],colClasses=list(character=c("iso3","project_key","source_id","leads")))
  reports <- fread("data/evaluation_reports.tsv",na.strings="")
  findings <- fread("data/evaluation_findings.tsv",na.strings="")
  reviews <- fread("data/evaluation_screening.tsv",na.strings="")
  p[,status:="No qualifying evaluation found in the sources searched"]
  p[searches[match_count>0],on=.(iso3,project_key),status:="Related records found; qualifying evaluation unverified"]
  p[,screening_note:=NA_character_]
  p[reviews,on=.(iso3,project_key),screening_note:=i.screening_note]
  p[reviews[has_lead==1],on=.(iso3,project_key),status:="Related records found; qualifying evaluation unverified"]
  p[reports,on=.(iso3,project_key),status:="Post-completion evaluation found"]
  stopifnot(nrow(searches)==5L*nrow(p),all(reviews$project_key %in% p$project_key),
            all(reports$project_key %in% p$project_key),all(findings$report_id %in% reports$report_id))
  us$evaluation_program <- p
  us$evaluation_search <- searches
  us$evaluation_report <- reports
  us$evaluation_finding <- findings
  us
}
