#!/usr/bin/env bash
# Adds screenshots to a published release: uploads each image and appends them to its notes on GitHub.
# Rule: every release with new or changed UI gets screenshots here, or a refreshed demo video
# (scripts/make-demo-video.sh) when the change is big enough to show in motion.
# Capture with staged or sample data, never a real calendar.
#
# Usage: scripts/release-screenshots.sh <version> <image.png> "<caption>" [<image.png> "<caption>" ...]
# Running it again for the same release replaces the earlier screenshots.
# The in-app update window shows plain text only, so the images appear on the GitHub release page.
set -euo pipefail
cd "$(dirname "$0")/.."
usage() { echo "Usage: scripts/release-screenshots.sh <version> <image.png> \"<caption>\" [...]" >&2; exit 1; }
[[ $# -ge 3 && $(( ($# - 1) % 2 )) -eq 0 ]] || usage
VERSION="${1#v}"
TAG="v$VERSION"
shift
REPO="${GITHUB_REPOSITORY:-AhmedEzzat12/soonbar}"
gh release view "$TAG" -R "$REPO" >/dev/null

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Replace, don't pile up: drop screenshots from an earlier run.
gh release view "$TAG" -R "$REPO" --json assets --jq '.assets[].name' | { grep '^screenshot-' || true; } \
  | while read -r old; do gh release delete-asset "$TAG" "$old" -R "$REPO" --yes; done

SECTION="## Screenshots"
INDEX=0
while [[ $# -gt 0 ]]; do
  IMAGE="$1"
  CAPTION="$2"
  shift 2
  [[ -f "$IMAGE" ]] || { echo "No such image: $IMAGE" >&2; exit 1; }
  INDEX=$((INDEX + 1))
  NAME="screenshot-$INDEX.${IMAGE##*.}"
  cp "$IMAGE" "$WORK/$NAME"
  gh release upload "$TAG" "$WORK/$NAME" -R "$REPO" --clobber
  SECTION+=$'\n\n'"**$CAPTION**"$'\n\n'"![$CAPTION](https://github.com/$REPO/releases/download/$TAG/$NAME)"
done

BODY="$(gh release view "$TAG" -R "$REPO" --json body --jq .body)"
BODY="${BODY%%## Screenshots*}"
BODY="${BODY%"${BODY##*[![:space:]]}"}"
printf '%s\n\n%s\n' "$BODY" "$SECTION" > "$WORK/notes.md"
gh release edit "$TAG" -R "$REPO" --notes-file "$WORK/notes.md" >/dev/null
echo "Added $INDEX screenshot(s) to $TAG"
