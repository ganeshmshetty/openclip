#!/bin/bash
# verify_signing.sh
#
# Fails if a packaged artifact is not signed the way OpenClip is supposed to ship.
#
# Inspecting build settings is not enough here. project.yml has asked for ENABLE_HARDENED_RUNTIME
# since long before any release actually carried it: the old `codesign --deep --sign -` step in the
# packaging scripts quietly replaced Xcode's hardened signature with a plain ad-hoc one, and
# nothing checked the finished bundle. So this reads the artifact, the way Gatekeeper and
# Apparency do, and it walks the nested code too — Xcode leaves Sparkle's Updater.app, XPC
# services, and Autoupdate helper ad-hoc signed even when the app itself gets a Developer ID,
# which is enough on its own to fail notarization.
#
# Usage:
#   ./scripts/verify_signing.sh <path-to-OpenClip.app|path-to.dmg> [--require <level>]
#
# Levels:
#   any           (default) structural signature, hardened runtime, entitlements match the
#                 checked-in entitlements file. Passes for ad-hoc builds.
#   developer-id  the above, plus a Developer ID Application certificate, a secure timestamp,
#                 and one consistent Team ID across every nested binary.
#   notarized     the above, plus a stapled notarization ticket and a Gatekeeper assessment that
#                 accepts the artifact as "Notarized Developer ID", checked again through a
#                 quarantined copy so the result matches what a downloader gets.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OC_PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/signing_config.sh
. "$SCRIPT_DIR/signing_config.sh"

TARGET=""
REQUIRE="any"
while [ $# -gt 0 ]; do
    case "$1" in
        --require)
            REQUIRE="${2:-}"
            shift 2
            ;;
        -h|--help)
            sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            echo "error: unknown option $1" >&2
            exit 2
            ;;
        *)
            TARGET="$1"
            shift
            ;;
    esac
done

case "$REQUIRE" in
    any|developer-id|notarized) ;;
    *) echo "error: --require must be any, developer-id, or notarized (got \"$REQUIRE\")" >&2; exit 2 ;;
esac

if [ -z "$TARGET" ] || [ ! -e "$TARGET" ]; then
    echo "usage: $0 <path-to-OpenClip.app|path-to.dmg> [--require any|developer-id|notarized]" >&2
    exit 2
fi
TARGET="${TARGET%/}"
LABEL="$(basename "$TARGET")"

FAILURES=0
fail() {
    echo "  ✗ $1" >&2
    FAILURES=$((FAILURES + 1))
}
pass() {
    echo "  ✓ $1"
}

# `codesign -dvv` writes its report to stderr; capture it once and query it repeatedly.
signature_report() {
    codesign -dvv "$1" 2>&1 || true
}

echo "==> Verifying $LABEL (--require $REQUIRE)"

REPORT="$(signature_report "$TARGET")"

if ! grep -q "^Signature=" <<<"$REPORT" && ! grep -q "^CodeDirectory" <<<"$REPORT"; then
    fail "$LABEL is not signed at all"
    echo "error: $LABEL failed signing verification ($FAILURES problem(s))." >&2
    exit 1
fi

IS_ADHOC=0
grep -qE "^CodeDirectory .*flags=.*adhoc" <<<"$REPORT" && IS_ADHOC=1
TEAM_ID="$(sed -n 's/^TeamIdentifier=\(.*\)$/\1/p' <<<"$REPORT" | head -1)"
[ "$TEAM_ID" = "not set" ] && TEAM_ID=""

# ---------------------------------------------------------------------------
# 1. Structural integrity. --deep so nested bundles are checked too, --strict so
#    Gatekeeper's own resource rules apply rather than the lenient defaults.
# ---------------------------------------------------------------------------
if codesign --verify --deep --strict --verbose=2 "$TARGET" >/dev/null 2>&1; then
    pass "signature is structurally valid (--deep --strict)"
else
    fail "codesign --verify --deep --strict failed:"
    codesign --verify --deep --strict --verbose=2 "$TARGET" 2>&1 | sed 's/^/      /' >&2 || true
fi

IS_APP=0
[ -d "$TARGET" ] && IS_APP=1

