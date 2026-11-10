#!/bin/zsh
set -eu
cd "${0:A:h:h}"
case "${1:---check}" in
  --check) action=(lint --strict) ;;
  --write) action=(format --in-place) ;;
  -h|--help) print 'Usage: scripts/format.sh [--check|--write]'; exit 0 ;;
  *) print -u2 "Unknown argument: $1"; exit 2 ;;
esac
xcrun swift-format "${action[@]}" --configuration .swift-format --recursive MacKit Extensions Packages/MacKitCore/Sources Packages/MacKitCore/Package.swift
