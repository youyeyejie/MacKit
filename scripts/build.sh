#!/bin/zsh
set -eu
cd "${0:A:h:h}"
configuration=${1:-Debug}
case "$configuration" in Debug|Release) ;; *) print -u2 'Usage: scripts/build.sh [Debug|Release]'; exit 2 ;; esac
python3 scripts/generate_project.py
xcodebuild -project MacKit.xcodeproj -scheme MacKit -configuration "$configuration" \
  -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
