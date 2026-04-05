#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/right-click-clipboard-reference.XXXXXX")"
trap 'rm -rf "${build_dir}"' EXIT

/usr/bin/xcrun swiftc \
  -module-cache-path "${build_dir}/ModuleCache" \
  -o "${build_dir}/clipboard-reference-smoke" \
  "${repo_root}/tests/clipboard-reference-smoke.swift" \
  "${repo_root}/app/RightClickApp/Clipboard/ClipboardActionCompatibility.swift" \
  "${repo_root}/app/RightClickApp/Clipboard/ClipboardItem.swift"

"${build_dir}/clipboard-reference-smoke"
