# Umbra for macOS task runner. Run `just` to list recipes.

default:
    @just --list

# Build the Umbra server program into build/helper/umbra.
# Set UMBRA_SRC to a folder to build that folder as it stands.
helper:
    scripts/build-helper.sh

# Copy the API description (and the commit it came from) out of Umbra's source.
# Set UMBRA_SRC to use a local folder; otherwise the version in UMBRA_VERSION.
gen:
    scripts/sync-api.sh

# Write build/licenses/THIRD-PARTY-LICENSES.txt, the licences of everything
# inside the app (the helper's Go modules, the Swift packages, Umbra itself).
# Needs the helper built (`just helper`); fetches the Swift packages if need be.
licenses: packages
    scripts/licenses.sh

# Fetch the Swift packages (into build/DerivedData/SourcePackages) without building.
packages: project
    xcodebuild -project Umbra.xcodeproj -scheme Umbra -derivedDataPath build/DerivedData -resolvePackageDependencies -skipPackagePluginValidation -skipMacroValidation

# Make the app's icons (App/Assets.xcassets) from Config/icon/umbra-icon.svg.
# The pictures are committed, so a build never needs this.
icon:
    swift scripts/make-icon.swift

# Make the Xcode project from project.yml
project:
    xcodegen generate

xcodebuild_debug := "xcodebuild -project Umbra.xcodeproj -scheme Umbra -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation"
app_binary := "build/DerivedData/Build/Products/Debug/Umbra.app/Contents/MacOS/Umbra"

# Build the app (Debug) into build/
build: project helper licenses
    {{xcodebuild_debug}} build

# Draw the views to PNG pictures (1x, light and dark) in build/snapshots.
# Uses the helper already built (building it first if there is none).
snapshot: project
    @test -x build/helper/umbra || just helper
    just licenses
    {{xcodebuild_debug}} -quiet build
    rm -rf build/snapshots
    {{app_binary}} --snapshot build/snapshots

xcodebuild_release := "xcodebuild -project Umbra.xcodeproj -scheme Umbra -configuration Release -derivedDataPath build/DerivedData -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation"

# Build the app (Release) into build/DerivedData/Build/Products/Release.
# Don't open it casually: a Release build uses the real data folder
# (~/Library/Application Support/Umbra) and is not loopback-only.
build-release: project helper licenses
    {{xcodebuild_release}} build

# Make the disk image to hand out: build/dist/Umbra-<version>.dmg (plus its checksum).
# Built in its own folder, so a running dev build is not disturbed. Set
# UMBRA_SIGN_IDENTITY to a Developer ID to sign for real (default: ad hoc).
dist: project helper licenses
    scripts/dist.sh

run: build
    open build/DerivedData/Build/Products/Debug/Umbra.app

# Run the UmbraKit tests
test:
    cd UmbraKit && swift test

# Check code style (fails on any problem)
lint:
    xcrun swift-format lint --strict --recursive App UmbraKit/Sources/UmbraKit UmbraKit/Tests

# Fix code style in place
fmt:
    xcrun swift-format format --in-place --recursive App UmbraKit/Sources/UmbraKit UmbraKit/Tests
