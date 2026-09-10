#!/bin/bash
# sign_artifact.sh
#
# Signs a packaged OpenClip artifact — either OpenClip.app or a .dmg — for distribution.
#
# This replaces the `codesign --force --deep --sign -` call the packaging scripts used to make.
# `--deep` is the wrong tool for a shipping bundle twice over: it walks the bundle outside-in, and
# it drops the flags and entitlements of everything it re-signs. That is how release builds ended
# up ad-hoc *and* without the hardened runtime that project.yml asks for. Here every nested piece
# of code is signed individually, deepest first, so a container is only sealed once its contents
# are final.
#
# Usage:
#   ./scripts/sign_artifact.sh <path-to-OpenClip.app|path-to.dmg> [--identity <name>]
#
# With no identity configured the artifact is signed ad-hoc, with the hardened runtime and the
# entitlements still applied, so unsigned local builds match release builds everywhere except the
# certificate. See scripts/signing_config.sh for the configuration precedence.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OC_PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/signing_config.sh
. "$SCRIPT_DIR/signing_config.sh"

TARGET=""
IDENTITY_ARG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --identity)
            IDENTITY_ARG="${2:-}"
            [ -n "$IDENTITY_ARG" ] || { echo "error: --identity needs a value" >&2; exit 2; }
            shift 2
            ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            echo "error: unknown option $1" >&2
            exit 2
            ;;
        *)
            [ -z "$TARGET" ] || { echo "error: unexpected extra argument $1" >&2; exit 2; }
            TARGET="$1"
            shift
            ;;
    esac
done

if [ -z "$TARGET" ]; then
    echo "usage: $0 <path-to-OpenClip.app|path-to.dmg> [--identity <name>]" >&2
    exit 2
fi
if [ ! -e "$TARGET" ]; then
    echo "error: nothing to sign at $TARGET" >&2
    exit 1
fi

oc_load_signing_env
IDENTITY="$(oc_resolve_identity "$IDENTITY_ARG")"
TEAM_ID="$(oc_team_from_identity "$IDENTITY")"

# A secure timestamp is what lets a signature keep verifying after the certificate expires, and
# the notary service rejects submissions without one. The ad-hoc pseudo-identity has no
# certificate to timestamp against, so asking for one there just fails the build.
TIMESTAMP_FLAG="--timestamp"
if oc_is_adhoc "$IDENTITY"; then
    TIMESTAMP_FLAG="--timestamp=none"
    echo "==> Signing ad-hoc (no Developer ID configured; not distributable)"
else
    echo "==> Signing with: $IDENTITY"
fi

sign_one() {
    # $1 = path, remaining args = extra codesign flags
    local path="$1"
    shift
    codesign \
        --force \
        --sign "$IDENTITY" \
        --options runtime \
        "$TIMESTAMP_FLAG" \
        "$@" \
        "$path"
}

if [ -d "$TARGET" ]; then
    APP_PATH="${TARGET%/}"
    ENTITLEMENTS="$(oc_entitlements_path)"
    if [ ! -f "$ENTITLEMENTS" ]; then
        echo "error: entitlements file missing at $ENTITLEMENTS" >&2
        exit 1
    fi

    # Nested code, deepest first (see oc_nested_code_items). Signing the framework does not
    # re-sign the helper binaries inside it, so each one is signed here in its own right;
    # otherwise Sparkle's helpers keep the ad-hoc signature they ship with and the notary
    # service rejects the whole app for containing code that is not Developer ID signed.
    NESTED=()
    while IFS= read -r item; do
        NESTED+=("$item")
    done < <(oc_nested_code_items "$APP_PATH")

    # Guarded because `"${NESTED[@]}"` on an empty array is an unbound-variable error under
    # `set -u` in the bash 3.2 that ships with macOS, and an empty list means the walk found
    # nothing — a wrong path, not a bundle with no nested code.
    if [ "${#NESTED[@]}" -eq 0 ]; then
        echo "error: found no nested code under $APP_PATH — wrong path?" >&2
        exit 1
    fi

    for item in "${NESTED[@]}"; do
        echo "    signing ${item#"$APP_PATH"/}"
        # Nested helpers get the hardened runtime but no entitlements of their own. Sparkle's
        # XPC services and Updater.app ship with an empty entitlement dictionary, and its
        # Autoupdate helper carries only a placeholder application-identifier that belongs to
        # Sparkle's own ad-hoc identity — carrying that into a real Developer ID signature would
        # claim an identifier this team does not own.
        sign_one "$item"
    done

    echo "    signing $(basename "$APP_PATH") (with entitlements)"
    sign_one "$APP_PATH" --entitlements "$ENTITLEMENTS"

elif [ -f "$TARGET" ]; then
    case "$TARGET" in
        *.dmg)
            # The disk image gets its own signature and, later, its own notarization ticket: it is
            # what the website links to, so Gatekeeper assesses the image itself before the user
            # ever reaches the app inside. `--options runtime` is meaningless for a disk image, so
            # this is a plain signature.
            echo "    signing $(basename "$TARGET")"
            codesign --force --sign "$IDENTITY" "$TIMESTAMP_FLAG" "$TARGET"
            ;;
        *)
            echo "error: don't know how to sign $TARGET (expected OpenClip.app or a .dmg)" >&2
            exit 2
            ;;
    esac
fi

echo "==> Signed $(basename "$TARGET")${TEAM_ID:+ (team $TEAM_ID)}"
