#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_home="$(mktemp -d "${TMPDIR:-/tmp}/right-click-native-home.XXXXXX")"
fake_build_root="$(mktemp -d "${TMPDIR:-/tmp}/right-click-native-build.XXXXXX")"
fake_app_bundle="${fake_build_root}/RightClickApp.app"
installed_app="${test_home}/Applications/RightClick AI.app"
runtime_root="${test_home}/Library/Application Support/RightClickAI"
direct_workflow="${test_home}/Library/Services/Add to Calendar.workflow/Contents/document.wflow"
trap 'rm -rf "${test_home}" "${fake_build_root}"' EXIT

mkdir -p "${fake_app_bundle}/Contents/MacOS"

cat > "${fake_app_bundle}/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.example.RightClickApp</string>
  <key>CFBundleName</key>
  <string>RightClick AI</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
</dict>
</plist>
EOF

printf '#!/bin/zsh\nexit 0\n' > "${fake_app_bundle}/Contents/MacOS/RightClickApp"
chmod +x "${fake_app_bundle}/Contents/MacOS/RightClickApp"

RCA_HOME="${test_home}" \
RCA_APP_BUNDLE="${fake_app_bundle}" \
RCA_SKIP_PBS=1 \
RCA_OPEN_APP_AFTER_INSTALL=0 \
  "${repo_root}/scripts/install-native-app.sh" >/dev/null

[[ -d "${installed_app}" ]]
[[ -f "${installed_app}/Contents/Info.plist" ]]
[[ -x "${runtime_root}/bin/right-click-action" ]]
[[ -f "${direct_workflow}" ]]
/usr/bin/grep -F "${test_home}/Library/Application Support/RightClickAI/bin/right-click-calendar" "${direct_workflow}" >/dev/null
