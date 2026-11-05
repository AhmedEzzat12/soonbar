#!/usr/bin/env bash
# Publishes a release from this Mac — no GitHub Actions, nothing to pay for.
#   1. runs the tests and builds the universal app with version <version>
#   2. signs the update with your Sparkle key (login keychain; created on first run — Keychain may ask)
#   3. writes appcast.xml and creates GitHub release v<version> with the zip and appcast attached
# Installed copies find the new version through the appcast and update themselves.
#
# Usage: scripts/release.sh 1.2.0
# Release notes (shown in the app's update window and on GitHub) are generated from the user-facing commits
# since the previous release — feat:/fix: with no scope or the app scope (core commits are internal building
# blocks, so they're left out). To write your own instead:
#   RELEASE_NOTES=notes.txt scripts/release.sh 1.2.0
# Signing: uses the "Developer ID Application" certificate in your keychain (or SIGN_IDENTITY="<name>"). One stable
# signature means macOS keeps the Calendar/Reminders permission across updates, so the script refuses to publish an
# ad-hoc build unless ALLOW_ADHOC=1. With a notary profile (NOTARY_PROFILE, default "soonbar-notary"; see
# docs/DEVELOPMENT.md), the app is also notarized, so copies downloaded in a browser open without a warning.
#
# Back up the signing key once (losing it means installed copies can't verify future updates):
#   .build/sparkle-tools/*/bin/generate_keys -x ~/sparkle-private-key.txt   → then into a password manager
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?Usage: scripts/release.sh <version, e.g. 1.2.0>}"
TAG="v$VERSION"

if ! command -v gh >/dev/null || ! gh auth status >/dev/null 2>&1; then
  echo "Install and sign in to the GitHub CLI first: brew install gh && gh auth login" >&2; exit 1
fi
if ! git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
  echo "This branch has no upstream on GitHub yet; publish the branch first." >&2; exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit or stash your changes first." >&2; exit 1
fi
git fetch --quiet --tags origin
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse '@{u}')" ]]; then
  echo "Push your commits first — the release tag points at what's on GitHub." >&2; exit 1
fi
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "Release $TAG already exists." >&2; exit 1
fi

source scripts/sparkle-tools.sh
"$SPARKLE_BIN/generate_keys" >/dev/null
export SPARKLE_PUBLIC_KEY="$("$SPARKLE_BIN/generate_keys" -p)"
export APP_VERSION="$VERSION"
# Sparkle compares build numbers; the commit count only ever grows on main.
export BUILD_NUMBER="$(git rev-list --count HEAD)"

scripts/test.sh
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi
if [[ -z "$SIGN_IDENTITY" && "${ALLOW_ADHOC:-0}" != "1" ]]; then
  echo "No Developer ID Application certificate in your keychain. An ad-hoc release makes every user grant Calendar" >&2
  echo "and Reminders access again; set ALLOW_ADHOC=1 to release one anyway." >&2
  exit 1
fi
export SIGN_IDENTITY
echo "Signing with: ${SIGN_IDENTITY:-ad-hoc}"
scripts/build-app.sh release

# Notarize (Developer ID only), then staple the ticket so the app opens offline without asking Apple first.
NOTARY_PROFILE="${NOTARY_PROFILE:-soonbar-notary}"
if [[ "$SIGN_IDENTITY" == "Developer ID Application:"* ]]; then
  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    rm -f build/notarize.zip
    ditto -c -k --keepParent build/Soonbar.app build/notarize.zip
    RESULT="$(xcrun notarytool submit build/notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
    rm -f build/notarize.zip
    if [[ "$(printf '%s' "$RESULT" | plutil -extract status raw -o - - 2>/dev/null)" != "Accepted" ]]; then
      echo "Notarization failed: $RESULT" >&2
      echo "Details: xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE" >&2
      exit 1
    fi
    xcrun stapler staple build/Soonbar.app
  else
    echo "Not notarizing: no notary profile \"$NOTARY_PROFILE\" (see docs/DEVELOPMENT.md). Updates still work." >&2
  fi
fi
# Stable asset name so releases/latest/download/Soonbar.zip always points at the newest build.
ZIP="build/Soonbar.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent build/Soonbar.app "$ZIP"
NOTES="build/release-notes.txt"
if [[ -n "${RELEASE_NOTES:-}" ]]; then
  cp "$RELEASE_NOTES" "$NOTES"
else
  PREVIOUS_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
  git log ${PREVIOUS_TAG:+"$PREVIOUS_TAG..HEAD"} --format=%s \
    | { grep -E '^(feat|fix)(\(app\))?: ' || true; } \
    | sed -E 's/^(feat|fix)(\([^)]*\))?: //' \
    | awk '{ print "• " toupper(substr($0, 1, 1)) substr($0, 2) }' > "$NOTES"
  [[ -s "$NOTES" ]] || echo "• Small improvements and fixes." > "$NOTES"
fi
echo "Release notes:"; cat "$NOTES"
scripts/make-appcast.sh "$VERSION" "$BUILD_NUMBER" "$ZIP" "$NOTES"

gh release create "$TAG" "$ZIP" build/appcast.xml \
  --target "$(git rev-parse HEAD)" --title "Soonbar $VERSION" --notes-file "$NOTES"
echo "Published $TAG"
echo "New or changed UI in this release? Add screenshots (sample data, not a real calendar):"
echo "  scripts/release-screenshots.sh $VERSION <image.png> \"<caption>\" ..."
