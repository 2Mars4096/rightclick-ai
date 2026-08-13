#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
plist_path="${repo_root}/app/RightClickApp/Resources/Info.plist"
plist_buddy="/usr/libexec/PlistBuddy"

[[ "$("${plist_buddy}" -c 'Print :NSServices:1:NSMenuItem:default' "${plist_path}")" == "Open Paper & Notes" ]]
[[ "$("${plist_buddy}" -c 'Print :NSServices:1:NSMessage' "${plist_path}")" == "openPaperAndNotes:userData:error:" ]]
[[ "$("${plist_buddy}" -c 'Print :NSServices:1:NSRequiredContext:NSApplicationIdentifier' "${plist_path}")" == "com.apple.finder" ]]
[[ "$("${plist_buddy}" -c 'Print :NSServices:1:NSSendFileTypes:0' "${plist_path}")" == "com.adobe.pdf" ]]

printf 'Finder paper service smoke passed.\n'
