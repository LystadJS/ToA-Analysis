# Post-completion evaluation review

The Results tab connects each ranked U.S.-linked program or financing deal to the findings that can be traced to it. The 19 November 2026 release covers 817 financing records in 184 jurisdictions. Of the 250 jurisdictions in the atlas, 142 have five eligible records, 42 have one to four, and 66 have none. The review uses the program or deal as its unit. Several outcomes from one evaluation still count as one study.

## Financing priorities

| Financing source | Ranking amount in nominal U.S. dollars |
| --- | --- |
| DFC and legacy portfolio | Largest disclosed commitment or exposure for the same project number |
| U.S. EXIM | Largest noncancelled, approved authorization for a deal in a named foreign market |
| MCC compact financial transactions | Net obligations by country and project ID in the FY2004–2013 archive, including negative adjustments |
| Pacific Aid Map | Confirmed U.S. disbursements for a named activity. Compact and Peace Corps operating lines are grouped under their respective country programs |
| World Bank Private Participation in Infrastructure | Disclosed U.S. sponsor equity by project and financial-close year |
| Gates Foundation | Country-attributed commitment for an identified grant |
| Documentary program cases | Reported original budget when the funded intervention can be identified |

The five largest eligible records are selected within each country. The source, financing measure, amount, year and locator appear beside each rank. The archive year shown for MCC or the Pacific Aid Map is the last recorded transaction year. A commitment, authorization, exposure, equity stake and payment have different financial meanings. A common nominal dollar scale sets the search order. It cannot establish total cash receipts or the benefit per dollar. Published country, account and sector totals, entries with undisclosed amounts, and unallocated regional records cannot identify an individually priced country project. Price disclosure and source vintages influence which programs appear.

Repeated authorizations under the same EXIM deal and duplicate DFC snapshots are consolidated before ranking. Repeated borrower names can identify different deals. Source identifiers support additional matching as new evidence becomes available. The Mozartambique rural water case sits under the MCC water project. DFC and PPI describe the same 2019 Acajutla power facility in El Salvador, so the ranking uses the larger disclosed financing measure for that facility.

## Evidence and gaps

| Catalogue | Scope of the search |
| --- | --- |
| 3ie Development Evidence Portal | Identified impact evaluations, abstracts, program names, authors and research funders in the June 2023 archive |
| USAID Development Experience Clearinghouse | Final and special evaluation metadata through September 2014. Some records labeled final or special describe studies undertaken during implementation |
| World Bank Independent Evaluation Group | Completion reviews and performance assessments in the June 2026 index. A World Bank rating alone cannot establish a donor or host evaluation |
| MCC Open Data | The May 2013 agency evaluation inventory, including four study records. The catalogue includes baselines and interim evaluations |
| U.S. Government Accountability Office | Product titles and summary excerpts through 18 November 2026. Relevant products can include projections, audits and reports covering multiple countries |
| AEA RCT Registry | Trial names, interventions, country descriptors and registered study status in the 19 November 2026 snapshot. A registration documents a plan and can identify a later publication |

Each ranked record has one search entry per catalogue. Project and component names, reviewed aliases, available financing identifiers and country names are searched across indexed fields. A distinct program name or a combination of overlapping terms produces a candidate. The search excludes publications that predate a dated DFC, EXIM or Gates record, while retaining trial registrations that can precede financing. The candidate log preserves every match, including unrelated ones. Targeted follow-up checked study abstracts, institutional roles, follow-up timing and the available report text. Selected program-level decisions are recorded in the screening file. The source manifests identify the public archives and their exact checksums. [Catalogue manifest](../data/evaluation_sources.tsv) · [Project aliases](../data/evaluation_aliases.tsv) · [Screening decisions](../data/evaluation_screening.tsv)

A qualifying evaluation needs a documented U.S. donor or participant-country evaluation role, an identifiable intervention, and findings following its completion or the completion of a named activity. The Results page identifies the scope and follow-up for each report. This includes a University of Ghana evaluation of farmers after training while the wider compact continued. A program funder and a research funder can differ. Studies that identify the intervention but leave the donor or host evaluation role unconfirmed are labeled separately.

| Review status | Ranked records |
| --- | ---: |
| Verified donor or participant-country post-completion evaluation | 6 |
| Published evaluation located, donor or participant-country role unverified | 2 |
| Related records located, qualifying evaluation unverified | 37 |
| No qualifying evaluation found in the sources searched | 772 |

Seven qualifying studies cover six programs. Three related publications cover two additional programs in Benin and Burkina Faso. The review is strongest for historical MCC compacts. Commercial finance records often identify the borrower or insurer without publishing a completion date or an evaluation. The catalogues have different cutoffs, and the live donor and national repositories were only partially accessible. An unsuccessful search leaves the program's effect unknown. Missing reports and statistically inconclusive research are separate states in both databases.

The Mozambique chart comes directly from the original report. Other charts draw on the evaluators’ abstracts reproduced in the source catalogue. Numeric findings retain their original units. Categorical charts show the direction or uncertainty described by the authors. No effect size is assigned to an inconclusive result. Both Nicaragua publications follow the same intervention.

## Reproduction

The database build fetches the pinned archives, ranks the financing records in R, executes the catalogue search, imports the reviewed studies and findings, and verifies their links. The standalone atlas, country CSVs, PostgreSQL backups and SQLite mirrors use the same four evaluation tables. The China database includes the shared schema. This review concerns U.S.-linked programs.

```sh
scripts/build.sh
scripts/build-atlas.sh
Rscript R/country.R all
scripts/restore.sh
```

Use the country JSON download on the Results page for the financing priorities, catalogue searches, reports and findings together. Country briefs also include `evaluation_programs.csv` and `evaluation_findings.csv`. [Reviewed studies](../data/evaluation_reports.tsv) · [Chart values and source locations](../data/evaluation_findings.tsv)
