# Trade over Aid | Country evidence

Build two PostgreSQL databases, export portable SQLite mirrors and generate a briefing for any of the 249 ISO 3166-1 countries and territories or Kosovo (XKX). Each database includes all 250 entries. See the country coverage table for the current number of program records by recipient and provider. The separate U.S. relationship register covers all 250 jurisdictions. An entry with no matching record means the included sources have no observation.

Start with [the evidence brief](docs/Evidence.md) for cited examples from Honduras, Niger, the Philippines, Mozambique and Ethiopia. The [open-source comparison](Open-Source%20Adoptions.md) explains the selections. Each input has a pinned archive URL, publisher reference and SHA-256 digest in the [source manifest](data/sources.tsv).

## Interactive country atlas

Open `Trade-over-Aid-Atlas.html` in a modern browser. Select a country on the map or search by name or ISO code. The coverage layer shows where each provider appears in the sources. The sponsor-equity layer compares disclosed U.S. and Chinese stakes in the same World Bank infrastructure series for 1999–2023. The map ranks providers when every listed stake for both providers has a disclosed amount. The country overview gives the number of stakes with a reported amount.

The funding history keeps U.S. payments, U.S. obligations and the two Chinese commitment series separate. Choose **Annual values** for exact amounts and years. The **Funding**, **Results** and **Programs** tabs link each entry to its source and record locator. **Download country data** exports the selected country's records, outcomes, national trade context and source references as JSON. The HTML embeds the full snapshot, geography, scripts and fonts. Following a publisher link requires a connection.

Open **U.S. contributors** for a ranked dollar and share breakdown and a selected contributor’s annual history. Choose one country or all 250 atlas recipients, a fiscal or calendar year, and a measure. The federal payment view uses funding-agency and account records from ForeignAssistance.gov. Its comparison shows the atlas sector-file total for the same selection. Each archive has its own release vintage. The historical economic obligation, infrastructure sponsor equity and reviewed foundation grant views each use their own disclosed subtotal. Unknown sponsor equity, signed adjustments and missing years are visible. Country JSON downloads include these chart values in integer cents and the supplementary agency source. The full build of the atlas fetches this [checksum-pinned funding file](data/atlas_sources.tsv).

The **Results** tab ranks up to five identifiable U.S.-linked programs or financing deals per country and shows the published post-completion evidence. Each program lists the financing basis, search status and sources. Evaluation charts preserve the original units, the comparison group and inconclusive findings. Country downloads include the full search trail. [Evaluation coverage and ranking rules](docs/Evaluation-review.md)

The EXIM measure includes a paginated list of named, approved, noncancelled authorizations, with original deal and authorization IDs. The Results rankings consolidate repeat authorizations under each deal before ranking. Contributor shares use the disclosed total for the selected measure, recipient scope and year from the same series.

To rebuild the HTML after populating the databases below, install Node.js 18 or newer with npm and run:

```bash
scripts/build-atlas.sh
```

The output is `artifacts/Trade-over-Aid-Atlas.html`. The initial build downloads locked JavaScript packages and a checksum-verified Natural Earth release. Subsequent readers only need the HTML. The map and country profiles describe documented financial engagement. The underlying sources provide program-specific evidence about outcomes and do not establish diplomatic influence.

## U.S. country relationships and annual contributions

Each country opens with the same four sections covering bilateral goods trade, formal relationships, U.S. organizations and evidence of host-country benefit. The Census figures give U.S. imports from the partner and exports to the partner in current dollars for complete calendar years. The latest matched year appears in the text. The accompanying series covers 232 jurisdictions across 1987–2025. Services and geographically unassigned trade lie outside its scope.

