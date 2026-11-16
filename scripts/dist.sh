#!/usr/bin/env bash
# Makes the disk image people download: build/dist/Umbra-<version>.dmg
#
# What it does, in order (each step is a "stage"; if one fails, the message
# names it):
#   1. Refuses to run while the app it is about to rebuild is open.
#   2. Builds the Release app into its own folder, build/dist/DerivedData
#      (never build/DerivedData, which you may be running an app from).
#   3. Checks the built app: signature, hardened mode, version, and that the
#      Umbra server program inside it starts.
#   4. (Later) notarization of the app. Not done yet; see the marked place.
#   5. Packs the app and a shortcut to /Applications into a compressed,
#      read-only disk image, signs it (real identity only) and writes its
#      checksum file.
#   6. (Later) notarization of the disk image. Not done yet.
#   7. Opens the finished image read-only and checks the app inside it again.
#   8. Prints a short summary.
#
# Run it with `just dist` (that makes the Xcode project and the Umbra server
# program first). It only reads the build; it never starts the app and never
# uses the network.
#
# How it is signed: with the identity in UMBRA_SIGN_IDENTITY. Left unset it
# is "-", which means "ad hoc": fine on this Mac, but other Macs will block
# the result. A real identity looks like
#   UMBRA_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" just dist
set -euo pipefail

# This folder (the project's root). scripts/common.sh is not used here: it
# fetches Umbra's source over the network when UMBRA_SRC is unset, and this script
# must never reach for the network.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

IDENTITY="${UMBRA_SIGN_IDENTITY:--}"
DIST="$ROOT/build/dist"
DERIVED="$DIST/DerivedData"
APP="$DERIVED/Build/Products/Release/Umbra.app"
HELPER="$APP/Contents/Helpers/umbra"

# The version, read from the one place it lives.
VERSION_FILE="$ROOT/Config/Version.xcconfig"
setting() { sed -n "s/^$1[[:space:]]*=[[:space:]]*//p" "$VERSION_FILE" | tr -d '[:space:]'; }
VERSION="$(setting MARKETING_VERSION)"
BUILD_NUMBER="$(setting CURRENT_PROJECT_VERSION)"

DMG="$DIST/Umbra-$VERSION.dmg"
SUM="$DMG.sha256"

# ---- Tidying up and failing loudly ---------------------------------------
STAGE="starting"
STAGING=""     # the temporary folder the image is made from
MOUNT=""       # where the finished image is opened for checking
mounted=""     # "yes" while the image is open

cleanup() {
  status=$?
  # Close the image if it is still open, then remove the temporary folders.
  if [ -n "$mounted" ]; then
    hdiutil detach "$MOUNT" -quiet 2>/dev/null || hdiutil detach "$MOUNT" -force -quiet 2>/dev/null || true
  fi
  [ -n "$MOUNT" ] && rmdir "$MOUNT" 2>/dev/null || true
  [ -n "$STAGING" ] && rm -rf "$STAGING"
  if [ "$status" -ne 0 ]; then
    echo >&2
    echo "dist FAILED during stage: $STAGE" >&2
  fi
}
trap cleanup EXIT

say() { echo; echo "==> $*"; }
fail() { echo "error: $*" >&2; exit 1; }

# The "flags" line codesign prints must mention "runtime" (hardened mode).
check_hardened() { # <path> <what it is>
  codesign -dv --verbose=4 "$1" 2>&1 | grep -E '^CodeDirectory .*flags=[^ ]*runtime' >/dev/null \
    || fail "$2 is not signed in hardened mode (no 'runtime' flag): $1"
}

# Everything we check about an app, used on the built app and again on the
# copy inside the finished image.
verify_app() { # <path to Umbra.app> <what to call it in messages>
  local app="$1" what="$2" found
  codesign --verify --deep --strict "$app" || fail "$what: the signature does not verify"
  check_hardened "$app" "$what (app)"
  check_hardened "$app/Contents/Helpers/umbra" "$what (Umbra server program)"
  # Notarization refuses an app that lets a debugger attach.
  if codesign -d --entitlements - "$app" 2>&1 | grep -q 'get-task-allow'; then
    fail "$what carries the debugger permission (get-task-allow); Apple would reject it"
  fi
  found="$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")"
  [ "$found" = "$VERSION" ] || fail "$what says version $found but Config/Version.xcconfig says $VERSION"
  found="$(plutil -extract CFBundleVersion raw "$app/Contents/Info.plist")"
  [ "$found" = "$BUILD_NUMBER" ] || fail "$what has build number $found but Config/Version.xcconfig says $BUILD_NUMBER"
  echo "ok: $what: signature, hardened mode, version $VERSION (build $BUILD_NUMBER)"
}

# ---- Stage 1: is the app open? -------------------------------------------
STAGE="1. checking the app is not open"
say "$STAGE"
[ -n "$VERSION" ] && [ -n "$BUILD_NUMBER" ] || fail "could not read the version from $VERSION_FILE"
[ -d Umbra.xcodeproj ] && [ -x build/helper/umbra ] \
  || fail "the Xcode project or the Umbra server program is missing. Run 'just dist', not this script on its own."
# ps lists every running program with the path it was started by; any inside
# build/dist means the app (or its server) is running from the folder we are
# about to overwrite. A path that starts with "/" is complete (that is how
# Finder and `open` start things). Otherwise it is relative to the folder the
# program was started from, so that folder is looked up too. A path may also
# reach us through a symlink (/tmp is /private/tmp), so both spellings count.
DIST_REAL="$(cd "$DIST" 2>/dev/null && pwd -P || echo "$DIST")"
running=""
while read -r pid path; do
  case "$path" in
    /*) full="$path" ;;
    */*) cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
         full="$cwd/$path" ;;
    *) continue ;;
  esac
  case "$full" in "$DIST/"* | "$DIST_REAL/"*) running="$full" ;; esac
