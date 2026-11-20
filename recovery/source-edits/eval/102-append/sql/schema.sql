
CREATE TABLE IF NOT EXISTS evaluation_program (
  iso3 TEXT NOT NULL REFERENCES country(iso3), project_key TEXT NOT NULL,
  rank INTEGER NOT NULL CHECK(rank BETWEEN 1 AND 5), title TEXT NOT NULL, organization TEXT,
  source_id TEXT NOT NULL REFERENCES source(source_id), locator TEXT NOT NULL, year INTEGER,
  amount_cents BIGINT NOT NULL CHECK(amount_cents>0), measure TEXT NOT NULL, search_name TEXT NOT NULL,
  citation TEXT NOT NULL, status TEXT NOT NULL, screening_note TEXT,
  PRIMARY KEY(iso3, project_key), UNIQUE(iso3,rank)
);
CREATE TABLE IF NOT EXISTS evaluation_search (
  iso3 TEXT NOT NULL, project_key TEXT NOT NULL, source_id TEXT NOT NULL REFERENCES source(source_id),
  match_count INTEGER NOT NULL CHECK(match_count>=0), leads TEXT NOT NULL,
  PRIMARY KEY(iso3,project_key,source_id), FOREIGN KEY(iso3,project_key) REFERENCES evaluation_program(iso3,project_key)
);
CREATE TABLE IF NOT EXISTS evaluation_report (
  report_id TEXT PRIMARY KEY, iso3 TEXT NOT NULL, project_key TEXT NOT NULL,
  title TEXT NOT NULL, published INTEGER NOT NULL, evaluator TEXT NOT NULL, authority TEXT NOT NULL,
  scope TEXT NOT NULL, timing TEXT NOT NULL, method TEXT NOT NULL, summary TEXT NOT NULL,
  limitation TEXT NOT NULL, url TEXT NOT NULL, evidence TEXT NOT NULL, source_id TEXT NOT NULL REFERENCES source(source_id),
  FOREIGN KEY(iso3,project_key) REFERENCES evaluation_program(iso3,project_key)
);
CREATE TABLE IF NOT EXISTS evaluation_finding (
  report_id TEXT NOT NULL REFERENCES evaluation_report(report_id), sequence INTEGER NOT NULL,
  indicator TEXT NOT NULL, result TEXT NOT NULL, value NUMERIC(14,3), unit TEXT,
  interpretation TEXT NOT NULL, locator TEXT NOT NULL, PRIMARY KEY(report_id,sequence)
);
