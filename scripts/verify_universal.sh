#!/bin/bash
# verify_universal.sh
#
# Fails if any Mach-O binary inside an app bundle is missing the arm64 or x86_64 slice.
#
# Release artifacts are built on an Apple Silicon runner, where an arm64-only build looks
# completely healthy right up until an Intel user tries to launch it and macOS refuses with
# "not supported on this type of Mac". Checking the build settings is not enough to catch
# that: `xcodebuild -showBuildSettings` reports the universal ARCHS even for invocations
# that go on to produce a thin arm64 binary. So this inspects the finished bundle instead,
# and release_update.sh runs it against the .zip and the .dmg separately rather than only
# against the build product they are cut from.
#
# Usage: ./scripts/verify_universal.sh <path-to-OpenClip.app> [label]

set -euo pipefail

APP_PATH="${1:-}"

if [ -z "$APP_PATH" ]; then
    echo "usage: $0 <path-to-OpenClip.app> [label]" >&2
    exit 2
fi

if [ ! -d "$APP_PATH" ]; then
    echo "error: app bundle not found at $APP_PATH" >&2
    exit 1
fi

LABEL="${2:-$(basename "$APP_PATH")}"
REQUIRED_ARCHS="arm64 x86_64"
CHECKED=0
FAILED=0

# Sparkle ships prebuilt and is already universal; the app binary and Core.framework are the
# ones we compile, so they are the ones that go thin. Walk everything anyway — a future
# embedded helper should not be able to slip through unchecked.
while IFS= read -r CANDIDATE; do
    file -b "$CANDIDATE" | grep -q "Mach-O" || continue
    FOUND="$(lipo -archs "$CANDIDATE" 2>/dev/null || true)"
    [ -n "$FOUND" ] || continue
    CHECKED=$((CHECKED + 1))
    for ARCH in $REQUIRED_ARCHS; do
        case " $FOUND " in
            *" $ARCH "*) ;;
            *)
                echo "error: ${CANDIDATE#"$APP_PATH"/} is missing the $ARCH slice (has: $FOUND)" >&2
                FAILED=1
                ;;
        esac
    done
done < <(find "$APP_PATH" -type f)

if [ "$CHECKED" -eq 0 ]; then
    echo "error: no Mach-O binaries found under $APP_PATH — wrong path?" >&2
    exit 1
fi

if [ "$FAILED" -ne 0 ]; then
    echo "error: $LABEL is not a universal build; Intel Macs cannot launch it." >&2
    exit 1
fi

echo "==> Verified $LABEL: $CHECKED Mach-O binaries, all universal ($REQUIRED_ARCHS)."