done < <(ps -axo pid=,comm=)
if [ -n "$running" ]; then
  fail "Umbra is open (it is running from $running). Quit Umbra first, then run this again."
fi
if hdiutil info | grep -F "$DMG" >/dev/null; then
  fail "the disk image $DMG is open in Finder. Eject it first, then run this again."
fi

# ---- Stage 2: build -------------------------------------------------------
STAGE="2. building the Release app"
say "$STAGE (signing identity: $IDENTITY)"
mkdir -p "$DIST"
rm -f "$DMG" "$SUM"
# CODE_SIGN_IDENTITY is passed down to the "Copy Umbra helper" step in
# project.yml, so one setting signs both the app and the server program.
# CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO stops Xcode adding its "let a debugger
# attach" permission (get-task-allow), which Apple's notarization rejects.
xcodebuild -project Umbra.xcodeproj -scheme Umbra -configuration Release \
  -derivedDataPath "$DERIVED" -destination 'platform=macOS,arch=arm64' \
  -skipPackagePluginValidation -skipMacroValidation \
  CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build
[ -d "$APP" ] || fail "the build did not produce $APP"

# ---- Stage 3: check the built app ----------------------------------------
STAGE="3. checking the built app"
say "$STAGE"
verify_app "$APP" "built app"
[ "$(lipo -archs "$APP/Contents/MacOS/Umbra")" = "arm64" ] || fail "the app is not arm64 only"
[ "$(lipo -archs "$HELPER")" = "arm64" ] || fail "the Umbra server program is not an arm64 Mach-O file"
# 'umbra version' only prints the version and exits; it starts nothing.
UMBRA_VERSION_TEXT="$("$HELPER" version)" || fail "the Umbra server program would not run 'umbra version'"
[ -n "$UMBRA_VERSION_TEXT" ] || fail "'umbra version' printed nothing"
echo "ok: Umbra server program is arm64 and says: $UMBRA_VERSION_TEXT"

# ---- Stage 4: notarize the app (NOT DONE YET) ----------------------------
# >>> LATER STEP: notarization goes here, only when IDENTITY is not "-". <<<
# Roughly: zip the app with `ditto -c -k --keepParent`, send it with
# `xcrun notarytool submit ... --wait`, then run `xcrun stapler staple "$APP"`
# so the approval travels inside the app. It must happen before stage 5, so
# the copy in the disk image is the approved one.
STAGE="4. notarizing the app"

# ---- Stage 5: make the disk image ----------------------------------------
STAGE="5. making the disk image"
say "$STAGE"
STAGING="$(mktemp -d "$DIST/staging.XXXXXX")"
# ditto copies the app exactly (keeping its signature); the shortcut lets
# people drag Umbra onto Applications. Nothing else goes in.
ditto --norsrc --noextattr "$APP" "$STAGING/Umbra.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -quiet -srcfolder "$STAGING" -volname "Umbra $VERSION" \
  -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGING"; STAGING=""

if [ "$IDENTITY" != "-" ]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  codesign --verify --strict "$DMG" || fail "the disk image's signature does not verify"
fi
# The checksum file is written next to the image, so people can run
# `shasum -a 256 -c Umbra-<version>.dmg.sha256` in the folder they downloaded to.
(cd "$DIST" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$SUM")" \
  && shasum -a 256 -c "$(basename "$SUM")" >/dev/null) || fail "could not write the checksum file"

# ---- Stage 6: notarize the disk image (NOT DONE YET) ---------------------
# >>> LATER STEP: notarize and staple the .dmg itself here (notarytool
# submit "$DMG" --wait; stapler staple "$DMG"), then re-write the checksum
# above, since stapling changes the file. <<<
STAGE="6. notarizing the disk image"

# ---- Stage 7: check what is inside the finished image --------------------
STAGE="7. checking the finished disk image"
say "$STAGE"
MOUNT="$(mktemp -d "$DIST/mount.XXXXXX")"
hdiutil attach -readonly -nobrowse -noautoopen -quiet -mountpoint "$MOUNT" "$DMG"
mounted="yes"
# Only the app and the Applications shortcut, nothing hidden.
CONTENTS="$(ls -A "$MOUNT" | grep -v '^\.fseventsd$' | LC_ALL=C sort | tr '\n' ' ')"
[ "$CONTENTS" = "Applications Umbra.app " ] || fail "the disk image holds unexpected items: $CONTENTS"
[ "$(readlink "$MOUNT/Applications")" = "/Applications" ] || fail "the Applications shortcut is wrong"
verify_app "$MOUNT/Umbra.app" "app inside the disk image"
hdiutil detach "$MOUNT" -quiet
mounted=""

# ---- Stage 8: summary -----------------------------------------------------
STAGE="8. summary"
SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
if [ "$IDENTITY" = "-" ]; then
  SIGNED="ad hoc (no developer certificate)"
else
  SIGNED="$IDENTITY"
fi
echo
echo "Done. The disk image is ready:"
echo "  File:           $DMG"
echo "  Size:           $SIZE"
echo "  Checksum:       $(cut -d' ' -f1 "$SUM")  (file: $SUM)"
echo "  App version:    $VERSION (build $BUILD_NUMBER)"
echo "  Umbra server:   $UMBRA_VERSION_TEXT"
echo "  Signed with:    $SIGNED"
if [ "$IDENTITY" = "-" ]; then
  echo
  echo "NOTE: this image is signed ad hoc and not notarized. macOS will block it"
  echo "on other Macs until it is signed with a Developer ID and notarized by Apple."
fi
