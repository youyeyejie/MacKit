#!/bin/zsh
# Install only a verified, developer-signed build. Never downgrades its signature.
set -eu
cd "${0:A:h:h}"
configuration=${1:-Debug}
source_app="$PWD/build/SignedPreview/Build/Products/$configuration/MacKit.app"
destination="$HOME/Applications/MacKit.app"
[[ -d "$source_app" ]] || { print -u2 'Build first: scripts/build.sh Debug --signed'; exit 2; }
codesign --verify --deep --strict "$source_app"
if codesign -dv "$source_app" 2>&1 | /usr/bin/grep -q 'Signature=adhoc'; then
  print -u2 'Refusing an ad-hoc build: Finder App Groups need the developer signature.'; exit 2
fi
if [[ -e "$destination" ]]; then
  identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")
  [[ "$identifier" == 'com.mackit.app' ]] || { print -u2 'Another app occupies the destination.'; exit 2; }
  backup="$PWD/build/Backups/MacKit-$(date +%Y%m%d-%H%M%S).app"
  mkdir -p "$PWD/build/Backups"
  mv "$destination" "$backup"
fi
mkdir -p "$HOME/Applications"
ditto "$source_app" "$destination"
# Xcode also registers the build copy. Prefer the stable installed location.
/usr/bin/pluginkit -r "$source_app/Contents/PlugIns/MacKitFinderExtension.appex" || true
/usr/bin/pluginkit -a "$destination/Contents/PlugIns/MacKitFinderExtension.appex"
print "Installed: $destination"
print 'Enable MacKit in System Settings > General > Login Items & Extensions > Finder Extensions.'
