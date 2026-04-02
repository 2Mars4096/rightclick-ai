#!/bin/zsh

set -euo pipefail

source "${RC_INSTALL_ROOT}/lib/runtime-common.sh"

action_title="${RC_ACTION_TITLE:-Right Click Calendar}"
calendar_name="${CALENDAR_NAME:-}"
default_event_duration_minutes="${DEFAULT_EVENT_DURATION_MINUTES:-60}"
notify_on_success="${NOTIFY_ON_SUCCESS:-1}"
notify_on_failure="${NOTIFY_ON_FAILURE:-1}"
jxa=(/usr/bin/osascript -l JavaScript "${RC_TOOLS_JS}")
normalized_tmp="$(mktemp "${TMPDIR:-/tmp}/rc-normalized-events.XXXXXX")"
handler_error_tmp="$(mktemp "${TMPDIR:-/tmp}/rc-handler-error.XXXXXX")"
trap 'rm -f "${normalized_tmp}" "${handler_error_tmp}"' EXIT

if ! "${jxa[@]}" normalize-events "${RC_ACTION_RAW_CONTENT_FILE}" "${default_event_duration_minutes}" > "${normalized_tmp}" 2> "${handler_error_tmp}"; then
  error_message="$(rc_trim_whitespace "$(<"${handler_error_tmp}")")"
  if [[ -z "${error_message}" ]]; then
    error_message="The model returned data that could not be turned into events."
  fi
  rc_log "Normalization failed for action '${RC_ACTION_NAME}': ${error_message}"
  if rc_is_true "${notify_on_failure}"; then
    rc_notify "${action_title}" "${error_message}"
  fi
  exit 1
fi

event_count="$("${jxa[@]}" event-count "${normalized_tmp}")"
reason="$("${jxa[@]}" reason "${normalized_tmp}" 2>/dev/null || true)"

if [[ "${event_count}" == "0" ]]; then
  if [[ -z "${reason}" ]]; then
    reason="No calendar event was found in the selected text."
  fi
  rc_log "No events created for action '${RC_ACTION_NAME}'. ${reason}"
  if rc_is_true "${notify_on_failure}"; then
    rc_notify "${action_title}" "${reason}"
  fi
  exit 1
fi

if [[ "${RC_ACTION_DRY_RUN:-0}" == "1" ]]; then
  /bin/cat "${normalized_tmp}"
  exit 0
fi

created_count=0
failed_count=0

while IFS=$'\t' read -r title_b64 start_date end_date all_day location_b64 notes_b64 calendar_b64; do
  [[ -z "${title_b64}" ]] && continue

  title="$(printf '%s' "${title_b64}" | /usr/bin/base64 -D)"
  location="$(printf '%s' "${location_b64}" | /usr/bin/base64 -D)"
  notes="$(printf '%s' "${notes_b64}" | /usr/bin/base64 -D)"
  event_calendar="$(printf '%s' "${calendar_b64}" | /usr/bin/base64 -D)"
  if [[ -z "${event_calendar}" ]]; then
    event_calendar="${calendar_name}"
  fi

  if /usr/bin/osascript "${RC_CREATE_EVENT_SCRIPT}" "${event_calendar}" "${title}" "${start_date}" "${end_date}" "${all_day}" "${location}" "${notes}" >/dev/null 2>&1; then
    created_count=$((created_count + 1))
  else
    failed_count=$((failed_count + 1))
    rc_log "Failed to create event '${title}' for action '${RC_ACTION_NAME}'."
  fi
done < <("${jxa[@]}" emit-event-lines "${normalized_tmp}")

if (( created_count > 0 )) && rc_is_true "${notify_on_success}"; then
  if (( failed_count == 0 )); then
    rc_notify "${action_title}" "Added ${created_count} event(s)."
  else
    rc_notify "${action_title}" "Added ${created_count} event(s); ${failed_count} failed."
  fi
fi

if (( created_count == 0 )); then
  if rc_is_true "${notify_on_failure}"; then
    rc_notify "${action_title}" "Calendar creation failed. Check ${RC_LOG_FILE}."
  fi
  exit 1
fi
