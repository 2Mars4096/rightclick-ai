#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
input_file="$(mktemp "${TMPDIR:-/tmp}/right-click-calendar-table.XXXXXX.txt")"
trap 'rm -f "${input_file}"' EXIT

cat > "${input_file}" <<'EOF'
2
Prof. Hu Ming
Distinguished Professor of Business Operations and Analytics, Rotman School of Management, University of Toronto
June 9, 11, 17, 22, 24, 26
(2:30 p.m. - 5:30 p.m.)
Demand and Platform Management
3
Prof. Zhou Zhengyuan
Associate Professor, Department of Technology, Operations and Statistics, Stern School of Business, New York University
June 29, 30, July 3, 6, 8, 10
(9:00 a.m. - 12:00 p.m.)
Overview of Le Cam's two-point method and its applications to proving lower bounds for data-driven decision making problems.
EOF

rendered_prompt="$(
  /usr/bin/osascript -l JavaScript "${repo_root}/runtime/lib/tools.js" render-prompt \
    "${repo_root}/actions/add-to-calendar/prompt.txt" \
    "${input_file}" \
    "2026-05-15 12:00:00 +0800" \
    "Asia/Hong_Kong" \
    "60"
)"

printf '%s' "${rendered_prompt}" | /usr/bin/grep -F 'This table rule overrides the separate-line rule.' >/dev/null
printf '%s' "${rendered_prompt}" | /usr/bin/grep -F 'First identify candidate events or event groups, then expand dates inside each candidate independently.' >/dev/null
printf '%s' "${rendered_prompt}" | /usr/bin/grep -F 'two candidates with six dates each must produce twelve event objects' >/dev/null
printf '%s' "${rendered_prompt}" | /usr/bin/grep -F 'one single-date event plus one six-date event plus another single-date event must produce eight event objects' >/dev/null
printf '%s' "${rendered_prompt}" | /usr/bin/grep -F "Pair each candidate's dates and time range only with that candidate's title, topic, location, and notes." >/dev/null
printf '%s' "${rendered_prompt}" | /usr/bin/grep -F 'June 29, 30, July 3, 6, 8, 10' >/dev/null
