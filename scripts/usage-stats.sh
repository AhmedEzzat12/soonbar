#!/usr/bin/env bash
# Rough usage numbers from GitHub, with no telemetry: zip downloads (installs and updates) and appcast fetches
# (each running copy checks for updates about once a day). Each run appends a snapshot to a local history file
# and shows the change since the previous run, so running it daily gives a trend.
# Usage: scripts/usage-stats.sh
set -euo pipefail
REPO="${GITHUB_REPOSITORY:-AhmedEzzat12/soonbar}"
HISTORY="${SOONBAR_USAGE_HISTORY:-$HOME/Library/Application Support/Soonbar Dev/usage-history.csv}"
mkdir -p "$(dirname "$HISTORY")"

ROWS="$(gh api "repos/$REPO/releases" --paginate --jq '.[] | [.tag_name,
  ([.assets[] | select(.name == "Soonbar.zip") | .download_count] | add // 0),
  ([.assets[] | select(.name == "appcast.xml") | .download_count] | add // 0)] | @tsv')"
LATEST="$(printf '%s\n' "$ROWS" | head -1 | cut -f1)"
ZIPS="$(printf '%s\n' "$ROWS" | awk -F'\t' '{ s += $2 } END { print s }')"
CHECKS="$(printf '%s\n' "$ROWS" | awk -F'\t' '{ s += $3 } END { print s }')"

PREVIOUS="$(tail -1 "$HISTORY" 2>/dev/null || true)"
[[ -f "$HISTORY" ]] || echo "date,latest,zip_downloads,update_checks" > "$HISTORY"
NOW="$(date '+%Y-%m-%d %H:%M')"
echo "$NOW,$LATEST,$ZIPS,$CHECKS" >> "$HISTORY"

printf '%s\n' "$ROWS" | awk -F'\t' 'BEGIN { printf "%-9s %10s %14s\n", "release", "downloads", "update checks" }
  { printf "%-9s %10d %14d\n", $1, $2, $3 }'
echo "Total: $ZIPS downloads, $CHECKS update checks (latest: $LATEST)"
if [[ "$PREVIOUS" == 20* ]]; then
  IFS=, read -r WHEN _ PREV_ZIPS PREV_CHECKS <<< "$PREVIOUS"
  echo "Since $WHEN: +$((ZIPS - PREV_ZIPS)) downloads, +$((CHECKS - PREV_CHECKS)) update checks (≈ copies running)"
fi
echo "History: $HISTORY"
