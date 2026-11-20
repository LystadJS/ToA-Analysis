# Open-Source Adoptions

The databases use the DBI interface and its PostgreSQL driver. Source-specific R adapters extend that foundation. Each import retains the original reporting unit and source locator. I found no single reviewed project covering both providers, private sponsors, and measured host-country results.

| Candidate reviewed | Advantage | Disadvantage for this study | Decision |
|---|---|---|---|
| [DBI and RPostgres](https://github.com/r-dbi/RPostgres) | Maintained R database interface with transactions, parameter binding and bulk appends into PostgreSQL. | Provides storage primitives. Country matching and finance definitions still require domain work. | Adopt as the core. Both databases use one schema and the same ingestion and reporting functions. |
| [IATI d-portal](https://github.com/IATI/D-Portal) | Existing aid-activity explorer with PostgreSQL support and IATI transaction semantics. | Requires IATI reporting. AidData's PRC records and PPI's sponsor disclosures use different data models. | Retain as a research reference. Import the non-IATI sources directly. The [legacy IATI Datastore](https://github.com/IATI/IATI-Datastore) is archived. |
| [ForeignAssistance.gov Datasette archive](https://github.com/andrewheiss/foreign-assistance-data) and [companion source archive](https://github.com/andrewheiss/foreignassistance) | Preserves official U.S. files with provenance and an inspectable existing SQL workflow. | The application targets SQLite and a fixed historical U.S. release. It has no PRC counterpart. | Reuse the archived Greenbook and DFC workbooks. Use ForeignAssistance.gov reported disbursements for the distinct question of actual spending. |
| [chinadevfin3](https://github.com/t-emery/chinadevfin3) | Provides AidData GCDF 3.0 in R with record IDs, methodology fields and source references. | Unofficial development version. Commitment coverage ends in 2021. | Adopt the pinned R data object. Respect AidData's aggregation flag and adjusted amounts. |
| [World Bank PPI source workbook](https://github.com/oad67/ProjectSuccessPredictor) | Records sponsors, their origins, reported equity and project status for infrastructure. | Undisclosed sponsor equity is common. Project participation can include foreign state-owned companies. A predictive success label would conflate closure with performance. | Reuse the underlying World Bank workbook. Read named sponsors and disclosed stakes directly. |
| [AGOA policy brief pipeline](https://github.com/mlarh-16/agoa_data_brief) | Publishes country/year eligibility and USITC DataWeb preference claims with a methodology. | A customs value measures use of a preference. Its economic incidence requires separate evidence. | Adopt its D-only import series. Keep the trade measure outside funding totals. |
| [PBIXRay](https://github.com/Hugoberry/pbixray) | Reads embedded Power BI tables directly, including the unfiltered MCC monitoring table. | Python dependency to decode one binary format. A secondary workbook can inherit transformations from its publisher. | Adopt for extraction only. R retains actuals, baselines, targets and source classifications separately. |
| [WDI](https://github.com/vincentarelbundock/WDI) and [versioned WDI series](https://github.com/datasets/world-development-indicators) | Country indicators support comparisons of trade logistics over time. | National trends include many influences. The WDI API requires live access. | Use pinned import and export lead-time observations for context. |
| [targets](https://github.com/ropensci/targets) | Maintained R pipeline with dependency-aware incremental caching. | Adds orchestration for a small batch of fixed releases. | Use checksum-verified source caching and transactional rebuilds for this release. |
| [CLG project extract](https://github.com/chentitus/china-exposure-dashboard) | Extends AidData coverage into higher-income economies and through 2023. The cleaning code identifies nominal and constant-dollar fields. | The extract starts in 2020 and overlaps the older release. Revised record dates can cross release windows. | Import its 2022–23 records in a separate series, retain the original AidData IDs and credit classifications, and avoid adding face values to GCDF adjusted commitments. |
| [Gates Foundation grant archive](https://github.com/Mike-Honey/gates) | Contains original grant IDs, dates, purposes, grantees and committed values. | A grantee's address can differ from the country served. | Include a reviewed set of large grants where the stated purpose and grantee location identify the same country. |

## Interactive country atlas

| Project reviewed | Advantage | Limitation for diplomats | Decision |
|---|---|---|---|
| [D3 Geo](https://github.com/d3/d3-geo) and [D3 Zoom](https://github.com/d3/d3-zoom) | Project country polygons, draw geographic grids and navigate vector maps without a tile account. | Country matching, record exploration and accessible controls need application code. | Adopt for the offline atlas. Embed the map and country-level extracts in one HTML file. |
| [Leaflet](https://github.com/Leaflet/Leaflet) and [R leaflet](https://github.com/rstudio/leaflet) | Mature interactive GIS with GeoJSON layers, popups and an R interface. | Its tile-oriented navigation adds less value to a whole-world, equal-area comparison. | Prefer D3 for a projected world view with a linked briefing and a single offline artifact. |
| [MapLibre GL JS](https://github.com/maplibre/maplibre-gl-js) | GPU-accelerated maps, labels and rich map styles. | WebGL and tiled map assets add runtime and packaging requirements. | Reserve for a future application needing detailed project locations. |
| [Shiny for R](https://github.com/rstudio/shiny) | Connects country selection and charts directly to R and PostgreSQL. | A conventional deployment needs a running R service. | Reuse the R database layer at build time so a diplomat can open the validated snapshot locally. |
| [Natural Earth](https://github.com/nvkelso/natural-earth-vector) and [World Atlas](https://github.com/topojson/world-atlas) | Both supply reusable world geography. Natural Earth map units include ISO fields, label positions and subregions. | Some small territories need point selectors at world scale. Map units and diplomatic recognition differ. | Use public-domain Natural Earth 1:50m map units with an explicit ISO concordance and accessible selectors for small territories. |


| Additional release or archive | Advantage | Limitation | Adoption decision |
|---|---|---|---|
| [MCC compact reporting calendars](https://github.com/openmunilabs/iati-gen) and archived indicator tracking table | Names each compact, calendar period and quarter number. The ITT supplies indicator IDs and quarter-specific actuals. | Five modern compact names match exactly. A publication date cannot date an individual actual-to-date snapshot. | Extend the existing R importer using exact compact names and explicit quarter anchors. |
| [Pacific Aid Map transaction archive](https://github.com/raphaelmerx/pacific-aid-streamlit) | Records transaction timing, confirmation status, collecting agency and source references. | The retained Chinese spending records are marked unconfirmed. | Include as searchable leads. Direct borrower-register drawdowns receive their own measure. |
| [AidData CLG](https://www.aiddata.org/data) and GCDF | Shared record IDs permit checking later face-value disclosures against previously unpriced facilities. | Adjusted amounts and nominal face values use different definitions. | Store matched disclosures as linked evidence and exclude them from both historical commitment series. |


## Portable SQLite mirrors

| Project reviewed | Advantage | Limitation for this release | Selection |
|---|---|---|---|
| [RSQLite](https://github.com/r-dbi/RSQLite) with DBI and RPostgres | Uses the existing R pipeline, supports transactions and ships the SQLite engine. | SQLite numbers need explicit handling for exact cents and high-precision indicators. | Adopt. Reuse the PostgreSQL schema and reporting SQL, preserve exact values, and compare the rendered views. |
| [db-to-sqlite](https://github.com/simonw/db-to-sqlite) | Provides a general-purpose command for copying PostgreSQL tables and queries to SQLite. | This release would still need custom handling for its currency aggregates, precision rules and parity checks. | Use RSQLite to keep these rules in the existing build. |


## U.S. contributor visualizations

| Source or tool compared | Advantage | Limitation | Selection |
|---|---|---|---|
| ForeignAssistance.gov funding-agency summary, archived raw CSV | Identifies funding agencies and accounts for disbursements by recipient and fiscal year. | The funding and sector files come from different snapshots. | Use within-file funding shares and show the sector total alongside. The [atlas manifest](data/atlas_sources.tsv) pins the input. |
| Existing Greenbook, PPI and Gates records | Identify government agencies, named infrastructure sponsors and a private foundation. | Economic obligations, disclosed sponsor equity and reviewed grant commitments have different scopes. | Show each as a selectable measure with its own denominator. Reuse the atlas’s offline renderer and R aggregation. |

## Figure rendering and fonts

| Tool compared | Advantage | Limitation | Selection |
|---|---|---|---|
| ggplot2 and patchwork | A shared `theme_minimal()` controls print typography and grid lines. Patchwork aligns panels with different scales. | Static output has no country selection or record drill-down. | Use for all generated PDF and PNG figures. [ggplot2](https://ggplot2.tidyverse.org/) · [patchwork](https://patchwork.data-imaginist.com/) |
| Base R graphics | Ships with R and produces small plots. | Each renderer must position labels, legends and axes by hand. | Replaced for print figures to keep the theme consistent across releases. |
| D3, SVG and HTML | Keep map zoom, keyboard controls, tooltips and linked evidence available offline. | Browser-rendered charts need explicit typography, spacing and grid rules. | Keep the atlas and audit interactive and match the print theme. Embed the same three [licensed font files](assets/fonts/README.md) in both HTML builds. |

## Country relationships and longitudinal funding

| Source or tool reviewed | Advantage | Limitation | Selection |
|---|---|---|---|
| Archived U.S. Census country workbook and Schedule C | Both trade directions share one reporting basis. The official crosswalk identifies partner geography. | Current-year totals can include unreleased months. Historical joint territories need separate geography. | Adopt the original workbook using R/readxl, full years with reported December world trade, and current-jurisdiction codes. [Archived inputs](data/relationship_sources.tsv) |
| R Shiny tradedeficits and the Census API | Both support country comparisons. The Shiny source contains monthly SITC detail. | The older Shiny archive ends in 2016. The live API was inaccessible in this build. | Reuse the existing offline D3/JavaScript atlas with the pinned Census workbook. [Shiny project](https://github.com/Karagul/tradedeficits) |
| EXIM authorization archives and ForeignAssistance.gov | EXIM identifies decision status, market, fiscal year and approved amount. The funding file identifies the disbursing account's funding agency. | Multi-market and domestic EXIM records cannot be attributed to a foreign country. Authorizations differ from payments. | Use eligible EXIM approvals as a distinct series. Preserve the annual federal funding totals in the same chart. [EXIM archive](data/relationship_sources.tsv) |
| Texts of Trade Agreements, UNCTAD IIA archive, USTR and free-association laws | Partner codes, treaty dates and statuses support a country-level legal inventory. | Older texts include NAFTA and unsigned or superseded provisions. The investment treaty snapshot has historical statuses. | Use TOTA alongside USTR for comprehensive FTA parties, USTR for USMCA, UNCTAD for archived BIT statuses and the statutes for free association. [TOTA](https://github.com/mappingtreaties/tota) · [BIT corpus](https://github.com/ogrnz/BITs) · [Compact sources](data/us_free_association.tsv) |
| Official USUN Trade over Aid roster | Names initiative participants directly. | No financial observations, joining dates or benefit estimates accompany the supplied list. | Use the supplied roster transcription and keep a separate participation status for every jurisdiction. [Official roster](https://usun.usmission.gov/trade-over-aid/) · [Transcription](data/usun_roster.tsv) |


## Post-completion evaluation review

| Candidate | Advantages | Limits | Adoption decision |
| --- | --- | --- | --- |
| 3ie Development Evidence Portal and the LearningFrom3ie archive | Indexed projects, countries, study abstracts and separate research and program funding fields | The available snapshot ends in 2023. Some funder and result fields are sparse | Use for study discovery and extraction of published results with explicit locators. [Archive](https://github.com/ravivanpong/LearningFrom3ie) |
| USAID DEC archive and MCC Open Data | Identify agency studies, final reports, and historical MCC obligations at project level | The archived indexes predate many newer projects. The MCC catalog also contains baseline and interim records | Use the agency records to check study identity, timing and sponsorship. [DEC archive](https://github.com/albert-decatur/get-usaid-evals) · [MCC catalogue](https://github.com/openmunilabs/data-mcc-gov) · [MCC transactions](https://github.com/openmunilabs/iati-gen) |
| GAO R package, IEG completion reviews and AEA plan tracker | Searchable public oversight records, completion reviews and trial registrations | These sources can identify audits or study plans that lack outcome evidence or a qualifying donor role | Use for discovery and corroboration. Require a verified connection to the financed activity before reporting a result. [GAO](https://github.com/CetiAlphaFive/gao) · [IEG archive](https://github.com/euihyunb/World-Bank-Group-MIGA-Development-Effectiveness-) · [AEA archive](https://github.com/difang-huang/aea-plan-tracker) |
| Existing R/data.table, PostgreSQL, SQLite and D3 workflows | Share the existing country keys, evidence source catalogue, offline rendering and typography | Automated text matching cannot adjudicate commissioning or causal attribution | Extend the existing release and use Python’s standard library for streaming mixed-format catalogues. [Review method](docs/Evaluation-review.md) |
