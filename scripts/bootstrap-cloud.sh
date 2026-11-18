#!/usr/bin/env bash
# Install the Linux x86_64 tools outside the checkout, then build the release.
set -euo pipefail
cd "$(dirname "$0")/.."
base=/workspace/.toa-tools
mkdir -p "$base"
export XDG_CACHE_HOME="$base/cache" MAMBA_ROOT_PREFIX="$base/mamba" CONDA_PKGS_DIRS="$base/mamba/pkgs"
export PIP_CACHE_DIR="$base/pip-cache" PIP_INDEX_URL=https://pypi.org/simple
sha=701f39c06f8e6a670a0e186c8479b9e5c0502a2f0cda6cef65d83bdd2875e8bd
if ! echo "$sha  $base/micromamba" | sha256sum --check --status; then
  tmp=$(mktemp "$base/.micromamba.XXXXXXXX")
  trap 'rm -f -- "$tmp"' EXIT
  curl -fsSL --retry 3 https://github.com/mamba-org/micromamba-releases/releases/download/2.10.0-0/micromamba-linux-64 -o "$tmp"
  echo "$sha  $tmp" | sha256sum --check --status
  chmod 755 "$tmp"
  mv "$tmp" "$base/micromamba"
fi
if [[ -f "$base/project/conda-meta/history" ]]; then
  "$base/micromamba" env update -y -p "$base/project" -f environment.yml
else
  "$base/micromamba" create -y -p "$base/project" -f environment.yml
fi
export PATH="$base/project/bin:$PATH"
scripts/build.sh
