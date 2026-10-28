#!/usr/bin/env python3
"""Generate the dependency-free Xcode project; rerun after adding Swift files."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
objects = {}
def ident(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def q(value): return json.dumps(str(value))
def obj(name, body):
    key = ident(name)
    objects[key] = body
    return key

def refs(items): return '(' + ', '.join(items) + (',' if items else '') + ')'
core = sorted(root.glob('Packages/MacKitCore/Sources/MacKitCore/*.swift'))
app = sorted(root.glob('MacKit/**/*.swift')) + core
ext = sorted(root.glob('MacKitFinderExtension/*.swift')) + [p for p in core if p.name == 'BadgeState.swift']
all_files = sorted(set(app + ext + list(root.glob('Config/*'))))
file_ids = {}
for path in all_files:
    rel = path.relative_to(root).as_posix()
    kind = 'sourcecode.swift' if path.suffix == '.swift' else ('text.xcconfig' if path.suffix == '.xcconfig' else 'text.plist.xml')
    file_ids[rel] = obj('file:' + rel, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {q(rel)}; sourceTree = SOURCE_ROOT;')
products = []
for name, suffix, kind in [('MacKit', 'app', 'wrapper.application'), ('MacKitFinderExtension', 'appex', 'wrapper.app-extension')]:
    products.append(obj('product:' + name, f'isa = PBXFileReference; explicitFileType = "{kind}"; path = "{name}.{suffix}"; sourceTree = BUILT_PRODUCTS_DIR;'))
product_group = obj('products', f'isa = PBXGroup; name = Products; children = {refs(products)}; sourceTree = "<group>";')
main_group = obj('mainGroup', f'isa = PBXGroup; children = {refs(list(file_ids.values()) + [product_group])}; sourceTree = "<group>";')

def configs(name, settings):
    ids = []
    for config in ['Debug', 'Release']:
        extra = 'SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; ONLY_ACTIVE_ARCH = YES; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if config == 'Debug' else 'SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
        ids.append(obj(name + config, f'isa = XCBuildConfiguration; baseConfigurationReference = {file_ids["Config/Shared.xcconfig"]}; buildSettings = {{{settings} {extra}}}; name = {config};'))
    return obj(name + 'configs', f'isa = XCConfigurationList; buildConfigurations = {refs(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

project_configs = configs('project', 'CLANG_ENABLE_MODULES = YES; SDKROOT = macosx;')
proxy = obj('extensionProxy', f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {ident("target:MacKitFinderExtension")}; remoteInfo = MacKitFinderExtension;')
dep = obj('extensionDependency', f'isa = PBXTargetDependency; target = {ident("target:MacKitFinderExtension")}; targetProxy = {proxy};')
embed_file = obj('embedFile', f'isa = PBXBuildFile; fileRef = {products[1]}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy,);}};')
embed_phase = obj('embedPhase', f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ({embed_file},); name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0;')
for i, (name, sources) in enumerate([('MacKit', app), ('MacKitFinderExtension', ext)]):
    builds = []
    for path in sources:
        rel = path.relative_to(root).as_posix()
        builds.append(obj(name + ':' + rel, f'isa = PBXBuildFile; fileRef = {file_ids[rel]};'))
    phase = obj(name + 'sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(builds)}; runOnlyForDeploymentPostprocessing = 0;')
    frameworks = obj(name + 'frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    plist = 'MacKit' if i == 0 else 'Finder'
    settings = f'PRODUCT_NAME = {name}; PRODUCT_BUNDLE_IDENTIFIER = com.mackit.{"app" if i == 0 else "app.finder"}; INFOPLIST_FILE = "Config/{plist}-Info.plist"; CODE_SIGN_ENTITLEMENTS = "Config/{plist}.entitlements"; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";'
    if i == 1: settings += ' APPLICATION_EXTENSION_API_ONLY = YES; SKIP_INSTALL = YES;'
    conf = configs(name, settings)
    phases = [phase, frameworks] + ([embed_phase] if i == 0 else [])
    obj('target:' + name, f'isa = PBXNativeTarget; buildConfigurationList = {conf}; buildPhases = {refs(phases)}; buildRules = (); dependencies = {refs([dep] if i == 0 else [])}; name = {name}; productName = {name}; productReference = {products[i]}; productType = "com.apple.product-type.{"application" if i == 0 else "app-extension"}";')
obj('project', f'isa = PBXProject; attributes = {{LastSwiftUpdateCheck = 2700; LastUpgradeCheck = 2700;}}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh-Hans; hasScannedForEncodings = 0; knownRegions = (en, "zh-Hans", Base); mainGroup = {main_group}; productRefGroup = {product_group}; projectDirPath = ""; projectRoot = ""; targets = {refs([ident("target:MacKit"), ident("target:MacKitFinderExtension")])};')
project = root / 'MacKit.xcodeproj'
project.mkdir(exist_ok=True)
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{\narchiveVersion = 1; classes = {}; objectVersion = 56;\nobjects = {\n' + '\n'.join(f'{key} = {{{body}}};' for key, body in objects.items()) + f'\n}}; rootObject = {ident("project")};\n}}\n')
schemes = project / 'xcshareddata/xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident("target:MacKit")}" BuildableName="MacKit.app" BlueprintName="MacKit" ReferencedContainer="container:MacKit.xcodeproj"/>'
(schemes / 'MacKit.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(f'Generated {project.name}: {len(app)} app sources, {len(ext)} extension sources')
