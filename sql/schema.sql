CREATE SCHEMA IF NOT EXISTS toa;
SET LOCAL search_path = toa, pg_catalog;
CREATE TABLE IF NOT EXISTS source (
  source_id text PRIMARY KEY, file_name text NOT NULL, title text NOT NULL,
  publisher_url text NOT NULL, download_url text NOT NULL, sha256 char(64) NOT NULL
);
CREATE TABLE IF NOT EXISTS country (
  iso3 char(3) PRIMARY KEY, name text NOT NULL, code_system text NOT NULL
);
CREATE TABLE IF NOT EXISTS program (
  id text PRIMARY KEY, iso3 char(3) NOT NULL REFERENCES country, source_id text NOT NULL REFERENCES source,
  locator text NOT NULL, name text NOT NULL, actor text, channel text NOT NULL,
  sector text, status text, year integer, period text, details text, citation text, project_investment_usd numeric(24,2)
);
CREATE TABLE IF NOT EXISTS finance (
  program_id text NOT NULL REFERENCES program, measure text NOT NULL,
  flow_year integer, period_ref text NOT NULL, instrument text, usd numeric(24,2), eligible_for_summary boolean NOT NULL,
  amount_estimated text, PRIMARY KEY(program_id,measure,period_ref)
);
CREATE TABLE IF NOT EXISTS result (
  id text PRIMARY KEY, program_id text NOT NULL REFERENCES program,
  indicator text NOT NULL, level text, unit text, baseline numeric(32,9), baseline_year integer,
  actual numeric(32,9), actual_text text, target numeric(32,9), observed_year integer,
  method text NOT NULL, interpretation text, comparator text, baseline_text text, target_text text
);
CREATE TABLE IF NOT EXISTS context (
  iso3 char(3) NOT NULL REFERENCES country, source_id text NOT NULL REFERENCES source,
  year integer NOT NULL, days numeric NOT NULL CHECK(days>=0), PRIMARY KEY(iso3,source_id,year)
);
CREATE TABLE IF NOT EXISTS exclusions (
  source_id text NOT NULL REFERENCES source, reason text NOT NULL, label text NOT NULL,
  n integer NOT NULL CHECK(n>0), PRIMARY KEY(source_id,reason,label)
);
CREATE INDEX IF NOT EXISTS program_country ON program(iso3,source_id,year);
CREATE INDEX IF NOT EXISTS result_program ON result(program_id);
CREATE OR REPLACE VIEW finance_by_country_year AS
SELECT p.iso3,p.source_id,f.flow_year AS year,f.period_ref AS period,p.channel,f.measure,f.instrument,
       count(*) AS records,count(f.usd) AS amounts_known,sum(f.usd) AS reported_usd
FROM program p JOIN finance f ON f.program_id=p.id
WHERE f.eligible_for_summary
GROUP BY p.iso3,p.source_id,f.flow_year,f.period_ref,p.channel,f.measure,f.instrument;
CREATE OR REPLACE VIEW country_coverage AS
SELECT c.iso3,c.name,coalesce(p.n,0) AS program_records,coalesce(r.n,0) AS numeric_results
FROM country c LEFT JOIN (SELECT iso3,count(*) n FROM program GROUP BY iso3) p USING(iso3)
LEFT JOIN (SELECT p.iso3,count(*) n FROM result r JOIN program p ON p.id=r.program_id
           WHERE r.actual IS NOT NULL GROUP BY p.iso3) r USING(iso3);

ALTER TABLE finance ADD COLUMN IF NOT EXISTS reported_amount numeric(24,2);
ALTER TABLE finance ADD COLUMN IF NOT EXISTS reported_currency char(3);
ALTER TABLE finance ADD COLUMN IF NOT EXISTS period_start date;
ALTER TABLE finance ADD COLUMN IF NOT EXISTS period_end date;
ALTER TABLE program ADD COLUMN IF NOT EXISTS sponsor_ownership_pct numeric(12,5);
ALTER TABLE program ADD COLUMN IF NOT EXISTS implied_sole_sponsor_equity_usd numeric(24,2);
ALTER TABLE result ADD COLUMN IF NOT EXISTS period_start date;
ALTER TABLE result ADD COLUMN IF NOT EXISTS period_end date;
ALTER TABLE result ADD COLUMN IF NOT EXISTS dating_basis text;
ALTER TABLE result ADD COLUMN IF NOT EXISTS timing_source_id text REFERENCES source;
CREATE OR REPLACE VIEW private_sponsor_coverage AS
SELECT p.iso3, f.flow_year, count(*) AS sponsor_records, count(f.usd) AS disclosed_records,
       count(p.sponsor_ownership_pct) AS known_ownership_shares, sum(f.usd) AS disclosed_sponsor_equity_usd,
       CASE WHEN count(f.usd)=0 THEN 'No disclosed amounts' WHEN count(f.usd)=count(*) THEN 'All listed stakes disclosed'
            ELSE 'Partial disclosure' END AS disclosure_status
