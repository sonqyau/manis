#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

BUILD_MODE="spm"
BUILD_PROFILE="release"
BUILD_BUNDLE=false
CODESIGN_IDENTITY=""
ENABLE_EXTENSION=false
FORCE_KERNEL_DOWNLOAD=false
FORCE_GEO_DOWNLOAD=false
CLEAN_BUILD=false

XCODE_PROJECT="manis.xcodeproj"
XCODE_SCHEME="manis"
APP_NAME="manis"
DAEMON_NAME="ProxyDaemon"
APP_BUNDLE_ID="com.sonqyau.manis"

ROOT_DIR_PATH="${BASH_SOURCE[0]%/*}"
[ "$ROOT_DIR_PATH" = "${BASH_SOURCE[0]}" ] && ROOT_DIR_PATH=.
ROOT_PATH="$(cd "$ROOT_DIR_PATH" && pwd -P)"
SPM_BUILD_DIR=".build/release"
XCODE_BUILD_DIR="build"
KERNEL_DIR="${ROOT_PATH}/manis/Resources/Kernel"
KERNEL_REPOSITORY_URL="https://github.com/MetaCubeX/mihomo.git"
KERNEL_BRANCH_NAME="Alpha"
KERNEL_SOURCE_DIR="${KERNEL_DIR}/src"
CONFIG_SOURCE_URL="https://raw.githubusercontent.com/MetaCubeX/mihomo/refs/heads/Meta/docs/config.yaml"
CONFIG_FILE_PATH="${ROOT_PATH}/manis/Resources/config.yaml"

log_info(){ builtin printf '%s\n' "$*"; }
log_error(){ builtin printf 'ERROR: %s\n' "$*" >&2; }
log_fatal(){ log_error "$*"; builtin exit 1; }

TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/manis.XXXXXX")"
trap 'rm -rf -- "${TMPDIR}"' EXIT

http_fetch(){ local url="$1" out="$2" etag_file="${3:-}"
    local curl_args=(-fsS --retry 3 --retry-delay 1 --connect-timeout 5 --max-time 30 -L "$url" -o "$out" --compressed)
    [ -n "$etag_file" ] && [ -f "$etag_file" ] && curl_args+=(--etag-compare "$etag_file" --etag-save "$etag_file")
    if [[ "$url" == https://api.github.com/* ]] && [ -n "${GITHUB_TOKEN:-}" ]; then
        curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}" -H "X-GitHub-Api-Version: 2022-11-28" -H "Accept: application/vnd.github+json")
    fi
    curl "${curl_args[@]}" 2>/dev/null || return $?
}

get_arch(){
    case "$(uname -m)" in
        arm64|aarch64) builtin printf 'arm64' ;;
        x86_64)        builtin printf 'amd64' ;;
        *) log_fatal "Architecture not supported: $(uname -m)" ;;
    esac
}

sha256_digest(){
    case "$(uname -s)" in
        Darwin) shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1 ;;
        *) sha256sum "$1" 2>/dev/null | cut -d' ' -f1 || openssl dgst -sha256 -r "$1" 2>/dev/null | cut -d' ' -f1 ;;
    esac
}

