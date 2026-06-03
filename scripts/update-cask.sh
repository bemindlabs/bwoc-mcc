#!/usr/bin/env bash
# Update version + sha256 in a Homebrew cask file (BSD sed / macOS).
#   scripts/update-cask.sh <cask.rb> <version> <sha256>
set -euo pipefail

cask="${1:?cask path}"
version="${2:?version}"
sha="${3:?sha256}"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version must be MAJOR.MINOR.PATCH, got: '$version'" >&2
  exit 1
fi
if [[ ! "$sha" =~ ^[0-9a-f]{64}$ ]]; then
  echo "error: sha256 must be 64 lowercase hex chars, got: '$sha'" >&2
  exit 1
fi

# Anchor to the cask's leading-indent fields so we only touch the real
# version/sha256 lines, never an empty or look-alike string elsewhere.
/usr/bin/sed -i '' -E "s/^([[:space:]]*)version \"[^\"]*\"/\1version \"${version}\"/" "$cask"
/usr/bin/sed -i '' -E "s/^([[:space:]]*)sha256 \"[0-9a-f]{64}\"/\1sha256 \"${sha}\"/" "$cask"

echo "updated ${cask} → v${version} (${sha})"
