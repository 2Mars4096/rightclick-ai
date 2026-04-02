#!/bin/zsh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="${RCA_XCODE_PROJECT:-${REPO_ROOT}/app/RightClickApp.xcodeproj}"
SCHEME_NAME="${RCA_XCODE_SCHEME:-RightClickApp}"
CONFIGURATION="${RCA_XCODE_CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${RCA_DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/right-click-ai-derived-data}"
OUTPUT_ROOT="${RCA_BUILD_OUTPUT_ROOT:-${REPO_ROOT}/build}"
OUTPUT_APP_PATH="${OUTPUT_ROOT}/RightClickApp.app"
XCODEBUILD_BIN="${RCA_XCODEBUILD_BIN:-/usr/bin/xcodebuild}"
DEVELOPER_DIR_OVERRIDE="${RCA_DEVELOPER_DIR:-}"

fail() {
  print -r -- "$*" >&2
  exit 1
}

resolve_developer_dir() {
  if [[ -n "${DEVELOPER_DIR_OVERRIDE}" ]]; then
    printf '%s\n' "${DEVELOPER_DIR_OVERRIDE}"
    return 0
  fi

  if [[ "${XCODEBUILD_BIN}" != "/usr/bin/xcodebuild" ]]; then
    return 0
  fi

  local active_dir
  active_dir="$(xcode-select -p 2>/dev/null || true)"
  if [[ "${active_dir}" != "/Library/Developer/CommandLineTools" && -n "${active_dir}" ]]; then
    printf '%s\n' "${active_dir}"
    return 0
  fi

  for candidate in \
    "/Applications/Xcode.app/Contents/Developer" \
    "$HOME/Applications/Xcode.app/Contents/Developer"
  do
    if [[ -d "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  fail "Full Xcode is not available. Install Xcode or set RCA_DEVELOPER_DIR and RCA_XCODEBUILD_BIN explicitly."
}

find_built_app() {
  local derived_data_root="$1"
  local configuration="$2"
  local preferred="${derived_data_root}/Build/Products/${configuration}/RightClickApp.app"

  if [[ -d "${preferred}" ]]; then
    printf '%s\n' "${preferred}"
    return 0
  fi

  find "${derived_data_root}/Build/Products" -type d -name 'RightClickApp.app' -print -quit 2>/dev/null || true
}

[[ -f "${PROJECT_PATH}/project.pbxproj" ]] || fail "Xcode project not found at ${PROJECT_PATH}"
[[ -x "${XCODEBUILD_BIN}" ]] || fail "xcodebuild executable not found at ${XCODEBUILD_BIN}"

developer_dir="$(resolve_developer_dir)"

mkdir -p "${DERIVED_DATA_PATH}" "${OUTPUT_ROOT}"

if [[ -n "${developer_dir}" ]]; then
  export DEVELOPER_DIR="${developer_dir}"
fi

"${XCODEBUILD_BIN}" \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME_NAME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  CODE_SIGNING_ALLOWED=NO \
  build >/dev/null

built_app="$(find_built_app "${DERIVED_DATA_PATH}" "${CONFIGURATION}")"
[[ -n "${built_app}" ]] || fail "xcodebuild completed but RightClickApp.app was not found in ${DERIVED_DATA_PATH}."

rm -rf "${OUTPUT_APP_PATH}"
mkdir -p "${OUTPUT_APP_PATH}"
/usr/bin/rsync -a --delete --exclude '.DS_Store' "${built_app}/" "${OUTPUT_APP_PATH}/"
/usr/bin/plutil -lint "${OUTPUT_APP_PATH}/Contents/Info.plist" >/dev/null

printf '%s\n' "${OUTPUT_APP_PATH}"
