#!/usr/bin/env bash
set -euo pipefail

umask 077

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
if [[ "$SCRIPT_DIR" == "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="."
fi
ROOT_DIR="$(cd -- "$SCRIPT_DIR" && builtin pwd)"

info(){ builtin printf '%s\n' "$*"; }
error(){ builtin printf 'ERROR: %s\n' "$*" >&2; }
fatal(){ error "$*"; builtin exit 1; }

TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/manis.XXXXXX")"
trap 'rm -rf -- "${TMPDIR}"' EXIT

fetch(){ local url="$1" out="$2" etag_file="${3:-}"
  local curl_args=(-fsS --retry 3 --retry-delay 1 --connect-timeout 5 --max-time 120 -L "$url" -o "$out" --compressed)
  [ -n "$etag_file" ] && [ -f "$etag_file" ] && curl_args+=(--etag-compare "$etag_file" --etag-save "$etag_file")
  if [[ "$url" == https://api.github.com/* ]] && [ -n "${GITHUB_TOKEN:-}" ]; then
    curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}" -H "X-GitHub-Api-Version: 2022-11-28" -H "Accept: application/vnd.github+json")
  fi
  curl "${curl_args[@]}" 2>/dev/null || return $?
}

arch(){
  case "$(uname -m)" in
    arm64|aarch64) builtin printf 'arm64' ;;
    x86_64)        builtin printf 'amd64' ;;
    *) fatal "Architecture not supported: $(uname -m)" ;;
  esac
}

kernel(){
  local kernel_dir="$ROOT_DIR/manis/Resources/Kernel"
  mkdir -p "$kernel_dir"

  local arch
  arch="$(arch)"

  local etag_file="${kernel_dir}/.mihomo_release_etag"
  local release_json="${TMPDIR}/release.json"
  fetch "https://api.github.com/repos/MetaCubeX/mihomo/releases/tags/Prerelease-Alpha" "$release_json" "$etag_file" || fatal "Release metadata fetch failed"

  local asset_url
  if command -v jq >/dev/null 2>&1; then
    asset_url="$(jq -r --arg arch "$arch" '.assets[]|select(.name|test("mihomo-darwin-"+$arch+"-alpha-.*\\.gz$"))|.browser_download_url' "$release_json" | { IFS= read -r line || true; builtin printf '%s' "$line"; })"
  else
    asset_url=""
    while IFS= read -r line; do
      case "$line" in
        *"\"browser_download_url\""*"mihomo-darwin-${arch}-alpha-"*".gz"*)
          line="${line#*\"browser_download_url\":\"}"
          line="${line%%\"*}"
          asset_url="$line"
          break
          ;;
      esac
    done < "$release_json"
  fi

  [ -n "$asset_url" ] || fatal "Kernel binary unavailable for darwin-$arch"

  local tmp_gz="${TMPDIR}/mihomo.gz" tmp_bin="${TMPDIR}/mihomo"
  info "Fetching kernel: ${asset_url##*/}"
  fetch "$asset_url" "$tmp_gz" || fatal "Kernel binary download failed"
  gunzip -c "$tmp_gz" > "$tmp_bin" || fatal "Kernel binary decompression failed"
  chmod 755 "$tmp_bin"
  mv -f "$tmp_bin" "${kernel_dir}/binary"
  info "Kernel binary: ${kernel_dir}/binary"
}

config(){
  local config_url="https://raw.githubusercontent.com/MetaCubeX/mihomo/refs/heads/Meta/docs/config.yaml"
  local config_path="$ROOT_DIR/manis/Resources/config.yaml"
  local etag_file="$ROOT_DIR/manis/Resources/.config_etag"
  mkdir -p "${config_path%/*}"

  local tmp_config="${TMPDIR}/config.yaml"
  info "Fetching config.yaml"
  fetch "$config_url" "$tmp_config" "$etag_file" || fatal "Configuration template acquisition failed"
  if [ -s "$tmp_config" ]; then
    mv -f "$tmp_config" "$config_path"
  fi
}

geo(){
  local res_dir="$ROOT_DIR/manis/Resources"
  mkdir -p "$res_dir"

  info "Fetching Country.mmdb and geosite.dat"

  fetch "https://github.com/MetaCubeX/meta-rules-dat/raw/release/country.mmdb" "${res_dir}/Country.mmdb" "${res_dir}/.country_etag" || fatal "Country.mmdb download failed"
  fetch "https://github.com/MetaCubeX/meta-rules-dat/raw/release/geosite.dat" "${res_dir}/geosite.dat" "${res_dir}/.geosite_etag" || fatal "geosite.dat download failed"
}

