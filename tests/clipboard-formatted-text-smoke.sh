#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/right-click-clipboard-formatted.XXXXXX")"
trap 'rm -rf "${build_dir}"' EXIT

/usr/bin/xcrun swiftc \
  -o "${build_dir}/clipboard-formatted-text-smoke" \
  "${repo_root}/tests/clipboard-formatted-text-smoke.swift" \
  "${repo_root}/app/RightClickApp/Clipboard/ClipboardActionCompatibility.swift" \
  "${repo_root}/app/RightClickApp/Clipboard/ClipboardHistoryStore.swift" \
  "${repo_root}/app/RightClickApp/Clipboard/ClipboardItem.swift" \
  "${repo_root}/app/RightClickApp/Clipboard/ClipboardManager.swift" \
  "${repo_root}/app/RightClickApp/Clipboard/ClipboardPrivacyPolicy.swift"

"${build_dir}/clipboard-formatted-text-smoke"
