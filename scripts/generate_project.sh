#!/bin/zsh
# Generate a standard Xcode project using zsh and macOS system utilities.
set -eu
case "${1:-}" in
  -h|--help|help)
    cat <<'HELP'
Usage: scripts/generate_project.sh [--help]
Generate MacKit.xcodeproj from Swift sources, Config and app resources.
Uses zsh and macOS system utilities; no Python or third-party dependencies.
Overwrites project.pbxproj and the shared MacKit scheme.
HELP
    exit 0 ;;
  "") ;;
  *) print -u2 "Unknown argument: $1"; exit 2 ;;
esac
(( $# == 0 )) || { print -u2 'Too many arguments'; exit 2; }
cd "${0:A:h:h}"
setopt nullglob
sources=(MacKit/**/*.swift Packages/MacKitCore/Sources/MacKitCore/*.swift)
resources=(MacKit/*.xcassets MacKit/Resources/*)
configs=(Config/*)
configs=(${configs:#Config/Local.xcconfig})
files=("${sources[@]}" "${resources[@]}" "${configs[@]}")
files=("${(@ou)files}")
(( ${#sources} > 0 )) || { print -u2 'No Swift sources found'; exit 1; }
# Stable IDs keep generated diffs small.
id() { local digest; digest=$(print -rn -- "$1" | shasum -a 1); print -rn -- "${(U)digest[1,24]}"; }
quote() { local value=$1; value=${value//\\/\\\\}; value=${value//\"/\\\"}; print -rn -- "\"$value\""; }
project_id=$(id project)
target_id=$(id target:MacKit)
product_id=$(id product:MacKit)
shared_id=$(id file:Config/Shared.xcconfig)
mkdir -p MacKit.xcodeproj/xcshareddata/xcschemes
work=$(mktemp -d "${TMPDIR:-/tmp}/mackit-project.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
{
  print -r -- '// !$*UTF8*$!'
  print -r -- '{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {'
  for file in "${files[@]}"; do
    case "$file" in
      *.swift) kind=sourcecode.swift ;;
      *.xcassets) kind=folder.assetcatalog ;;
      *.wav) kind=audio.wav ;;
      *.xcconfig) kind=text.xcconfig ;;
      *.plist) kind=text.plist.xml ;;
      *) kind=file ;;
    esac
    print -r -- "$(id file:$file) = {isa = PBXFileReference; lastKnownFileType = $kind; path = $(quote "$file"); sourceTree = SOURCE_ROOT;};"
  done
  print -r -- "$product_id = {isa = PBXFileReference; explicitFileType = wrapper.application; path = MacKit.app; sourceTree = BUILT_PRODUCTS_DIR;};"
  print -r -- "$(id products) = {isa = PBXGroup; name = Products; children = ($product_id,); sourceTree = \"<group>\";};"
  print -rn -- "$(id mainGroup) = {isa = PBXGroup; children = ("
  for file in "${files[@]}"; do print -rn -- "$(id file:$file),"; done
  print -r -- "$(id products),); sourceTree = \"<group>\";};"
  for scope in project MacKit; do
    for configuration in Debug Release; do
      if [[ "$configuration" == Debug ]]; then
        extra='SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; ONLY_ACTIVE_ARCH = YES; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;'
      else
        extra='SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
      fi
      if [[ "$scope" == project ]]; then
        settings='CLANG_ENABLE_MODULES = YES; SDKROOT = macosx;'
      else
        settings='PRODUCT_NAME = MacKit; PRODUCT_BUNDLE_IDENTIFIER = com.mackit.app; INFOPLIST_FILE = "Config/MacKit-Info.plist"; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks"; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;'
      fi
      print -r -- "$(id $scope$configuration) = {isa = XCBuildConfiguration; baseConfigurationReference = $shared_id; buildSettings = {$settings $extra}; name = $configuration;};"
    done
    print -r -- "$(id ${scope}configs) = {isa = XCConfigurationList; buildConfigurations = ($(id ${scope}Debug),$(id ${scope}Release),); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};"
  done
  for file in "${sources[@]}"; do
    print -r -- "$(id MacKit:$file) = {isa = PBXBuildFile; fileRef = $(id file:$file);};"
  done
  print -rn -- "$(id MacKitsources) = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ("
  for file in "${sources[@]}"; do print -rn -- "$(id MacKit:$file),"; done
  print -r -- '); runOnlyForDeploymentPostprocessing = 0;};'
  print -r -- "$(id MacKitframeworks) = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;};"
  for file in "${resources[@]}"; do
    print -r -- "$(id resource:$file) = {isa = PBXBuildFile; fileRef = $(id file:$file);};"
  done
  print -rn -- "$(id appResources) = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ("
  for file in "${resources[@]}"; do print -rn -- "$(id resource:$file),"; done
  print -r -- '); runOnlyForDeploymentPostprocessing = 0;};'
  print -r -- "$target_id = {isa = PBXNativeTarget; buildConfigurationList = $(id MacKitconfigs); buildPhases = ($(id MacKitsources),$(id MacKitframeworks),$(id appResources),); buildRules = (); dependencies = (); name = MacKit; productName = MacKit; productReference = $product_id; productType = \"com.apple.product-type.application\";};"
  print -r -- "$project_id = {isa = PBXProject; attributes = {LastSwiftUpdateCheck = 2700; LastUpgradeCheck = 2700;}; buildConfigurationList = $(id projectconfigs); compatibilityVersion = \"Xcode 14.0\"; developmentRegion = zh-Hans; hasScannedForEncodings = 0; knownRegions = (en,\"zh-Hans\",Base); mainGroup = $(id mainGroup); productRefGroup = $(id products); projectDirPath = \"\"; projectRoot = \"\"; targets = ($target_id,);};"
  print -r -- "}; rootObject = $project_id; }"
} > "$work/project.pbxproj"
ref="<BuildableReference BuildableIdentifier=\"primary\" BlueprintIdentifier=\"$target_id\" BuildableName=\"MacKit.app\" BlueprintName=\"MacKit\" ReferencedContainer=\"container:MacKit.xcodeproj\"/>"
cat > "$work/MacKit.xcscheme" <<SCHEME
<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">$ref</BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">$ref</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">$ref</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
SCHEME
plutil -lint "$work/project.pbxproj" >/dev/null
mv "$work/project.pbxproj" MacKit.xcodeproj/project.pbxproj
mv "$work/MacKit.xcscheme" MacKit.xcodeproj/xcshareddata/xcschemes/MacKit.xcscheme
print "Generated MacKit.xcodeproj: ${#sources} sources, ${#resources} resources"
