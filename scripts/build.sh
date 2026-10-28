#!/bin/zsh
set -eu
configuration=Release
mode=--unsigned
for arg in "$@"; do
  case "$arg" in
    -h|--help|help)
      cat <<'HELP'
Usage: scripts/build.sh [Debug|Release] [--signed|--unsigned] [--help]
Build MacKit.app for Apple Silicon and Intel (default: Release, unsigned).
Output: build/DerivedData/Build/Products/<configuration>/MacKit.app
Requires Xcode. Generate the project first with generate_project.sh if needed.
Signed builds require DEVELOPMENT_TEAM in Config/Local.xcconfig.
HELP
      exit 0 ;;
    Debug|Release) configuration=$arg ;;
    --signed|--unsigned) mode=$arg ;;
    *) print -u2 "Unknown argument: $arg"; exit 2 ;;
  esac
done
cd "${0:A:h:h}"
[[ -f MacKit.xcodeproj/project.pbxproj ]] || { print -u2 'Run scripts/generate_project.sh first.'; exit 1; }
signing=(CODE_SIGNING_ALLOWED=NO)
if [[ "$mode" == --signed ]]; then
  [[ -f Config/Local.xcconfig ]] || { print -u2 'Set DEVELOPMENT_TEAM in Config/Local.xcconfig first.'; exit 2; }
  signing=(CODE_SIGN_STYLE=Automatic)
fi
xcodebuild -project MacKit.xcodeproj -scheme MacKit -configuration "$configuration" \
  -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO "${signing[@]}" build
print "Built: $PWD/build/DerivedData/Build/Products/$configuration/MacKit.app"
