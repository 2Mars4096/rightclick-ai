#!/bin/zsh

set -euo pipefail

APP_NAME="${RCA_NATIVE_APP_NAME:-RightClick AI.app}"
RUNTIME_APP_ID="${RCA_RUNTIME_APP_ID:-RightClickAI}"
DIRECT_CALENDAR_SERVICE_NAME="${RCA_DIRECT_CALENDAR_SERVICE_NAME:-Add to Calendar}"
INSTALL_ACTION_SERVICE_WORKFLOWS="${RCA_INSTALL_ACTION_SERVICE_WORKFLOWS:-1}"
REMOVE_DIRECT_CALENDAR_WORKFLOW="${RCA_REMOVE_DIRECT_CALENDAR_WORKFLOW:-0}"
SKIP_PBS_UPDATE="${RCA_SKIP_PBS:-0}"
OPEN_APP_AFTER_INSTALL="${RCA_OPEN_APP_AFTER_INSTALL:-1}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_APP_BUNDLE="${REPO_ROOT}/build/RightClickApp.app"
BUILD_SCRIPT="${REPO_ROOT}/scripts/build-native-app.sh"

fail() {
  print -r -- "$*" >&2
  exit 1
}

resolve_user_home() {
  if [[ -n "${RCA_HOME:-}" ]]; then
    printf '%s\n' "${RCA_HOME}"
    return 0
  fi

  local resolved_home=""
  resolved_home="$(
    /usr/bin/python3 - <<'PY' 2>/dev/null || true
import os
import pwd
print(pwd.getpwuid(os.getuid()).pw_dir)
PY
  )"
  resolved_home="${resolved_home//$'\n'/}"

  if [[ -n "${resolved_home}" && "${resolved_home}" != "${HOME}" ]]; then
    printf '%s\n' "${resolved_home}"
    return 0
  fi

  printf '%s\n' "${HOME}"
}

find_default_app_bundle() {
  if [[ -d "${DEFAULT_APP_BUNDLE}" ]]; then
    printf '%s\n' "${DEFAULT_APP_BUNDLE}"
    return 0
  fi
}

copy_app_bundle() {
  local source_bundle="$1"
  local destination_bundle="$2"

  rm -rf "${destination_bundle}"
  mkdir -p "${destination_bundle}"
  /usr/bin/rsync -a --delete --exclude '.DS_Store' "${source_bundle}/" "${destination_bundle}/"
}

remove_direct_calendar_workflow() {
  local workflow_path="$1"

  if [[ -e "${workflow_path}" ]]; then
    rm -rf "${workflow_path}"
    printf 'Removed direct workflow: %s\n' "${workflow_path}"
  fi
}

SOURCE_APP_BUNDLE="${RCA_APP_BUNDLE:-}"
if [[ -z "${SOURCE_APP_BUNDLE}" ]]; then
  SOURCE_APP_BUNDLE="$(find_default_app_bundle)"
fi

if [[ -z "${SOURCE_APP_BUNDLE}" ]]; then
  [[ -x "${BUILD_SCRIPT}" ]] || fail "Build script not found at ${BUILD_SCRIPT}"
  SOURCE_APP_BUNDLE="$("${BUILD_SCRIPT}")"
fi

[[ -d "${SOURCE_APP_BUNDLE}" ]] || fail "App bundle does not exist: ${SOURCE_APP_BUNDLE}"
[[ -f "${SOURCE_APP_BUNDLE}/Contents/Info.plist" ]] || fail "App bundle is missing Contents/Info.plist: ${SOURCE_APP_BUNDLE}"

USER_HOME="$(resolve_user_home)"
APPLICATIONS_DIR="${USER_HOME}/Applications"
INSTALLED_APP_PATH="${APPLICATIONS_DIR}/${APP_NAME}"
DIRECT_CALENDAR_WORKFLOW_PATH="${USER_HOME}/Library/Services/${DIRECT_CALENDAR_SERVICE_NAME}.workflow"

mkdir -p "${APPLICATIONS_DIR}"

RCA_HOME="${USER_HOME}" \
RCA_APP_ID="${RUNTIME_APP_ID}" \
RCA_SKIP_PBS="${SKIP_PBS_UPDATE}" \
RCA_OPEN_SETTINGS=0 \
RCA_INSTALL_SERVICE_WORKFLOW="${INSTALL_ACTION_SERVICE_WORKFLOWS}" \
  "${REPO_ROOT}/install.sh"

copy_app_bundle "${SOURCE_APP_BUNDLE}" "${INSTALLED_APP_PATH}"
/usr/bin/plutil -lint "${INSTALLED_APP_PATH}/Contents/Info.plist" >/dev/null

if [[ "${INSTALL_ACTION_SERVICE_WORKFLOWS}" != "1" && "${REMOVE_DIRECT_CALENDAR_WORKFLOW}" == "1" ]]; then
  remove_direct_calendar_workflow "${DIRECT_CALENDAR_WORKFLOW_PATH}"
fi

if [[ "${SKIP_PBS_UPDATE}" != "1" ]]; then
  /System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true
fi

printf 'Installed app: %s\n' "${INSTALLED_APP_PATH}"
printf 'Installed runtime: %s\n' "${USER_HOME}/Library/Application Support/${RUNTIME_APP_ID}"
printf 'Settings: %s\n' "${USER_HOME}/Library/Application Support/${RUNTIME_APP_ID}/settings.env"
printf 'Service menu item: RightClick AI\n'
if [[ "${INSTALL_ACTION_SERVICE_WORKFLOWS}" == "1" ]]; then
  printf 'Direct service shortcuts installed, including: %s\n' "${DIRECT_CALENDAR_SERVICE_NAME}"
fi
printf 'First launch opens in-app settings if provider setup is still missing.\n'
printf 'After setup, RightClick AI stays available from the menu bar and selected-text Services.\n'

if [[ "${OPEN_APP_AFTER_INSTALL}" == "1" ]]; then
  open "${INSTALLED_APP_PATH}" || true
fi
