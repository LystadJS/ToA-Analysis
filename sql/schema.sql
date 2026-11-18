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
