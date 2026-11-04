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
Generate the project first with generate_project.sh if needed.
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
app_path="$PWD/build/DerivedData/Build/Products/$configuration/MacKit.app"

# Build and embed the system-hosted wallpaper provider.
mkdir -p build/WallpaperExtension/MacKitWallpaper.xcodeproj
# The companion app stays compatible with macOS 14; only the system-hosted
# wallpaper provider is a macOS 26+ ExtensionKit target.
python3 - <<'PY'
from pathlib import Path
import hashlib
root=Path.cwd()
def ident(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def q(s): return '"'+str(s).replace('\\','\\\\').replace('"','\\"')+'"'
files=sorted((root/'Extensions/Wallpaper').glob('*.swift')) + [root/'Packages/MacKitCore/Sources/MacKitCore/WallpaperRouting.swift', root/'Packages/MacKitCore/Sources/MacKitCore/WallpaperOcclusion.swift']
objects=[]
def add(key,body): objects.append(f'{ident(key)} = {{{body}}};')
refs=[]; builds=[]
for p in files:
 r='file:'+p.name;b='build:'+p.name;refs.append(ident(r));builds.append(ident(b))
 add(r,'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = '+q(p)+'; sourceTree = "<absolute>";')
 add(b,'isa = PBXBuildFile; fileRef = '+ident(r)+';')
add('product','isa = PBXFileReference; explicitFileType = "wrapper.extensionkit-extension"; path = MacKitWallpaper.appex; sourceTree = BUILT_PRODUCTS_DIR;')
add('group','isa = PBXGroup; children = ('+','.join(refs+[ident('product')])+'); sourceTree = "<group>";')
add('sources','isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ('+','.join(builds)+'); runOnlyForDeploymentPostprocessing = 0;')
add('frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
for mode in ['Debug','Release']:
 settings='CLANG_ENABLE_MODULES = YES; SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 26.0; SWIFT_VERSION = 6.0; CODE_SIGN_STYLE = Automatic; ENABLE_HARDENED_RUNTIME = YES; ENABLE_APP_SANDBOX = YES; GENERATE_INFOPLIST_FILE = YES; PRODUCT_NAME = MacKitWallpaper; PRODUCT_BUNDLE_IDENTIFIER = com.mackit.app.wallpaper.extension; INFOPLIST_KEY_CFBundleDisplayName = "MacKit-动态壁纸"; SKIP_INSTALL = YES; SWIFT_APPROACHABLE_CONCURRENCY = YES; SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES; '
 settings+='SWIFT_OPTIMIZATION_LEVEL = '+('"-O"' if mode=='Release' else '"-Onone"')+'; '
 settings+='INFOPLIST_FILE = '+q(root/'Extensions/Wallpaper/Info.plist')+'; SWIFT_OBJC_BRIDGING_HEADER = '+q(root/'Extensions/Wallpaper/WallpaperExtension-Bridging-Header.h')+';'
 add(mode,'isa = XCBuildConfiguration; baseConfigurationReference = '+ident('config')+'; buildSettings = {'+settings+'}; name = '+mode+';')
add('config','isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = '+q(root/'Config/Shared.xcconfig')+'; sourceTree = "<absolute>";')
add('configs','isa = XCConfigurationList; buildConfigurations = ('+ident('Debug')+','+ident('Release')+'); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
add('target','isa = PBXNativeTarget; buildConfigurationList = '+ident('configs')+'; buildPhases = ('+ident('sources')+','+ident('frameworks')+'); buildRules = (); dependencies = (); name = MacKitWallpaper; productName = MacKitWallpaper; productReference = '+ident('product')+'; productType = "com.apple.product-type.extensionkit-extension";')
add('project','isa = PBXProject; buildConfigurationList = '+ident('configs')+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en); mainGroup = '+ident('group')+'; projectDirPath = ""; projectRoot = ""; targets = ('+ident('target')+');')
Path('build/WallpaperExtension/MacKitWallpaper.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+'\n}; rootObject = '+ident('project')+';}')
PY
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
if [[ "$identity" == - ]]; then codesign --force --sign - "$app_path/Contents/Extensions/MacKitWallpaper.appex"; fi
mkdir -p "$app_path/Contents/Resources/Licenses"
ditto LICENSES "$app_path/Contents/Resources/Licenses"
ditto LICENSE "$app_path/Contents/Resources/Licenses/MacKit-LICENSE.txt"
ditto THIRD_PARTY_NOTICES.md "$app_path/Contents/Resources/THIRD_PARTY_NOTICES.md"
rm -rf "$app_path/Contents/Resources/ThirdParty-Licenses"
codesign --force --options runtime --sign "$identity" "$app_path"
codesign --verify --deep --strict "$app_path"
print "Built: $PWD/build/DerivedData/Build/Products/$configuration/MacKit.app"
