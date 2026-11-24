#!/bin/bash
# Fast local development build, install to ~/Applications, and run.
#
# Builds OpenClip in Debug mode with bundle ID com.openclip.OpenClip.dev
# and installs to ~/Applications/OpenClip Dev.app so macOS TCC Accessibility
# permissions stay permanently granted and never collide with /Applications/OpenClip.app.
# Use --verbose to show the full xcodebuild output.

set -eo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

NO_INSTALL=false
FORCE_GENERATE=false
VERBOSE=false

for arg in "$@"; do
  case "$arg" in
    --no-install)
      NO_INSTALL=true
      ;;
    --generate|-g)
      FORCE_GENERATE=true
      ;;
    --verbose)
      VERBOSE=true
      ;;
    --help|-h)
      printf 'Usage: ./scripts/dev_run.sh [--no-install] [--generate] [--verbose]\n'
      printf '  --no-install  Launch from DerivedData without copying the app\n'
      printf '  --generate    Regenerate the Xcode project before building\n'
      printf '  --verbose     Show the full xcodebuild output\n'
      exit 0
      ;;
    *)
      ;;
  esac
done

# Keep output plain when piped, in CI, or when the caller disables color.
COLOR=false
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ -z "${CI:-}" ] && [ "${TERM:-}" != dumb ]; then
  COLOR=true
fi

if [ "$COLOR" = true ]; then
  C_RESET=$'\033[0m'
  C_MUTED=$'\033[2m'
  C_ACCENT=$'\033[36m'
  C_OK=$'\033[32m'
  C_WARN=$'\033[33m'
  C_FAIL=$'\033[31m'
else
  C_RESET=''
  C_MUTED=''
  C_ACCENT=''
  C_OK=''
  C_WARN=''
  C_FAIL=''
fi

START_TIME=$(date +%s)
BUILD_RESULT='Pending'
INSTALL_RESULT='Pending'
LAUNCH_RESULT='Pending'
BUILD_LOG=''

elapsed_time() {
  local seconds=$(( $(date +%s) - START_TIME ))
  printf '%dm %02ds' "$((seconds / 60))" "$((seconds % 60))"
}

print_summary() {
  local code=$1
  local build_color install_color launch_color
  build_color=$(result_color "$BUILD_RESULT")
  install_color=$(result_color "$INSTALL_RESULT")
  launch_color=$(result_color "$LAUNCH_RESULT")
  printf '\n%sRun%s  ' "$C_ACCENT" "$C_RESET"
  printf '%sBuild%s %s%s%s · ' "$C_ACCENT" "$C_RESET" "$build_color" "$BUILD_RESULT" "$C_RESET"
  printf '%sInstall%s %s%s%s · ' "$C_ACCENT" "$C_RESET" "$install_color" "$INSTALL_RESULT" "$C_RESET"
  printf '%sLaunch%s %s%s%s · %s%s%s\n' \
    "$C_ACCENT" "$C_RESET" "$launch_color" "$LAUNCH_RESULT" "$C_RESET" \
    "$C_MUTED" "$(elapsed_time)" "$C_RESET"
  if [ "$code" -ne 0 ] && [ -n "$BUILD_LOG" ] && [ -f "$BUILD_LOG" ]; then
    printf 'Output: %s\n' "$BUILD_LOG"
  fi
}

result_color() {
  case "$1" in
    Succeeded|Installed|Running) printf '%s' "$C_OK" ;;
    Failed*) printf '%s' "$C_FAIL" ;;
    *) printf '%s' "$C_MUTED" ;;
  esac
}

on_exit() {
  local code=$?
  trap - EXIT
  print_summary "$code"
}
trap on_exit EXIT

status_line() {
  local mark=$1 color=$2 message=$3
  printf '  %s%s%s %s\n' "$color" "$mark" "$C_RESET" "$message"
}

stage_line() {
  local mark=$1 marker_color=$2 stage=$3 detail=$4
  printf '  %s%s%s %s%s%s · %s\n' \
    "$marker_color" "$mark" "$C_RESET" "$C_ACCENT" "$stage" "$C_RESET" "$detail"
}

printf '\n%sOpenClip%s %s/%s Dev%s\n' "$C_ACCENT" "$C_RESET" "$C_MUTED" "$C_RESET" "$C_RESET"
printf '%s────────────────────────────────────────────%s\n' "$C_MUTED" "$C_RESET"

# Smart xcodegen: only regenerate if project.yml is newer or forced.
if [ "$FORCE_GENERATE" = true ] || [ ! -d "OpenClip.xcodeproj" ] || [ "project.yml" -nt "OpenClip.xcodeproj" ]; then
  status_line '>' "$C_ACCENT" 'Generating Xcode project'
  if xcodegen generate; then
    status_line '✓' "$C_OK" 'Project generated'
  else
    code=$?
    BUILD_RESULT="Failed during project generation (exit $code)"
    exit "$code"
  fi
