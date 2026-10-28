#!/bin/zsh
set -eu
cd "${0:A:h:h}"
swift test --package-path Packages/MacKitCore --scratch-path build/CoreTests
