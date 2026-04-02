#!/bin/zsh

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
install_root="${script_dir}"
user_home="$(cd "${install_root}/../../.." && pwd)"
service_name="Add to Calendar"
workflow_path="${user_home}/Library/Services/${service_name}.workflow"

rm -rf "${install_root}"
rm -rf "${workflow_path}"
/System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true
printf 'Removed %s.\n' "${service_name}"
