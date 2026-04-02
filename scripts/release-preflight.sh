#!/bin/zsh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_APP_BUNDLE="${REPO_ROOT}/build/RightClickApp.app"
BUILD_SCRIPT="${REPO_ROOT}/scripts/build-native-app.sh"
APP_BUNDLE="${RCA_APP_BUNDLE:-${DEFAULT_APP_BUNDLE}}"
BUILD_IF_MISSING="${RCA_BUILD_IF_MISSING:-0}"
REQUIRE_SIGNED="${RCA_REQUIRE_SIGNED:-0}"
CHECK_SIGNATURE="${RCA_CHECK_SIGNATURE:-0}"
REQUIRE_GATEKEEPER="${RCA_REQUIRE_GATEKEEPER:-0}"
PLUTIL_BIN="${RCA_PLUTIL_BIN:-/usr/bin/plutil}"
PLIST_BUDDY_BIN="${RCA_PLIST_BUDDY_BIN:-/usr/libexec/PlistBuddy}"
CODESIGN_BIN="${RCA_CODESIGN_BIN:-/usr/bin/codesign}"
SPCTL_BIN="${RCA_SPCTL_BIN:-/usr/sbin/spctl}"

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
    fail "App bundle not found at ${APP_BUNDLE}. Build it first or set RCA_BUILD_IF_MISSING=1."
  fi
fi

[[ -x "${PLUTIL_BIN}" ]] || fail "plutil not found at ${PLUTIL_BIN}"
[[ -x "${PLIST_BUDDY_BIN}" ]] || fail "PlistBuddy not found at ${PLIST_BUDDY_BIN}"

info_plist="${APP_BUNDLE}/Contents/Info.plist"
[[ -f "${info_plist}" ]] || fail "App bundle is missing Contents/Info.plist: ${APP_BUNDLE}"
"${PLUTIL_BIN}" -lint "${info_plist}" >/dev/null || fail "Info.plist is invalid: ${info_plist}"

bundle_name="$(plist_value "${info_plist}" ":CFBundleName")"
bundle_identifier="$(plist_value "${info_plist}" ":CFBundleIdentifier")"
bundle_executable="$(plist_value "${info_plist}" ":CFBundleExecutable")"
service_name="$(plist_value "${info_plist}" ":NSServices:0:NSMenuItem:default")"
service_message="$(plist_value "${info_plist}" ":NSServices:0:NSMessage")"

[[ -n "${bundle_name}" ]] || fail "CFBundleName is empty."
[[ -n "${bundle_identifier}" ]] || fail "CFBundleIdentifier is empty."
[[ -n "${bundle_executable}" ]] || fail "CFBundleExecutable is empty."
[[ -n "${service_name}" ]] || fail "NSServices[0].NSMenuItem.default is missing."
[[ -n "${service_message}" ]] || fail "NSServices[0].NSMessage is missing."

executable_path="${APP_BUNDLE}/Contents/MacOS/${bundle_executable}"
[[ -f "${executable_path}" ]] || fail "Executable is missing: ${executable_path}"
[[ -x "${executable_path}" ]] || fail "Executable is not marked executable: ${executable_path}"

printf 'Bundle: %s\n' "${APP_BUNDLE}"
printf 'Name: %s\n' "${bundle_name}"
printf 'Bundle ID: %s\n' "${bundle_identifier}"
printf 'Executable: %s\n' "${bundle_executable}"
printf 'Service: %s\n' "${service_name}"
printf 'Service Message: %s\n' "${service_message}"

if is_true "${CHECK_SIGNATURE}" || is_true "${REQUIRE_SIGNED}"; then
  [[ -x "${CODESIGN_BIN}" ]] || fail "codesign not found at ${CODESIGN_BIN}"
  if "${CODESIGN_BIN}" --verify --deep --strict --verbose=2 "${APP_BUNDLE}" >/dev/null 2>&1; then
    printf 'Code Signature: verified\n'
  elif is_true "${REQUIRE_SIGNED}"; then
    fail "codesign verification failed for ${APP_BUNDLE}"
  else
    printf 'Code Signature: missing or invalid\n'
  fi
fi

if is_true "${REQUIRE_GATEKEEPER}"; then
  [[ -x "${SPCTL_BIN}" ]] || fail "spctl not found at ${SPCTL_BIN}"
  "${SPCTL_BIN}" --assess --type execute --verbose=4 "${APP_BUNDLE}" >/dev/null
  printf 'Gatekeeper: accepted\n'
fi
