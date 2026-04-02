#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/right-click-keychain.XXXXXX")"
security_log="${test_root}/security.log"
fake_security="${test_root}/security"
trap 'rm -rf "${test_root}"' EXIT

cat > "${fake_security}" <<'EOF'
#!/bin/zsh

set -euo pipefail

command_name="${1:-}"
shift || true

if [[ "${command_name}" != "find-generic-password" ]]; then
  print -r -- "Unexpected security command: ${command_name}" >&2
  exit 1
fi

service=""
account=""

while (( $# > 0 )); do
  case "$1" in
    -w)
      shift
      ;;
    -s)
      service="$2"
      shift 2
      ;;
    -a)
      account="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

printf '%s|%s\n' "${service}" "${account}" >> "${RC_FAKE_SECURITY_LOG}"

case "${account}" in
  OPENAI_API_KEY)
    printf '%s' 'keychain-openai-secret'
    ;;
  ANTHROPIC_API_KEY)
    printf '%s' 'keychain-anthropic-secret'
    ;;
  GEMINI_API_KEY)
    printf '%s' 'keychain-gemini-secret'
    ;;
  *)
    exit 44
    ;;
esac
EOF

chmod +x "${fake_security}"

export RC_FAKE_SECURITY_LOG="${security_log}"
export RC_SECURITY_BIN="${fake_security}"
export RC_INSTALL_ROOT="${test_root}/Runtime Root"
mkdir -p "${RC_INSTALL_ROOT}"

source "${repo_root}/runtime/lib/runtime-common.sh"

unset OPENAI_API_KEY
rc_resolve_secret OPENAI_API_KEY
[[ "${OPENAI_API_KEY}" == "keychain-openai-secret" ]]
/usr/bin/grep -F "RightClickAI:${RC_INSTALL_ROOT}|OPENAI_API_KEY" "${security_log}" >/dev/null

: > "${security_log}"
export OPENAI_API_KEY="plain-env-secret"
rc_resolve_secret OPENAI_API_KEY
[[ "${OPENAI_API_KEY}" == "plain-env-secret" ]]
[[ ! -s "${security_log}" ]]

unset MISSING_SECRET
if rc_resolve_secret MISSING_SECRET; then
  print -r -- "Expected missing secret lookup to fail." >&2
  exit 1
fi
