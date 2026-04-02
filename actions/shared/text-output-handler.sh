#!/bin/zsh

set -euo pipefail

source "${RC_INSTALL_ROOT}/lib/runtime-common.sh"

action_title="${RC_ACTION_TITLE:-Right Click Output}"
notify_on_failure="${NOTIFY_ON_FAILURE:-1}"
output_mode="${RC_ACTION_OUTPUT_MODE:-text}"
normalized_tmp="$(mktemp "${TMPDIR:-/tmp}/rc-text-output.XXXXXX")"
handler_error_tmp="$(mktemp "${TMPDIR:-/tmp}/rc-text-output-error.XXXXXX")"
trap 'rm -f "${normalized_tmp}" "${handler_error_tmp}"' EXIT

if ! /usr/bin/osascript -l JavaScript "${RC_TOOLS_JS}" normalize-text-output "${RC_ACTION_RAW_CONTENT_FILE}" "${output_mode}" > "${normalized_tmp}" 2> "${handler_error_tmp}"; then
  error_message="$(rc_trim_whitespace "$(<"${handler_error_tmp}")")"
  if [[ -z "${error_message}" ]]; then
    error_message="The model returned output that could not be normalized."
  fi
  rc_log "Text-output normalization failed for action '${RC_ACTION_NAME}': ${error_message}"
  if rc_is_true "${notify_on_failure}"; then
    rc_notify "${action_title}" "${error_message}"
  fi
  exit 1
fi

/bin/cat "${normalized_tmp}"
