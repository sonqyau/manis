#!/usr/bin/env bash
set -euo pipefail
umask 077

log(){ printf '%s\n' "$1"; }
die(){ printf 'ERR:%s\n' "$1" >&2; exit 1; }

root="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd -P)"
src="${root}/../source"
dst="${root}/../build"
stub="${root}/capi.go"
capi_dir="${dst}/capi_build"

[ -d "$src" ] || die "source absent"
[ -r "$stub" ] || die "stub unreadable"
command -v go >/dev/null 2>&1 || die "Go toolchain missing"
mkdir -p "$dst" "$capi_dir"

arch_in="${1:-$(uname -m)}"
case "$arch_in" in
  arm64|aarch64) sets=(arm64) ;;
  x86_64|amd64)  sets=(amd64) ;;
  dual|all)      sets=(arm64 amd64) ;;
  *)             die "unsupported arch" ;;
esac

trap 'rm -rf -- "$capi_dir"' EXIT INT TERM

cp "$stub" "$capi_dir/capi.go"
cat > "$capi_dir/go.mod" << 'EOF'
module mihomo-capi

go 1.21
EOF

build(){
  local a="$1"
  local dylib_out="${dst}/libmihomo_${a}.dylib"
  local static_out="${dst}/libmihomo_${a}.a"
  
  log "compile:${a} (dylib)"
  ( cd "$capi_dir" && GOOS=darwin GOARCH="$a" CGO_ENABLED=1 GO111MODULE=on go build -trimpath -buildmode=c-shared -o "$dylib_out" ./capi.go )
  
  log "compile:${a} (static)"
  ( cd "$capi_dir" && GOOS=darwin GOARCH="$a" CGO_ENABLED=1 GO111MODULE=on go build -trimpath -buildmode=c-archive -o "$static_out" ./capi.go )
  
  if [ "$a" = "${sets[0]}" ]; then
    ln -sf "libmihomo_${a}.dylib" "${dst}/libmihomo.dylib"
    ln -sf "libmihomo_${a}.a" "${dst}/libmihomo.a"
  fi
  
  local hdr="${dst}/libmihomo_${a}.h"
  [ -f "$hdr" ] || die "header missing:${a}"
  install -m 0644 "$hdr" "${dst}/libmihomo.h"
  log "ready:${a}"
}

for a in "${sets[@]}"; do
  build "$a"
done
