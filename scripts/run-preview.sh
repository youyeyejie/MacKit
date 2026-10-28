#!/bin/zsh
set -eu
cd "${0:A:h:h}"
installed="$HOME/Applications/MacKit.app"
signed="$PWD/build/SignedPreview/Build/Products/Debug/MacKit.app"
if [[ -d "$installed" ]]; then open "$installed"; exit; fi
if [[ -d "$signed" ]]; then open "$signed"; exit; fi
app_path="$PWD/build/DerivedData/Build/Products/Debug/MacKit.app"
[[ -d "$app_path" ]] || scripts/build.sh Debug
# Do not re-sign developer-signed builds.
codesign --force --sign - "$app_path"
open "$app_path"
