#!/usr/bin/env bash
# Verify a full restore and rerun the same integration suite against both copies.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/start-postgres.sh
(cd artifacts && sha256sum -c SHA256SUMS)
scratch=()
cleanup() {
  for db in "${scratch[@]}"; do dropdb "$db"; done
}
trap cleanup EXIT
for provider in us china; do
  db="toa_restore_${provider}_$$_$RANDOM"
  createdb "$db"
  scratch+=("$db")
  pg_restore --exit-on-error --single-transaction --no-owner --no-privileges -d "$db" "artifacts/toa_$provider.dump"
done
TOA_TEST_US="${scratch[0]}" TOA_TEST_CHINA="${scratch[1]}" Rscript tests/verify.R