resources(){
  kernel
  config
  geo
}

resources

APP_NAME="manis.app"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$BUILD_DIR/$APP_NAME"

swift build --product manis --configuration release -Xswiftc -warn-concurrency
swift build --product MainXPC --configuration release -Xswiftc -warn-concurrency
swift build --product MainDaemon --configuration release -Xswiftc -warn-concurrency

BIN_DIR="$(swift build --configuration release -Xswiftc -warn-concurrency --show-bin-path)"

APP_STAGING="$TMPDIR/$APP_NAME"
PLIST_STAGING="$APP_STAGING/Contents/Info.plist"

rm -rf "$APP_STAGING"
mkdir -p "$APP_STAGING/Contents/MacOS"
mkdir -p "$APP_STAGING/Contents/Resources"
mkdir -p "$APP_STAGING/Contents/Library/LaunchServices"
mkdir -p "$APP_STAGING/Contents/Library/LaunchDaemons"

cp "$BIN_DIR/manis" "$APP_STAGING/Contents/MacOS/"
cp "$BIN_DIR/MainXPC" "$APP_STAGING/Contents/Library/LaunchServices/"
cp "$BIN_DIR/MainDaemon" "$APP_STAGING/Contents/Library/LaunchServices/"

cp "$BIN_DIR/MainDaemon" "$APP_STAGING/Contents/Library/LaunchServices/com.manis.Daemon"

APP_BUNDLE_FOR_LAUNCHD="${APP_BUNDLE_FOR_LAUNCHD:-$APP_DIR}"

PRIV_HELPER_PLIST_PATH="$APP_STAGING/Contents/Library/LaunchDaemons/com.manis.Daemon.plist"
cp "$ROOT_DIR/manis/Daemon/Launchd.plist" "$PRIV_HELPER_PLIST_PATH"

PRIV_HELPER_BIN_RELATIVE="Contents/Library/LaunchServices/com.manis.Daemon"
/usr/libexec/PlistBuddy -c "Set :Program $PRIV_HELPER_BIN_RELATIVE" "$PRIV_HELPER_PLIST_PATH" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :ProgramArguments" "$PRIV_HELPER_PLIST_PATH" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "$PRIV_HELPER_PLIST_PATH" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string $PRIV_HELPER_BIN_RELATIVE" "$PRIV_HELPER_PLIST_PATH"

USER_XPC_PLIST_PATH="$BUILD_DIR/com.manis.XPC.plist"
cp "$ROOT_DIR/manis/XPC/com.manis.XPC.plist" "$USER_XPC_PLIST_PATH"
/usr/libexec/PlistBuddy -c "Delete :ProgramArguments" "$USER_XPC_PLIST_PATH" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "$USER_XPC_PLIST_PATH" 2>/dev/null || true

/usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string $APP_BUNDLE_FOR_LAUNCHD/Contents/Library/LaunchServices/MainXPC" "$USER_XPC_PLIST_PATH"
cp "$USER_XPC_PLIST_PATH" "$APP_STAGING/Contents/Library/LaunchServices/com.manis.XPC.plist"

cp -R "$ROOT_DIR/manis/Resources/." "$APP_STAGING/Contents/Resources/" 2>/dev/null || true
cp "$ROOT_DIR/manis/Supporting Files/Info.plist" "$APP_STAGING/Contents/"

/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable manis" "$PLIST_STAGING" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.manis.app" "$PLIST_STAGING" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleName manis" "$PLIST_STAGING" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string manis" "$PLIST_STAGING" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName manis" "$PLIST_STAGING" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 26.0" "$PLIST_STAGING" 2>/dev/null || true

rm -rf "$APP_DIR"
mkdir -p "$BUILD_DIR"
mv -f "$APP_STAGING" "$APP_DIR"

echo "Built: $APP_DIR"
echo "Built: $USER_XPC_PLIST_PATH"

if [[ ! -d "$APP_DIR" ]]; then
  echo "manis.app not found." >&2
  exit 1
fi

/usr/bin/xattr -cr "$APP_DIR"

SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -n "$SIGN_IDENTITY" ]]; then
  /usr/bin/codesign -fs "$SIGN_IDENTITY" --force --timestamp=none --deep "$APP_DIR"
else
  /usr/bin/codesign -fs - --force --timestamp=none --deep "$APP_DIR"
fi

/usr/bin/codesign --verify --deep --strict "$APP_DIR"

echo "Signed: $APP_DIR"
