#!/bin/zsh

set -euo pipefail

prompt_file="$1"
output_file="$2"
response_file="$3"
script_dir="$(cd "$(dirname "$0")" && pwd)"
install_root="${INSTALL_ROOT:-$(cd "${script_dir}/.." && pwd)}"
tools_js="${install_root}/lib/tools.js"
source "${install_root}/lib/runtime-common.sh"
payload_file="$(mktemp "${TMPDIR:-/tmp}/rc-anthropic-payload.XXXXXX")"
trap 'rm -f "${payload_file}"' EXIT

rc_resolve_secret ANTHROPIC_API_KEY || true
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  print -r -- "ANTHROPIC_API_KEY is empty in settings.env and Keychain." >&2
  exit 1
fi

if [[ -z "${ANTHROPIC_MODEL:-}" ]]; then
  print -r -- "ANTHROPIC_MODEL is empty in settings.env." >&2
  exit 1
fi

/usr/bin/osascript -l JavaScript "${tools_js}" build-anthropic-payload "${prompt_file}" "${ANTHROPIC_MODEL}" "${RC_ACTION_SYSTEM_PROMPT:-}" > "${payload_file}"

http_code="$(
  /usr/bin/curl \
    --silent \
    --show-error \
    --connect-timeout "${REQUEST_TIMEOUT_SECONDS:-120}" \
    --max-time "${REQUEST_TIMEOUT_SECONDS:-120}" \
    -H "Content-Type: application/json" \
    -H "x-api-key: ${ANTHROPIC_API_KEY}" \
    -H "anthropic-version: ${ANTHROPIC_VERSION:-2023-06-01}" \
    -o "${response_file}" \
    -w "%{http_code}" \
    -X POST \
    "${ANTHROPIC_API_URL}" \
    --data-binary "@${payload_file}"
)"

if [[ "${http_code}" != 2* ]]; then
  error_message="$(/usr/bin/plutil -extract error.message raw -o - "${response_file}" 2>/dev/null || true)"
  if [[ -z "${error_message}" ]]; then
    error_message="$(/bin/cat "${response_file}" 2>/dev/null || true)"
  fi
  print -r -- "Anthropic request failed with HTTP ${http_code}: ${error_message}" >&2
  exit 1
fi

content="$(
  /usr/bin/plutil -extract content.0.text raw -o - "${response_file}" 2>/dev/null ||
  true
)"

if [[ -z "${content}" ]]; then
  print -r -- "The Anthropic response did not include content[0].text." >&2
  exit 1
fi

printf '%s' "${content}" > "${output_file}"
