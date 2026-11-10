"""Generate the system-hosted wallpaper extension project."""
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parents[1]

def ident(s):
    return hashlib.sha1(s.encode()).hexdigest()[:24].upper()

def q(s):
    return '"' + str(s).replace('\\', '\\\\').replace('"', '\\"') + '"'
files = sorted((root / 'Extensions/Wallpaper').rglob('*.swift')) + [root / 'Packages/MacKitCore/Sources/MacKitCore/Wallpaper/WallpaperRouting.swift', root / 'Packages/MacKitCore/Sources/MacKitCore/Wallpaper/WallpaperOcclusion.swift']
objects = []

def add(key, body):
    objects.append(f'{ident(key)} = {{{body}}};')
refs = []
builds = []
for p in files:
    r = 'file:' + p.name
    b = 'build:' + p.name
    refs.append(ident(r))
    builds.append(ident(b))
    add(r, 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ' + q(p) + '; sourceTree = "<absolute>";')
    add(b, 'isa = PBXBuildFile; fileRef = ' + ident(r) + ';')
add('product', 'isa = PBXFileReference; explicitFileType = "wrapper.extensionkit-extension"; path = MacKitWallpaper.appex; sourceTree = BUILT_PRODUCTS_DIR;')
add('group', 'isa = PBXGroup; children = (' + ','.join(refs + [ident('product')]) + '); sourceTree = "<group>";')
add('sources', 'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (' + ','.join(builds) + '); runOnlyForDeploymentPostprocessing = 0;')
add('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
for mode in ['Debug', 'Release']:
    settings = 'CLANG_ENABLE_MODULES = YES; SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 26.0; SWIFT_VERSION = 6.0; CODE_SIGN_STYLE = Automatic; ENABLE_HARDENED_RUNTIME = YES; ENABLE_APP_SANDBOX = YES; GENERATE_INFOPLIST_FILE = YES; PRODUCT_NAME = MacKitWallpaper; PRODUCT_BUNDLE_IDENTIFIER = com.mackit.app.wallpaper.extension; INFOPLIST_KEY_CFBundleDisplayName = "MacKit-动态壁纸"; SKIP_INSTALL = YES; SWIFT_APPROACHABLE_CONCURRENCY = YES; SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES; '
    settings += 'SWIFT_OPTIMIZATION_LEVEL = ' + ('"-O"' if mode == 'Release' else '"-Onone"') + '; '
    settings += 'INFOPLIST_FILE = ' + q(root / 'Extensions/Wallpaper/Info.plist') + '; SWIFT_OBJC_BRIDGING_HEADER = ' + q(root / 'Extensions/Wallpaper/WallpaperExtension-Bridging-Header.h') + ';'
    add(mode, 'isa = XCBuildConfiguration; baseConfigurationReference = ' + ident('config') + '; buildSettings = {' + settings + '}; name = ' + mode + ';')
add('config', 'isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = ' + q(root / 'Config/Shared.xcconfig') + '; sourceTree = "<absolute>";')
add('configs', 'isa = XCConfigurationList; buildConfigurations = (' + ident('Debug') + ',' + ident('Release') + '); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
add('target', 'isa = PBXNativeTarget; buildConfigurationList = ' + ident('configs') + '; buildPhases = (' + ident('sources') + ',' + ident('frameworks') + '); buildRules = (); dependencies = (); name = MacKitWallpaper; productName = MacKitWallpaper; productReference = ' + ident('product') + '; productType = "com.apple.product-type.extensionkit-extension";')
add('project', 'isa = PBXProject; buildConfigurationList = ' + ident('configs') + '; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en); mainGroup = ' + ident('group') + '; projectDirPath = ""; projectRoot = ""; targets = (' + ident('target') + ');')
Path('build/WallpaperExtension/MacKitWallpaper.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + '\n}; rootObject = ' + ident('project') + ';}')
