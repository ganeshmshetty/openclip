#!/bin/bash
# build_release.sh
#
# Builds OpenClip in Release configuration, signs it with the system default
# code signing identity (or ad-hoc fallback with hardened runtime), verifies
# signature integrity, and optionally installs/updates the app to /Applications/OpenClip.app.
#
# Usage:
#   ./scripts/build_release.sh [OPTIONS]
#
# Options:
#   -i, --install          Install / update to the installation directory (/Applications by default)
#       --no-install       Do not install, only compile and sign
#       --install-dir DIR  Custom installation directory (default: /Applications)
#   -l, --launch           Launch OpenClip after building / installing
#   -u, --universal        Build universal binary (arm64 + x86_64) instead of host architecture
#       --identity NAME    Override code signing identity
#   -g, --generate         Force regenerate Xcode project with xcodegen
#   -v, --verbose          Show full xcodebuild compilation output
#   -h, --help             Show this help message

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

OC_PROJECT_DIR="$PROJECT_DIR"
# shellcheck source=scripts/signing_config.sh
. "$SCRIPT_DIR/signing_config.sh"

INSTALL_ACTION="ask" # "ask", "yes", "no"
INSTALL_DIR="/Applications"
LAUNCH=false
UNIVERSAL=false
FORCE_GENERATE=false
VERBOSE=false
IDENTITY_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    -i|--install)
      INSTALL_ACTION="yes"
      shift
      ;;
    --no-install)
      INSTALL_ACTION="no"
      shift
      ;;
    --install-dir)
      INSTALL_DIR="${2:-}"
      [ -n "$INSTALL_DIR" ] || { echo "error: --install-dir requires a directory path" >&2; exit 2; }
      shift 2
      ;;
    -l|--launch)
      LAUNCH=true
      shift
      ;;
    -u|--universal)
      UNIVERSAL=true
      shift
      ;;
    --identity)
      IDENTITY_OVERRIDE="${2:-}"
      [ -n "$IDENTITY_OVERRIDE" ] || { echo "error: --identity requires an identity name" >&2; exit 2; }
      shift 2
      ;;
    -g|--generate)
      FORCE_GENERATE=true
      shift
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -h|--help)
      sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      echo "Run '$0 --help' for usage." >&2
      exit 2
      ;;
  esac
done

# Color formatting
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
SIGN_RESULT='Pending'
INSTALL_RESULT='Pending'
BUILD_LOG=''

elapsed_time() {
  local seconds=$(( $(date +%s) - START_TIME ))
  printf '%dm %02ds' "$((seconds / 60))" "$((seconds % 60))"
}

status_line() {
  local mark=$1 color=$2 message=$3
  printf '  %s%s%s %s\n' "$color" "$mark" "$C_RESET" "$message"
}

stage_line() {
  local mark=$1 marker_color=$2 stage=$3 detail=$4
  printf '  %s%s%s %s%s%s · %s\n' \
    "$marker_color" "$mark" "$C_RESET" "$C_ACCENT" "$stage" "$C_RESET" "$detail"
}

print_summary() {
  local code=$1
  printf '\n%sRelease Build Summary%s\n' "$C_ACCENT" "$C_RESET"
  printf '%s────────────────────────────────────────────%s\n' "$C_MUTED" "$C_RESET"
  printf '  Build:     %s%s%s\n' "$(result_color "$BUILD_RESULT")" "$BUILD_RESULT" "$C_RESET"
  printf '  Signing:   %s%s%s\n' "$(result_color "$SIGN_RESULT")" "$SIGN_RESULT" "$C_RESET"
  printf '  Install:   %s%s%s\n' "$(result_color "$INSTALL_RESULT")" "$INSTALL_RESULT" "$C_RESET"
  printf '  Time:      %s%s%s\n' "$C_MUTED" "$(elapsed_time)" "$C_RESET"
  if [ -n "${FINAL_APP_PATH:-}" ] && [ -d "$FINAL_APP_PATH" ]; then
    printf '  Location:  %s%s%s\n' "$C_OK" "$FINAL_APP_PATH" "$C_RESET"
  fi
  if [ "$code" -ne 0 ] && [ -n "$BUILD_LOG" ] && [ -f "$BUILD_LOG" ]; then
    printf '  Build Log: %s\n' "$BUILD_LOG"
  fi
}

