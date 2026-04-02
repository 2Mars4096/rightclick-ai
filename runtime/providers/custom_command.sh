#!/bin/zsh

set -euo pipefail

prompt_file="$1"
output_file="$2"
response_file="$3"

if [[ -z "${CUSTOM_PROVIDER_COMMAND:-}" ]]; then
  print -r -- "CUSTOM_PROVIDER_COMMAND is empty in settings.env." >&2
  exit 1
fi

if ! /bin/zsh -lc "${CUSTOM_PROVIDER_COMMAND}" < "${prompt_file}" > "${output_file}"; then
  print -r -- "CUSTOM_PROVIDER_COMMAND failed." >&2
  exit 1
fi

printf '%s\n' "custom-command" > "${response_file}"
