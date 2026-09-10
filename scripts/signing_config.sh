#!/bin/bash
# signing_config.sh
#
# Sourced by sign_artifact.sh, notarize_artifact.sh, and verify_signing.sh. Not executable on
# its own.
#
# Signing is opt-in: with nothing configured every script falls back to an ad-hoc signature, so
# a fresh clone builds and packages with no Apple Developer account, no certificate, and no
# network. Distribution builds turn it on by naming a "Developer ID Application" identity.
#
# Configuration, highest precedence first:
#   1. --identity <name> on the command line (sign_artifact.sh / verify_signing.sh)
#   2. OPENCLIP_SIGN_IDENTITY in the environment
#   3. keys/signing.env, if it exists — a gitignored shell fragment for local release builds:
#        OPENCLIP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#        NOTARY_KEY="$PROJECT_DIR/keys/AuthKey_XXXXXXXXXX.p8"
#        NOTARY_KEY_ID="XXXXXXXXXX"
#        NOTARY_ISSUER="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
#   4. "-" (ad-hoc)
#
# OPENCLIP_SIGN_IDENTITY may also be the literal "auto", which picks the one Developer ID
# Application identity in the keychain and fails if there is none or more than one.

# shellcheck shell=bash

OC_ADHOC_IDENTITY="-"

# Absolute path to the entitlements the app bundle is signed with. Kept here so the signer and
# the verifier can never disagree about which file is authoritative.
oc_entitlements_path() {
    printf '%s\n' "$OC_PROJECT_DIR/Sources/OpenClip/OpenClip.entitlements"
}

# Sources keys/signing.env if present. Called before the identity is resolved.
#
# Anything already set in the environment survives the file, so a one-off override still works on
# a machine that has signing.env configured — e.g. OPENCLIP_SIGN_IDENTITY=- to force an ad-hoc
# build, or a different NOTARY_PROFILE for one run. Without this, plain assignments in the file
# would clobber the caller's intent and the documented precedence would be a lie.
oc_load_signing_env() {
    local env_file="$OC_PROJECT_DIR/keys/signing.env"
    [ -f "$env_file" ] || return 0

    local env_identity="${OPENCLIP_SIGN_IDENTITY:-}"
    local env_profile="${NOTARY_PROFILE:-}"
    local env_key="${NOTARY_KEY:-}"
    local env_key_id="${NOTARY_KEY_ID:-}"
    local env_issuer="${NOTARY_ISSUER:-}"
    local env_apple_id="${NOTARY_APPLE_ID:-}"
    local env_password="${NOTARY_PASSWORD:-}"
    local env_team="${NOTARY_TEAM_ID:-}"

    # PROJECT_DIR is set for the duration of the source so signing.env can reference key files
    # relative to the repo root.
    # shellcheck disable=SC1090
    PROJECT_DIR="$OC_PROJECT_DIR" . "$env_file"

    [ -n "$env_identity" ] && OPENCLIP_SIGN_IDENTITY="$env_identity"
    [ -n "$env_profile" ] && NOTARY_PROFILE="$env_profile"
    [ -n "$env_key" ] && NOTARY_KEY="$env_key"
    [ -n "$env_key_id" ] && NOTARY_KEY_ID="$env_key_id"
    [ -n "$env_issuer" ] && NOTARY_ISSUER="$env_issuer"
    [ -n "$env_apple_id" ] && NOTARY_APPLE_ID="$env_apple_id"
    [ -n "$env_password" ] && NOTARY_PASSWORD="$env_password"
    [ -n "$env_team" ] && NOTARY_TEAM_ID="$env_team"

    echo "==> Loaded signing configuration from keys/signing.env"
    return 0
}