**U.S. contributors** plots each organization's annual dollar amount alongside a dashed line for the full disclosed total in the chosen measure. Choose leading contributors, all organizations, or one organization. The period selector applies to the ranking below the timeline. Federal disbursements, historical obligations, DFC commitments or exposure, EXIM authorizations, sponsor equity and private grants each have their own total. The numeric table gives counts for partial disclosure. Negative adjustments and missing years stay visible. The leading-three option ranks organizations by the sum of their absolute annual amounts across the displayed history. The EXIM archive ends in FY2025 Q3, and the DFC source is an active-project snapshot.

The relationship inventory includes the 20 partners in comprehensive U.S. FTAs through 2025, AGOA eligibility and preference use in the source years, 47 U.S. bilateral investment treaty records with historical UNCTAD statuses, and the three Compacts of Free Association. It also records the 47 names supplied from the USUN Trade over Aid roster on 19 November 2026. The official site returned HTTP 403 during the build. The checked-in transcription preserves its names, including Naoero (Nauru). The roster supplies neither joining dates nor payments. Country overviews give priority to comparison-group studies, program reports and dated monitoring. Where only undated MCC monitoring values are available, the overview states that their timing and attribution are unknown. In the original results ledger, 23 jurisdictions have a numeric U.S.-linked outcome or output under these criteria, including 15 with undated monitoring only. The treaty inventory is selective. Other frameworks, sectoral deals and tariff changes require additional sources. [USUN roster](https://usun.usmission.gov/trade-over-aid/) · [Transcription](data/usun_roster.tsv) · [FTA crosswalk](data/us_fta_partners.tsv)

The U.S. PostgreSQL and SQLite releases contain `us_goods_trade`, `us_relationship` and `us_contribution`. The last table stores exact current-dollar cents and both disclosed and total record counts. Use the source and year together when summing contributors. The China schema has empty counterparts for these U.S.-specific tables. The country downloads include the annual goods and contribution series, documented relationships and source citations.

## Visualization style

EB Garamond sets titles, Atkinson Hyperlegible Next sets labels and explanatory text, and JetBrains Mono sets numeric axes, amounts and codes. The country, coverage and evidence figures use a shared ggplot2 `theme_minimal()` theme. The interactive atlas and coverage matrix use the same white plot surfaces, light guides and typography. Both standalone HTML files embed the fonts. Cairo embeds font subsets in the printable PDFs. After generating the full release, run `python tests/print_figures.py` to verify PDF typography, coverage and empty panels. Font files and licenses are in [assets/fonts](assets/fonts).

## Audit completeness by country and year

Read the [coverage findings](docs/Coverage.md) for the reconciliations against U.S. government disbursement files, the USAID Greenbook and Kenya’s national debt register. With both databases populated, run `scripts/audit-coverage.sh` from the repository root. The audit uses R, `pdftotext` from Poppler and the [pinned report sources](data/audit_sources.tsv). The prepared cloud environment includes these tools.

Open `artifacts/coverage/Trade-over-Aid-coverage.html` for the offline heatmap or `artifacts/coverage/Country-year-coverage.pdf` for a printable comparison across all 250 jurisdictions. The same directory contains country-year observations and reconciliation CSVs, including amounts outside the current country registry. The audit reads the two databases and writes its own outputs. Run `Rscript tests/coverage_data.R` after sourcing `scripts/start-postgres.sh`, and use Python with Playwright and Chromium for `python tests/coverage_browser.py`.

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

Open `artifacts/countries/HND/brief.md`. The folder includes charts, the complete program list, finance with source locators, observed indicators with baselines and targets, and country-level trade context. `Rscript R/country.R ALL` generates all 250 briefs. On Linux, set `TOA_BRIEF_JOBS=4` to render four independent briefs at a time. The Philippines analysis produces a chart and a CSV showing which registration times rose or fell.

To query the U.S. or PRC database, use `psql -d toa_us` or `psql -d toa_china` after sourcing the startup script. For example, this query returns the actuals behind the Honduras case with the original report.

```sql
SELECT r.indicator, r.comparator, r.actual, r.unit, p.locator, s.download_url
FROM toa.result r
JOIN toa.program p ON p.id = r.program_id
JOIN toa.source s USING (source_id)
WHERE p.iso3 = 'HND' AND p.source_id = 'ftf';
```

## SQLite mirrors

Open `toa_us.sqlite` or `toa_china.sqlite` in an SQLite client for offline analysis. Each file contains all fourteen base tables, their keys and indexes, and all five reporting views. Use unqualified table names such as `program` and `finance_by_currency_period`. Both providers use the same schema. For cross-provider queries, open the U.S. file and run `ATTACH DATABASE 'toa_china.sqlite' AS prc` to access tables such as `prc.finance`. For example, run this in the China file to reproduce the Kenyan Treasury drawdowns in each source currency.

```sql
SELECT period_ref, currency, records, disclosed_amount
FROM finance_by_currency_period
WHERE iso3 = 'KEN' AND source_id = 'kenya_debt'
ORDER BY currency;
```

Dates use ISO text, Boolean flags use 1 and 0, and missing observations use SQL NULL. Monetary columns are expressed in their original units. Use `finance.usd_cents` and `finance.reported_amount_cents` for exact integer sums, grouping by currency when using the latter. The reporting views sum integer cents. Indicators and survey lead times retain numeric fields for filtering and arithmetic. The `baseline_decimal`, `actual_decimal`, `target_decimal` and `days_decimal` text columns preserve the original PostgreSQL decimals at full precision.

The full build generates both mirrors in `artifacts/`. To refresh only SQLite from an existing populated release, run `scripts/build-sqlite.sh`. Each export reads a repeatable, read-only PostgreSQL snapshot, compares every base and reporting row, and checks SQLite file integrity and foreign keys. After copying the files, run `sha256sum -c SQLite-SHA256SUMS` in their directory. These files are release snapshots. Updates to the source databases reach them on the next export.

## Coverage and units

| Portfolio | Unit of observation and dates | Interpretation |
|---|---|---|
| USAID Greenbook | Country, fiscal period and funding account, FY1946–2020 | Economic assistance obligations in historical dollars. Negative adjustments are retained. FY1976 and its transition quarter remain distinct. |
| ForeignAssistance.gov | Sector, country and fiscal year, FY2001–25. The older country file is archived separately | All reported sectors, including military assistance. Dollar amounts are country allocations. An implementing organization may receive the payment. The last year in a snapshot can be partial. |
| USAID GeoCenter | Operating unit, fiscal year and sector, FY2009–2013 | Spent amounts from annual sector rows. Total and obligated rows are excluded. This series overlaps U.S. government-wide disbursements. |
| DFC | Individual rows in an active-project portfolio, known fiscal years 1961–2024 | Commitment or exposure by instrument, including insurance. Domestic and regional rows are excluded. Repeated project numbers occur. Identical source rows remain inspectable and are excluded from summary amounts. |
| AidData GCDF 3.0 | PRC official project or facility, commitment years 2000–2021 | Adjusted nominal dollars reduce rollover double counting. Source-recommended records enter summaries. Retained pledges, cancellations and suspensions can be inspected. 152 dated payment observations across eight recipients plus two cumulative snapshots have their own dates and measures. |
| Kenya National Treasury and Lowy Pacific Aid Map | Six FY2022/23 borrower-reported facility drawdowns and 769 unconfirmed Pacific spending entries | Kenya’s original-currency drawdowns reconcile to its creditor totals. Pacific entries are leads and are excluded from summaries. |
| AidData CLG-Global 1.0 | PRC project or facility, 2022–23 extract | Nominal face values from the newer release, including separately identified official commercial finance (OFIC). 57 historical face values for 34 countries are separately linked to GCDF gaps by exact year, recipient and ID. Thirteen IDs in the 2022–23 series also occur in GCDF with different years. Keep source series separate across the break. |
| World Bank PPI | Named foreign sponsor at financial close, 1999–2023 | 366 U.S. and 161 PRC sponsor records. The source discloses sponsor equity in 80 and 52 respectively. Project-wide investment is a separate field repeated per sponsor. The PPI frame covers infrastructure with private participation and includes state-owned sponsors. |
| Gates Foundation | 35 reviewed private grants of at least $1 million, from the September 2025 archive | Each grant names its host in its stated purpose and a locally based grantee. Covers 28 countries. Commitments are disclosed. Actual payments and impacts require further evidence. |
| MCC and project evaluations | 4,737 tracking indicators across 21 countries, plus linked report cases | The monitoring table retains process, output, outcome and missing records. It reports 3,299 nonempty actuals, including dates. The release adds 6,858 quarterly numeric values across five compacts and dates 210 explicit milestone actuals. Source documents supply selected program-level results for both providers. |
| AGOA | 45 countries × 25 years, 2000–2024 | Published eligibility and U.S. customs value claiming AGOA alone, excluding GSP. The claims measure use of a trade preference. They are separate from aid, tariff savings, and incremental exports. |
| World Bank logistics | Country-level import and export median lead times in available survey years | National observations in days. Shared across the two databases for context. |

For infrastructure, significance follows the PPI financial-close reporting frame. A dollar cutoff would discard projects with undisclosed sponsor stakes. For private philanthropy, the release uses a $1 million threshold and manual host-country verification. Private coverage is selective. Reported domicile identifies a sponsor's origin at the source date. Corporate ownership is identified only where separately supported. Several Chinese facilities can finance one physical project.

## Database conventions

The `toa` schema contains `country`, `source`, `program`, `finance`, `result`, `context` and `exclusions`. “Program” is a source record and can denote a named project, a funding account, a monitoring project or an annual preference observation. Its ID is scoped to its release. Use the locator with the pinned source file to inspect the underlying row. The exclusions table records unmatched and non-country labels from the country-matching step. Scope filters such as economic-only assistance are documented above.

`toa.finance_by_country_year` groups eligible records by source, amount measure, instrument and period. It returns both the disclosed-amount count and the record count. A group with no known amounts has a null sum. Keep commitments, disbursements, portfolio exposures and sponsor equity separate. Sources can overlap within one country. A universal donor total would duplicate flows and mix measures. Use `toa.finance_by_currency_period` for native-currency flows, `toa.private_sponsor_coverage` for the PPI stake denominator and `toa.dated_program_results` for dated numeric outputs and outcomes. Six implied sole-owner equity amounts are stored separately on the program records. The budget fields and cumulative disbursement snapshots remain available in `toa.finance`.

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

For the atlas, run `python tests/atlas_data.py` after sourcing the PostgreSQL startup script. This checks the finished HTML against both databases, including money, missing amounts, outcomes, citations and country scope. Run `python tests/atlas_browser.py` with a Python environment containing Playwright and Chromium to exercise country selection, both map layers, funding and results, downloads and offline rendering. Set `CHROMIUM_PATH` to use a specific Chromium executable.

### Assemble the portable release

With the project dependencies installed, build the databases, standalone atlas, review exports and briefs. The audit and print checks require Poppler. Browser checks use Playwright with Chromium.

```sh
scripts/build.sh
scripts/build-atlas.sh
scripts/audit-coverage.sh
source scripts/start-postgres.sh
Rscript R/evaluation_exports.R
Rscript R/country.R ALL
Rscript R/evidence.R
tests/restore.sh
python tests/atlas_data.py
python tests/atlas_browser.py
python tests/coverage_browser.py
python tests/country_profiles.py
python tests/print_figures.py
```

After recording the results of those checks in a plain-text verification file, run `python scripts/package_release.py --verification /path/to/Verification.txt` from a clean feature checkout. The ZIP includes both offline HTML files, both PostgreSQL backups and SQLite mirrors, every brief, the audit and evaluation search CSVs, source at that commit, and a release checksum manifest.
