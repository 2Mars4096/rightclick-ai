#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_home="$(mktemp -d "${TMPDIR:-/tmp}/right-click-preview-apply.XXXXXX")"
output_file="$(mktemp "${TMPDIR:-/tmp}/right-click-preview-apply-output.XXXXXX.json")"
trap 'rm -rf "${test_home}" "${output_file}"' EXIT

RCA_HOME="${test_home}" \
RCA_APP_ID=RightClickAI \
RCA_DEFAULT_PROVIDER=custom_command \
RCA_SKIP_PBS=1 \
RCA_INSTALL_SERVICE_WORKFLOW=0 \
  "${repo_root}/install.sh" >/dev/null

runtime_cli="${test_home}/Library/Application Support/RightClickAI/bin/right-click-action"

printf '%s' '{"events":[{"title":"Reviewed Event","start":"2027-08-12T09:30:00+08:00","end":"2027-08-12T10:15:00+08:00","allDay":false,"location":"Test Room","notes":"Exact reviewed payload","calendar":""}],"reason":""}' \
  | "${runtime_cli}" add-to-calendar --apply-preview --dry-run > "${output_file}"

/usr/bin/python3 -c '
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert len(payload["events"]) == 1, payload
event = payload["events"][0]
assert event["title"] == "Reviewed Event", event
assert event["start"].startswith("2027-08-12 09:30:00"), event
assert event["end"].startswith("2027-08-12 10:15:00"), event
assert event["location"] == "Test Room", event
assert event["notes"] == "Exact reviewed payload", event
' "${output_file}"

print "Calendar preview apply smoke passed."
