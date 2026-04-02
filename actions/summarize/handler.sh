#!/bin/zsh

set -euo pipefail

source "${RC_INSTALL_ROOT}/lib/runtime-common.sh"

action_title="${RC_ACTION_TITLE:-Right Click Summary}"
notify_on_failure="${NOTIFY_ON_FAILURE:-1}"
summary_tmp="$(mktemp "${TMPDIR:-/tmp}/rc-summary.XXXXXX")"
handler_error_tmp="$(mktemp "${TMPDIR:-/tmp}/rc-summary-error.XXXXXX")"
trap 'rm -f "${summary_tmp}" "${handler_error_tmp}"' EXIT

if ! /usr/bin/osascript -l JavaScript "${RC_TOOLS_JS}" normalize-summary "${RC_ACTION_RAW_CONTENT_FILE}" > "${summary_tmp}" 2> "${handler_error_tmp}"; then
  error_message="$(rc_trim_whitespace "$(<"${handler_error_tmp}")")"
  if [[ -z "${error_message}" ]]; then
    error_message="The model returned data that could not be turned into a summary."
  fi
  rc_log "Summary normalization failed for action '${RC_ACTION_NAME}': ${error_message}"
  if rc_is_true "${notify_on_failure}"; then
    rc_notify "${action_title}" "${error_message}"
  fi
  exit 1
fi

/bin/cat "${summary_tmp}"