fi

# Prefer Xcode-managed Apple Development signing when a local team or identity is supplied.
# keys/ is gitignored, so a linked worktree has none; look in the main checkout too, otherwise the worktree
# build is ad-hoc and replaces the installed Dev app with a different signature, which resets its permissions.
if [ -z "${OPENCLIP_DEV_TEAM:-}" ] && [ -z "${OPENCLIP_DEV_SIGN_IDENTITY:-}" ]; then
  MAIN_CHECKOUT=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)/.." 2>/dev/null && pwd || true)
  for identity_file in "$PROJECT_DIR/keys/dev-signing-identity" "${MAIN_CHECKOUT:+$MAIN_CHECKOUT/keys/dev-signing-identity}"; do
    if [ -n "$identity_file" ] && [ -f "$identity_file" ]; then
      IFS= read -r OPENCLIP_DEV_SIGN_IDENTITY < "$identity_file" || true
      break
    fi
  done
fi

SIGNING_ARGS=()
if [ -n "${OPENCLIP_DEV_TEAM:-}" ]; then
  SIGNING_ARGS+=("DEVELOPMENT_TEAM=$OPENCLIP_DEV_TEAM" "CODE_SIGN_IDENTITY=Apple Development" "CODE_SIGN_STYLE=Automatic" "-allowProvisioningUpdates")
elif [ -n "${OPENCLIP_DEV_SIGN_IDENTITY:-}" ]; then
  SIGNING_ARGS+=("CODE_SIGN_IDENTITY=$OPENCLIP_DEV_SIGN_IDENTITY" "CODE_SIGN_STYLE=Manual")
fi

DERIVED_DATA="$PROJECT_DIR/build/DerivedData"
BUILT_APP="$DERIVED_DATA/Build/Products/Debug/OpenClip.app"

BUILD_CMD=(
  xcodebuild
  -scheme OpenClip
  -configuration Debug
  -destination 'platform=macOS,arch=arm64'
  -derivedDataPath "$DERIVED_DATA"
  "${SIGNING_ARGS[@]}"
  build
)

BUILD_LOG=$(mktemp "${TMPDIR:-/tmp}/openclip-build.XXXXXX")
BUILD_RESULT='Running'
stage_line '>' "$C_ACCENT" 'Build · Debug' 'Building'

# Save all Xcode output for warning summaries and failure diagnostics. In normal
# mode, use xcbeautify if installed; otherwise print a compact progress heartbeat.
set +e
if [ "$VERBOSE" = true ]; then
  "${BUILD_CMD[@]}" 2>&1 | tee "$BUILD_LOG"
  PIPE_STATUS=("${PIPESTATUS[@]}")
  BUILD_STATUS=${PIPE_STATUS[0]}
elif command -v xcbeautify >/dev/null 2>&1; then
  "${BUILD_CMD[@]}" 2>&1 | tee "$BUILD_LOG" | xcbeautify
  PIPE_STATUS=("${PIPESTATUS[@]}")
  BUILD_STATUS=${PIPE_STATUS[0]}
else
  "${BUILD_CMD[@]}" >"$BUILD_LOG" 2>&1 &
  BUILD_PID=$!
  while kill -0 "$BUILD_PID" 2>/dev/null; do
    sleep 5
    if kill -0 "$BUILD_PID" 2>/dev/null; then
      status_line '·' "$C_MUTED" 'Build still running'
    fi
  done
  wait "$BUILD_PID"
  BUILD_STATUS=$?
fi
set -e

if [ "$BUILD_STATUS" -eq 0 ]; then
  BUILD_RESULT='Succeeded'
  awk -v root="$PROJECT_DIR/" '
    /warning:/ {
      warningAt = index($0, "warning:")
      message = substr($0, warningAt + 9)
      sub(/^[[:space:]]*/, "", message)
      if (!(message in warningIndex)) {
        warningIndex[message] = ++warningCount
        warningMessages[warningCount] = message
      }
      indexForMessage = warningIndex[message]
      occurrences[indexForMessage]++
      location = substr($0, 1, warningAt - 1)
      sub(/[[:space:]]*$/, "", location)
      if (location !~ /:[0-9]+(:[0-9]+)?:[[:space:]]*$/) next
      sub(/:[[:space:]]*$/, "", location)
      if (index(location, root) == 1) location = substr(location, length(root) + 1)
      if (location != "" && location != $0 && shownLocations[indexForMessage] < 3) {
        locationKey = indexForMessage SUBSEP location
        if (!(locationKey in locationSeen)) {
          locationSeen[locationKey] = 1
          locations[indexForMessage, ++shownLocations[indexForMessage]] = location
        }
      }
    }
    END {
      if (warningCount == 0) {
        exit
      }
      shown = warningCount < 5 ? warningCount : 5
      printf "  %s!%s Warnings · %d distinct\n", warn, reset, warningCount
      for (i = 1; i <= shown; i++) {
        printf "    %s", warningMessages[i]
        if (occurrences[i] > 1) printf " ×%d", occurrences[i]
        printf "\n"
        for (j = 1; j <= shownLocations[i]; j++) printf "      %s\n", locations[i, j]
      }
      if (warningCount > shown) printf "    + %d additional warning messages\n", warningCount - shown
      printf "  Full output: %s\n", buildLog
    }
  ' warn="$C_WARN" buildLog="$BUILD_LOG" "$BUILD_LOG"
  # Keep the complete build log accessible whenever it contains warnings.
  if ! grep -q 'warning:' "$BUILD_LOG"; then rm -f "$BUILD_LOG"; BUILD_LOG=''; fi
