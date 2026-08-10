#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
input_file="$(mktemp "${TMPDIR:-/tmp}/right-click-calendar-multidate.XXXXXX.json")"
output_file="$(mktemp "${TMPDIR:-/tmp}/right-click-calendar-multidate-output.XXXXXX.json")"
trap 'rm -f "${input_file}" "${output_file}"' EXIT

cat > "${input_file}" <<'JSON'
{
  "events": [
    {
      "title": "Paths to Research",
      "start": "May 27, 28, 29, June 1, 3, 5 (9:00 a.m. - 12:00 p.m.)",
      "notes": "Prof. Chris Ryan"
    },
    {
      "title": "Demand and Platform Management",
      "start": "June 9, 11, 17, 22, 24, 26 (2:30 p.m. - 5:30 p.m.)",
      "notes": "Prof. Hu Ming"
    },
    {
      "title": "Le Cam two-point method",
      "date": [
        "2026-06-29",
        "2026-06-30",
        "2026-07-03",
        "2026-07-06",
        "2026-07-08",
        "2026-07-10"
      ],
      "start": "09:00",
      "end": "12:00",
      "notes": "Prof. Zhou Zhengyuan"
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
assert len(events) == 18, len(events)
assert sum(event["title"] == "Paths to Research" for event in events) == 6
assert sum(event["title"] == "Demand and Platform Management" for event in events) == 6
assert sum(event["title"] == "Le Cam two-point method" for event in events) == 6
starts = [event["start"] for event in events]
assert "2026-05-27 09:00:00" in starts[0], starts[0]
assert any(start.startswith("2026-06-26 14:30:00") for start in starts), starts
assert any(start.startswith("2026-07-10 09:00:00") for start in starts), starts
' "${output_file}"
