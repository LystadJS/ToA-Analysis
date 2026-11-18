#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .toa
exec 9>.toa/build.lock
flock 9
scripts/fetch.sh
source scripts/start-postgres.sh
Rscript R/build.R
Rscript tests/verify.R
mkdir -p artifacts
for db in toa_us toa_china; do
  pg_dump -Fc --no-owner --no-privileges -d "$db" -f "artifacts/$db.dump.tmp"
  mv "artifacts/$db.dump.tmp" "artifacts/$db.dump"
done
(cd artifacts && sha256sum toa_us.dump toa_china.dump > SHA256SUMS)
