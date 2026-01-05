#!/bin/bash
#===============================================================================
# build_mbedtls.sh - Build mbedTLS for iOS and Android
#===============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

#===============================================================================
# Configuration
#===============================================================================
MBEDTLS_VERSION="v3.5.2"  # Compatible with libwebsockets v4.3.3
MBEDTLS_SOURCE="${SCRIPT_DIR}/mbedtls"
MBEDTLS_REPO="https://github.com/Mbed-TLS/mbedtls.git"

BUILD_DIR="${SCRIPT_DIR}/build/mbedtls-ios"
OUTPUT_DIR="${SCRIPT_DIR}/ios/mbedtls"

IOS_DEPLOYMENT_TARGET="13.0"
BUILD_TYPE="Release"

#===============================================================================
# Download mbedTLS
#===============================================================================
download_mbedtls() {
    if [ -d "${MBEDTLS_SOURCE}" ]; then
        log_info "mbedTLS source already exists at ${MBEDTLS_SOURCE}"
        # Make sure submodules are initialized
        cd "${MBEDTLS_SOURCE}"
        if [ ! -d "framework/.git" ]; then
            log_info "Initializing submodules..."
            git submodule update --init --recursive
        fi
        cd "${SCRIPT_DIR}"
        return 0
    fi

    log_info "Cloning mbedTLS ${MBEDTLS_VERSION}..."

    git clone --depth 1 --branch "${MBEDTLS_VERSION}" "${MBEDTLS_REPO}" "${MBEDTLS_SOURCE}"

    log_info "Initializing submodules..."
    cd "${MBEDTLS_SOURCE}"
    git submodule update --init --recursive
    cd "${SCRIPT_DIR}"

    log_success "Downloaded mbedTLS ${MBEDTLS_VERSION}"
}

#===============================================================================
# Configure mbedTLS for ARM (disable x86-specific features)
#===============================================================================
configure_mbedtls_for_arm() {
    log_info "Configuring mbedTLS for ARM..."

    local CONFIG_FILE="${MBEDTLS_SOURCE}/include/mbedtls/mbedtls_config.h"

    # Disable AESNI (Intel x86 AES instructions) - not available on ARM
    if grep -q "^#define MBEDTLS_AESNI_C" "${CONFIG_FILE}"; then
        sed -i.bak 's/^#define MBEDTLS_AESNI_C/\/\/ #define MBEDTLS_AESNI_C/' "${CONFIG_FILE}"
        log_info "Disabled MBEDTLS_AESNI_C (x86-only)"
    fi

    # Disable PADLOCK (VIA PadLock) - x86 only
    if grep -q "^#define MBEDTLS_PADLOCK_C" "${CONFIG_FILE}"; then
        sed -i.bak 's/^#define MBEDTLS_PADLOCK_C/\/\/ #define MBEDTLS_PADLOCK_C/' "${CONFIG_FILE}"
        log_info "Disabled MBEDTLS_PADLOCK_C (x86-only)"
    fi

    log_success "mbedTLS configured for ARM"
}

#===============================================================================
# Build for a specific platform
#===============================================================================
build_platform() {
    local PLATFORM=$1
    local ARCH=$2
    local SDK=$3

    log_info "Building mbedTLS for ${PLATFORM} (${ARCH})..."

    local PLATFORM_BUILD_DIR="${BUILD_DIR}/${PLATFORM}"
    local PLATFORM_OUTPUT_DIR="${PLATFORM_BUILD_DIR}/output"

    rm -rf "${PLATFORM_BUILD_DIR}"
    mkdir -p "${PLATFORM_BUILD_DIR}"

    # Get SDK path
    local SDK_PATH=$(xcrun --sdk ${SDK} --show-sdk-path)

    cd "${PLATFORM_BUILD_DIR}"

    # Configure with CMake
    cmake "${MBEDTLS_SOURCE}" \
        -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="${SDK_PATH}" \
        -DCMAKE_OSX_ARCHITECTURES="${ARCH}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET}" \
        -DCMAKE_INSTALL_PREFIX="${PLATFORM_OUTPUT_DIR}" \
        -DCMAKE_C_FLAGS="-fembed-bitcode" \
        -DENABLE_PROGRAMS=OFF \
        -DENABLE_TESTING=OFF \
        -DUSE_SHARED_MBEDTLS_LIBRARY=OFF \
        -DUSE_STATIC_MBEDTLS_LIBRARY=ON \
        -DMBEDTLS_HAVE_X86_64=OFF \
        -DMBEDTLS_AESNI_C=OFF

    # Build
    cmake --build . --config ${BUILD_TYPE} -j$(sysctl -n hw.ncpu)

    # Install
    cmake --install . --config ${BUILD_TYPE}

    log_success "Built mbedTLS for ${PLATFORM}"
    cd "${SCRIPT_DIR}"
}

#===============================================================================
# Create fat libraries
#===============================================================================
create_fat_libs() {
    log_info "Creating fat libraries..."

    mkdir -p "${OUTPUT_DIR}/lib"
    mkdir -p "${OUTPUT_DIR}/include"

    # Create fat library for simulator (arm64 + x86_64)
    for lib in libmbedcrypto.a libmbedtls.a libmbedx509.a; do
        log_info "Creating fat library for ${lib}..."

        lipo -create \
            "${BUILD_DIR}/SIMULATORARM64/output/lib/${lib}" \
            "${BUILD_DIR}/SIMULATOR64/output/lib/${lib}" \
            -output "${OUTPUT_DIR}/lib/simulator-${lib}"

        # Copy device library
        cp "${BUILD_DIR}/OS64/output/lib/${lib}" "${OUTPUT_DIR}/lib/device-${lib}"

        log_success "Created ${lib}"
    done

    # Copy headers (same for all platforms)
    cp -R "${BUILD_DIR}/OS64/output/include/" "${OUTPUT_DIR}/include/"

    log_success "Created fat libraries at ${OUTPUT_DIR}"
}

#===============================================================================
# Clean
#===============================================================================
clean() {
    log_info "Cleaning mbedTLS build..."
    rm -rf "${BUILD_DIR}"
    rm -rf "${OUTPUT_DIR}"
    rm -rf "${MBEDTLS_SOURCE}"
    log_success "Clean complete"
}

#===============================================================================
# Main
#===============================================================================
main() {
    local BUILD_IOS=true

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --clean)
                clean
                exit 0
                ;;
            --ios)
                BUILD_IOS=true
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Usage: $0 [--clean|--ios]"
                exit 1
                ;;
        esac
        shift
    done

    log_info "=== Building mbedTLS ==="
    log_info "Version: ${MBEDTLS_VERSION}"
    log_info ""

    download_mbedtls

    # Configure mbedTLS for ARM (disable x86-specific features)
    configure_mbedtls_for_arm

    # Build for iOS (Android builds mbedTLS internally)
    if [ "$BUILD_IOS" = true ]; then
        log_info "Building mbedTLS for iOS..."
        build_platform "OS64" "arm64" "iphoneos"
        build_platform "SIMULATORARM64" "arm64" "iphonesimulator"
        build_platform "SIMULATOR64" "x86_64" "iphonesimulator"
        create_fat_libs

        log_success "=== mbedTLS iOS build completed ==="
        log_info ""
        log_info "Device libraries: ${OUTPUT_DIR}/lib/device-*.a"
        log_info "Simulator libraries: ${OUTPUT_DIR}/lib/simulator-*.a"
        log_info "Headers: ${OUTPUT_DIR}/include/"
    fi
}

main "$@"
