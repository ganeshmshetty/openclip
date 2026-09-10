#!/bin/bash
# release_update.sh
#
# Builds a Release archive, signs it with a Developer ID certificate, notarizes and staples it,
# zips it, generates a Sparkle appcast.xml signed with an Ed25519 private key, and packages a
# .dmg that is signed, notarized, and stapled in its own right. The resulting .zip, .dmg, and
# appcast.xml are ready to upload to a GitHub Release.
#
# A release is required to be signed and notarized. Anything less does not open on a machine
# other than the one that built it, so the script refuses to produce one rather than emitting an
# artifact that looks fine locally and fails for every user.
#
# Prerequisites:
#   1. Generate Ed25519 keys once:
#        ./scripts/bin/generate_keys --account openclip
#      This saves the private key to your macOS Keychain and prints the public
#      key (add to Info.plist SUPublicEDKey).
#
#   2. For CI (GitHub Actions), export the private key as a secret:
#        SPARKLE_ED_PRIVATE_KEY=<base64 private key>
#
#   3. A "Developer ID Application" certificate in the keychain, named by
#        OPENCLIP_SIGN_IDENTITY (or "auto" to pick the only one), and notary credentials in
#        NOTARY_PROFILE or NOTARY_KEY/NOTARY_KEY_ID/NOTARY_ISSUER. Locally these can all live in
#        the gitignored keys/signing.env. See scripts/signing_config.sh.
#
# Usage:
#   ./scripts/release_update.sh [version]
#
# Example:
#   ./scripts/release_update.sh 1.2.0
#   → build/release/OpenClip-v1.2.0.zip   (signed, notarized, stapled)
#   → build/release/OpenClip-v1.2.0.dmg   (signed, notarized, stapled)
#   → build/release/appcast.xml
#
# OPENCLIP_ALLOW_UNSIGNED_RELEASE=1 downgrades the whole run to an ad-hoc build with the
# notarization steps skipped. It exists so the release pipeline can still be exercised end to end
# without certificates; artifacts it produces must not be published.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/release"
DERIVED_DATA="$PROJECT_DIR/build/DerivedData"

OC_PROJECT_DIR="$PROJECT_DIR"
# shellcheck source=scripts/signing_config.sh
. "$SCRIPT_DIR/signing_config.sh"

# Checked before the build rather than after it: a missing certificate is a five-second failure
# here and a five-minute one at the end.
oc_load_signing_env
IDENTITY="$(oc_resolve_identity "")"
ALLOW_UNSIGNED="${OPENCLIP_ALLOW_UNSIGNED_RELEASE:-0}"
if [ "$ALLOW_UNSIGNED" = "1" ]; then
    echo "warning: OPENCLIP_ALLOW_UNSIGNED_RELEASE=1 — building an ad-hoc, un-notarized release." >&2
    echo "warning: these artifacts will not open on other Macs. Do not publish them." >&2
else
    oc_require_distribution_identity "$IDENTITY"
