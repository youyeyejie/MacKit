#!/bin/zsh
# Regenerate the single MacKit application target with the integrated notch runtime.
set -eu
cd "${0:A:h:h}"
case "${1:-}" in
  -h|--help|help) print 'Usage: scripts/generate_project.sh (requires Python 3 and Xcode)'; exit 0;;
  '') ;;
  *) print -u2 "Unknown argument: $1"; exit 2;;
esac
python3 scripts/generate_app_project.py
