#!/bin/bash
set -euo pipefail

# HiddifyTunnelCore.xcframework is built only in hiddify-core (gomobile bind).
# Place it here via:
#   make macos-libs          # from hiddify-lib-macos.tar.gz
#   make build-macos-libs    # local: make -C hiddify-core macos

task_root="$(cd "$(dirname "$0")/../.." && pwd)"
task_framework="$task_root/macos/Frameworks/HiddifyTunnelCore.xcframework"

if [[ -d "$task_framework" ]]; then
  echo "using $task_framework"
  exit 0
fi

echo "error: missing macos/Frameworks/HiddifyTunnelCore.xcframework" >&2
echo "  make macos-libs         # download from hiddify-core releases" >&2
echo "  make build-macos-libs   # build in the hiddify-core checkout (Go stays there)" >&2
exit 1
