#!/bin/zsh

set -euo pipefail

APP_ID="${RCA_APP_ID:-RightClickCalendar}"
DEFAULT_PROVIDER="${RCA_DEFAULT_PROVIDER:-openai_compatible}"
OPEN_SETTINGS_AFTER_INSTALL="${RCA_OPEN_SETTINGS:-0}"
SKIP_PBS_UPDATE="${RCA_SKIP_PBS:-0}"
INSTALL_SERVICE_WORKFLOW="${RCA_INSTALL_SERVICE_WORKFLOW:-1}"
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_ROOT="${REPO_ROOT}/runtime"
ACTIONS_ROOT="${REPO_ROOT}/actions"
CALENDAR_ACTION_ROOT="${ACTIONS_ROOT}/add-to-calendar"

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

require_asset() {
  local path="$1"
  [[ -f "${path}" ]] || fail "Missing installer asset: ${path}"
}

install_file() {
  local source="$1"
  local destination="$2"
  require_asset "${source}"
  /usr/bin/install -m 0644 "${source}" "${destination}"
}

install_executable() {
  local source="$1"
  local destination="$2"
  require_asset "${source}"
  /usr/bin/install -m 0755 "${source}" "${destination}"
}

require_directory() {
  local path="$1"
  [[ -d "${path}" ]] || fail "Missing installer asset directory: ${path}"
}

install_tree() {
  local source="$1"
  local destination="$2"
  require_directory "${source}"
  rm -rf "${destination}"
  mkdir -p "${destination}"
  /usr/bin/rsync -a --delete --exclude '.DS_Store' --exclude '.git' "${source}/" "${destination}/"
}

get_timezone_name() {
  /usr/bin/osascript -l JavaScript <<'JXA' 2>/dev/null || true
ObjC.import('Foundation');
function run() {
  return ObjC.unwrap($.NSTimeZone.localTimeZone.name);
}
JXA
}

render_settings_template() {
  local source="$1"
  local destination="$2"
  require_asset "${source}"
  RC_DEFAULT_PROVIDER="${DEFAULT_PROVIDER}" \
  RC_SYSTEM_TIMEZONE="${SYSTEM_TIMEZONE}" \
    /usr/bin/perl -0pe '
      s/__DEFAULT_PROVIDER__/$ENV{RC_DEFAULT_PROVIDER}/g;
      s/__SYSTEM_TIMEZONE__/$ENV{RC_SYSTEM_TIMEZONE}/g;
    ' "${source}" > "${destination}"
}

render_workflow_template() {
  local source="$1"
  local destination="$2"
  require_asset "${source}"
  RC_WORKFLOW_COMMAND="${WORKFLOW_COMMAND}" \
    /usr/bin/perl -0pe '
      s/__WORKFLOW_COMMAND__/$ENV{RC_WORKFLOW_COMMAND}/g;
    ' "${source}" > "${destination}"
}

render_workflow_info_template() {
  local source="$1"
  local destination="$2"
  require_asset "${source}"
  RC_SERVICE_NAME="${WORKFLOW_SERVICE_NAME}" \
    /usr/bin/perl -0pe '
      s/__SERVICE_NAME__/$ENV{RC_SERVICE_NAME}/g;
    ' "${source}" > "${destination}"
}

load_action_manifest() {
  local manifest_file="$1"

  unset ACTION_ID ACTION_TITLE ACTION_SERVICE_NAME ACTION_SERVICE_KIND ACTION_SYSTEM_PROMPT ACTION_PROMPT_FILE ACTION_HANDLER ACTION_OUTPUT_MODE ACTION_SELF_TEST_INPUT ACTION_SELF_TEST_PROVIDER ACTION_MOCK_RESPONSE_FILE
  source "${manifest_file}"

  [[ -n "${ACTION_ID:-}" ]] || fail "Missing ACTION_ID in ${manifest_file}"
  [[ -n "${ACTION_SERVICE_NAME:-}" ]] || fail "Missing ACTION_SERVICE_NAME in ${manifest_file}"
  [[ -n "${ACTION_SERVICE_KIND:-}" ]] || fail "Missing ACTION_SERVICE_KIND in ${manifest_file}"
}

install_action_workflow() {
  local manifest_file="$1"
  local action_id=""
  local service_name=""
  local workflow_dir=""

  load_action_manifest "${manifest_file}"
  action_id="${ACTION_ID}"
  service_name="${ACTION_SERVICE_NAME}"
  workflow_dir="${SERVICES_DIR}/${service_name}.workflow/Contents"

  mkdir -p "${workflow_dir}"

  WORKFLOW_SERVICE_NAME="${service_name}"
  WORKFLOW_COMMAND="\"${USER_HOME}/Library/Application Support/${APP_ID}/bin/right-click-service-action\" \"${action_id}\""

  render_workflow_info_template "${CALENDAR_ACTION_ROOT}/workflow/Info.plist" "${workflow_dir}/Info.plist"
  render_workflow_template "${CALENDAR_ACTION_ROOT}/workflow/document.wflow" "${workflow_dir}/document.wflow"

  /usr/bin/plutil -lint "${workflow_dir}/Info.plist" >/dev/null
  /usr/bin/plutil -lint "${workflow_dir}/document.wflow" >/dev/null

  printf '%s\n' "${service_name}"
}

