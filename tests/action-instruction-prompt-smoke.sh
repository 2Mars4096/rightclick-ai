#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
input_file="$(mktemp "${TMPDIR:-/tmp}/right-click-instruction-input.XXXXXX.txt")"
trap 'rm -f "${input_file}"' EXIT

cat > "${input_file}" <<'EOF'
Please confirm whether we can move the meeting to Friday afternoon.
EOF

rendered_prompt="$(
  /usr/bin/osascript -l JavaScript "${repo_root}/runtime/lib/tools.js" render-prompt \
    "${repo_root}/actions/draft-response/prompt.txt" \
    "${input_file}" \
    "2026-04-02 12:00:00 +0800" \
    "Asia/Hong_Kong" \
    "60" \
    "Keep it warm and under three sentences."
)"

printf '%s' "${rendered_prompt}" | /usr/bin/grep -F 'Optional user instruction: Keep it warm and under three sentences.' >/dev/null
printf '%s' "${rendered_prompt}" | /usr/bin/grep -F 'Please confirm whether we can move the meeting to Friday afternoon.' >/dev/null