prepare_kernel_binary(){
    mkdir -p "$KERNEL_DIR"
    local arch
    arch="$(get_arch)"
    local etag_file="${KERNEL_DIR}/.etag"
    local release_json="${TMPDIR}/release.json"
    http_fetch "https://api.github.com/repos/MetaCubeX/mihomo/releases/tags/Prerelease-Alpha" "$release_json" "$etag_file" || log_fatal "Release metadata fetch failed"

    local asset_url checksums_url
    if command -v jq >/dev/null 2>&1; then
        asset_url="$(jq -r --arg arch "$arch" '.assets[]|select(.name|test("mihomo-darwin-"+$arch+"-alpha-.*\\.gz$"))|.browser_download_url' "$release_json" | head -1)"
        checksums_url="$(jq -r '.assets[]|select(.name=="checksums.txt")|.browser_download_url' "$release_json")"
    else
        asset_url="$(grep -o '"browser_download_url":"[^"]*mihomo-darwin-'"$arch"'-alpha-[^"]*\.gz"' "$release_json" | cut -d'"' -f4 | head -1)"
        checksums_url="$(grep -o '"browser_download_url":"[^"]*checksums\.txt"' "$release_json" | cut -d'"' -f4)"
    fi
    [ -n "$asset_url" ] || log_fatal "Kernel binary unavailable for darwin-$arch"

    local tmp_gz="${TMPDIR}/binary.gz" tmp_bin="${TMPDIR}/binary"
    log_info "Kernel binary: ${asset_url##*/}"
    http_fetch "$asset_url" "$tmp_gz" || log_fatal "Binary acquisition failed"

    if [ -n "$checksums_url" ]; then
        local checksums="${TMPDIR}/checksums.txt" expected actual
        http_fetch "$checksums_url" "$checksums" && {
            expected="$(grep "${asset_url##*/}" "$checksums" 2>/dev/null | cut -d' ' -f1)"
            actual="$(sha256_digest "$tmp_gz")"
            [ "$expected" = "$actual" ] || log_fatal "Integrity verification failed"
        }
    fi

    gunzip -c "$tmp_gz" > "$tmp_bin" && chmod 755 "$tmp_bin" && mv "$tmp_bin" "${KERNEL_DIR}/binary"
    log_info "Kernel binary deployed: ${KERNEL_DIR}/binary"
}

prepare_kernel_source(){
    mkdir -p "$KERNEL_DIR"
    local use_git_transport=true
    if ! command -v git >/dev/null 2>&1; then
        log_info "Git unavailable; utilizing tarball transport"
        use_git_transport=false
    fi

    if [ "$use_git_transport" = true ]; then
        if [ -d "$KERNEL_SOURCE_DIR/.git" ] && [ "$FORCE_KERNEL_DOWNLOAD" = true ]; then
            rm -rf -- "$KERNEL_SOURCE_DIR"
        fi

        if [ -d "$KERNEL_SOURCE_DIR/.git" ]; then
            log_info "Source tree: ${KERNEL_BRANCH_NAME}"
            if ! git -C "$KERNEL_SOURCE_DIR" fetch --depth 1 origin "$KERNEL_BRANCH_NAME" >/dev/null 2>&1; then
                log_info "Git synchronization failed; reverting to tarball transport"
                use_git_transport=false
            elif ! git -C "$KERNEL_SOURCE_DIR" checkout -q "$KERNEL_BRANCH_NAME" >/dev/null 2>&1; then
                log_info "Branch checkout failed; reverting to tarball transport"
                use_git_transport=false
            elif ! git -C "$KERNEL_SOURCE_DIR" reset --hard "origin/${KERNEL_BRANCH_NAME}" >/dev/null 2>&1; then
                log_info "Repository reset failed; reverting to tarball transport"
                use_git_transport=false
            else
                git -C "$KERNEL_SOURCE_DIR" clean -fdx >/dev/null 2>&1 || true
            fi
        else
            log_info "Source repository: ${KERNEL_BRANCH_NAME}"
            if ! git clone --depth 1 --branch "$KERNEL_BRANCH_NAME" --single-branch "$KERNEL_REPOSITORY_URL" "$KERNEL_SOURCE_DIR" >/dev/null 2>&1; then
                log_info "Repository initialization failed; reverting to tarball transport"
                use_git_transport=false
            fi
        fi
    fi

    if [ "$use_git_transport" != true ]; then
        local tarball_url="https://github.com/MetaCubeX/mihomo/archive/refs/tags/Prerelease-Alpha.tar.gz"
        local tmp_tarball_path="${TMPDIR}/mihomo-src.tar.gz"
        log_info "Acquiring source archive: ${tarball_url##*/}"
        http_fetch "$tarball_url" "$tmp_tarball_path" || log_fatal "Source archive acquisition failed"
        rm -rf -- "$KERNEL_SOURCE_DIR"
        mkdir -p "$KERNEL_SOURCE_DIR"
        if ! tar -xzf "$tmp_tarball_path" -C "$KERNEL_SOURCE_DIR" --strip-components=1; then
            log_fatal "Source archive extraction failed"
        fi
        log_info "Source tree established: ${KERNEL_SOURCE_DIR}"
    fi
}

prepare_reference_config(){
    local config_dir_path="${CONFIG_FILE_PATH%/*}"
    [ "$config_dir_path" = "$CONFIG_FILE_PATH" ] && config_dir_path=.
    mkdir -p "$config_dir_path"
    local tmp_config_path="${TMPDIR}/config.yaml"
    http_fetch "$CONFIG_SOURCE_URL" "$tmp_config_path" || log_fatal "Configuration template acquisition failed"
    mv -f "$tmp_config_path" "$CONFIG_FILE_PATH"
    log_info "Configuration template deployed: $CONFIG_FILE_PATH"
}

prepare_geo_datasets(){
    local res_dir="${ROOT_PATH}/manis/Resources"
    local lzfse_avail=false
    command -v lzfse >/dev/null && lzfse_avail=true
    mkdir -p "$res_dir"

    fetch_and_compress(){
        local url="$1" name="$2" tmp
        tmp="${TMPDIR}/${name}"
        http_fetch "$url" "$tmp" || builtin return 1
        if $lzfse_avail; then
            lzfse -encode -i "$tmp" -o "${res_dir}/${name}.lzfse"
        else
            mv "$tmp" "${res_dir}/${name}"
        fi
    }

    { [ ! -f "$res_dir/Country.mmdb.lzfse" ] && [ ! -f "$res_dir/Country.mmdb" ]; } || [ "$FORCE_GEO_DOWNLOAD" = true ] && {
        fetch_and_compress "https://github.com/MetaCubeX/meta-rules-dat/raw/release/country.mmdb" "Country.mmdb" &
    }

    [ "$FORCE_GEO_DOWNLOAD" = true ] && [ ! -f "$res_dir/geosite.dat.lzfse" ] && {
        fetch_and_compress "https://github.com/MetaCubeX/meta-rules-dat/raw/release/geosite.dat" "geosite.dat" &
    }
    builtin wait
}

prepare_resources(){
    local pids=() rc=0
    { [ ! -f "${KERNEL_DIR}/binary" ] || [ "$FORCE_KERNEL_DOWNLOAD" = true ]; } && { prepare_kernel_binary & pids+=($!); }
    prepare_kernel_source & pids+=($!)
    [ ! -f "$CONFIG_FILE_PATH" ] && { prepare_reference_config & pids+=($!); }
    { [ "$FORCE_GEO_DOWNLOAD" = true ] || { [ ! -f "${ROOT_PATH}/manis/Resources/Country.mmdb.lzfse" ] && [ ! -f "${ROOT_PATH}/manis/Resources/Country.mmdb" ]; }; } && { prepare_geo_datasets & pids+=($!); }
    for p in "${pids[@]}"; do builtin wait "$p" || rc=$?; done
    [ "$rc" -eq 0 ] || log_fatal "Resource preparation failed"
}

build_spm(){
    local build_flags=(-c "$BUILD_PROFILE" --arch "$(get_arch)")
    [ "$BUILD_PROFILE" = "release" ] && build_flags+=(--disable-sandbox)
    swift build "${build_flags[@]}"

    local exe="${SPM_BUILD_DIR}/${APP_NAME}"
    local arch
    arch="$(get_arch)"
    local dylib="${ROOT_PATH}/manis/Resources/Kernel/lib/libmihomo_${arch}.dylib"
    if [ -f "$exe" ] && [ -f "$dylib" ]; then
        install_name_tool -change "libmihomo_${arch}.dylib" "@rpath/libmihomo_${arch}.dylib" "$exe" 2>/dev/null
        install_name_tool -add_rpath "${ROOT_PATH}/manis/Resources/Kernel/lib" "$exe" 2>/dev/null
        install_name_tool -add_rpath "@executable_path/../Resources/Kernel/lib" "$exe" 2>/dev/null
    fi
    log_info "Swift Package Manager compilation complete"
}

build_xcode(){
    local xcode_configuration="Release"
    [ "$BUILD_PROFILE" = "debug" ] && xcode_configuration="Debug"
    [ "$CLEAN_BUILD" = true ] && (rm -rf "$XCODE_BUILD_DIR" || true) && xcodebuild -project "$XCODE_PROJECT" -scheme "$XCODE_SCHEME" -configuration "$xcode_configuration" clean >/dev/null 2>&1 || true
    xcodebuild -project "$XCODE_PROJECT" -scheme "$XCODE_SCHEME" -configuration "$xcode_configuration" -derivedDataPath "$XCODE_BUILD_DIR" build >/dev/null 2>&1
    log_info "Xcode compilation complete"
}

package_app_bundle(){
    local bundle_path="${SPM_BUILD_DIR}/${APP_NAME}.app"
    rm -rf -- "$bundle_path"

    mkdir -p "${bundle_path}/Contents/MacOS" \
             "${bundle_path}/Contents/Resources" \
             "${bundle_path}/Contents/Library/LaunchServices" \
             "${bundle_path}/Contents/Helpers"

    cp -a -- "${SPM_BUILD_DIR}/${APP_NAME}" "${bundle_path}/Contents/MacOS/" 2>/dev/null || log_fatal "Primary executable unavailable: ${SPM_BUILD_DIR}/${APP_NAME}"

    if [ -f "${SPM_BUILD_DIR}/${DAEMON_NAME}" ]; then
        cp -a -- "${SPM_BUILD_DIR}/${DAEMON_NAME}" "${bundle_path}/Contents/Helpers/"
        log_info "Helper daemon integrated"
    else
        log_info "WARNING: Helper daemon unavailable: ${SPM_BUILD_DIR}/${DAEMON_NAME}"
    fi

    if [ -d "${SPM_BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle" ]; then
        cp -a -- "${SPM_BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle" "${bundle_path}/Contents/Resources/"
        if [ -f "${bundle_path}/Contents/Resources/${APP_NAME}_${APP_NAME}.bundle/binary" ]; then
            ln -sf "../Resources/${APP_NAME}_${APP_NAME}.bundle/binary" "${bundle_path}/Contents/Resources/binary"
        fi
    else
        if [ -f "${KERNEL_DIR}/binary" ]; then
            cp -a -- "${KERNEL_DIR}/binary" "${bundle_path}/Contents/Resources/"
        fi

        if [ -f "${KERNEL_DIR}/lib/libmihomo_arm64.dylib" ]; then
            mkdir -p "${bundle_path}/Contents/Resources/Kernel/lib"
            mkdir -p "${bundle_path}/Contents/Resources/Kernel/include"
            cp -a -- "${KERNEL_DIR}/lib/libmihomo_arm64.dylib" "${bundle_path}/Contents/Resources/Kernel/lib/"
            cp -a -- "${KERNEL_DIR}/include/libmihomo.h" "${bundle_path}/Contents/Resources/Kernel/include/" 2>/dev/null || true
        fi
    fi

    if [ -f "manis/Supporting Files/Info.plist" ]; then
        cp -a -- "manis/Supporting Files/Info.plist" "${bundle_path}/Contents/Info.plist"
    else
        log_fatal "Bundle metadata unavailable"
    fi

    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${APP_NAME}" "${bundle_path}/Contents/Info.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${APP_BUNDLE_ID}" "${bundle_path}/Contents/Info.plist"

    if [ -f "manis/Daemons/LaunchDaemon/com.sonqyau.manis.daemon.plist" ]; then
        mkdir -p "${bundle_path}/Contents/Library/LaunchDaemons"
        cp -a -- "manis/Daemons/LaunchDaemon/com.sonqyau.manis.daemon.plist" \
            "${bundle_path}/Contents/Library/LaunchDaemons/"
    fi

    log_info "Application bundle assembled: ${bundle_path}"
}

codesign_app_bundle(){
    [ -n "$CODESIGN_IDENTITY" ] || log_fatal "Code signing identity unspecified"
    local bundle_path="${SPM_BUILD_DIR}/${APP_NAME}.app"

    if [ -f "${bundle_path}/Contents/Helpers/${DAEMON_NAME}" ]; then
        log_info "Authenticating helper daemon"
        codesign --force --sign "$CODESIGN_IDENTITY" \
                 --entitlements "manis/Daemons/ProxyDaemon/ProxyDaemon.entitlements" \
                 --options runtime --timestamp \
                 "${bundle_path}/Contents/Helpers/${DAEMON_NAME}" || log_fatal "Helper daemon authentication failed"
    fi

    find "$bundle_path" -name "*.dylib" -exec codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --timestamp {} \; || true

    log_info "Authenticating primary application bundle"
    codesign --force --sign "$CODESIGN_IDENTITY" \
             --entitlements "manis/manis.entitlements" \
             --options runtime --timestamp \
             "$bundle_path" || log_fatal "Primary bundle authentication failed"

    codesign --verify --deep --strict "$bundle_path" || log_fatal "Authentication verification failed"
    log_info "Bundle authentication complete: ${bundle_path}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --mode) BUILD_MODE="$2"; shift 2 ;;
        --config) BUILD_PROFILE="$2"; shift 2 ;;
        --bundle) BUILD_BUNDLE=true; shift ;;
        --sign) CODESIGN_IDENTITY="$2"; shift 2 ;;
        --ne) ENABLE_EXTENSION=true; shift ;;
        --kernel) FORCE_KERNEL_DOWNLOAD=true; shift ;;
        --geo) FORCE_GEO_DOWNLOAD=true; shift ;;
        --clean) CLEAN_BUILD=true; shift ;;
        --help) builtin printf 'Usage: %s [--mode spm|xcode] [--config debug|release] [--bundle] [--sign "IDENTITY"]\n' "$0"; builtin exit 0 ;;
        *) log_fatal "Invalid parameter: $1" ;;
    esac
