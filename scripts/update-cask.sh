#!/usr/bin/env bash
# Update version + sha256 in a Homebrew cask file (BSD sed / macOS).
#   scripts/update-cask.sh <cask.rb> <version> <sha256>
set -euo pipefail

cask="${1:?cask path}"
version="${2:?version}"
sha="${3:?sha256}"

/usr/bin/sed -i '' -E "s/version \"[^\"]*\"/version \"${version}\"/" "$cask"
/usr/bin/sed -i '' -E "s/sha256 \"[0-9a-f]*\"/sha256 \"${sha}\"/" "$cask"

echo "updated ${cask} → v${version} (${sha})"
