#!/bin/zsh
set -eu
cd "${0:A:h:h}"
configuration=${1:-Debug}
mode=${2:---unsigned}
case "$configuration" in Debug|Release) ;; *) print -u2 'Usage: scripts/build.sh [Debug|Release] [--signed|--unsigned]'; exit 2 ;; esac
python3 scripts/generate_project.py
if [[ "$mode" == '--signed' ]]; then
  [[ -f Config/Local.xcconfig ]] || { print -u2 'Set DEVELOPMENT_TEAM in Config/Local.xcconfig first.'; exit 2; }
  xcodebuild -project MacKit.xcodeproj -scheme MacKit -configuration "$configuration" \
    -destination 'generic/platform=macOS' -derivedDataPath build/SignedPreview \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Apple Development' build
elif [[ "$mode" == '--unsigned' ]]; then
  xcodebuild -project MacKit.xcodeproj -scheme MacKit -configuration "$configuration" \
    -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
    CODE_SIGNING_ALLOWED=NO build
else
  print -u2 'Unknown signing mode.'; exit 2
fi
