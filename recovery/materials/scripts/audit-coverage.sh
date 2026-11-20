#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .toa data/cache artifacts/coverage
exec 9>.toa/build.lock
flock 9
source scripts/start-postgres.sh
scripts/fetch.sh data/audit_sources.tsv
Rscript R/completeness.R
