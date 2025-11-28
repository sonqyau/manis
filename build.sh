#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

BUILD_MODE="spm"              # spm|xcode
BUILD_PROFILE="release"       # debug|release
BUILD_BUNDLE=false
CODESIGN_IDENTITY=""
ENABLE_EXTENSION=false
FORCE_KERNEL_DOWNLOAD=false
FORCE_GEO_DOWNLOAD=false
CLEAN_BUILD=false

XCODE_PROJECT="miho.xcodeproj"
XCODE_SCHEME="miho"
APP_NAME="miho"
DAEMON_NAME="ProxyDaemon"
APP_BUNDLE_ID="com.sonqyau.miho"

ROOT_DIR_PATH="${BASH_SOURCE[0]%/*}"
[ "$ROOT_DIR_PATH" = "${BASH_SOURCE[0]}" ] && ROOT_DIR_PATH=.
ROOT_PATH="$(cd "$ROOT_DIR_PATH" && pwd -P)"
SPM_BUILD_DIR=".build/release"
XCODE_BUILD_DIR="build"
KERNEL_DIR="${ROOT_PATH}/miho/Resources/Kernel"
KERNEL_REPOSITORY_URL="https://github.com/MetaCubeX/mihomo.git"
KERNEL_BRANCH_NAME="Alpha"
KERNEL_SOURCE_DIR="${KERNEL_DIR}/source"
CONFIG_SOURCE_URL="https://raw.githubusercontent.com/MetaCubeX/mihomo/refs/heads/Meta/docs/config.yaml"
CONFIG_FILE_PATH="${ROOT_PATH}/miho/Resources/config.yaml"

log_info(){ printf '%s\n' "$*"; }
log_error(){ printf 'ERR: %s\n' "$*" >&2; }
fatal(){ log_error "$*"; exit 1; }

TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/miho.XXXXXX")"
trap 'rm -rf -- "${TMPDIR}"' EXIT

http_fetch(){ local url="$1"; local out="$2";
    local curl_args=(-fsS --retry 5 --retry-delay 2 --connect-timeout 10 -L "$url" -o "$out")
    if [[ "$url" == https://api.github.com/* ]] && [ -n "${GITHUB_TOKEN:-}" ]; then
        curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}" -H "X-GitHub-Api-Version: 2022-11-28" -H "Accept: application/vnd.github+json")
    fi
    curl "${curl_args[@]}" || return 22;
}

get_arch(){
    case "$(uname -m)" in
        arm64|aarch64) printf 'arm64' ;;
        x86_64)        printf 'amd64' ;;
        *) fatal "Unsupported architecture: $(uname -m)" ;;
    esac
}

fetch_release_metadata(){
    local tag="Prerelease-Alpha"
    local release_json_path="${TMPDIR}/release.json"
    http_fetch "https://api.github.com/repos/MetaCubeX/mihomo/releases/tags/${tag}" "$release_json_path"
    printf '%s' "$release_json_path"
}

