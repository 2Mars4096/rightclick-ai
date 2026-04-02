#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
fake_build_root="$(mktemp -d "${TMPDIR:-/tmp}/right-click-release-build.XXXXXX")"
fake_dist_root="$(mktemp -d "${TMPDIR:-/tmp}/right-click-release-dist.XXXXXX")"
fake_app_bundle="${fake_build_root}/RightClickApp.app"
archive_path="${fake_dist_root}/RightClickAI-macOS-0.1.0.zip"
trap 'rm -rf "${fake_build_root}" "${fake_dist_root}"' EXIT

mkdir -p "${fake_app_bundle}/Contents/MacOS"

cat > "${fake_app_bundle}/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>RightClickApp</string>
  <key>CFBundleIdentifier</key>
  <string>com.example.RightClickApp</string>
  <key>CFBundleName</key>
  <string>RightClick AI</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key>
      <dict>
        <key>default</key>
        <string>RightClick AI</string>
      </dict>
      <key>NSMessage</key>
      <string>captureSelectedText:userData:error:</string>
    </dict>
  </array>
</dict>
</plist>
EOF

printf '#!/bin/zsh\nexit 0\n' > "${fake_app_bundle}/Contents/MacOS/RightClickApp"
chmod +x "${fake_app_bundle}/Contents/MacOS/RightClickApp"

RCA_APP_BUNDLE="${fake_app_bundle}" \
RCA_BUILD_IF_MISSING=0 \
  "${repo_root}/scripts/release-preflight.sh" >/dev/null

package_output="$(
  RCA_APP_BUNDLE="${fake_app_bundle}" \
  RCA_BUILD_IF_MISSING=0 \
  RCA_RELEASE_DIR="${fake_dist_root}" \
    "${repo_root}/scripts/package-native-release.sh"
)"

printf '%s\n' "${package_output}"
[[ -f "${archive_path}" ]]
