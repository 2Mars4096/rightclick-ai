#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
input_file="$(mktemp "${TMPDIR:-/tmp}/right-click-calendar-lines.XXXXXX.txt")"
trap 'rm -f "${input_file}"' EXIT

cat > "${input_file}" <<'EOF'
4/6 20:15 笼民 KG

4/7 20:00 我的初恋赤裸裸 GL
4/12 19:15 诗佬正传之误人子弟 IS
EOF

rendered_prompt="$(
  /usr/bin/osascript -l JavaScript "${repo_root}/runtime/lib/tools.js" render-prompt \
    "${repo_root}/actions/add-to-calendar/prompt.txt" \
    "${input_file}" \
    "2026-04-02 12:00:00 +0800" \
    "Asia/Hong_Kong" \
    "60"
)"

printf '%s' "${rendered_prompt}" | /usr/bin/grep -F 'Non-empty line count: 3' >/dev/null
printf '%s' "${rendered_prompt}" | /usr/bin/grep -F '1. 4/6 20:15 笼民 KG' >/dev/null
printf '%s' "${rendered_prompt}" | /usr/bin/grep -F '2. 4/7 20:00 我的初恋赤裸裸 GL' >/dev/null
printf '%s' "${rendered_prompt}" | /usr/bin/grep -F '3. 4/12 19:15 诗佬正传之误人子弟 IS' >/dev/null
