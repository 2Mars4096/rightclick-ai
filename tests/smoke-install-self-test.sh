#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_home="$(mktemp -d "${TMPDIR:-/tmp}/right-click-smoke-home.XXXXXX")"
calendar_json_file="$(mktemp "${TMPDIR:-/tmp}/right-click-smoke-calendar.XXXXXX.json")"
actions_file="$(mktemp "${TMPDIR:-/tmp}/right-click-smoke-actions.XXXXXX.txt")"
trap 'rm -rf "${test_home}" "${calendar_json_file}" "${actions_file}"' EXIT

RCA_HOME="${test_home}" RCA_DEFAULT_PROVIDER=mock RCA_SKIP_PBS=1 "${repo_root}/install.sh"

bin_dir="${test_home}/Library/Application Support/RightClickCalendar/bin"
runtime_cli="${bin_dir}/right-click-action"
calendar_cli="${bin_dir}/right-click-calendar"

"${runtime_cli}" --list-actions > "${actions_file}"
/usr/bin/grep -F $'add-to-calendar\tRight Click Calendar' "${actions_file}" >/dev/null
/usr/bin/grep -F $'draft-response\tRight Click Draft Response' "${actions_file}" >/dev/null
/usr/bin/grep -F $'explain\tRight Click Explain' "${actions_file}" >/dev/null
/usr/bin/grep -F $'polish-draft\tRight Click Polish Draft' "${actions_file}" >/dev/null
/usr/bin/grep -F $'summarize\tRight Click Summary' "${actions_file}" >/dev/null
/usr/bin/grep -F $'rewrite-friendly\tRight Click Rewrite Friendly' "${actions_file}" >/dev/null
/usr/bin/grep -F $'extract-action-items\tRight Click Action Items' "${actions_file}" >/dev/null

"${runtime_cli}" --validate-action add-to-calendar >/dev/null
"${runtime_cli}" --validate-action draft-response >/dev/null
"${runtime_cli}" --validate-action explain >/dev/null
"${runtime_cli}" --validate-action polish-draft >/dev/null
"${runtime_cli}" --validate-action summarize >/dev/null
"${runtime_cli}" --validate-action rewrite-friendly >/dev/null
"${runtime_cli}" --validate-action extract-action-items >/dev/null

calendar_output="$("${runtime_cli}" add-to-calendar --self-test)"
printf '%s\n' "${calendar_output}"
printf '%s' "${calendar_output}" > "${calendar_json_file}"

/usr/bin/python3 -c 'import json, pathlib, sys; payload=json.loads(pathlib.Path(sys.argv[1]).read_text()); assert len(payload["events"]) == 4' "${calendar_json_file}"
printf '%s' "${calendar_output}" | /usr/bin/grep -F '"title":"笼民"' >/dev/null
printf '%s' "${calendar_output}" | /usr/bin/grep -F '"title":"断手断脚鬼工厂"' >/dev/null
printf '%s' "${calendar_output}" | /usr/bin/grep -F '"location":"IS"' >/dev/null

draft_output="$("${runtime_cli}" draft-response --self-test)"
printf '%s\n' "${draft_output}"
printf '%s' "${draft_output}" | /usr/bin/grep -F 'the venue is still available on Sunday afternoon' >/dev/null

explain_output="$("${runtime_cli}" explain --self-test)"
printf '%s\n' "${explain_output}"
printf '%s' "${explain_output}" | /usr/bin/grep -F 'how much of each dollar of sales is left' >/dev/null

polish_output="$("${runtime_cli}" polish-draft --self-test)"
printf '%s\n' "${polish_output}"
printf '%s' "${polish_output}" | /usr/bin/grep -F 'Sorry for the late reply.' >/dev/null

summary_output="$(printf '%s' 'Release notes for the current sprint.' | "${runtime_cli}" summarize)"
printf '%s\n' "${summary_output}"
printf '%s' "${summary_output}" | /usr/bin/grep -F 'Mock summary output.' >/dev/null

rewrite_output="$("${runtime_cli}" rewrite-friendly --self-test)"
printf '%s\n' "${rewrite_output}"
printf '%s' "${rewrite_output}" | /usr/bin/grep -F 'Could you please send the revised deck by tomorrow morning? Thanks.' >/dev/null

action_items_output="$("${runtime_cli}" extract-action-items --self-test)"
printf '%s\n' "${action_items_output}"
printf '%s' "${action_items_output}" | /usr/bin/grep -F -- "- Confirm Friday's review." >/dev/null
printf '%s' "${action_items_output}" | /usr/bin/grep -F -- "- Send the budget update to finance." >/dev/null

wrapper_output="$("${calendar_cli}" --self-test)"
[[ "${wrapper_output}" == "${calendar_output}" ]]

"${repo_root}/tests/keychain-secret-resolution-smoke.sh"
"${repo_root}/tests/action-instruction-prompt-smoke.sh"
"${repo_root}/tests/add-to-calendar-prompt-smoke.sh"
"${repo_root}/tests/calendar-queue-smoke.sh"
zsh "${repo_root}/tests/direct-service-install-smoke.sh"
"${repo_root}/tests/native-build-smoke.sh"
"${repo_root}/tests/native-app-install-smoke.sh"
"${repo_root}/tests/release-packaging-smoke.sh"