result_color() {
  case "$1" in
    Succeeded|Signed|Installed|Running) printf '%s' "$C_OK" ;;
    Failed*) printf '%s' "$C_FAIL" ;;
    Skipped*) printf '%s' "$C_WARN" ;;
    *) printf '%s' "$C_MUTED" ;;
  esac
}

on_exit() {
  local code=$?
  trap - EXIT
  print_summary "$code"
}
trap on_exit EXIT

printf '\n%sOpenClip%s %s/%s Release Build%s\n' "$C_ACCENT" "$C_RESET" "$C_MUTED" "$C_RESET" "$C_RESET"
printf '%s────────────────────────────────────────────%s\n' "$C_MUTED" "$C_RESET"

# 1. Resolve signing identity from system default / environment
oc_load_signing_env
IDENTITY=""
if [ -n "$IDENTITY_OVERRIDE" ]; then
  IDENTITY="$(oc_resolve_identity "$IDENTITY_OVERRIDE")"
else
  IDENTITY="$(oc_default_system_identity "")"
fi

if oc_is_adhoc "$IDENTITY"; then
  status_line '·' "$C_WARN" "Signing identity: Ad-hoc (-) with Hardened Runtime"
else
  status_line '✓' "$C_OK" "System signing identity: $IDENTITY"
fi

# 2. Smart xcodegen: only regenerate if project.yml is newer or forced
if [ "$FORCE_GENERATE" = true ] || [ ! -d "OpenClip.xcodeproj" ] || [ "project.yml" -nt "OpenClip.xcodeproj" ]; then
  stage_line '>' "$C_ACCENT" 'Generate' 'Regenerating Xcode project...'
  if xcodegen generate; then
    status_line '✓' "$C_OK" 'Project generated'
  else
    code=$?
    BUILD_RESULT="Failed during project generation (exit $code)"
    exit "$code"
  fi
fi

# 3. Prepare build parameters
DERIVED_DATA="$PROJECT_DIR/build/DerivedData"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/OpenClip.app"

BUILD_CMD=(
  xcodebuild
  -project "$PROJECT_DIR/OpenClip.xcodeproj"
  -scheme OpenClip
  -configuration Release
  -derivedDataPath "$DERIVED_DATA"
  CODE_SIGN_IDENTITY="-"
  CODE_SIGN_STYLE=Manual
  DEVELOPMENT_TEAM=""
)

if [ "$UNIVERSAL" = true ]; then
  stage_line '>' "$C_ACCENT" 'Build' 'Compiling Release (universal: arm64 + x86_64)...'
  BUILD_CMD+=(
    -destination 'generic/platform=macOS'
    ARCHS='arm64 x86_64'
    ONLY_ACTIVE_ARCH=NO
  )
else
  NATIVE_ARCH="$(uname -m)"
  stage_line '>' "$C_ACCENT" 'Build' "Compiling Release ($NATIVE_ARCH)..."
  BUILD_CMD+=(
    -destination "platform=macOS,arch=$NATIVE_ARCH"
    ONLY_ACTIVE_ARCH=YES
  )
fi
BUILD_CMD+=(build)

BUILD_LOG=$(mktemp "${TMPDIR:-/tmp}/openclip-release-build.XXXXXX")
BUILD_RESULT='Running'

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
      status_line '·' "$C_MUTED" 'Build still running...'
    fi
  done
  wait "$BUILD_PID"
  BUILD_STATUS=$?
fi
set -e

if [ "$BUILD_STATUS" -ne 0 ]; then
  BUILD_RESULT="Failed (exit $BUILD_STATUS)"
  status_line '×' "$C_FAIL" "Release build failed (exit $BUILD_STATUS)"
  awk -v root="$PROJECT_DIR/" '
    /error:/ {
      line = $0
      position = index(line, root)
      if (position) line = substr(line, position + length(root))
      if (!seen[line]++) errors[++count] = line
    }
    END {
      if (count == 0) print "  No compiler error lines found; see build log."
      for (i = 1; i <= count; i++) printf "  %s\n", errors[i]
    }
  ' "$BUILD_LOG"
  exit "$BUILD_STATUS"
fi

BUILD_RESULT='Succeeded'
status_line '✓' "$C_OK" 'Release build succeeded'
rm -f "$BUILD_LOG"