fi

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    # Read from project.yml MARKETING_VERSION
    VERSION=$(grep 'MARKETING_VERSION' "$PROJECT_DIR/project.yml" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
    if [ -z "$VERSION" ]; then
        echo "error: Could not determine version. Pass it as an argument: $0 <version>"
        exit 1
    fi
fi

echo "==> Generating Xcode project..."
xcodegen generate

echo "==> Building OpenClip v$VERSION (Release)..."
mkdir -p "$BUILD_DIR"
rm -rf "${BUILD_DIR:?}"/*

# Without an explicit destination xcodebuild resolves the scheme's default one — "My Mac" —
# and narrows the build to that Mac's architecture, so on an Apple Silicon runner it emits an
# arm64-only app however ARCHS is configured. 'generic/platform=macOS' plus the explicit ARCHS
# is what keeps the release universal; scripts/package_app.sh builds the same way.
xcodebuild \
    -project "$PROJECT_DIR/OpenClip.xcodeproj" \
    -scheme OpenClip \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    -destination 'generic/platform=macOS' \
    ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    build 2>&1 | tail -5

APP_PATH="$DERIVED_DATA/Build/Products/Release/OpenClip.app"
if [ ! -d "$APP_PATH" ]; then
    echo "error: Build did not produce OpenClip.app at $APP_PATH"
    exit 1
fi

# The build above is deliberately left ad-hoc; this is where the real signature goes on. The old
# `codesign --force --deep -s -` that used to live here is what kept every release ad-hoc and
# stripped the hardened runtime that project.yml asks for, because --deep re-signs outside-in and
# discards the flags and entitlements of everything it touches.
"$SCRIPT_DIR/sign_artifact.sh" "$APP_PATH"

"$SCRIPT_DIR/verify_universal.sh" "$APP_PATH" "build product"

REQUIRE="developer-id"
[ "$ALLOW_UNSIGNED" = "1" ] && REQUIRE="any"
"$SCRIPT_DIR/verify_signing.sh" "$APP_PATH" --require "$REQUIRE"

# Notarize and staple before the archive is cut. Stapling writes the ticket into the bundle, so a
# zip made beforehand would carry an unstapled app and Gatekeeper would have to reach Apple at
# first launch — which fails for anyone offline or behind a filtered network. The Sparkle
# signature and the Homebrew sha256 are both taken from the archive produced further down, so
# they have to describe the stapled bundle.
if [ "$ALLOW_UNSIGNED" != "1" ]; then
    "$SCRIPT_DIR/notarize_artifact.sh" "$APP_PATH"
    REQUIRE="notarized"
    "$SCRIPT_DIR/verify_signing.sh" "$APP_PATH" --require "$REQUIRE"
fi

echo "==> Packaging OpenClip-v$VERSION.zip..."
ZIP_NAME="OpenClip-v$VERSION.zip"
cd "$BUILD_DIR"
# Remove stale files if present
rm -f "$ZIP_NAME" "$BUILD_DIR/appcast.xml"
rm -rf ~/Library/Caches/Sparkle_generate_appcast
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_NAME"

# Check the archive itself, not just the bundle it was cut from, and do it before the appcast
# is signed so a bad build can never be handed to Sparkle. The scratch directory lives outside
# BUILD_DIR because generate_appcast scans BUILD_DIR for release archives.
VERIFY_DIR="$PROJECT_DIR/build/.verify"
rm -rf "$VERIFY_DIR"
mkdir -p "$VERIFY_DIR"
ditto -x -k "$BUILD_DIR/$ZIP_NAME" "$VERIFY_DIR"
"$SCRIPT_DIR/verify_universal.sh" "$VERIFY_DIR/OpenClip.app" "$ZIP_NAME"
# The strongest check available: the app as it comes out of the archive people download, rather
# than the bundle the archive was cut from. It proves the notarization ticket survived the
# round trip through ditto, so Gatekeeper accepts the unpacked app with no network access.
"$SCRIPT_DIR/verify_signing.sh" "$VERIFY_DIR/OpenClip.app" --require "$REQUIRE"
rm -rf "$VERIFY_DIR"

echo "==> Generating appcast.xml with Ed25519 signature..."

# Locate generate_appcast — first check scripts/bin, then SPM checkout, then /tmp/sparkle.
GENERATE_APPCAST=""
if [ -x "$SCRIPT_DIR/bin/generate_appcast" ]; then
    GENERATE_APPCAST="$SCRIPT_DIR/bin/generate_appcast"
elif [ -x "/tmp/sparkle/bin/generate_appcast" ]; then
    GENERATE_APPCAST="/tmp/sparkle/bin/generate_appcast"
else
    SPM_SPARKLE=$(find "$DERIVED_DATA/SourcePackages/artifacts" -name "generate_appcast" -type f 2>/dev/null | head -1)
    if [ -n "$SPM_SPARKLE" ]; then
        GENERATE_APPCAST="$SPM_SPARKLE"
    fi
fi

if [ -z "$GENERATE_APPCAST" ]; then
    echo "warning: generate_appcast not found. Download the Sparkle release archive:"
    echo "  curl -sL 'https://github.com/sparkle-project/Sparkle/releases/latest' | tar xJ -C /tmp/sparkle"
    echo ""
    echo "Zip created at: $BUILD_DIR/$ZIP_NAME"
    exit 1
fi

DOWNLOAD_PREFIX="https://github.com/ganeshmshetty/openclip/releases/download/v$VERSION/"

echo "==> Extracting release notes for v$VERSION from CHANGELOG.md..."
NOTES_FILE="$BUILD_DIR/OpenClip-v$VERSION.md"
awk -v ver="## v$VERSION" '
    $0 ~ ver { flag=1; next }
    flag && /^## v/ { flag=0 }
    flag && !/^---$/ { print }
' "$PROJECT_DIR/CHANGELOG.md" > "$NOTES_FILE"

if [ ! -s "$NOTES_FILE" ]; then
    echo "warning: No entry found for v$VERSION in CHANGELOG.md; generating default note."
    echo "OpenClip version $VERSION release." > "$NOTES_FILE"
fi

if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
    printf '%s\n' "$SPARKLE_ED_PRIVATE_KEY" | "$GENERATE_APPCAST" \
        --ed-key-file - \
        --download-url-prefix "$DOWNLOAD_PREFIX" \
        --embed-release-notes \
        --full-release-notes-url "https://github.com/ganeshmshetty/openclip/releases/tag/v$VERSION" \
        -o appcast.xml \
        "$BUILD_DIR"
else
    "$GENERATE_APPCAST" \
        --account openclip \
        --download-url-prefix "$DOWNLOAD_PREFIX" \
        --embed-release-notes \
        --full-release-notes-url "https://github.com/ganeshmshetty/openclip/releases/tag/v$VERSION" \
        -o appcast.xml \
        "$BUILD_DIR"
fi

# Ensure sparkle:edSignature is present in the enclosure tag
if ! grep -q 'sparkle:edSignature=' "$BUILD_DIR/appcast.xml"; then
    SIGN_UPDATE=""
    if [ -x "$SCRIPT_DIR/bin/sign_update" ]; then
        SIGN_UPDATE="$SCRIPT_DIR/bin/sign_update"
    elif [ -x "/tmp/sparkle/bin/sign_update" ]; then
        SIGN_UPDATE="/tmp/sparkle/bin/sign_update"
    else
        SPM_SIGN_UPDATE=$(find "$DERIVED_DATA/SourcePackages/artifacts" -name "sign_update" -type f 2>/dev/null | head -1)
        if [ -n "$SPM_SIGN_UPDATE" ]; then
            SIGN_UPDATE="$SPM_SIGN_UPDATE"
        fi
    fi

    if [ -n "$SIGN_UPDATE" ] && [ -x "$SIGN_UPDATE" ]; then
        if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
            SIG=$(printf '%s\n' "$SPARKLE_ED_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - -p "$BUILD_DIR/$ZIP_NAME" 2>/dev/null || true)
        else
            SIG=$("$SIGN_UPDATE" --account openclip -p "$BUILD_DIR/$ZIP_NAME" 2>/dev/null || true)
        fi
        if [ -n "$SIG" ]; then
            sed -i '' "s|type=\"application/octet-stream\"|type=\"application/octet-stream\" sparkle:edSignature=\"$SIG\"|g" "$BUILD_DIR/appcast.xml"
        fi
    fi
fi

if ! grep -q 'sparkle:edSignature=' "$BUILD_DIR/appcast.xml"; then
    echo "error: appcast.xml does not contain a valid sparkle:edSignature." >&2
    exit 1
fi

echo "==> Packaging OpenClip-v$VERSION.dmg..."
DMG_NAME="OpenClip-v$VERSION.dmg"
"$SCRIPT_DIR/make_dmg.sh" "$APP_PATH" "$BUILD_DIR/$DMG_NAME"

# Gatekeeper assesses the disk image itself before the user ever reaches the app inside it, and
# the image is what the website links to, so it needs its own signature and its own ticket. The
# app within is already stapled; this covers the container.
"$SCRIPT_DIR/sign_artifact.sh" "$BUILD_DIR/$DMG_NAME"
if [ "$ALLOW_UNSIGNED" != "1" ]; then
    "$SCRIPT_DIR/notarize_artifact.sh" "$BUILD_DIR/$DMG_NAME"
fi
"$SCRIPT_DIR/verify_signing.sh" "$BUILD_DIR/$DMG_NAME" --require "$REQUIRE"

# The .dmg is the download the website points at, so it gets the same check as the .zip.
MOUNT_POINT="$(mktemp -d)"
hdiutil attach "$BUILD_DIR/$DMG_NAME" -mountpoint "$MOUNT_POINT" -nobrowse -readonly -quiet
DMG_CHECKS_OK=1
# Both checks run against the app as it sits inside the image, because that is what someone who
# downloads from the website drags to /Applications. dmgbuild copies the bundle rather than
# ditto'ing it, so this is where a lost symlink or a dropped notarization ticket would surface.
"$SCRIPT_DIR/verify_universal.sh" "$MOUNT_POINT/OpenClip.app" "$DMG_NAME" || DMG_CHECKS_OK=0
"$SCRIPT_DIR/verify_signing.sh" "$MOUNT_POINT/OpenClip.app" --require "$REQUIRE" || DMG_CHECKS_OK=0
hdiutil detach "$MOUNT_POINT" -quiet || true
rmdir "$MOUNT_POINT" 2>/dev/null || true
if [ "$DMG_CHECKS_OK" -ne 1 ]; then
    exit 1
fi

echo ""
echo "==> Done! Release artifacts created:"
echo "    $BUILD_DIR/$ZIP_NAME"
echo "    $BUILD_DIR/$DMG_NAME"
echo "    $BUILD_DIR/appcast.xml"
if [ "$ALLOW_UNSIGNED" = "1" ]; then
    echo ""
    echo "warning: ad-hoc, un-notarized artifacts — for pipeline testing only, do not publish." >&2
else
    echo "    signed by: $IDENTITY"
    echo "    notarized and stapled: OpenClip.app and $DMG_NAME"
fi