select_release_asset_url(){
    local jsonfile="$1"; local arch="$2"
    if command -v jq >/dev/null 2>&1; then
        jq -r --arg arch "$arch" '.assets[] | .browser_download_url | select(test("mihomo-darwin-"+$arch+"-alpha-.*\\.gz$"))' "$jsonfile" | head -n1
    else
        grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+"' "$jsonfile" \
            | sed -E 's/.*"([^"]+)".*/\1/' \
            | grep "mihomo-darwin-${arch}-alpha-.*\\.gz$" \
            | head -n1 || true
    fi
}

select_checksum_file_url(){
    local jsonfile="$1"
    if command -v jq >/dev/null 2>&1; then
        jq -r '.assets[] | .browser_download_url | select(test("checksums.txt$"))' "$jsonfile" | head -n1
    else
        grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+"' "$jsonfile" \
            | sed -E 's/.*"([^"]+)".*/\1/' \
            | grep "checksums.txt$" || true
    fi
}

sha256_digest(){
    local file_path="$1"
    if command -v shasum >/dev/null 2>&1; then
        local digest_value _
        if ! read -r digest_value _ < <(shasum -a 256 "$file_path"); then
            return 1
        fi
        printf '%s\n' "$digest_value"
    elif command -v sha256sum >/dev/null 2>&1; then
        local digest_value _
        if ! read -r digest_value _ < <(sha256sum "$file_path"); then
            return 1
        fi
        printf '%s\n' "$digest_value"
    elif command -v openssl >/dev/null 2>&1; then
        local _ digest_value
        if ! read -r _ digest_value < <(openssl dgst -sha256 "$file_path"); then
            return 1
        fi
        printf '%s\n' "$digest_value"
    else
        return 1
    fi
}

prepare_kernel_binary(){
    mkdir -p "$KERNEL_DIR"
    local system_architecture; system_architecture="$(get_arch)"
    local release_json_path; release_json_path="$(fetch_release_metadata)"
    local asset_download_url; asset_download_url="$(select_release_asset_url "$release_json_path" "$system_architecture")"
    [ -n "$asset_download_url" ] || fatal "No kernel artifact available for darwin-$system_architecture"

    local tmp_asset_gz_path="${TMPDIR}/binary.gz"
    log_info "Downloading kernel artifact ${asset_download_url##*/}"
    http_fetch "$asset_download_url" "$tmp_asset_gz_path" || fatal "Kernel download failed"

    local checksums_file_url=""
    checksums_file_url="$(select_checksum_file_url "$release_json_path")" || true
    if [ -n "$checksums_file_url" ]; then
        local tmp_checksums_path="${TMPDIR}/checksums.txt"
        if http_fetch "$checksums_file_url" "$tmp_checksums_path"; then
            local asset_name expected_checksum line hash
            asset_name="${asset_download_url##*/}"
            while IFS= read -r line; do
                case "$line" in
                    *"$asset_name"*)
                        hash=${line%% *}
                        expected_checksum="$hash"
                        break
                        ;;
                esac
            done < "$tmp_checksums_path"
            if [ -n "$expected_checksum" ]; then
                local actual_checksum_raw actual_checksum expected_checksum_sanitized
                actual_checksum_raw="$(sha256_digest "$tmp_asset_gz_path" || true)"
                if [ -z "$actual_checksum_raw" ]; then
                    log_info "SHA256 tool not available; skipping integrity verification"
                else
                    actual_checksum="${actual_checksum_raw%% *}"
                    expected_checksum_sanitized="${expected_checksum%% *}"
                    if [ "$actual_checksum" != "$expected_checksum_sanitized" ]; then
                        fatal "Checksum mismatch (expected=${expected_checksum_sanitized}, actual=${actual_checksum})"
                    fi
                fi
            fi
        fi
    fi

    local tmp_binary_path="${TMPDIR}/miho.bin"
    if ! gunzip -c "$tmp_asset_gz_path" > "$tmp_binary_path"; then
        fatal "Kernel extraction failed"
    fi
    chmod +x "$tmp_binary_path"
    mv -f "$tmp_binary_path" "${KERNEL_DIR}/binary"
    log_info "Kernel prepared at ${KERNEL_DIR}/binary"
}

prepare_kernel_source(){
    mkdir -p "$KERNEL_DIR"
    local use_git_transport=true
    if ! command -v git >/dev/null 2>&1; then
        log_info "Git not available; falling back to tarball source retrieval"
        use_git_transport=false
    fi

    if [ "$use_git_transport" = true ]; then
        if [ -d "$KERNEL_SOURCE_DIR/.git" ] && [ "$FORCE_KERNEL_DOWNLOAD" = true ]; then
            rm -rf -- "$KERNEL_SOURCE_DIR"
        fi

        if [ -d "$KERNEL_SOURCE_DIR/.git" ]; then
            log_info "Updating kernel source branch ${KERNEL_BRANCH_NAME}"
            if ! git -C "$KERNEL_SOURCE_DIR" fetch --depth 1 origin "$KERNEL_BRANCH_NAME" >/dev/null 2>&1; then
                log_info "Kernel source fetch failed; falling back to tarball"
                use_git_transport=false
            elif ! git -C "$KERNEL_SOURCE_DIR" checkout -q "$KERNEL_BRANCH_NAME" >/dev/null 2>&1; then
                log_info "Kernel branch checkout failed; falling back to tarball"
                use_git_transport=false
            elif ! git -C "$KERNEL_SOURCE_DIR" reset --hard "origin/${KERNEL_BRANCH_NAME}" >/dev/null 2>&1; then
                log_info "Kernel source reset failed; falling back to tarball"
                use_git_transport=false
            else
                git -C "$KERNEL_SOURCE_DIR" clean -fdx >/dev/null 2>&1 || true
            fi
        else
            log_info "Cloning kernel source branch ${KERNEL_BRANCH_NAME}"
            if ! git clone --depth 1 --branch "$KERNEL_BRANCH_NAME" --single-branch "$KERNEL_REPOSITORY_URL" "$KERNEL_SOURCE_DIR" >/dev/null 2>&1; then
                log_info "Kernel source clone failed; falling back to tarball"
                use_git_transport=false
            fi
        fi
    fi

    if [ "$use_git_transport" != true ]; then
        local tarball_url="https://github.com/MetaCubeX/mihomo/archive/refs/tags/Prerelease-Alpha.tar.gz"
        local tmp_tarball_path="${TMPDIR}/mihomo-src.tar.gz"
        log_info "Downloading kernel source tarball ${tarball_url##*/}"
        http_fetch "$tarball_url" "$tmp_tarball_path" || fatal "Kernel source tarball download failed"
        rm -rf -- "$KERNEL_SOURCE_DIR"
        mkdir -p "$KERNEL_SOURCE_DIR"
        if ! tar -xzf "$tmp_tarball_path" -C "$KERNEL_SOURCE_DIR" --strip-components=1; then
            fatal "Kernel source tarball extraction failed"
        fi
        log_info "Kernel source prepared from tarball at ${KERNEL_SOURCE_DIR}"
    fi
}

prepare_reference_config(){
    local config_dir_path="${CONFIG_FILE_PATH%/*}"
    [ "$config_dir_path" = "$CONFIG_FILE_PATH" ] && config_dir_path=.
    mkdir -p "$config_dir_path"
    local tmp_config_path="${TMPDIR}/config.yaml"
    http_fetch "$CONFIG_SOURCE_URL" "$tmp_config_path" || fatal "Reference configuration download failed"
    mv -f "$tmp_config_path" "$CONFIG_FILE_PATH"
    log_info "Reference configuration prepared at $CONFIG_FILE_PATH"
}

prepare_geo_datasets(){
    local RESOURCES_DIR="${ROOT_PATH}/miho/Resources"
    mkdir -p "$RESOURCES_DIR"
    if [ ! -f "$RESOURCES_DIR/Country.mmdb.lzfse" ] || [ "$FORCE_GEO_DOWNLOAD" = true ]; then
        local src="https://github.com/MetaCubeX/meta-rules-dat/raw/release/country.mmdb"
        local tmp_mmdb="${TMPDIR}/country.mmdb"
        http_fetch "$src" "$tmp_mmdb" || fatal "Country dataset download failed"
        if command -v lzfse >/dev/null 2>&1; then
            lzfse -encode -i "$tmp_mmdb" -o "${TMPDIR}/country.lzfse" || fatal "LZFSE compression failed"
            mv -f "${TMPDIR}/country.lzfse" "$RESOURCES_DIR/Country.mmdb.lzfse"
        else
            mv -f "$tmp_mmdb" "$RESOURCES_DIR/Country.mmdb"
            log_info "LZFSE encoder not available; storing uncompressed Country.mmdb"
        fi
        log_info "Country dataset prepared at ${RESOURCES_DIR}"
    fi
    if [ ! -f "$RESOURCES_DIR/geosite.dat.lzfse" ] && [ "$FORCE_GEO_DOWNLOAD" = true ]; then
        local src2="https://github.com/MetaCubeX/meta-rules-dat/raw/release/geosite.dat"
        local tmp2="${TMPDIR}/geosite.dat"
        if http_fetch "$src2" "$tmp2"; then
            if command -v lzfse >/dev/null 2>&1; then
                lzfse -encode -i "$tmp2" -o "${TMPDIR}/geosite.lzfse" && mv -f "${TMPDIR}/geosite.lzfse" "$RESOURCES_DIR/geosite.dat.lzfse"
            else
                mv -f "$tmp2" "$RESOURCES_DIR/geosite.dat"
                log_info "LZFSE encoder not available; storing uncompressed geosite.dat"
            fi
            log_info "Geosite dataset prepared at ${RESOURCES_DIR}"
        else
            log_info "Optional geosite dataset not available"
        fi
    fi
}

prepare_resources(){
    local RESOURCES_DIR="${ROOT_PATH}/miho/Resources"
    local jobs=() rc=0 pid
    if [ ! -f "${KERNEL_DIR}/binary" ] || [ "$FORCE_KERNEL_DOWNLOAD" = true ]; then
        prepare_kernel_binary & jobs+=("$!")
    fi
    prepare_kernel_source & jobs+=("$!")
    if [ ! -f "$CONFIG_FILE_PATH" ]; then
        prepare_reference_config & jobs+=("$!")
    fi
    if [ "$FORCE_GEO_DOWNLOAD" = true ] || { [ ! -f "$RESOURCES_DIR/Country.mmdb.lzfse" ] && [ ! -f "$RESOURCES_DIR/Country.mmdb" ]; }; then
        prepare_geo_datasets & jobs+=("$!")
    fi
    if [ "${#jobs[@]}" -gt 0 ]; then
        for pid in "${jobs[@]}"; do
            wait "$pid" || rc=$?
        done
        [ "$rc" -eq 0 ] || fatal "Preparation failed (rc=$rc)"
    fi
}

build_spm(){
    swift build -c "$BUILD_PROFILE"
    
    local executable_path="${SPM_BUILD_DIR}/arm64-apple-macosx/${BUILD_PROFILE}/${APP_NAME}"
    if [ -f "$executable_path" ]; then
        local dylib_path="${ROOT_PATH}/miho/Resources/Kernel/build/libmihomo_arm64.dylib"
        if [ -f "$dylib_path" ]; then
            install_name_tool -change libmihomo_arm64.dylib "$dylib_path" "$executable_path" 2>/dev/null || true
            log_info "Fixed dylib path for runtime loading"
        fi
    fi
    
    log_info "Swift Package Manager build completed"
}

build_xcode(){
    local xcode_configuration="Release"
    [ "$BUILD_PROFILE" = "debug" ] && xcode_configuration="Debug"
    [ "$CLEAN_BUILD" = true ] && (rm -rf "$XCODE_BUILD_DIR" || true) && xcodebuild -project "$XCODE_PROJECT" -scheme "$XCODE_SCHEME" -configuration "$xcode_configuration" clean >/dev/null 2>&1 || true
    xcodebuild -project "$XCODE_PROJECT" -scheme "$XCODE_SCHEME" -configuration "$xcode_configuration" -derivedDataPath "$XCODE_BUILD_DIR" build >/dev/null 2>&1
    log_info "Xcode build completed"
}

package_app_bundle(){
    local bundle_path="${SPM_BUILD_DIR}/${APP_NAME}.app"
    rm -rf -- "$bundle_path"
    
    mkdir -p "${bundle_path}/Contents/MacOS" \
             "${bundle_path}/Contents/Resources" \
             "${bundle_path}/Contents/Library/LaunchServices" \
             "${bundle_path}/Contents/Helpers"
    
    cp -a -- "${SPM_BUILD_DIR}/${APP_NAME}" "${bundle_path}/Contents/MacOS/" 2>/dev/null || fatal "Primary executable not found: ${SPM_BUILD_DIR}/${APP_NAME}"
    
    [ -f "${SPM_BUILD_DIR}/${DAEMON_NAME}" ] && cp -a -- "${SPM_BUILD_DIR}/${DAEMON_NAME}" "${bundle_path}/Contents/Helpers/" || true
    
    if [ -d "${SPM_BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle" ]; then
        cp -a -- "${SPM_BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle" "${bundle_path}/Contents/Resources/"
        if [ -f "${bundle_path}/Contents/Resources/${APP_NAME}_${APP_NAME}.bundle/binary" ]; then
            ln -sf "../Resources/${APP_NAME}_${APP_NAME}.bundle/binary" "${bundle_path}/Contents/Resources/binary"
        fi
    else
        cp -a -- "${KERNEL_DIR}/binary" "${bundle_path}/Contents/Resources/" 2>/dev/null || true
    fi
    
    if [ -f "miho/Supporting Files/Info.plist" ]; then
        cp -a -- "miho/Supporting Files/Info.plist" "${bundle_path}/Contents/Info.plist"
    else
        fatal "Info.plist not found"
    fi
    
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${APP_NAME}" "${bundle_path}/Contents/Info.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${APP_BUNDLE_ID}" "${bundle_path}/Contents/Info.plist"
    
    if [ -f "miho/Sources/Daemons/LaunchDaemon/com.sonqyau.miho.daemon.plist" ]; then
        mkdir -p "${bundle_path}/Contents/Library/LaunchDaemons"
        cp -a -- "miho/Sources/Daemons/LaunchDaemon/com.sonqyau.miho.daemon.plist" \
            "${bundle_path}/Contents/Library/LaunchDaemons/"
        # cp -a -- "miho/Sources/Daemons/LaunchDaemon/com.sonqyau.miho.daemon.plist" \
        #     "${bundle_path}/Contents/Resources/com.sonqyau.miho.daemon.plist"
    fi
    
    log_info "Application bundle prepared at ${bundle_path}"
}

codesign_app_bundle(){
    [ -n "$CODESIGN_IDENTITY" ] || fatal "Code signing identity not specified"
    local bundle_path="${SPM_BUILD_DIR}/${APP_NAME}.app"

    if [ -f "${bundle_path}/Contents/Helpers/${DAEMON_NAME}" ]; then
        codesign --force --sign "$CODESIGN_IDENTITY" --entitlements "miho/Sources/Daemons/ProxyDaemon/ProxyDaemon.entitlements" --options runtime --timestamp "${bundle_path}/Contents/Helpers/${DAEMON_NAME}" || fatal "Helper code signing failed"
    fi
    codesign --force --sign "$CODESIGN_IDENTITY" --entitlements "miho/miho.entitlements" --options runtime --timestamp --deep "$bundle_path" || fatal "Bundle code signing failed"
    codesign --verify --deep --strict "$bundle_path" || fatal "Code signing verification failed"
    log_info "Bundle signed: ${bundle_path}"
}

print_build_summary(){
    printf '\n'
    printf 'mode=%s config=%s bundle=%s extension=%s clean=%s signer=%s\n' "$BUILD_MODE" "$BUILD_PROFILE" "$BUILD_BUNDLE" "$ENABLE_EXTENSION" "$CLEAN_BUILD" "[[${CODESIGN_IDENTITY:-}]]"
    if [ "$BUILD_MODE" = "spm" ] && [ "$BUILD_BUNDLE" = true ]; then
        local bundle_path="${SPM_BUILD_DIR}/${APP_NAME}.app"
        if [ -d "$bundle_path" ]; then
            local bundle_size _
            if read -r bundle_size _ < <(du -sh "$bundle_path"); then
                printf 'bundle_size=%s\n' "$bundle_size"
            fi
        fi
    fi
    printf '\n'
}

while [ "$#" -gt 0 ]; do
    case "${1:-}" in
        --mode) BUILD_MODE="${2:-}"; shift 2 ;;
        --config) BUILD_PROFILE="${2:-}"; shift 2 ;;
        --bundle) BUILD_BUNDLE=true; shift ;;
        --sign) CODESIGN_IDENTITY="${2:-}"; shift 2 ;;
        --ne) ENABLE_EXTENSION=true; shift ;;
        --kernel) FORCE_KERNEL_DOWNLOAD=true; shift ;;
        --geo) FORCE_GEO_DOWNLOAD=true; shift ;;
        --clean) CLEAN_BUILD=true; shift ;;
        --help) printf 'Usage: %s [--mode spm|xcode] [--config debug|release] [--bundle] [--sign "IDENTITY"]\n' "$0"; exit 0 ;;
        *) die "Unrecognized option: ${1:-}" ;;
    esac
done

case "$BUILD_MODE" in
    spm|xcode) ;;
    *) die "Unsupported mode: ${BUILD_MODE}" ;;
esac

case "$BUILD_PROFILE" in
    debug|release) ;;
    *) die "Unsupported configuration: ${BUILD_PROFILE}" ;;
esac

log_info "mode=${BUILD_MODE} config=${BUILD_PROFILE} bundle=${BUILD_BUNDLE} extension=${ENABLE_EXTENSION} clean=${CLEAN_BUILD}"

prepare_resources

if [ -d "$KERNEL_SOURCE_DIR" ] && [ -f "${KERNEL_DIR}/toolchain/build.sh" ]; then
    log_info "Building FFI library from kernel source"
    chmod +x "${KERNEL_DIR}/toolchain/build.sh"
    "${KERNEL_DIR}/toolchain/build.sh" || fatal "FFI library build failed"
fi

if [ "$BUILD_MODE" = "spm" ]; then
    build_spm
    if [ "$BUILD_BUNDLE" = true ]; then
        package_app_bundle
        [ -n "$CODESIGN_IDENTITY" ] && codesign_app_bundle
    fi
else
    build_xcode
fi

print_build_summary
exit 0