done

case "$BUILD_MODE" in
    spm|xcode) ;;
    *) log_fatal "Build mode unsupported: ${BUILD_MODE}" ;;
esac

case "$BUILD_PROFILE" in
    debug|release) ;;
    *) log_fatal "Build configuration unsupported: ${BUILD_PROFILE}" ;;
esac

log_info "mode=${BUILD_MODE} config=${BUILD_PROFILE} bundle=${BUILD_BUNDLE} extension=${ENABLE_EXTENSION} clean=${CLEAN_BUILD}"

prepare_resources

if [ -d "$KERNEL_SOURCE_DIR" ] && [ -f "${KERNEL_DIR}/bridge/bridge.sh" ]; then
    log_info "Compiling FFI interface from kernel source"
    chmod +x "${KERNEL_DIR}/bridge/bridge.sh"
    "${KERNEL_DIR}/bridge/bridge.sh" || log_fatal "FFI interface compilation failed"
fi

if [ "$BUILD_MODE" = "spm" ]; then
    build_spm
    if [ "$BUILD_BUNDLE" = true ]; then
        package_app_bundle
        if [ -n "$CODESIGN_IDENTITY" ]; then
            codesign_app_bundle
        else
            bundle_path="${SPM_BUILD_DIR}/${APP_NAME}.app"
            log_info "Applying ad-hoc signature for development"
            xattr -cr "$bundle_path" 2>/dev/null || true
            codesign -fs - "$bundle_path" 2>/dev/null || true
        fi
    fi
else
    build_xcode
fi

builtin exit 0
