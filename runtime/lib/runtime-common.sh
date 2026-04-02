#!/bin/zsh

rc_fail() {
  print -r -- "$*" >&2
  exit 1
}

rc_trim_whitespace() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

rc_escape_notification() {
  local value="${1:-}"
  value="${value//$'\n'/ }"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "${value}"
}

rc_notify() {
  local title="${1:-Right Click}"
  local message="${2:-}"
  /usr/bin/osascript -e "display notification \"$(rc_escape_notification "${message}")\" with title \"$(rc_escape_notification "${title}")\"" >/dev/null 2>&1 || true
}

rc_runtime_namespace() {
  local runtime_root="${1:-${RC_INSTALL_ROOT:-${INSTALL_ROOT:-}}}"
  if [[ -z "${runtime_root}" ]]; then
    printf 'RightClickAI\n'
    return 0
  fi

  printf '%s\n' "${runtime_root:t}"
}

rc_default_log_file() {
  printf '%s/Library/Logs/%s.log\n' "${RCA_HOME:-$HOME}" "$(rc_runtime_namespace)"
}

rc_log() {
  local log_file="${RC_LOG_FILE:-$(rc_default_log_file)}"
  mkdir -p "$(dirname "${log_file}")"
  printf '[%s] %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')" "$*" >> "${log_file}"
}

rc_is_true() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES|y|Y|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

rc_resolve_path() {
  local base_dir="$1"
  local path="$2"
  local parent_dir

  [[ -n "${path}" ]] || return 1

  if [[ "${path}" = /* ]]; then
    printf '%s\n' "${path}"
    return 0
  fi

  parent_dir="${base_dir}/${path:h}"
  parent_dir="$(cd "${parent_dir}" 2>/dev/null && pwd)" || return 1
  printf '%s/%s\n' "${parent_dir}" "${path:t}"
}

rc_keychain_service_for_root() {
  local runtime_root="${1:-${RC_INSTALL_ROOT:-${INSTALL_ROOT:-}}}"
  if [[ -z "${runtime_root}" ]]; then
    printf 'RightClickAI\n'
    return 0
  fi

  if [[ -d "${runtime_root}" ]]; then
    runtime_root="$(cd "${runtime_root}" && pwd)"
  fi

  printf 'RightClickAI:%s\n' "${runtime_root}"
}

rc_read_keychain_secret() {
  local service="$1"
  local account="$2"
  local security_bin="${RC_SECURITY_BIN:-/usr/bin/security}"

  [[ -x "${security_bin}" ]] || return 1
  "${security_bin}" find-generic-password -w -s "${service}" -a "${account}" 2>/dev/null
}

rc_resolve_secret() {
  local variable_name="$1"
  local current_value="${(P)variable_name:-}"
  local account_variable="${variable_name}_KEYCHAIN_ACCOUNT"
  local account_name="${(P)account_variable:-}"
  local keychain_service="${RC_KEYCHAIN_SERVICE:-$(rc_keychain_service_for_root "${RC_INSTALL_ROOT:-${INSTALL_ROOT:-}}")}"
  local secret=""

  [[ -n "${current_value}" ]] && return 0

  if [[ -z "${account_name}" ]]; then
    account_name="${variable_name}"
  fi

  secret="$(rc_read_keychain_secret "${keychain_service}" "${account_name}")" || return 1
  typeset -gx "${variable_name}=${secret}"
}
