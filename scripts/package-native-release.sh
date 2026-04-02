#!/bin/zsh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_APP_BUNDLE="${REPO_ROOT}/build/RightClickApp.app"
BUILD_SCRIPT="${REPO_ROOT}/scripts/build-native-app.sh"
PREFLIGHT_SCRIPT="${REPO_ROOT}/scripts/release-preflight.sh"
APP_BUNDLE="${RCA_APP_BUNDLE:-${DEFAULT_APP_BUNDLE}}"
BUILD_IF_MISSING="${RCA_BUILD_IF_MISSING:-1}"
RUN_PREFLIGHT="${RCA_RUN_PREFLIGHT:-1}"
RELEASE_DIR="${RCA_RELEASE_DIR:-${REPO_ROOT}/dist}"
PLIST_BUDDY_BIN="${RCA_PLIST_BUDDY_BIN:-/usr/libexec/PlistBuddy}"
DITTO_BIN="${RCA_DITTO_BIN:-/usr/bin/ditto}"

fail() {
  print -r -- "$*" >&2
  exit 1
}

is_true() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

plist_value() {
  local plist_path="$1"
  local key_path="$2"
  [[ -x "${PLIST_BUDDY_BIN}" ]] || fail "PlistBuddy not found at ${PLIST_BUDDY_BIN}"
  "${PLIST_BUDDY_BIN}" -c "Print ${key_path}" "${plist_path}" 2>/dev/null
}

if [[ ! -d "${APP_BUNDLE}" ]]; then
  if is_true "${BUILD_IF_MISSING}"; then
    [[ -x "${BUILD_SCRIPT}" ]] || fail "Build script not found at ${BUILD_SCRIPT}"
    APP_BUNDLE="$("${BUILD_SCRIPT}")"
  else
    fail "App bundle not found at ${APP_BUNDLE}."
  fi
fi

if is_true "${RUN_PREFLIGHT}"; then
  RCA_APP_BUNDLE="${APP_BUNDLE}" \
  RCA_BUILD_IF_MISSING=0 \
  RCA_REQUIRE_SIGNED="${RCA_REQUIRE_SIGNED:-0}" \
  RCA_CHECK_SIGNATURE="${RCA_CHECK_SIGNATURE:-0}" \
  RCA_REQUIRE_GATEKEEPER="${RCA_REQUIRE_GATEKEEPER:-0}" \
    "${PREFLIGHT_SCRIPT}" >/dev/null
fi

[[ -x "${DITTO_BIN}" ]] || fail "ditto not found at ${DITTO_BIN}"

info_plist="${APP_BUNDLE}/Contents/Info.plist"
[[ -f "${info_plist}" ]] || fail "App bundle is missing Contents/Info.plist: ${APP_BUNDLE}"

bundle_name="$(plist_value "${info_plist}" ":CFBundleName")"
bundle_version="$(plist_value "${info_plist}" ":CFBundleShortVersionString" || true)"
if [[ -z "${bundle_version}" || "${bundle_version}" == '$('* ]]; then
  bundle_version="$(/bin/date '+%Y.%m.%d')"
fi

release_basename="${RCA_RELEASE_NAME:-RightClickAI-macOS-${bundle_version}}"
archive_path="${RELEASE_DIR}/${release_basename}.zip"

mkdir -p "${RELEASE_DIR}"
rm -f "${archive_path}"
"${DITTO_BIN}" -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${archive_path}"

printf 'Packaged %s %s\n' "${bundle_name}" "${bundle_version}"
printf '%s\n' "${archive_path}"
