#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
fake_tool_root="$(mktemp -d "${TMPDIR:-/tmp}/right-click-build-tool.XXXXXX")"
fake_xcodebuild="${fake_tool_root}/xcodebuild"
output_root="$(mktemp -d "${TMPDIR:-/tmp}/right-click-build-output.XXXXXX")"
derived_data_root="$(mktemp -d "${TMPDIR:-/tmp}/right-click-build-derived.XXXXXX")"
trap 'rm -rf "${fake_tool_root}" "${output_root}" "${derived_data_root}"' EXIT

cat > "${fake_xcodebuild}" <<'EOF'
#!/bin/zsh

set -euo pipefail

derived_data=""
configuration="Release"

while (( $# > 0 )); do
  case "$1" in
    -derivedDataPath)
      derived_data="$2"
      shift 2
      ;;
    -configuration)
      configuration="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

mkdir -p "${derived_data}/Build/Products/${configuration}/RightClickApp.app/Contents/MacOS"
cat > "${derived_data}/Build/Products/${configuration}/RightClickApp.app/Contents/Info.plist" <<'PLIST'
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
PLIST
printf '#!/bin/zsh\nexit 0\n' > "${derived_data}/Build/Products/${configuration}/RightClickApp.app/Contents/MacOS/RightClickApp"
chmod +x "${derived_data}/Build/Products/${configuration}/RightClickApp.app/Contents/MacOS/RightClickApp"
EOF

chmod +x "${fake_xcodebuild}"

build_output="$(
  RCA_XCODEBUILD_BIN="${fake_xcodebuild}" \
  RCA_BUILD_OUTPUT_ROOT="${output_root}" \
  RCA_DERIVED_DATA_PATH="${derived_data_root}" \
    "${repo_root}/scripts/build-native-app.sh"
)"

[[ "${build_output}" == "${output_root}/RightClickApp.app" ]]
[[ -f "${output_root}/RightClickApp.app/Contents/Info.plist" ]]
