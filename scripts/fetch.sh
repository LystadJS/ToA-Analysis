#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p data/cache
tmp=$(mktemp -d data/cache/.fetch.XXXXXXXX)
trap 'rm -rf -- "$tmp"' EXIT
while IFS=$'\t' read -r id name title publisher url digest; do
  [[ "$id" == source_id ]] && continue
  path="data/cache/$name"
  if ! echo "$digest  $path" | sha256sum --check --status; then
    curl --fail --silent --show-error --location --retry 3 "$url" -o "$tmp/$name"
    echo "$digest  $tmp/$name" | sha256sum --check --status
    mv "$tmp/$name" "$path"
  fi
done < data/sources.tsv
"${TOA_PYTHON:-python}" scripts/read_mcc.py data/cache/mcc.pbix "$tmp/mcc.csv"
mv "$tmp/mcc.csv" data/cache/mcc.csv