SYSTEM_TIMEZONE="$(get_timezone_name)"
if [[ -z "${SYSTEM_TIMEZONE}" ]]; then
  SYSTEM_TIMEZONE="UTC"
fi

USER_HOME="$(resolve_user_home)"
INSTALL_ROOT="${USER_HOME}/Library/Application Support/${APP_ID}"
BIN_DIR="${INSTALL_ROOT}/bin"
LIB_DIR="${INSTALL_ROOT}/lib"
PROVIDERS_DIR="${INSTALL_ROOT}/providers"
ACTIONS_DIR="${INSTALL_ROOT}/actions"
SERVICES_DIR="${USER_HOME}/Library/Services"
SETTINGS_FILE="${INSTALL_ROOT}/settings.env"
PROMPT_FILE="${INSTALL_ROOT}/prompt.txt"
LOG_DIR="${USER_HOME}/Library/Logs"
UNINSTALL_FILE="${INSTALL_ROOT}/uninstall.sh"

mkdir -p "${BIN_DIR}" "${LIB_DIR}" "${PROVIDERS_DIR}" "${ACTIONS_DIR}" "${LOG_DIR}"
mkdir -p "${SERVICES_DIR}"

if [[ ! -f "${SETTINGS_FILE}" ]]; then
  render_settings_template "${RUNTIME_ROOT}/defaults/settings.env.template" "${SETTINGS_FILE}"
fi

if [[ ! -f "${PROMPT_FILE}" ]]; then
  install_file "${CALENDAR_ACTION_ROOT}/prompt.txt" "${PROMPT_FILE}"
fi

install_tree "${ACTIONS_ROOT}" "${ACTIONS_DIR}"
install_executable "${RUNTIME_ROOT}/bin/right-click-action" "${BIN_DIR}/right-click-action"
install_executable "${RUNTIME_ROOT}/bin/right-click-calendar" "${BIN_DIR}/right-click-calendar"
install_executable "${RUNTIME_ROOT}/bin/right-click-calendar-settings" "${BIN_DIR}/right-click-calendar-settings"
install_executable "${RUNTIME_ROOT}/bin/right-click-service-action" "${BIN_DIR}/right-click-service-action"
install_file "${RUNTIME_ROOT}/lib/runtime-common.sh" "${LIB_DIR}/runtime-common.sh"
install_file "${RUNTIME_ROOT}/lib/tools.js" "${LIB_DIR}/tools.js"
install_file "${RUNTIME_ROOT}/lib/create-event.applescript" "${LIB_DIR}/create-event.applescript"
install_executable "${RUNTIME_ROOT}/providers/openai_compatible.sh" "${PROVIDERS_DIR}/openai_compatible.sh"
install_executable "${RUNTIME_ROOT}/providers/anthropic.sh" "${PROVIDERS_DIR}/anthropic.sh"
install_executable "${RUNTIME_ROOT}/providers/gemini.sh" "${PROVIDERS_DIR}/gemini.sh"
install_executable "${RUNTIME_ROOT}/providers/custom_command.sh" "${PROVIDERS_DIR}/custom_command.sh"
install_executable "${RUNTIME_ROOT}/providers/mock.sh" "${PROVIDERS_DIR}/mock.sh"
install_executable "${RUNTIME_ROOT}/uninstall.sh" "${UNINSTALL_FILE}"

if [[ "${INSTALL_SERVICE_WORKFLOW}" == "1" ]]; then
  installed_services=()
  while IFS= read -r manifest_file; do
    [[ -n "${manifest_file}" ]] || continue
    installed_services+=("$(install_action_workflow "${manifest_file}")")
  done < <(find "${ACTIONS_ROOT}" -mindepth 2 -maxdepth 2 -name action.env -print | sort)

  if [[ "${SKIP_PBS_UPDATE}" != "1" ]]; then
    /System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true
  fi

  printf 'Installed Services:\n'
  printf ' - %s\n' "${installed_services[@]}"
  printf 'Settings: %s\n' "${SETTINGS_FILE}"
  printf 'Prompt: %s\n' "${PROMPT_FILE}"
  printf 'Edit settings: %s --edit-settings\n' "${BIN_DIR}/right-click-calendar"
  printf 'If the menu item does not appear immediately, run: /System/Library/CoreServices/pbs -update\n'
  printf 'The first live run will ask macOS for Calendar access.\n'
else
  printf 'Installed shared runtime: %s\n' "${INSTALL_ROOT}"
  printf 'Settings: %s\n' "${SETTINGS_FILE}"
  printf 'Actions: %s\n' "${ACTIONS_DIR}"
fi

if [[ "${OPEN_SETTINGS_AFTER_INSTALL}" == "1" ]]; then
  open -e "${SETTINGS_FILE}" || true
fi
