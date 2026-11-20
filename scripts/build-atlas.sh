#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .toa
exec 9>.toa/build.lock
flock 9
source scripts/start-postgres.sh 9>&-
scripts/fetch.sh data/atlas_sources.tsv
Rscript R/atlas.R
export npm_config_cache="${npm_config_cache:-$PWD/.toa/npm-cache}"
npm --prefix atlas ci --no-audit --no-fund
npm --prefix atlas run build
