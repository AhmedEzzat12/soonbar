#!/usr/bin/env bash
# Moves installs that update from another repo's feed (e.g. the app's previous home) onto Soonbar,
# with no reinstall: republishes a Soonbar release in that repo, so its feed offers the update.
#
# Sparkle only installs an update whose app has the installed app's file name or bundle identifier,
# so the bridge zip carries Soonbar.app renamed to the installed file name. After the update, Soonbar
# renames itself back to Soonbar.app on first launch (BundleRelocator) and from then on follows this
# repo's feed. It's signed with the same Sparkle key, so old installs accept it.
#
# Usage: scripts/publish-bridge.sh <owner/repo> <InstalledName.app> [version]
#   version defaults to the latest Soonbar release; it must be newer than everything in that repo's feed.
#   DRY_RUN=1 builds and checks build/bridge/ without publishing.
# Keep that repo (archive it if you like) until everyone has updated; its feed is how they get here.
set -euo pipefail
cd "$(dirname "$0")/.."
TARGET_REPO="${1:?Usage: scripts/publish-bridge.sh <owner/repo> <InstalledName.app> [version]}"
INSTALLED_NAME="${2:?Usage: scripts/publish-bridge.sh <owner/repo> <InstalledName.app> [version]}"
SOURCE_REPO="AhmedEzzat12/soonbar"
[[ "$INSTALLED_NAME" == *.app ]] || { echo "The installed name must end in .app" >&2; exit 1; }
VERSION="${3:-$(gh release view -R "$SOURCE_REPO" --json tagName --jq .tagName)}"
VERSION="${VERSION#v}"

OUT=build/bridge
rm -rf "$OUT"
mkdir -p "$OUT/app"
gh release download "v$VERSION" -R "$SOURCE_REPO" -p Soonbar.zip -p appcast.xml -D "$OUT"

source scripts/sparkle-tools.sh
# Only republish what we published: the zip must match the signature in Soonbar's own feed.
SIGNATURE="$(grep -o 'sparkle:edSignature="[^"]*"' "$OUT/appcast.xml" | cut -d'"' -f2)"
"$SPARKLE_BIN/sign_update" --verify "$OUT/Soonbar.zip" "$SIGNATURE"

ditto -x -k "$OUT/Soonbar.zip" "$OUT/app"
mv "$OUT/app/Soonbar.app" "$OUT/app/$INSTALLED_NAME"
# The bundle's folder name isn't part of its code signature, so renaming keeps the signature valid.
codesign --verify --deep --strict "$OUT/app/$INSTALLED_NAME"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$OUT/app/$INSTALLED_NAME/Contents/Info.plist")"

FEED_BUILD="$(curl -fsSL "https://github.com/$TARGET_REPO/releases/latest/download/appcast.xml" \
  | grep -o '<sparkle:version>[0-9]*' | grep -o '[0-9]*$' | sort -n | tail -1 || true)"
if [[ -n "$FEED_BUILD" && "$BUILD" -le "$FEED_BUILD" ]]; then
  echo "Build $BUILD isn't newer than build $FEED_BUILD in $TARGET_REPO's feed; installs wouldn't see it." >&2
  exit 1
fi

ZIP="$OUT/Soonbar.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$OUT/app/$INSTALLED_NAME" "$ZIP"
cat > "$OUT/notes.txt" <<'EOF'
• This app is now Soonbar. It renames itself on first launch and updates from its new home from now on.
• macOS asks for Calendar and Reminders access once more, and settings start fresh.
EOF
GITHUB_REPOSITORY="$TARGET_REPO" scripts/make-appcast.sh "$VERSION" "$BUILD" "$ZIP" "$OUT/notes.txt"
mv build/appcast.xml "$OUT/appcast.xml"
"$SPARKLE_BIN/sign_update" --verify "$ZIP" \
  "$(grep -o 'sparkle:edSignature="[^"]*"' "$OUT/appcast.xml" | cut -d'"' -f2)"

if [[ -n "${DRY_RUN:-}" ]]; then
  echo "Dry run: bridge for build $BUILD is in $OUT (not published)"
  exit 0
fi
gh release create "v$VERSION" "$ZIP" "$OUT/appcast.xml" -R "$TARGET_REPO" \
  --title "Soonbar $VERSION" --notes-file "$OUT/notes.txt"
echo "Published the bridge to $TARGET_REPO; installs there move to Soonbar on their next update check."
