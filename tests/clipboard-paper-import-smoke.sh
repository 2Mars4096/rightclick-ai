#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/right-click-paper-import.XXXXXX")"
trap 'rm -rf "${build_dir}"' EXIT

/usr/bin/xcrun swiftc \
  -module-cache-path "${build_dir}/ModuleCache" \
  -o "${build_dir}/clipboard-paper-import-smoke" \
  "${repo_root}/tests/clipboard-paper-import-smoke.swift" \
  "${repo_root}/app/RightClickApp/Clipboard/ClipboardActionCompatibility.swift" \
  "${repo_root}/app/RightClickApp/Clipboard/ClipboardItem.swift"

"${build_dir}/clipboard-paper-import-smoke"
