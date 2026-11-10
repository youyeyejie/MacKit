#!/bin/zsh
set -eu
configuration=Release
mode=--signed
for arg in "$@"; do
  case "$arg" in
    -h|--help|help)
      cat <<'HELP'
Usage: scripts/build.sh [Debug|Release] [--signed|--unsigned] [--help]
Build MacKit.app for Apple Silicon and Intel (default: Release, signed).
Output: build/DerivedData/Build/Products/<configuration>/MacKit.app
Requires Xcode and Python 3. Builds the app and native wallpaper extension.
The application project is regenerated automatically.
Signed builds require DEVELOPMENT_TEAM in Config/Local.xcconfig.
HELP
      exit 0 ;;
    Debug|Release) configuration=$arg ;;
    --signed|--unsigned) mode=$arg ;;
    *) print -u2 "Unknown argument: $arg"; exit 2 ;;
  esac
done
cd "${0:A:h:h}"
scripts/generate_project.sh
signing=(CODE_SIGNING_ALLOWED=NO)
if [[ "$mode" == --signed ]]; then
  [[ -f Config/Local.xcconfig ]] || { print -u2 'Set DEVELOPMENT_TEAM in Config/Local.xcconfig first.'; exit 2; }
  signing=(CODE_SIGN_STYLE=Automatic)
fi
xcodebuild -project MacKit.xcodeproj -scheme MacKit -configuration "$configuration" \
  -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO "${signing[@]}" build
app_path="$PWD/build/DerivedData/Build/Products/$configuration/MacKit.app"

# Build and embed the system-hosted wallpaper provider.
mkdir -p build/WallpaperExtension/MacKitWallpaper.xcodeproj
# The companion app stays compatible with macOS 14; only the system-hosted
# wallpaper provider is a macOS 26+ ExtensionKit target.
python3 scripts/generate_wallpaper_project.py
identity=$(codesign -dv --verbose=2 "$app_path" 2>&1 | sed -n 's/^Authority=//p' | head -1)
signing=(CODE_SIGN_STYLE=Automatic)
if [[ "$mode" == --unsigned ]]; then
  signing=(CODE_SIGNING_ALLOWED=NO)
  identity=-
elif [[ -z "$identity" ]]; then
  print -u2 'The signed app has no certificate identity; refusing an ad-hoc fallback.'
  exit 1
fi
xcodebuild -project build/WallpaperExtension/MacKitWallpaper.xcodeproj -scheme MacKitWallpaper -configuration "$configuration" \
  -derivedDataPath "$PWD/build/WallpaperExtension/DerivedData" 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO "${signing[@]}" build
extension="$PWD/build/WallpaperExtension/DerivedData/Build/Products/$configuration/MacKitWallpaper.appex"
mkdir -p "$app_path/Contents/Extensions"
ditto "$extension" "$app_path/Contents/Extensions/MacKitWallpaper.appex"
if [[ "$identity" == - ]]; then
  # Xcode Debug builds may emit a separate executable dylib.
  for library in "$app_path"/Contents/MacOS/*.dylib(N) "$app_path"/Contents/Extensions/MacKitWallpaper.appex/Contents/MacOS/*.dylib(N); do
    codesign --force --sign - "$library"
  done
  codesign --force --sign - "$app_path/Contents/Extensions/MacKitWallpaper.appex"
fi
rm -rf "$app_path/Contents/Frameworks/Sparkle.framework"
rm -rf "$app_path/Contents/Resources/Licenses"
mkdir -p "$app_path/Contents/Resources/Licenses"
ditto LICENSES "$app_path/Contents/Resources/Licenses"
ditto LICENSE "$app_path/Contents/Resources/Licenses/MacKit-LICENSE.txt"
ditto THIRD_PARTY_NOTICES.md "$app_path/Contents/Resources/THIRD_PARTY_NOTICES.md"
rm -rf "$app_path/Contents/Resources/ThirdParty-Licenses"
# Remove the obsolete compatibility probe from incremental build products.
# The adapter is dynamically loaded from Resources by the upstream Perl bridge.
# Sign it explicitly with the host identity before sealing the outer application.
adapter="$app_path/Contents/Resources/MediaRemoteAdapter.framework"
rm -rf "$adapter"
ditto Vendor/MediaRemoteAdapter.framework "$adapter"
codesign --force --options runtime --sign "$identity" "$adapter"
if [[ "$identity" == - ]]; then
  for framework in "$app_path"/Contents/Frameworks/*.framework(N); do
    codesign --force --sign - "$framework"
  done
fi
codesign --force --options runtime --entitlements Config/MacKit.entitlements --sign "$identity" "$app_path"
codesign --verify --deep --strict "$app_path"
print "Built: $PWD/build/DerivedData/Build/Products/$configuration/MacKit.app"
