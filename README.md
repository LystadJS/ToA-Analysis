# Trade over Aid | Country evidence

Build two PostgreSQL databases and generate a briefing for any of the 249 ISO 3166-1 countries and territories or Kosovo (XKX). Each database includes all 250 entries. This release has country-attributed program, finance or preference records for **208** entries in the U.S. database and **181** in the PRC database. An entry with no matching record means the included sources have no observation.

Start with [the evidence brief](docs/Evidence.md) for cited examples from Honduras, Niger, the Philippines, Mozambique and Ethiopia. The [open-source comparison](Open-Source%20Adoptions.md) explains the selections. Each input has a pinned archive URL, publisher reference and SHA-256 digest in the [source manifest](data/sources.tsv).

## Build and use

Run these commands on Linux as an ordinary user with Bash, micromamba, curl, flock and sha256sum. They create a local Unix-socket PostgreSQL cluster and two regular databases. Run from the repository root.

```bash
micromamba create -y -p "$PWD/.toa/env" -f environment.yml
export PATH="$PWD/.toa/env/bin:$PATH"
scripts/build.sh
source scripts/start-postgres.sh
Rscript R/country.R HND
Rscript R/evidence.R
```

Open `artifacts/countries/HND/brief.md`. The folder includes charts, the complete program list, finance with source locators, observed indicators with baselines and targets, and country-level trade context. `Rscript R/country.R ALL` generates all 250 briefs. The Philippines analysis produces a chart and a CSV showing which registration times rose or fell.

To query the U.S. or PRC database, use `psql -d toa_us` or `psql -d toa_china` after sourcing the startup script. For example, this query returns the actuals behind the Honduras case with the original report.

```sql
SELECT r.indicator, r.comparator, r.actual, r.unit, p.locator, s.download_url
FROM toa.result r
JOIN toa.program p ON p.id = r.program_id
JOIN toa.source s USING (source_id)
WHERE p.iso3 = 'HND' AND p.source_id = 'ftf';
```

## Coverage and units

| Portfolio | Unit of observation and dates | Interpretation |
|---|---|---|
| USAID Greenbook | Country, fiscal period and funding account, FY1946–2020 | Economic assistance obligations in historical dollars. Negative adjustments are retained. FY1976 and its transition quarter remain distinct. |
| ForeignAssistance.gov | Country and fiscal year, FY2001–2024 in disbursement rows | All reported sectors, including military assistance. Dollar amounts are country allocations. An implementing organization may receive the payment. The last year in a snapshot can be partial. |
| USAID GeoCenter | Operating unit, fiscal year and sector, FY2009–2013 | Spent amounts from annual sector rows. Total and obligated rows are excluded. This series overlaps U.S. government-wide disbursements. |
| DFC | Individual rows in an active-project portfolio, known fiscal years 1961–2024 | Commitment or exposure by instrument, including insurance. Domestic and regional rows are excluded. Repeated project numbers occur. Identical source rows remain inspectable and are excluded from summary amounts. |
| AidData GCDF 3.0 | PRC official project or facility, commitment years 2000–2021 | Adjusted nominal dollars reduce rollover double counting. Source-recommended records enter summaries. Retained pledges, cancellations and suspensions can be inspected. Eleven reviewed payment observations plus two cumulative snapshots have their own dates and measures. |
| AidData CLG-Global 1.0 | PRC project or facility, 2022–23 extract | Nominal face values from the newer release, including separately identified official commercial finance (OFIC). Thirteen IDs also occur in GCDF with different years. Keep source series separate across the break. |
| World Bank PPI | Named foreign sponsor at financial close, 1999–2023 | 366 U.S. and 161 PRC sponsor records. The source discloses sponsor equity in 80 and 52 respectively. Project-wide investment is a separate field repeated per sponsor. The PPI frame covers infrastructure with private participation and includes state-owned sponsors. |
| Gates Foundation | Twelve reviewed private grants of at least $1 million, from the September 2025 archive | Each grant names its host in its stated purpose and a locally based grantee. Covers 12 countries. Commitments are disclosed. Actual payments and impacts require further evidence. |
| MCC and project evaluations | 4,737 tracking indicators across 21 countries, plus linked report cases | The monitoring table retains process, output, outcome and missing records. It reports 3,299 nonempty actuals, including dates. Baseline year and observation year are independent. Source documents supply selected program-level results for both providers. |
| AGOA | 45 countries × 25 years, 2000–2024 | Published eligibility and U.S. customs value claiming AGOA alone, excluding GSP. The claims measure use of a trade preference. They are separate from aid, tariff savings, and incremental exports. |
| World Bank logistics | Country-level import and export median lead times in available survey years | National observations in days. Shared across the two databases for context. |

For infrastructure, significance follows the PPI financial-close reporting frame. A dollar cutoff would discard projects with undisclosed sponsor stakes. For private philanthropy, the release uses a $1 million threshold and manual host-country verification. Private coverage is selective. Reported domicile identifies a sponsor's origin at the source date. Corporate ownership is identified only where separately supported. Several Chinese facilities can finance one physical project.

## Database conventions

The `toa` schema contains `country`, `source`, `program`, `finance`, `result`, `context` and `exclusions`. “Program” is a source record and can denote a named project, a funding account, a monitoring project or an annual preference observation. Its ID is scoped to its release. Use the locator with the pinned source file to inspect the underlying row. The exclusions table records unmatched and non-country labels from the country-matching step. Scope filters such as economic-only assistance are documented above.

`toa.finance_by_country_year` groups eligible records by source, amount measure, instrument and period. It returns both the disclosed-amount count and the record count. A group with no known amounts has a null sum. Keep commitments, disbursements, portfolio exposures and sponsor equity separate. Sources can overlap within one country. A universal donor total would duplicate flows and mix measures. The budget fields and cumulative disbursement snapshots remain available in `toa.finance`.

`toa.result` links each observation to its program. It stores measurement method, comparator, unit, baseline, actual, target and evidence notes. A greater-than comparator preserves a reported lower bound. Program-monitoring changes, causal estimates and country trends support different inferences. Some monitoring indicators include both totals and subgroup rows. Read them individually. A target or a completed construction project alone gives no estimate of host-country welfare.

## Backups and validation

`scripts/build.sh` checks source hashes, cleans in R, replaces each provider release in a transaction, runs integration checks and writes `artifacts/toa_us.dump`, `artifacts/toa_china.dump` and `artifacts/SHA256SUMS`. Python decodes the embedded Power BI monitoring table. Raw source files, databases and generated briefs are kept outside Git.

Restore a downloaded backup into an empty PostgreSQL 18 database. Use the corresponding name for the second backup.

```bash
createdb toa_us_restored
pg_restore --exit-on-error --single-transaction --no-owner --no-privileges -d toa_us_restored artifacts/toa_us.dump
```

`tests/restore.sh` restores both backups into temporary databases, reruns the integration suite, and removes its temporary copies. `Rscript tests/verify.R` checks the live release, including source reconciliation, missing amounts, joins, coverage, monetary precision, lower bounds, fiscal periods and evaluated results. Running the build again uses the same pinned inputs. To adopt a new source vintage, update the manifest, audit its definitions and country concordance, then review the release-specific tests.

The prepared Codex cloud runtime uses `/workspace/.toa-tools/project/bin`. Add that directory to PATH and source `scripts/start-postgres.sh` in a fresh shell. The prepared databases reside in the checkout's ignored `.toa/pgdata`; backups are portable.
