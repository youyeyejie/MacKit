#!/bin/zsh
# Build and package a universal Release application.
set -eu
cd "${0:A:h:h}"
mode=${1:---unsigned}
scripts/build.sh Release "$mode"
source_app="$PWD/build/DerivedData/Build/Products/Release/MacKit.app"
output_dir="$PWD/dist"
mkdir -p "$output_dir"
if [[ -e "$output_dir/MacKit.app" ]]; then
  print -u2 'dist/MacKit.app already exists. Move it aside before packaging again.'
  exit 2
fi
ditto "$source_app" "$output_dir/MacKit.app"
if [[ "$mode" == '--unsigned' ]]; then
  codesign --force --sign - "$output_dir/MacKit.app"
fi
codesign --verify --deep --strict "$output_dir/MacKit.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$output_dir/MacKit.app/Contents/Info.plist")
archive="MacKit-$version-macOS-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$output_dir/MacKit.app" "$output_dir/$archive"
(cd "$output_dir" && shasum -a 256 "$archive" > "$archive.sha256")
print "Packaged: $output_dir/$archive"
