-- Aggregate each fact at its own grain. An unknown year stays NULL.
SELECT 'Funding' AS kind, p.source_id, f.measure AS series, p.iso3, f.flow_year AS year,
       count(*) AS n, count(f.usd) AS known, count(f.usd) AS reported,
       count(*) FILTER (WHERE f.usd=0) AS zeroes,
       count(*) FILTER (WHERE f.eligible_for_summary) AS eligible
FROM toa.finance f JOIN toa.program p ON p.id=f.program_id
GROUP BY p.source_id,f.measure,p.iso3,f.flow_year
UNION ALL
SELECT 'Programs',source_id,'Source record',iso3,year,count(*),count(*),count(*),NULL,NULL
FROM toa.program GROUP BY source_id,iso3,year
UNION ALL
SELECT 'Results',p.source_id,coalesce(r.level,'Unclassified'),p.iso3,r.observed_year,
       count(*),count(r.actual),
       count(*) FILTER (WHERE r.actual IS NOT NULL OR nullif(trim(r.actual_text),'') IS NOT NULL),
       count(*) FILTER (WHERE r.actual=0),NULL
FROM toa.result r JOIN toa.program p ON p.id=r.program_id
GROUP BY p.source_id,r.level,p.iso3,r.observed_year
