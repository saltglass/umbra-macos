#!/usr/bin/env bash
# Writes build/licenses/THIRD-PARTY-LICENSES.txt: the licences of everything
# that is really inside the app. The app copies this file into itself at
# build time and shows it under About Umbra → Licences….
#
#   1. Umbra, the server program inside the app (GPL-3.0, with its source address)
#   2. every Go module built into that program (read from the program itself,
#      so the list can't drift from what ships), and Go's own library
#   3. the Swift packages the app links
#
# A module or package whose licence file can't be found stops the script and
# says which: a missing licence must never go unnoticed.
#
# Needs the helper built first (`just helper`) and the Swift packages
# fetched (`just packages`). Set UMBRA_SRC to use a local copy of Umbra
# instead of the one in build/umbra-src (as the other scripts do).
set -euo pipefail
. "$(dirname "$0")/common.sh"

HELPER="$ROOT/build/helper/umbra"
OUT_DIR="$ROOT/build/licenses"
OUT="$OUT_DIR/THIRD-PARTY-LICENSES.txt"

die() {
  echo "licenses: $*" >&2
  exit 1
}

[ -x "$HELPER" ] || die "the Umbra helper has not been built yet. Run 'just helper' first."

# Swift packages: where SwiftPM keeps them after a build.
CHECKOUTS=""
for dir in "$ROOT/build/DerivedData/SourcePackages/checkouts" "$ROOT/UmbraKit/.build/checkouts"; do
  if [ -d "$dir" ]; then
    CHECKOUTS="$dir"
    break
  fi
done
[ -n "$CHECKOUTS" ] || die "the Swift packages have not been fetched yet. Run 'just packages' first."

# The Swift packages that end up inside the app, by the folder name SwiftPM
# uses. (swift-openapi-urlsession also uses swift-collections' DequeModule.)
LINKED_SWIFT="swift-openapi-runtime swift-openapi-urlsession swift-http-types swift-collections"
# Packages that only run while building (the code generator and what it
# needs). They never reach the app, so their licences aren't listed. Any
# package in UmbraKit/Package.resolved that is in neither list stops the
# script: someone has to decide which it is.
BUILD_ONLY_SWIFT="swift-openapi-generator openapikit yams swift-argument-parser swift-algorithms swift-numerics"