# Echoes the identity to sign with. Resolves "auto" against the keychain.
oc_resolve_identity() {
    local requested="${1:-}"
    [ -n "$requested" ] || requested="${OPENCLIP_SIGN_IDENTITY:-$OC_ADHOC_IDENTITY}"

    if [ "$requested" != "auto" ]; then
        printf '%s\n' "$requested"
        return 0
    fi

    local matches
    matches="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p')"
    local count
    count="$(printf '%s' "$matches" | grep -c . || true)"

    if [ "$count" -eq 0 ]; then
        echo "error: OPENCLIP_SIGN_IDENTITY=auto but no \"Developer ID Application\" identity is in the keychain." >&2
        echo "       Import one, or unset OPENCLIP_SIGN_IDENTITY to build ad-hoc." >&2
        return 1
    fi
    if [ "$count" -gt 1 ]; then
        echo "error: OPENCLIP_SIGN_IDENTITY=auto is ambiguous — $count Developer ID identities found:" >&2
        printf '       %s\n' "$matches" >&2
        echo "       Name the one to use explicitly instead of \"auto\"." >&2
        return 1
    fi
    printf '%s\n' "$matches"
}

# True when the resolved identity is the ad-hoc pseudo-identity.
oc_is_adhoc() {
    [ "${1:-}" = "$OC_ADHOC_IDENTITY" ]
}

# Echoes the Team ID out of a "Developer ID Application: Name (TEAMID)" identity string, or
# nothing when the identity is ad-hoc or carries no parenthesised team.
oc_team_from_identity() {
    printf '%s\n' "${1:-}" | sed -n 's/.*(\([A-Z0-9]\{10\}\))[[:space:]]*$/\1/p'
}

# Echoes every item inside an app bundle that carries a signature of its own, ordered deepest
# first so that a container always follows its own contents. The bundle itself is not included.
#
# Two kinds of item qualify: nested bundles (.framework, .app, .xpc, .bundle) and loose Mach-O
# executables. Sparkle contributes both — an Updater.app, two XPC services, and an `Autoupdate`
# helper binary sitting directly inside the framework. Symlinks are skipped, because
# Sparkle.framework/Updater.app and .../Versions/Current only point at the real items under
# Versions/B and signing through a link corrupts the seal.
oc_nested_code_items() {
    local app="${1%/}"
    {
        find "$app" \
            \( -name "*.framework" -o -name "*.app" -o -name "*.xpc" -o -name "*.bundle" \) \
            -type d -print
        find "$app" -type f -print | while IFS= read -r f; do
            file -b "$f" | grep -q "Mach-O" && printf '%s\n' "$f"
        done
    } | awk -F'/' '{ print NF "\t" $0 }' | sort -k1,1rn -s | cut -f2- | awk -v self="$app" '$0 != self'
}

# True when a path is a Mach-O binary or a bundle containing one. Resource-only bundles (the
# .bundle directories SwiftPM emits for a package's assets) are still signed, but the hardened
# runtime is a property of executable code, so requiring the flag on them would be meaningless.
oc_item_has_code() {
    local path="$1"
    if [ -f "$path" ]; then
        file -b "$path" | grep -q "Mach-O"
        return $?
    fi
    local found
    found="$(
        find "$path" -type f -print | while IFS= read -r f; do
            if file -b "$f" | grep -q "Mach-O"; then
                echo yes
                break
            fi
        done
    )"
    [ "$found" = "yes" ]
}

# Fails when the identity is not usable for distribution. Used by release paths that must never
# ship an ad-hoc build.
oc_require_distribution_identity() {
    local identity="${1:-}"
    if oc_is_adhoc "$identity"; then
        cat >&2 <<'MSG'
error: this is a distribution build, but no Developer ID identity is configured.

  A release must be signed with a "Developer ID Application" certificate and notarized,
  otherwise Gatekeeper refuses to launch it on any machine but the one that built it.

  Configure one of:
    export OPENCLIP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
    export OPENCLIP_SIGN_IDENTITY=auto        # pick the only one in the keychain
    keys/signing.env                          # gitignored, see scripts/signing_config.sh

  To package an unsigned build on purpose (local testing, CI without secrets), use
  scripts/package_app.sh, which is ad-hoc by default.
MSG
        return 1
    fi
    if [ -z "$(oc_team_from_identity "$identity")" ]; then
        echo "error: cannot read a Team ID out of the signing identity \"$identity\"." >&2
        echo "       Expected a name ending in \"(TEAMID)\"; Sparkle and TCC both key on that team." >&2
        return 1
    fi
    return 0
}
