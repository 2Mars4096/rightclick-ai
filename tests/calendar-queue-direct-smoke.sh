#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/right-click-calendar-direct-queue.XXXXXX")"
log_file="${test_root}/processed.log"
trap 'rm -rf "${test_root}"' EXIT

mkdir -p "${test_root}/bin" "${test_root}/lib"
cp "${repo_root}/runtime/bin/right-click-calendar" "${test_root}/bin/right-click-calendar"
cp "${repo_root}/runtime/lib/runtime-common.sh" "${test_root}/lib/runtime-common.sh"

cat > "${test_root}/bin/right-click-action" <<'EOF'
#!/bin/zsh

set -euo pipefail

printf '%s\n' "$*" >> "${RCA_FAKE_ACTION_LOG}"
cat >> "${RCA_FAKE_ACTION_LOG}"
sleep "${RCA_FAKE_ACTION_DELAY:-0}"
printf '\n--\n' >> "${RCA_FAKE_ACTION_LOG}"
EOF

chmod +x "${test_root}/bin/right-click-calendar" "${test_root}/bin/right-click-action"

export RCA_FAKE_ACTION_LOG="${log_file}"
export RCA_FAKE_ACTION_DELAY=1

printf 'first event' | "${test_root}/bin/right-click-calendar" >/dev/null &
first_pid=$!
sleep 0.2
printf 'second event' | "${test_root}/bin/right-click-calendar" >/dev/null
wait "${first_pid}"

[[ -z "$(find "${test_root}/queue/add-to-calendar-v2/pending" -type f -print -quit)" ]]
/usr/bin/grep -F $'add-to-calendar\nfirst event\n--\nadd-to-calendar\nsecond event' "${log_file}" >/dev/null
