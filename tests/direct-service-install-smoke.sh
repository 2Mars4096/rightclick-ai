#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_home="$(mktemp -d "${TMPDIR:-/tmp}/right-click-direct-services.XXXXXX")"
trap 'rm -rf "${test_home}"' EXIT

RCA_HOME="${test_home}" RCA_DEFAULT_PROVIDER=mock RCA_SKIP_PBS=1 "${repo_root}/install.sh" >/dev/null

services_dir="${test_home}/Library/Services"
runtime_root="${test_home}/Library/Application Support/RightClickCalendar"
wrapper_path="${runtime_root}/bin/right-click-service-action"

[[ -x "${wrapper_path}" ]]
[[ -d "${services_dir}/Add to Calendar.workflow" ]]
[[ -d "${services_dir}/Draft Response.workflow" ]]
[[ -d "${services_dir}/Explain.workflow" ]]
[[ -d "${services_dir}/Extract Action Items.workflow" ]]
[[ -d "${services_dir}/Polish Draft.workflow" ]]
[[ -d "${services_dir}/Rewrite Friendly.workflow" ]]
[[ -d "${services_dir}/Summarize.workflow" ]]

/usr/bin/grep -F '__SERVICE_NAME__' "${services_dir}/Draft Response.workflow/Contents/Info.plist" >/dev/null && exit 1
/usr/bin/grep -F '<string>Draft Response</string>' "${services_dir}/Draft Response.workflow/Contents/Info.plist" >/dev/null
/usr/bin/grep -F 'right-click-service-action" "draft-response"' "${services_dir}/Draft Response.workflow/Contents/document.wflow" >/dev/null
/usr/bin/grep -F 'right-click-service-action" "add-to-calendar"' "${services_dir}/Add to Calendar.workflow/Contents/document.wflow" >/dev/null
