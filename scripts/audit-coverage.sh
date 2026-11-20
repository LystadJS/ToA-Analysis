#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .toa data/cache artifacts/coverage
exec 9>.toa/build.lock
flock 9
source scripts/start-postgres.sh 9>&-
scripts/fetch.sh data/audit_sources.tsv
Rscript R/completeness.R
Rscript R/coverage_plot.R
Rscript tests/coverage_data.R
