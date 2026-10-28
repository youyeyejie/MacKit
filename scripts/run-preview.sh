#!/bin/zsh
# Local ad-hoc preview only. Finder App Group access needs a real development team.
set -eu
cd "${0:A:h:h}"
app_path="$PWD/build/DerivedData/Build/Products/Debug/MacKit.app"
if [[ ! -d "$app_path" ]]; then scripts/build.sh Debug; fi
codesign --force --sign - "$app_path/Contents/PlugIns/MacKitFinderExtension.appex"
codesign --force --sign - "$app_path"
open "$app_path"