if [ "$IS_APP" -eq 1 ]; then
    # -----------------------------------------------------------------------
    # 2. Hardened runtime on the app itself. This is the "Hardening: Not enabled"
    #    row in Apparency, and the reason notarization used to be impossible.
    # -----------------------------------------------------------------------
    if grep -qE "^CodeDirectory .*flags=.*runtime" <<<"$REPORT"; then
        pass "hardened runtime enabled"
    else
        fail "hardened runtime flag missing — notarization will be refused"
    fi

    # -----------------------------------------------------------------------
    # 3. Entitlements must be exactly what the repo declares. Comparing against the
    #    checked-in file (rather than a list hard-coded here) keeps one source of
    #    truth, and it catches the entitlement Xcode injects on its own:
    #    com.apple.security.get-task-allow, a debugging hole that the notary service
    #    rejects and that a plain `xcodebuild build` adds to every Release build.
    # -----------------------------------------------------------------------
    ENTITLEMENTS_FILE="$(oc_entitlements_path)"
    # The signed entitlements go to a file rather than a pipe: the comparison program arrives on
    # python's stdin via heredoc, so a pipe into it would be swallowed and every artifact would
    # look like it had no entitlements at all.
    SIGNED_ENTITLEMENTS="$(mktemp)"
    codesign -d --entitlements - --xml "$TARGET" >"$SIGNED_ENTITLEMENTS" 2>/dev/null || true
    if ENT_DIFF="$(
        python3 - "$ENTITLEMENTS_FILE" "$SIGNED_ENTITLEMENTS" <<'PY'
import plistlib, sys

expected_path, actual_path = sys.argv[1], sys.argv[2]
with open(expected_path, "rb") as fh:
    expected = plistlib.load(fh)

with open(actual_path, "rb") as fh:
    raw = fh.read()
start = raw.find(b"<?xml")
actual = plistlib.loads(raw[start:]) if start >= 0 else {}

missing = sorted(k for k in expected if k not in actual)
extra = sorted(k for k in actual if k not in expected)
changed = sorted(k for k in expected if k in actual and expected[k] != actual[k])

problems = []
if missing:
    problems.append("missing: " + ", ".join(missing))
if extra:
    problems.append("not declared in OpenClip.entitlements: " + ", ".join(extra))
if changed:
    problems.append("value differs from OpenClip.entitlements: " + ", ".join(changed))

if problems:
    print("; ".join(problems))
    sys.exit(1)
sys.exit(0)
PY
    )"; then
        pass "entitlements match Sources/OpenClip/OpenClip.entitlements"
    else
        fail "entitlements do not match Sources/OpenClip/OpenClip.entitlements — $ENT_DIFF"
    fi
    rm -f "$SIGNED_ENTITLEMENTS"

    # -----------------------------------------------------------------------
    # 4. Every nested binary, not just the app. One ad-hoc helper is enough for the
    #    notary service to reject the submission, and mixed teams break Sparkle's
    #    check that its updater belongs to the app that launched it.
    # -----------------------------------------------------------------------
    NESTED_TOTAL=0
    NESTED_BAD=0
    while IFS= read -r item; do
        NESTED_TOTAL=$((NESTED_TOTAL + 1))
        NESTED_REPORT="$(signature_report "$item")"
        REL="${item#"$TARGET"/}"

        if oc_item_has_code "$item" && ! grep -qE "^CodeDirectory .*flags=.*runtime" <<<"$NESTED_REPORT"; then
            fail "$REL is not signed with the hardened runtime"
            NESTED_BAD=$((NESTED_BAD + 1))
        fi

        NESTED_ADHOC=0
        grep -qE "^CodeDirectory .*flags=.*adhoc" <<<"$NESTED_REPORT" && NESTED_ADHOC=1

        if [ "$IS_ADHOC" -eq 0 ] && [ "$NESTED_ADHOC" -eq 1 ]; then
            fail "$REL is still ad-hoc signed while the app is not — notarization will reject this"
            NESTED_BAD=$((NESTED_BAD + 1))
        fi

        if [ -n "$TEAM_ID" ]; then
            NESTED_TEAM="$(sed -n 's/^TeamIdentifier=\(.*\)$/\1/p' <<<"$NESTED_REPORT" | head -1)"
            if [ "$NESTED_TEAM" != "$TEAM_ID" ]; then
                fail "$REL is signed by team \"${NESTED_TEAM:-none}\", expected \"$TEAM_ID\""
                NESTED_BAD=$((NESTED_BAD + 1))
            fi
        fi
    done < <(oc_nested_code_items "$TARGET")

    if [ "$NESTED_TOTAL" -eq 0 ]; then
        fail "found no nested code under $LABEL — wrong path?"
    elif [ "$NESTED_BAD" -eq 0 ]; then
        pass "all $NESTED_TOTAL nested binaries hardened and consistently signed"
    fi
fi