else
  BUILD_RESULT="Failed (exit $BUILD_STATUS)"
  status_line '×' "$C_FAIL" "Build failed (exit $BUILD_STATUS)"
  awk -v root="$PROJECT_DIR/" '
    /error:/ {
      line = $0
      position = index(line, root)
      if (position) line = substr(line, position + length(root))
      if (!seen[line]++) errors[++count] = line
    }
    END {
      if (count == 0) print "  No compiler error lines found; see the full output below."
      for (i = 1; i <= count; i++) printf "  %s\n", errors[i]
    }
  ' "$BUILD_LOG"
  printf '  Full Xcode output: %s\n' "$BUILD_LOG"
  exit "$BUILD_STATUS"
fi

if [ ! -d "$BUILT_APP" ]; then
  printf 'Error: Could not find the built application at:\n  %s\n' "$BUILT_APP" >&2
  BUILD_RESULT='Failed (built app missing)'
  exit 1
fi

APP_TO_RUN="$BUILT_APP"

if [ "$NO_INSTALL" = false ]; then
  INSTALL_DIR="$HOME/Applications"
  TARGET_APP="$INSTALL_DIR/OpenClip Dev.app"
  INSTALL_RESULT='Failed'
  mkdir -p "$INSTALL_DIR"
  stage_line '>' "$C_ACCENT" 'Install' 'Installing app'
  # Capture first: `codesign | grep -q` under pipefail fails at random when grep's early exit SIGPIPEs codesign.
  built_sig=$(codesign -dvvv "$BUILT_APP" 2>&1 || true)
  installed_sig=$(codesign -dvvv "$TARGET_APP" 2>&1 || true)
  if [[ $built_sig == *Signature=adhoc* ]] && [ -d "$TARGET_APP" ] && [[ $installed_sig != *Signature=adhoc* ]]; then
    status_line '!' "$C_WARN" 'Ad-hoc build replacing a signed Dev app: macOS will ask for permissions again (see docs/developer-guide/signing-and-notarization.md)'
  fi
  # An ad-hoc grant is pinned to the build's cdhash, and re-enabling an existing Accessibility row keeps the old
  # hash, so a changed ad-hoc build stays untrusted. Drop the row so this build registers a fresh one.
  if [[ $built_sig == *Signature=adhoc* ]] \
     && [ "$(awk -F= '/^CDHash=/{print $2}' <<<"$built_sig")" != "$(awk -F= '/^CDHash=/{print $2}' <<<"$installed_sig")" ]; then
    bundle_id=$(defaults read "$BUILT_APP/Contents/Info" CFBundleIdentifier)
    if tccutil reset Accessibility "$bundle_id" >/dev/null 2>&1; then
      status_line '!' "$C_WARN" 'New ad-hoc build: Accessibility reset, grant it again when prompted'
    fi
  fi
  # Terminate old dev instance before updating the binary.
  pkill -f "OpenClip Dev" 2>/dev/null || true
  sleep 0.2
  rm -rf "$TARGET_APP"
  ditto "$BUILT_APP" "$TARGET_APP"
  APP_TO_RUN="$TARGET_APP"
  INSTALL_RESULT='Installed'
else
  INSTALL_RESULT='Skipped (--no-install)'
  status_line '–' "$C_MUTED" "Install · $INSTALL_RESULT"
  pkill -f "$BUILT_APP" 2>/dev/null || true
  sleep 0.2
fi

stage_line '>' "$C_ACCENT" 'Launch' 'Launching'
LAUNCH_RESULT='Failed'
/usr/bin/open -n --stdout /tmp/openclip.log --stderr /tmp/openclip.log "$APP_TO_RUN"
LAUNCH_RESULT='Running'

printf '\n%sLog%s  /tmp/openclip.log\n' "$C_ACCENT" "$C_RESET"
printf 'Accessibility: System Settings > Privacy & Security > Accessibility (if prompted).\n'