# Prints the licence files at the top of a folder (LICENSE, LICENSE.txt,
# COPYING, NOTICE...), each under its own file name. Fails, naming $2, when
# there is no real licence file (a NOTICE alone isn't one).
print_licence_files() {
  local dir="$1" label="$2" found=0 file base lower
  for file in "$dir"/*; do
    [ -f "$file" ] || continue
    base="$(basename "$file")"
    lower="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
      licen[cs]e | licen[cs]e[-._]* | copying | copying[-._]* | unlicense | unlicense[-._]*)
        found=1
        ;;
      notice | notice[-._]* | patents | patents[-._]*) ;;
      *) continue ;;
    esac
    # Tidy line endings and strip control characters so the file is plain text.
    echo "[$base]"
    echo
    tr -d '\r' < "$file"
    echo
  done
  if [ "$found" -eq 0 ]; then
    die "no licence file found for $label (looked in $dir)"
  fi
}

# One entry: a separator, "name version", then the licence text.
entry() {
  local name="$1" version="$2" dir="$3" text
  # Run it first so a failure stops the script (a pipe into the file would hide it).
  text="$(print_licence_files "$dir" "$name $version")" || exit 1
  printf '%s\n' "================================================================================"
  printf '%s %s\n' "$name" "$version"
  printf '%s\n\n' "--------------------------------------------------------------------------------"
  printf '%s\n\n' "$text"
}

mkdir -p "$OUT_DIR"
TMP="$(mktemp "$OUT_DIR/.licenses.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

BUILD_INFO="$(go version -m "$HELPER")"
GO_VERSION="$(printf '%s\n' "$BUILD_INFO" | head -1 | sed -E 's/^.*: //')"
UMBRA_MODULE_VERSION="$(printf '%s\n' "$BUILD_INFO" | awk -F'\t' '$2 == "mod" { print $4; exit }')"

{
  cat <<'TEXT'
THIRD-PARTY LICENCES

Umbra for macOS is free software under the GNU General Public License,
version 3. Its source code is at https://github.com/saltglass/umbra-macos
It contains the Umbra server program, also under the GNU General Public
License, version 3 (source code at https://github.com/saltglass/umbra), and
the free software listed below. Each is under its own licence, which follows
its name.

TEXT

  # 1. Umbra itself.
  printf '%s\n' "================================================================================"
  printf 'Umbra (the server program inside this app) %s\n' "${UMBRA_MODULE_VERSION:-}"
  printf '%s\n\n' "--------------------------------------------------------------------------------"
  cat <<'TEXT'
Umbra is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License as published by the Free Software
Foundation, version 3.

Umbra is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
details.

Source code: https://github.com/saltglass/umbra

TEXT
  [ -f "$SRC/LICENSE" ] || die "no LICENSE file in the Umbra source ($SRC)"
  tr -d '\r' < "$SRC/LICENSE"
  echo
  echo

  # 2. The Go standard library, then every module built into the helper.
  # Go keeps its licence in its main folder; Homebrew's install moves it one up.
  GOROOT_DIR="$(go env GOROOT)"
  if [ ! -f "$GOROOT_DIR/LICENSE" ] && [ -f "$GOROOT_DIR/../LICENSE" ]; then
    GOROOT_DIR="$GOROOT_DIR/.."
  fi
  entry "Go standard library" "$GO_VERSION" "$GOROOT_DIR"

  # Each "dep" line is a module. A "=>" line right after it says it was
  # replaced, by a folder (used as it stands in Umbra's source) or by
  # another version of a module.
  printf '%s\n' "$BUILD_INFO" | awk -F'\t' '
    $2 == "dep" { if (name != "") print name "\t" version "\t" path; name = $3; version = $4; path = "" }
    $2 == "=>"  { path = $3; if (path !~ /^[.\/]/) { version = $4; name = name; path = "module:" $3 } }
    END { if (name != "") print name "\t" version "\t" path }
  ' | while IFS=$'\t' read -r name version replacement; do
    if [ -z "$replacement" ]; then
      module="$name@$version"
      shown="$version"
    elif [ "${replacement#module:}" != "$replacement" ]; then
      module="${replacement#module:}@$version"
      shown="$version (replaced by ${replacement#module:})"
    else
      # A local folder in Umbra's source, e.g. the patched anacrolix torrent.
      folder="$SRC/$replacement"
      [ -d "$folder" ] || die "$name is replaced by $replacement, which is not in the Umbra source ($SRC)"
      entry "$name" "$version, patched copy ($replacement)" "$folder"
      continue
    fi
    # Asks the Go module cache only: never the network.
    dir="$(GOFLAGS=-mod=mod GOPROXY=off go mod download -json "$module" 2>/dev/null |
      awk -F'"' '/"Dir":/ { print $4 }')"
    [ -n "$dir" ] && [ -d "$dir" ] || die "module $module is not in the Go module cache ($(go env GOMODCACHE)); build the helper first"
    entry "$name" "$shown" "$dir"
  done

  # 3. The Swift packages the app links.
  RESOLVED="$ROOT/UmbraKit/Package.resolved"
  [ -f "$RESOLVED" ] || die "no $RESOLVED"
  # "identity" and "version" lines of Package.resolved, paired up.
  PINS="$(awk -F'"' '/"identity"/ { id = $4 } /"version"/ && id != "" { print id "\t" $4; id = "" }' "$RESOLVED")"
  while IFS=$'\t' read -r identity version; do
    case " $LINKED_SWIFT $BUILD_ONLY_SWIFT " in
      *" $identity "*) ;;
      *) die "Swift package $identity (in Package.resolved) is in neither list at the top of scripts/licenses.sh: say whether it ends up inside the app" ;;
    esac
  done <<< "$PINS"
  for package in $LINKED_SWIFT; do
    version="$(printf '%s\n' "$PINS" | awk -F'\t' -v p="$package" '$1 == p { print $2 }')"
    [ -n "$version" ] || die "Swift package $package is not in $RESOLVED"
    [ -d "$CHECKOUTS/$package" ] || die "Swift package $package is not in $CHECKOUTS"
    entry "$package" "$version" "$CHECKOUTS/$package"
  done
} > "$TMP"

mv "$TMP" "$OUT"
trap - EXIT
echo "Licences written: $OUT"