# ---------------------------------------------------------------------------
# 5. Distribution requirements.
# ---------------------------------------------------------------------------
if [ "$REQUIRE" = "developer-id" ] || [ "$REQUIRE" = "notarized" ]; then
    if [ "$IS_ADHOC" -eq 1 ]; then
        fail "$LABEL is ad-hoc signed; --require $REQUIRE needs a Developer ID Application certificate"
    else
        if grep -q "^Authority=Developer ID Application:" <<<"$REPORT"; then
            pass "signed by $(sed -n 's/^Authority=\(Developer ID Application:.*\)$/\1/p' <<<"$REPORT" | head -1)"
        else
            fail "not signed by a \"Developer ID Application\" certificate (found: $(sed -n 's/^Authority=\(.*\)$/\1/p' <<<"$REPORT" | head -1 | sed 's/^$/none/'))"
        fi

        # Without a secure timestamp the signature stops verifying the day the certificate
        # expires, and the notary service refuses the submission outright.
        if grep -q "^Timestamp=" <<<"$REPORT"; then
            pass "secure timestamp present"
        else
            fail "no secure timestamp — sign with --timestamp"
        fi

        if [ -n "$TEAM_ID" ]; then
            pass "Team ID $TEAM_ID"
        else
            fail "no Team ID in the signature"
        fi
    fi
fi

if [ "$REQUIRE" = "notarized" ]; then
    if xcrun stapler validate "$TARGET" >/dev/null 2>&1; then
        pass "notarization ticket is stapled (works offline)"
    else
        fail "no stapled notarization ticket:"
        xcrun stapler validate "$TARGET" 2>&1 | sed 's/^/      /' >&2 || true
    fi

    # Gatekeeper's own verdict. A disk image is assessed as something the user opens, and
    # --context context:primary-signature makes spctl judge the image's signature instead of
    # looking for a document handler for it.
    if [ "$IS_APP" -eq 1 ]; then
        ASSESS="$(spctl -a -vv -t exec "$TARGET" 2>&1 || true)"
    else
        ASSESS="$(spctl -a -vv -t open --context context:primary-signature "$TARGET" 2>&1 || true)"
    fi
    if grep -q "accepted" <<<"$ASSESS" && grep -q "source=Notarized Developer ID" <<<"$ASSESS"; then
        pass "Gatekeeper accepts it as Notarized Developer ID"
    else
        fail "Gatekeeper did not accept it:"
        sed 's/^/      /' <<<"$ASSESS" >&2
    fi

    # The assessment above ran on a file with no quarantine attribute. Repeat it on a
    # quarantined copy, which is the state a .dmg or .zip arrives in from a browser, so the
    # result is the one a person downloading OpenClip actually gets.
    QUARANTINE_DIR="$(mktemp -d)"
    trap 'rm -rf "$QUARANTINE_DIR"' EXIT
    ditto "$TARGET" "$QUARANTINE_DIR/$LABEL"
    xattr -w com.apple.quarantine "0083;$(printf '%x' "$(date +%s)");Safari;$(uuidgen)" "$QUARANTINE_DIR/$LABEL"
    if [ "$IS_APP" -eq 1 ]; then
        QASSESS="$(spctl -a -vv -t exec "$QUARANTINE_DIR/$LABEL" 2>&1 || true)"
    else
        QASSESS="$(spctl -a -vv -t open --context context:primary-signature "$QUARANTINE_DIR/$LABEL" 2>&1 || true)"
    fi
    if grep -q "accepted" <<<"$QASSESS"; then
        pass "still accepted after download quarantine is applied"
    else
        fail "rejected once quarantined — users would see Gatekeeper's warning:"
        sed 's/^/      /' <<<"$QASSESS" >&2
    fi
fi

# The designated requirement is what TCC records when the user grants Accessibility. An ad-hoc
# build's requirement is a bare cdhash, which changes on every build and is why the Accessibility
# grant kept being forgotten across updates; a Developer ID build pins bundle id plus team, so
# the grant survives.
# codesign prefixes the requirement with "# " for an ad-hoc signature but not for a real one,
# so both spellings are stripped here.
echo "  · designated requirement: $(codesign -d -r- "$TARGET" 2>&1 | sed -n 's/^#\{0,1\}[[:space:]]*designated => //p' | head -1)"

if [ "$FAILURES" -ne 0 ]; then
    echo "error: $LABEL failed signing verification ($FAILURES problem(s))." >&2
    exit 1
fi

# The hardened runtime and entitlements are properties of the app; a disk image only carries a
# signature, so its summary must not claim more than was checked.
if [ "$IS_ADHOC" -eq 1 ] && [ "$IS_APP" -eq 1 ]; then
    echo "==> $LABEL is a valid ad-hoc build (hardened, entitlements as declared) — not distributable."
elif [ "$IS_ADHOC" -eq 1 ]; then
    echo "==> $LABEL is ad-hoc signed — not distributable."
else
    echo "==> $LABEL passed all --require $REQUIRE checks."
fi
