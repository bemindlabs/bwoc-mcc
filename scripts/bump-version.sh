#!/usr/bin/env bash
# Bump the semver in VERSION. Prints the new version to stdout.
#   scripts/bump-version.sh {major|minor|patch}
set -euo pipefail
cd "$(dirname "$0")/.."

level="${1:-patch}"
cur="$(tr -d '[:space:]' <VERSION)"
if [[ ! "$cur" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: VERSION must be MAJOR.MINOR.PATCH, got: '$cur'" >&2
  exit 1
fi
IFS=. read -r maj min pat <<<"$cur"

case "$level" in
  major) maj=$((maj + 1)); min=0; pat=0 ;;
  minor) min=$((min + 1)); pat=0 ;;
  patch) pat=$((pat + 1)) ;;
  *) echo "usage: bump-version.sh {major|minor|patch}" >&2; exit 1 ;;
esac

new="${maj}.${min}.${pat}"
printf '%s\n' "$new" >VERSION
echo "$new"
