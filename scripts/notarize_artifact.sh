#!/bin/bash
# notarize_artifact.sh
#
# Submits an artifact to Apple's notary service, waits for the verdict, and staples the resulting
# ticket to it.
#
# Stapling is the part that matters for a download: it writes the ticket into the artifact so
# Gatekeeper can accept it without asking Apple at launch time, which is what makes the app open
# on a machine that is offline or behind a filtered network.
#
# Usage:
#   ./scripts/notarize_artifact.sh <path-to-OpenClip.app|path-to.dmg>
#
# An .app cannot be submitted as-is — the notary service takes an archive — so the bundle is
# zipped to a scratch directory for the submission and the ticket is stapled back onto the
# original bundle. A .dmg is submitted and stapled directly.
#
# Credentials, highest precedence first (see also keys/signing.env in scripts/signing_config.sh):
#   NOTARY_PROFILE                                  a profile stored by
#                                                   `xcrun notarytool store-credentials`
#   NOTARY_KEY + NOTARY_KEY_ID + NOTARY_ISSUER      App Store Connect API key. NOTARY_KEY is
#                                                   either a path to the .p8 or the key text
#                                                   itself, so a CI secret can be passed inline.
#   NOTARY_APPLE_ID + NOTARY_PASSWORD + NOTARY_TEAM_ID
#                                                   Apple ID with an app-specific password.
#
# Set NOTARY_TIMEOUT to override the 30m ceiling on how long to wait for a verdict.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OC_PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/signing_config.sh
. "$SCRIPT_DIR/signing_config.sh"

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
    echo "usage: $0 <path-to-OpenClip.app|path-to.dmg>" >&2
    exit 2
fi
if [ ! -e "$TARGET" ]; then
    echo "error: nothing to notarize at $TARGET" >&2
    exit 1
fi
TARGET="${TARGET%/}"
LABEL="$(basename "$TARGET")"

oc_load_signing_env

WORK_DIR="$(mktemp -d)"
# The scratch directory can hold a private key written out of an environment variable, so it is
# removed on every exit path, not just the happy one.
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

CREDENTIALS=()
if [ -n "${NOTARY_PROFILE:-}" ]; then
    CREDENTIALS=(--keychain-profile "$NOTARY_PROFILE")
    echo "==> Notarizing with keychain profile \"$NOTARY_PROFILE\""
elif [ -n "${NOTARY_KEY:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER:-}" ]; then
    KEY_PATH="$NOTARY_KEY"
    if [ ! -f "$KEY_PATH" ]; then
        # Treat the value as the key material itself. Written with a private mode before the
        # content lands in it, so it is never briefly world-readable.
        KEY_PATH="$WORK_DIR/AuthKey.p8"
        (umask 077; printf '%s\n' "$NOTARY_KEY" > "$KEY_PATH")
        if ! grep -q "BEGIN PRIVATE KEY" "$KEY_PATH"; then
            echo "error: NOTARY_KEY is neither a readable file path nor a PEM private key." >&2
            exit 1
        fi
    fi
    CREDENTIALS=(--key "$KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
    echo "==> Notarizing with App Store Connect API key $NOTARY_KEY_ID"
elif [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ]; then
    CREDENTIALS=(--apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" --team-id "$NOTARY_TEAM_ID")
    echo "==> Notarizing with Apple ID $NOTARY_APPLE_ID"
else
    cat >&2 <<'MSG'
error: no notarization credentials configured.

  Set one of these groups in the environment, or in the gitignored keys/signing.env:

    NOTARY_PROFILE                                   (from `xcrun notarytool store-credentials`)
    NOTARY_KEY, NOTARY_KEY_ID, NOTARY_ISSUER         (App Store Connect API key)
    NOTARY_APPLE_ID, NOTARY_PASSWORD, NOTARY_TEAM_ID (app-specific password)

  The Key ID is the XXXXXXXXXX in the AuthKey_XXXXXXXXXX.p8 filename. The Issuer ID is the UUID
  shown above the key list in App Store Connect under Users and Access > Integrations.
MSG
    exit 1
fi

# What actually gets uploaded: the disk image itself, or a zip of the bundle.
if [ -d "$TARGET" ]; then
    SUBMISSION="$WORK_DIR/${LABEL%.app}-notarize.zip"
    echo "==> Archiving $LABEL for submission..."
    # --sequesterRsrc --keepParent matches how the release zip is built, so the notary service
    # sees the same bundle layout that users will unpack.
    ditto -c -k --sequesterRsrc --keepParent "$TARGET" "$SUBMISSION"
else
    SUBMISSION="$TARGET"
fi

echo "==> Submitting $(basename "$SUBMISSION") to the notary service (this usually takes a few minutes)..."
SUBMIT_JSON="$WORK_DIR/submit.json"
SUBMIT_STATUS=0
xcrun notarytool submit "$SUBMISSION" \
    "${CREDENTIALS[@]}" \
    --wait \
    --timeout "${NOTARY_TIMEOUT:-30m}" \
    --output-format json \
    > "$SUBMIT_JSON" 2>"$WORK_DIR/submit.err" || SUBMIT_STATUS=$?

# notarytool writes progress to stderr; surface it only when something went wrong, so a normal
# run stays readable.
read_json() {
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as fh:
        print(json.load(fh).get(sys.argv[2], '') or '')
except Exception:
    print('')
" "$SUBMIT_JSON" "$1"
}

SUBMISSION_ID="$(read_json id)"
VERDICT="$(read_json status)"

if [ "$VERDICT" != "Accepted" ]; then
    echo "error: notarization did not succeed for $LABEL (status: ${VERDICT:-unknown})." >&2
    [ -s "$WORK_DIR/submit.err" ] && sed 's/^/      /' "$WORK_DIR/submit.err" >&2
    [ -s "$SUBMIT_JSON" ] && sed 's/^/      /' "$SUBMIT_JSON" >&2
    if [ -n "$SUBMISSION_ID" ]; then
        # The log is the only place Apple explains *why*; without it the failure is unactionable.
        echo "--- notarytool log for $SUBMISSION_ID ---" >&2
        xcrun notarytool log "$SUBMISSION_ID" "${CREDENTIALS[@]}" 2>&1 | sed 's/^/      /' >&2 || true
    fi
    exit 1
fi

echo "==> Accepted (submission $SUBMISSION_ID)"

echo "==> Stapling the ticket to $LABEL..."
if ! xcrun stapler staple "$TARGET"; then
    echo "error: notarization succeeded but stapling $LABEL failed." >&2
    exit 1
fi

xcrun stapler validate "$TARGET" >/dev/null
echo "==> $LABEL is notarized and stapled."
