#!/usr/bin/env bash
# Compatibility wrapper — product path is generic DSC import.
exec "$(cd "$(dirname "$0")" && pwd)/acceptance-dsc-import.sh" "$@"
