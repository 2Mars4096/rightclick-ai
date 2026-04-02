#!/bin/zsh

set -euo pipefail

prompt_file="$1"
output_file="$2"
response_file="$3"
script_dir="$(cd "$(dirname "$0")" && pwd)"
install_root="${INSTALL_ROOT:-$(cd "${script_dir}/.." && pwd)}"
tools_js="${install_root}/lib/tools.js"
source "${install_root}/lib/runtime-common.sh"
payload_file="$(mktemp "${TMPDIR:-/tmp}/rc-openai-payload.XXXXXX")"
trap 'rm -f "${payload_file}"' EXIT

rc_resolve_secret OPENAI_API_KEY || true
if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  print -r -- "OPENAI_API_KEY is empty in settings.env and Keychain." >&2
  exit 1
fi

if [[ -z "${OPENAI_MODEL:-}" ]]; then
  print -r -- "OPENAI_MODEL is empty in settings.env." >&2
  exit 1
fi

openai_temperature="${OPENAI_TEMPERATURE:-0.1}"
/usr/bin/osascript -l JavaScript "${tools_js}" build-openai-chat-payload "${prompt_file}" "${OPENAI_MODEL}" "${RC_ACTION_SYSTEM_PROMPT:-}" "${openai_temperature}" > "${payload_file}"

auth_header="${OPENAI_AUTH_HEADER:-Authorization}"
auth_scheme="${OPENAI_AUTH_SCHEME:-Bearer}"
auth_value="${OPENAI_API_KEY}"
if [[ -n "${auth_scheme}" ]]; then
  auth_value="${auth_scheme} ${auth_value}"
fi

http_code="$(
  /usr/bin/curl \
    --silent \
    --show-error \
    --connect-timeout "${REQUEST_TIMEOUT_SECONDS:-120}" \
    --max-time "${REQUEST_TIMEOUT_SECONDS:-120}" \
    -H "Content-Type: application/json" \
    -H "${auth_header}: ${auth_value}" \
    -o "${response_file}" \
    -w "%{http_code}" \
    -X POST \
    "${OPENAI_API_URL}" \
    --data-binary "@${payload_file}"
)"

if [[ "${http_code}" != 2* ]]; then
  error_message="$(/usr/bin/plutil -extract error.message raw -o - "${response_file}" 2>/dev/null || true)"
  if [[ -z "${error_message}" ]]; then
    error_message="$(/bin/cat "${response_file}" 2>/dev/null || true)"
  fi
  print -r -- "OpenAI-compatible request failed with HTTP ${http_code}: ${error_message}" >&2
  exit 1
fi

content="$(
  /usr/bin/plutil -extract choices.0.message.content raw -o - "${response_file}" 2>/dev/null ||
  /usr/bin/plutil -extract choices.0.message.content.0.text raw -o - "${response_file}" 2>/dev/null ||
  true
)"

if [[ -z "${content}" ]]; then
  print -r -- "The OpenAI-compatible response did not include choices[0].message.content." >&2
  exit 1
fi

printf '%s' "${content}" > "${output_file}"
