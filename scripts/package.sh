#!/bin/zsh
set -eu
app_path=''
for arg in "$@"; do
  case "$arg" in
    -h|--help|help)
      cat <<'HELP'
Usage: scripts/package.sh [path/to/MacKit.app] [--help]
Package an existing app as a compressed DMG with an Applications shortcut.
Default input: build/DerivedData/Build/Products/Release/MacKit.app
Output: dist/MacKit-<version>-macOS.dmg and .sha256
Build first with scripts/build.sh. Existing output files are never overwritten.
Requires macOS hdiutil. A signed app keeps its signature; an unsigned copy is ad-hoc signed.
HELP
      exit 0 ;;
    -*) print -u2 "Unknown argument: $arg"; exit 2 ;;
    *) [[ -z "$app_path" ]] || { print -u2 'Only one app path is accepted.'; exit 2; }; app_path=${arg:A} ;;
  esac
done
cd "${0:A:h:h}"
app_path=${app_path:-$PWD/build/DerivedData/Build/Products/Release/MacKit.app}
[[ -d "$app_path" ]] || { print -u2 "App not found: $app_path"; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
[[ "$version" == [0-9]* && "$version" != *[^a-zA-Z0-9.-]* ]] || { print -u2 'Invalid app version'; exit 1; }
mkdir -p dist
output="$PWD/dist/MacKit-$version-macOS.dmg"
[[ ! -e "$output" && ! -e "$output.sha256" ]] || { print -u2 "Output already exists: $output"; exit 1; }
staging=$(mktemp -d "${TMPDIR:-/tmp}/mackit-dmg.XXXXXX")
trap 'rm -rf -- "$staging"' EXIT
mkdir "$staging/content"
ditto "$app_path" "$staging/content/MacKit.app"
if [[ ! -d "$staging/content/MacKit.app/Contents/_CodeSignature" ]]; then
  codesign --force --sign - "$staging/content/MacKit.app"
fi
codesign --verify --deep --strict "$staging/content/MacKit.app"
ln -s /Applications "$staging/content/Applications"
hdiutil create -volname MacKit -srcfolder "$staging/content" -format UDZO "$staging/MacKit.dmg"
hdiutil verify "$staging/MacKit.dmg"
mv -n "$staging/MacKit.dmg" "$output"
(cd dist && shasum -a 256 "${output:t}" > "${output:t}.sha256")
print "Packaged: $output"