if [ ! -d "$BUILT_APP" ]; then
  BUILD_RESULT='Failed (built app missing)'
  echo "error: build output not found at $BUILT_APP" >&2
  exit 1
fi

# 4. Sign artifact using inside-out recursive signing
stage_line '>' "$C_ACCENT" 'Sign' "Signing bundle with $IDENTITY..."
"$SCRIPT_DIR/sign_artifact.sh" "$BUILT_APP" --identity "$IDENTITY"
SIGN_RESULT='Signed'
status_line '✓' "$C_OK" "Signed with $IDENTITY"

# Verify signature
stage_line '>' "$C_ACCENT" 'Verify' 'Verifying signature and entitlements...'
"$SCRIPT_DIR/verify_signing.sh" "$BUILT_APP" --require any
if [ "$UNIVERSAL" = true ]; then
  "$SCRIPT_DIR/verify_universal.sh" "$BUILT_APP" "OpenClip.app"
fi
status_line '✓' "$C_OK" 'Signature and entitlements verified'

FINAL_APP_PATH="$BUILT_APP"
TARGET_APP="$INSTALL_DIR/OpenClip.app"

# 5. Handle installation to target directory
DO_INSTALL=false
if [ "$INSTALL_ACTION" = "yes" ]; then
  DO_INSTALL=true
elif [ "$INSTALL_ACTION" = "no" ]; then
  DO_INSTALL=false
  INSTALL_RESULT='Skipped (--no-install)'
else
  # "ask" mode: prompt if interactive TTY, otherwise skip
  if [ -t 0 ]; then
    printf '\n%sInstall Options:%s\n' "$C_ACCENT" "$C_RESET"
    printf 'Target path: %s%s%s\n' "$C_OK" "$TARGET_APP" "$C_RESET"
    read -r -p "Update/install to $TARGET_APP? [y/N]: " USER_CHOICE
    case "$USER_CHOICE" in
      [yY]|[yY][eE][sS])
        DO_INSTALL=true
        ;;
      *)
        DO_INSTALL=false
        INSTALL_RESULT='Skipped by user'
        ;;
    esac
  else
    DO_INSTALL=false
    INSTALL_RESULT='Skipped (non-interactive mode)'
  fi
fi

if [ "$DO_INSTALL" = true ]; then
  stage_line '>' "$C_ACCENT" 'Install' "Updating to $TARGET_APP..."
  INSTALL_RESULT='Failed'

  # Terminate existing instance before overwriting binary
  if pgrep -x "OpenClip" >/dev/null 2>&1; then
    status_line '·' "$C_WARN" 'Closing running OpenClip instance...'
    pkill -x "OpenClip" 2>/dev/null || true
    sleep 0.5
  fi

  # Check write permissions for target location
  NEED_SUDO=false
  if [ -d "$TARGET_APP" ] && [ ! -w "$TARGET_APP" ]; then
    NEED_SUDO=true
  elif [ ! -d "$TARGET_APP" ] && [ -d "$INSTALL_DIR" ] && [ ! -w "$INSTALL_DIR" ]; then
    NEED_SUDO=true
  elif [ ! -d "$INSTALL_DIR" ] && [ ! -w "$(dirname "$INSTALL_DIR")" ]; then
    NEED_SUDO=true
  fi

  if [ "$NEED_SUDO" = true ]; then
    status_line '·' "$C_WARN" "Administrator permissions required for $INSTALL_DIR:"
    sudo mkdir -p "$INSTALL_DIR"
    sudo rm -rf "$TARGET_APP"
    sudo ditto "$BUILT_APP" "$TARGET_APP"
  else
    mkdir -p "$INSTALL_DIR"
    rm -rf "$TARGET_APP"
    ditto "$BUILT_APP" "$TARGET_APP"
  fi

  FINAL_APP_PATH="$TARGET_APP"
  INSTALL_RESULT='Installed'
  status_line '✓' "$C_OK" "Installed to $TARGET_APP"
fi

# 6. Launch if requested
if [ "$LAUNCH" = true ]; then
  stage_line '>' "$C_ACCENT" 'Launch' "Launching $FINAL_APP_PATH..."
  /usr/bin/open "$FINAL_APP_PATH"
  status_line '✓' "$C_OK" 'Application launched'
fi
