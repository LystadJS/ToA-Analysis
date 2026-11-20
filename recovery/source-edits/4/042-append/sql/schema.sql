
ALTER TABLE finance ADD COLUMN IF NOT EXISTS reported_amount numeric(24,2);
ALTER TABLE finance ADD COLUMN IF NOT EXISTS reported_currency char(3);
ALTER TABLE finance ADD COLUMN IF NOT EXISTS period_start date;
ALTER TABLE finance ADD COLUMN IF NOT EXISTS period_end date;
ALTER TABLE program ADD COLUMN IF NOT EXISTS sponsor_ownership_pct numeric(12,5);
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
