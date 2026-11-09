#!/bin/zsh
# Regenerate the single MacKit application target with the integrated notch runtime.
set -eu
cd "${0:A:h:h}"
case "${1:-}" in
  -h|--help|help) print 'Usage: scripts/generate_project.sh (requires Python 3 and Xcode)'; exit 0;;
  '') ;;
  *) print -u2 "Unknown argument: $1"; exit 2;;
esac
python3 - <<'MACKIT_PROJECT_GENERATOR'
"""Generate one app, one lifecycle, and one settings window from both source trees.

Keep upstream's package graph and synchronized groups, while adding MacKit's
sources explicitly. No helper Atoll application is launched or embedded.
"""
from pathlib import Path
import hashlib
import json
import plistlib
import subprocess

root = Path.cwd()
upstream = root / 'MacKit/Features/NotchRuntime'
project = json.loads(subprocess.check_output([
    'plutil', '-convert', 'json', '-o', '-',
    str(root / 'Config/RuntimeProject.pbxproj')]))
objects = project['objects']
app_id = 'F54406E62CD4987A00C7AFD9'
app = objects[app_id]
project_object = objects[project['rootObject']]
project_object['targets'] = [app_id]
project_object['developmentRegion'] = 'zh-Hans'
project_object['packageReferences'] = [k for k in project_object['packageReferences'] if objects[k].get('repositoryURL') != 'https://github.com/open-meteo/open-meteo']
project_object['knownRegions'] = ['en', 'zh-Hans', 'Base']
project_object['attributes'].pop('TargetAttributes', None)
app['name'] = app['productName'] = 'MacKit'
objects[app['productReference']]['path'] = 'MacKit.app'
for obj in objects.values():
    if 'children' in obj:
        obj['children'] = [v for v in obj['children'] if v in objects]
    if obj.get('isa') == 'PBXFileSystemSynchronizedRootGroup' or (
        obj.get('isa') == 'PBXGroup' and obj.get('path') in ['mediaremote-adapter', 'LottieAnimations']
    ) or (obj.get('isa') == 'PBXFileReference' and obj.get('path') == 'Frameworks/MediaRemoteAdapter.framework'):
        obj['path'] = 'MacKit/Features/NotchRuntime/' + obj['path']
        obj['sourceTree'] = 'SOURCE_ROOT'
# These two host-owned asset sets must never collide with MacKit's app icon/accent.
exceptions = objects['7EA69B212F5B100000EB2D16']['membershipExceptions']
exceptions.extend(['Assets.xcassets/AppIcon.appiconset', 'Assets.xcassets/AccentColor.colorset'])
# Compile a generated resource catalog containing upstream images only.
# Asset-catalog nested exclusions aren't respected by actool, so stage a catalog.
import shutil
staged = root / 'build/NotchAssets/Notch.xcassets'
if staged.exists(): shutil.rmtree(staged)
shutil.copytree(upstream/'Resources/Assets.xcassets', staged)
for name in ['AppIcon.appiconset', 'AccentColor.colorset']:
    shutil.rmtree(staged/name, ignore_errors=True)
exceptions.extend(['Assets.xcassets'])
# All settings are owned by the same app; preserve Swift 5 semantics upstream.
for obj in objects.values():
    if obj.get('isa') == 'XCBuildConfiguration':
        s = obj['buildSettings']
        if 'PRODUCT_NAME' in s:
            s.clear()
            s.update({
                'PRODUCT_NAME': 'MacKit', 'PRODUCT_MODULE_NAME': 'MacKit',
                'PRODUCT_BUNDLE_IDENTIFIER': 'com.mackit.app',
                'INFOPLIST_FILE': 'Config/MacKit-Info.plist',
                'GENERATE_INFOPLIST_FILE': 'NO',
                'CODE_SIGN_ENTITLEMENTS': 'Config/MacKit.entitlements',
                'CODE_SIGN_STYLE': 'Automatic',
                'ENABLE_APP_SANDBOX': 'NO', 'ENABLE_HARDENED_RUNTIME': 'YES',
                'SWIFT_VERSION': '5.0', 'SWIFT_STRICT_CONCURRENCY': 'minimal',
                'MACOSX_DEPLOYMENT_TARGET': '14.6',
                'FRAMEWORK_SEARCH_PATHS': ['$(inherited)', '$(PROJECT_DIR)/MacKit/Features/NotchRuntime/Frameworks'],
                'SYSTEM_FRAMEWORK_SEARCH_PATHS': ['$(SDKROOT)/System/Library/Frameworks', '$(SDKROOT)/System/Library/PrivateFrameworks'],
                'LD_RUNPATH_SEARCH_PATHS': ['$(inherited)', '@executable_path/../Frameworks'],
                'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon',
                'ENABLE_USER_SCRIPT_SANDBOXING': 'NO',
                'SWIFT_EMIT_LOC_STRINGS': 'YES',
            })
        else:
            s.update({'MACOSX_DEPLOYMENT_TARGET': '14.6', 'SWIFT_VERSION': '5.0',
                      'SWIFT_STRICT_CONCURRENCY': 'minimal'})
        obj['baseConfigurationReference'] = hashlib.sha1(b'config:shared').hexdigest()[:24].upper()

def add(name, value):
    key = hashlib.sha1(name.encode()).hexdigest()[:24].upper()
    objects[key] = value
    return key
config = add('config:shared', {'isa':'PBXFileReference', 'lastKnownFileType':'text.xcconfig',
                            'path':'Config/Shared.xcconfig', 'sourceTree':'SOURCE_ROOT'})
children = [config]
sources = sorted(p for p in (root/'MacKit').rglob('*.swift') if upstream not in p.parents) + sorted((root/'Packages/MacKitCore/Sources/MacKitCore').glob('*.swift'))
resources = list((root/'MacKit').glob('*.xcassets')) + list((root/'MacKit/Resources').iterdir()) + [staged]
for path in sources + resources:
    relative = str(path.relative_to(root))
    kind = 'sourcecode.swift' if path in sources else ('folder.assetcatalog' if path.suffix == '.xcassets' else 'file')
    ref = add('host:'+relative, {'isa':'PBXFileReference', 'lastKnownFileType':kind, 'path':relative, 'sourceTree':'SOURCE_ROOT'})
    children.append(ref)
    entry = add('hostbuild:'+relative, {'isa':'PBXBuildFile','fileRef':ref})
    phase = 'F54406E32CD4987A00C7AFD9' if path in sources else 'F54406E52CD4987A00C7AFD9'
    objects[phase]['files'].append(entry)
host = add('hostgroup', {'isa':'PBXGroup','name':'MacKit','children':children,'sourceTree':'<group>'})
objects[project_object['mainGroup']]['children'].insert(0, host)
output = root/'MacKit.xcodeproj'
output.mkdir(exist_ok=True)
(output/'project.pbxproj').write_bytes(plistlib.dumps(project, fmt=plistlib.FMT_XML, sort_keys=False))
shared = output/'xcshareddata/xcschemes'
shared.mkdir(parents=True, exist_ok=True)
ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_id}" BuildableName="MacKit.app" BlueprintName="MacKit" ReferencedContainer="container:MacKit.xcodeproj"/>'
(shared/'MacKit.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="NO" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
workspace = output/'project.xcworkspace/xcshareddata/swiftpm'
workspace.mkdir(parents=True, exist_ok=True)
pins = root/'Config/RuntimePackages.resolved'
shutil.copy2(pins, workspace/'Package.resolved')
print('Generated MacKit.xcodeproj from application sources and pinned dependencies.')

MACKIT_PROJECT_GENERATOR
