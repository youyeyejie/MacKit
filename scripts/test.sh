#!/bin/zsh
set -eu
cd "${0:A:h:h}"
swift test --package-path Packages/MacKitCore --scratch-path build/CoreTests
mkdir -p build/Checks
swiftc -swift-version 6 -parse-as-library MacKit/Platform/ShortcutSettings.swift Tests/ShortcutSettingsChecks.swift -o build/Checks/ShortcutSettingsChecks
build/Checks/ShortcutSettingsChecks
