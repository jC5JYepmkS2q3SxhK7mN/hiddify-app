#!/bin/bash
set -euo pipefail

task_root="$(cd "$(dirname "$0")/../.." && pwd)"
task_build="$task_root/build/macos/tunnel-core"
task_framework="$task_root/macos/Frameworks/HiddifyTunnelCore.xcframework"
task_source="$task_root/hiddify-core/v2/hcore/tunnel"
task_core_source="$task_root/hiddify-core"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
# Psiphon's TLS adapter depends on the standard-library struct layout. Match the
# core's toolchain (hiddify-core/go.mod); another Go can compile and then panic at startup.
export GOTOOLCHAIN=go1.26.3
mkdir -p "$task_build/tools" "$task_root/macos/Frameworks"

if ! command -v go >/dev/null; then
  echo 'error: Go is required to build the macOS packet tunnel core.' >&2
  exit 1
fi
# The tunnel runs the app's own core, the hiddify-core submodule with its nested submodules.
for task_module in hiddify-core hiddify-core/hiddify-sing-box hiddify-core/ray2sing; do
  if [[ ! -f "$task_root/$task_module/go.mod" ]]; then
    echo "error: $task_module is missing. Run: git submodule update --init --recursive" >&2
    exit 1
  fi
done

# Cache only matching source/toolchain/tag combinations. Never reuse a framework
# after changing the wrapper or a core/submodule source file.
task_tags='with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,with_grpc,with_awg,tfogo_checklinkname0,with_naive_outbound,with_conntrack,with_dhcp'
task_stamp="$task_build/source.sha256"
task_hash=$({
  go version
  xcodebuild -version
  echo "$task_tags"
  cat "$task_root/macos/scripts/build-tunnel-core.sh"
  find "$task_source" "$task_core_source" \( -name .git -o -path "$task_core_source/build" \) -prune -o -type f \
    \( -name '*.go' -o -name 'go.mod' -o -name 'go.sum' -o -name '*.h' -o -name '*.c' \) -print0 | sort -z | xargs -0 shasum -a 256
} | shasum -a 256 | cut -d ' ' -f 1)
if [[ -d "$task_framework" && -f "$task_stamp" && "$(cat "$task_stamp")" == "$task_hash" ]]; then
  exit 0
fi

export GOBIN="$task_build/tools"
export PATH="$GOBIN:$PATH"
if [[ ! -x "$GOBIN/gomobile" || ! -x "$GOBIN/gobind" ]]; then
  go install github.com/sagernet/gomobile/cmd/gomobile@v0.1.12
  go install github.com/sagernet/gomobile/cmd/gobind@v0.1.12
fi
cd "$task_core_source"
# Bind libbox plus the shared tunnel package used by the system extension and the root service.
# Build id for the unsigned tunnel service comes from the downloaded hiddify-core dylib/CLI, not here.
gomobile bind -target macos -macosversion 12.0 -libname HiddifyTunnelCore -tags "$task_tags" \
  -trimpath -ldflags '-w -s -checklinkname=0' \
  -o "$task_build/HiddifyTunnelCore.xcframework" \
  github.com/sagernet/sing-box/experimental/libbox github.com/hiddify/hiddify-core/v2/hcore/tunnel
if [[ -d "$task_framework" ]]; then
  mv "$task_framework" "$task_build/previous-framework-$(date +%s)"
fi
mv "$task_build/HiddifyTunnelCore.xcframework" "$task_framework"
echo "$task_hash" > "$task_stamp"
