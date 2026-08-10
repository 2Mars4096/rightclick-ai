#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
input_file="$(mktemp "${TMPDIR:-/tmp}/right-click-calendar-mixed.XXXXXX.json")"
output_file="$(mktemp "${TMPDIR:-/tmp}/right-click-calendar-mixed-output.XXXXXX.json")"
trap 'rm -f "${input_file}" "${output_file}"' EXIT

cat > "${input_file}" <<'JSON'
{
  "events": [
    {
      "title": "Prep meeting",
      "start": "2026-06-08T10:00:00+08:00",
      "end": "2026-06-08T10:30:00+08:00"
    },
    {
      "title": "Demand and Platform Management",
      "start": "June 9, 11, 17, 22, 24, 26 (2:30 p.m. - 5:30 p.m.)",
      "notes": "Prof. Hu Ming"
    },
    {
      "title": "Wrap-up call",
      "start": "2026-06-27T16:00:00+08:00",
      "end": "2026-06-27T17:00:00+08:00"
    }
  ],
  "reason": ""
}
JSON

/usr/bin/osascript -l JavaScript "${repo_root}/runtime/lib/tools.js" normalize-events \
  "${input_file}" \
  "60" \
  "2026-05-15 12:00:00 +0800" > "${output_file}"

/usr/bin/python3 -c '
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
events = payload["events"]
assert len(events) == 8, len(events)
assert events[0]["title"] == "Prep meeting", events[0]
assert events[-1]["title"] == "Wrap-up call", events[-1]
assert sum(event["title"] == "Demand and Platform Management" for event in events) == 6
assert events[1]["start"].startswith("2026-06-09 14:30:00"), events[1]
assert events[6]["start"].startswith("2026-06-26 14:30:00"), events[6]
' "${output_file}"