FROM finance f JOIN program p ON p.id=f.program_id
WHERE p.source_id='ppi' AND f.measure='sponsor equity commitment'
GROUP BY p.iso3, f.flow_year;
CREATE OR REPLACE VIEW dated_program_results AS
SELECT p.iso3,p.source_id,r.* FROM result r JOIN program p ON p.id=r.program_id
WHERE r.observed_year IS NOT NULL AND r.level IN ('Outcome','Output') AND r.actual IS NOT NULL;
CREATE OR REPLACE VIEW finance_by_currency_period AS
SELECT p.iso3,p.source_id,f.measure,f.flow_year,f.period_ref,
       coalesce(f.reported_currency,'USD') AS currency, count(*) AS records,
       count(coalesce(f.reported_amount,f.usd)) AS disclosed_records,
       sum(coalesce(f.reported_amount,f.usd)) AS disclosed_amount
FROM program p JOIN finance f ON f.program_id=p.id
WHERE f.eligible_for_summary
GROUP BY p.iso3,p.source_id,f.measure,f.flow_year,f.period_ref,coalesce(f.reported_currency,'USD');


CREATE TABLE IF NOT EXISTS us_goods_trade (
  iso3 char(3) NOT NULL REFERENCES country, year integer NOT NULL,
  census_code text NOT NULL, exports_usd bigint NOT NULL, imports_usd bigint NOT NULL,
  source_id text NOT NULL REFERENCES source, PRIMARY KEY (iso3,year,census_code)
);
CREATE TABLE IF NOT EXISTS us_contribution (
  iso3 char(3) NOT NULL REFERENCES country, source_id text NOT NULL REFERENCES source,
  year integer NOT NULL, actor text NOT NULL, cents bigint, known integer NOT NULL,
  records integer NOT NULL, PRIMARY KEY (iso3,source_id,year,actor),
  CHECK (known>=0 AND records>=known AND records>0), CHECK ((known=0)=(cents IS NULL))
);
CREATE TABLE IF NOT EXISTS us_relationship (
  iso3 char(3) NOT NULL REFERENCES country, source_id text NOT NULL REFERENCES source,
  name text NOT NULL, kind text NOT NULL, status text NOT NULL,
  first_year integer, last_year integer, detail text NOT NULL, citation text NOT NULL,
  PRIMARY KEY (iso3,source_id,name)
);

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
  eligibility TEXT NOT NULL, title TEXT NOT NULL, published INTEGER NOT NULL, evaluator TEXT NOT NULL, authority TEXT NOT NULL,
  scope TEXT NOT NULL, timing TEXT NOT NULL, method TEXT NOT NULL, summary TEXT NOT NULL,
  limitation TEXT NOT NULL, url TEXT NOT NULL, evidence TEXT NOT NULL, source_id TEXT NOT NULL REFERENCES source(source_id),
  FOREIGN KEY(iso3,project_key) REFERENCES evaluation_program(iso3,project_key)
);
CREATE TABLE IF NOT EXISTS evaluation_finding (
  report_id TEXT NOT NULL REFERENCES evaluation_report(report_id), sequence INTEGER NOT NULL,
  panel TEXT NOT NULL, indicator TEXT NOT NULL, result TEXT NOT NULL, value NUMERIC(14,3), unit TEXT,
  interpretation TEXT NOT NULL, locator TEXT NOT NULL, PRIMARY KEY(report_id,sequence)
);
ALTER TABLE evaluation_program ADD COLUMN IF NOT EXISTS screening_url TEXT;
ALTER TABLE evaluation_search ADD COLUMN IF NOT EXISTS review_as_of DATE;
