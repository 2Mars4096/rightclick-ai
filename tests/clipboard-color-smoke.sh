#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/right-click-clipboard-color.XXXXXX")"
trap 'rm -rf "${build_dir}"' EXIT

/usr/bin/xcrun swiftc \
  -module-cache-path "${build_dir}/ModuleCache" \
  -o "${build_dir}/clipboard-color-smoke" \
  "${repo_root}/tests/clipboard-color-smoke.swift" \
  "${repo_root}/app/RightClickApp/Clipboard/ClipboardActionCompatibility.swift" \
  "${repo_root}/app/RightClickApp/Clipboard/ClipboardHistoryStore.swift" \
  "${repo_root}/app/RightClickApp/Clipboard/ClipboardItem.swift" \
  "${repo_root}/app/RightClickApp/Clipboard/ClipboardManager.swift" \
  "${repo_root}/app/RightClickApp/Clipboard/ClipboardPrivacyPolicy.swift"

"${build_dir}/clipboard-color-smoke"
