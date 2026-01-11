#!/bin/bash
#===============================================================================
# build_libwebsockets_ios.sh - Build libwebsockets + mbedTLS for iOS
# Builds both mbedTLS and libwebsockets, creates XCFrameworks
# Merged functionality from build_mbedtls.sh
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
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

#===============================================================================
# Configuration
#===============================================================================
# mbedTLS Configuration
MBEDTLS_VERSION="v3.6.4"
MBEDTLS_SOURCE="${SCRIPT_DIR}/mbedtls"
MBEDTLS_REPO="https://github.com/Mbed-TLS/mbedtls.git"
MBEDTLS_BUILD_DIR="${SCRIPT_DIR}/build/mbedtls-ios"
MBEDTLS_OUTPUT_DIR="${SCRIPT_DIR}/output/ios/mbedtls"

# libwebsockets Configuration
LWS_SOURCE="${SCRIPT_DIR}/libwebsockets"
LWS_BUILD_DIR="${SCRIPT_DIR}/build/ios"
OUTPUT_DIR="${SCRIPT_DIR}/output/ios"

# iOS Settings
IOS_DEPLOYMENT_TARGET="13.0"
BUILD_TYPE="Release"

# Build Options
ENABLE_SSL=ON           # Enable SSL/TLS for wss:// support
ENABLE_IPV6=ON
ENABLE_UNIX_SOCK=OFF

#===============================================================================
# mbedTLS Functions
#===============================================================================

#===============================================================================
# Download mbedTLS
#===============================================================================
download_mbedtls() {
    if [ -d "${MBEDTLS_SOURCE}" ]; then
        log_info "mbedTLS source already exists"
        cd "${MBEDTLS_SOURCE}"
        if [ ! -d "framework/.git" ]; then
            log_info "Initializing mbedTLS submodules..."
            git submodule update --init --recursive
        fi
        cd "${SCRIPT_DIR}"
        return 0
    fi

    log_info "Downloading mbedTLS ${MBEDTLS_VERSION}..."
    git clone --depth 1 --branch "${MBEDTLS_VERSION}" "${MBEDTLS_REPO}" "${MBEDTLS_SOURCE}"

    cd "${MBEDTLS_SOURCE}"
    git submodule update --init --recursive
    cd "${SCRIPT_DIR}"

    log_success "Downloaded mbedTLS ${MBEDTLS_VERSION}"
}

#===============================================================================
# Configure mbedTLS for ARM
#===============================================================================
configure_mbedtls_for_arm() {
    log_info "Configuring mbedTLS for ARM..."
    local CONFIG_FILE="${MBEDTLS_SOURCE}/include/mbedtls/mbedtls_config.h"

    if grep -q "^#define MBEDTLS_AESNI_C" "${CONFIG_FILE}"; then
        sed -i.bak 's/^#define MBEDTLS_AESNI_C/\/\/ #define MBEDTLS_AESNI_C/' "${CONFIG_FILE}"
        log_info "Disabled MBEDTLS_AESNI_C (x86-only)"
    fi

    if grep -q "^#define MBEDTLS_PADLOCK_C" "${CONFIG_FILE}"; then
        sed -i.bak 's/^#define MBEDTLS_PADLOCK_C/\/\/ #define MBEDTLS_PADLOCK_C/' "${CONFIG_FILE}"
        log_info "Disabled MBEDTLS_PADLOCK_C (x86-only)"
    fi

    log_success "mbedTLS configured for ARM"
}

#===============================================================================
# Build mbedTLS for a specific platform
#===============================================================================
build_mbedtls_platform() {
    local PLATFORM=$1
    local ARCH=$2
    local SDK=$3

    log_info "Building mbedTLS for ${PLATFORM} (${ARCH})..."

    local PLATFORM_BUILD_DIR="${MBEDTLS_BUILD_DIR}/${PLATFORM}"
    local PLATFORM_OUTPUT_DIR="${PLATFORM_BUILD_DIR}/output"

    rm -rf "${PLATFORM_BUILD_DIR}"
    mkdir -p "${PLATFORM_BUILD_DIR}"

    local SDK_PATH=$(xcrun --sdk ${SDK} --show-sdk-path)
    cd "${PLATFORM_BUILD_DIR}"

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

    cmake --build . --config ${BUILD_TYPE} -j$(sysctl -n hw.ncpu)
    cmake --install . --config ${BUILD_TYPE}

    log_success "Built mbedTLS for ${PLATFORM}"
    cd "${SCRIPT_DIR}"
}

#===============================================================================
# Create mbedTLS fat libraries
#===============================================================================
create_mbedtls_fat_libs() {
    log_info "Creating mbedTLS fat libraries..."

    mkdir -p "${MBEDTLS_OUTPUT_DIR}/lib"
    mkdir -p "${MBEDTLS_OUTPUT_DIR}/include"

    for lib in libmbedcrypto.a libmbedtls.a libmbedx509.a; do
        lipo -create \
            "${MBEDTLS_BUILD_DIR}/SIMULATORARM64/output/lib/${lib}" \
            "${MBEDTLS_BUILD_DIR}/SIMULATOR64/output/lib/${lib}" \
            -output "${MBEDTLS_OUTPUT_DIR}/lib/simulator-${lib}"

        cp "${MBEDTLS_BUILD_DIR}/OS64/output/lib/${lib}" "${MBEDTLS_OUTPUT_DIR}/lib/device-${lib}"
    done

    cp -R "${MBEDTLS_BUILD_DIR}/OS64/output/include/" "${MBEDTLS_OUTPUT_DIR}/include/"

    log_success "Created mbedTLS fat libraries"
}

#===============================================================================
# Create mbedTLS XCFrameworks
#===============================================================================
create_mbedtls_xcframeworks() {
    local CLEANUP=$1

    log_info "Creating mbedTLS XCFrameworks..."

    local TEMP_DIR="${SCRIPT_DIR}/temp_xcframework"

    rm -rf "${OUTPUT_DIR}/mbedcrypto.xcframework"
    rm -rf "${OUTPUT_DIR}/mbedtls.xcframework"
    rm -rf "${OUTPUT_DIR}/mbedx509.xcframework"
    rm -rf "${TEMP_DIR}"

    mkdir -p "${TEMP_DIR}/device"
    mkdir -p "${TEMP_DIR}/simulator"

    cp "${MBEDTLS_OUTPUT_DIR}/lib/device-libmbedcrypto.a" "${TEMP_DIR}/device/libmbedcrypto.a"
    cp "${MBEDTLS_OUTPUT_DIR}/lib/simulator-libmbedcrypto.a" "${TEMP_DIR}/simulator/libmbedcrypto.a"
    cp "${MBEDTLS_OUTPUT_DIR}/lib/device-libmbedtls.a" "${TEMP_DIR}/device/libmbedtls.a"
    cp "${MBEDTLS_OUTPUT_DIR}/lib/simulator-libmbedtls.a" "${TEMP_DIR}/simulator/libmbedtls.a"
    cp "${MBEDTLS_OUTPUT_DIR}/lib/device-libmbedx509.a" "${TEMP_DIR}/device/libmbedx509.a"
    cp "${MBEDTLS_OUTPUT_DIR}/lib/simulator-libmbedx509.a" "${TEMP_DIR}/simulator/libmbedx509.a"

    xcodebuild -create-xcframework \
        -library "${TEMP_DIR}/device/libmbedcrypto.a" \
        -headers "${MBEDTLS_OUTPUT_DIR}/include" \
        -library "${TEMP_DIR}/simulator/libmbedcrypto.a" \
        -headers "${MBEDTLS_OUTPUT_DIR}/include" \
        -output "${OUTPUT_DIR}/mbedcrypto.xcframework"

    xcodebuild -create-xcframework \
        -library "${TEMP_DIR}/device/libmbedtls.a" \
        -headers "${MBEDTLS_OUTPUT_DIR}/include" \
        -library "${TEMP_DIR}/simulator/libmbedtls.a" \
        -headers "${MBEDTLS_OUTPUT_DIR}/include" \
        -output "${OUTPUT_DIR}/mbedtls.xcframework"

    xcodebuild -create-xcframework \
        -library "${TEMP_DIR}/device/libmbedx509.a" \
        -headers "${MBEDTLS_OUTPUT_DIR}/include" \
        -library "${TEMP_DIR}/simulator/libmbedx509.a" \
        -headers "${MBEDTLS_OUTPUT_DIR}/include" \
        -output "${OUTPUT_DIR}/mbedx509.xcframework"

    rm -rf "${TEMP_DIR}"

    log_success "Created mbedTLS XCFrameworks"

    if [ "$CLEANUP" = true ]; then
        log_info "Cleaning up redundant mbedTLS files..."
        rm -rf "${MBEDTLS_OUTPUT_DIR}/lib" "${MBEDTLS_OUTPUT_DIR}/include"
        log_success "Removed ios/mbedtls/lib and ios/mbedtls/include"
    fi
}

#===============================================================================
# libwebsockets Functions
#===============================================================================

#===============================================================================
# Check Prerequisites
#===============================================================================
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v cmake &> /dev/null; then
        log_error "cmake is required. Install with: brew install cmake"
        exit 1
    fi

    if ! command -v xcodebuild &> /dev/null; then
        log_error "Xcode command line tools are required"
        exit 1
    fi

    if [ ! -d "${LWS_SOURCE}" ]; then
        log_error "libwebsockets source not found. Run ./download.sh first"
        exit 1
    fi

    log_success "Prerequisites OK"
}

#===============================================================================
# Patch libwebsockets CMakeLists.txt for modern CMake
#===============================================================================
patch_libwebsockets_cmake() {
    local CMAKE_FILE="${LWS_SOURCE}/CMakeLists.txt"

    # Check if already patched
    if grep -q "cmake_minimum_required(VERSION 3.5" "${CMAKE_FILE}"; then
        return 0
    fi

    log_info "Patching libwebsockets CMakeLists.txt for CMake 3.5+"

    # Update cmake_minimum_required from 2.8.12 to 3.5
    if grep -q "cmake_minimum_required(VERSION 2.8.12)" "${CMAKE_FILE}"; then
        sed -i.bak 's/cmake_minimum_required(VERSION 2.8.12)/cmake_minimum_required(VERSION 3.5)/' "${CMAKE_FILE}"
        log_success "Patched CMake version requirement"
    fi

    # Patch lws-genhash.c to use mbedtls_md_setup (modern API) instead of deprecated mbedtls_md_init_ctx
    local GENHASH_FILE="${LWS_SOURCE}/lib/tls/mbedtls/lws-genhash.c"
    if [ -f "${GENHASH_FILE}" ]; then
        if grep -q "mbedtls_md_init_ctx" "${GENHASH_FILE}"; then
            log_info "Patching lws-genhash.c to use mbedtls_md_setup API"
            sed -i.bak '/#if !defined(LWS_HAVE_mbedtls_md_setup)/,/#endif/c\
	if (mbedtls_md_setup(\&ctx->ctx, ctx->hmac, 1))\
		return -1;
' "${GENHASH_FILE}"
            log_success "Patched mbedtls API compatibility"
        fi
    fi
}

#===============================================================================
# Create iOS Toolchain File
#===============================================================================
create_toolchain() {
    local PLATFORM=$1
    local TOOLCHAIN_FILE="${BUILD_DIR}/toolchain-${PLATFORM}.cmake"
    
    mkdir -p "${BUILD_DIR}"
    
    cat > "${TOOLCHAIN_FILE}" << 'EOF'
# iOS CMake Toolchain
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_OSX_DEPLOYMENT_TARGET "${IOS_DEPLOYMENT_TARGET}" CACHE STRING "")

# Determine SDK and architectures based on platform
if(PLATFORM STREQUAL "OS64")
    set(CMAKE_OSX_SYSROOT iphoneos)
    set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "")
elseif(PLATFORM STREQUAL "SIMULATORARM64")
    set(CMAKE_OSX_SYSROOT iphonesimulator)
    set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "")
elseif(PLATFORM STREQUAL "SIMULATOR64")
    set(CMAKE_OSX_SYSROOT iphonesimulator)
    set(CMAKE_OSX_ARCHITECTURES "x86_64" CACHE STRING "")
endif()

set(CMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH NO)
set(CMAKE_IOS_INSTALL_COMBINED YES)

# Skip compiler tests
set(CMAKE_C_COMPILER_WORKS 1)
set(CMAKE_CXX_COMPILER_WORKS 1)

# Find the SDK path
execute_process(
    COMMAND xcrun --sdk ${CMAKE_OSX_SYSROOT} --show-sdk-path
    OUTPUT_VARIABLE CMAKE_OSX_SYSROOT_PATH
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
set(CMAKE_OSX_SYSROOT ${CMAKE_OSX_SYSROOT_PATH})
EOF

    echo "${TOOLCHAIN_FILE}"
}

#===============================================================================
# Build libwebsockets for a specific platform
#===============================================================================
build_lws_platform() {
    local PLATFORM=$1
    local ARCH=$2
    local SDK=$3

    log_info "Building libwebsockets for ${PLATFORM} (${ARCH})..."

    local PLATFORM_BUILD_DIR="${LWS_BUILD_DIR}/${PLATFORM}"
    local PLATFORM_OUTPUT_DIR="${PLATFORM_BUILD_DIR}/output"

    rm -rf "${PLATFORM_BUILD_DIR}"
    mkdir -p "${PLATFORM_BUILD_DIR}"
    mkdir -p "${PLATFORM_OUTPUT_DIR}"

    # Get SDK path
    local SDK_PATH=$(xcrun --sdk ${SDK} --show-sdk-path)

    cd "${PLATFORM_BUILD_DIR}"

    # Configure mbedTLS options based on SSL setting
    local CMAKE_SSL_OPTIONS=""
    if [ "${ENABLE_SSL}" == "ON" ]; then
        # Select appropriate library variant based on platform
        local MBEDTLS_LIB_PREFIX
        if [ "${PLATFORM}" == "OS64" ]; then
            MBEDTLS_LIB_PREFIX="device"
        else
            MBEDTLS_LIB_PREFIX="simulator"
        fi

        log_info "Using mbedTLS from: ${MBEDTLS_OUTPUT_DIR} (${MBEDTLS_LIB_PREFIX})"

        CMAKE_SSL_OPTIONS="-DLWS_WITH_MBEDTLS=ON -DLWS_MBEDTLS_LIBRARIES=${MBEDTLS_OUTPUT_DIR}/lib/${MBEDTLS_LIB_PREFIX}-libmbedtls.a;${MBEDTLS_OUTPUT_DIR}/lib/${MBEDTLS_LIB_PREFIX}-libmbedx509.a;${MBEDTLS_OUTPUT_DIR}/lib/${MBEDTLS_LIB_PREFIX}-libmbedcrypto.a -DLWS_MBEDTLS_INCLUDE_DIRS=${MBEDTLS_OUTPUT_DIR}/include"
        CMAKE_C_FLAGS="-fembed-bitcode -Wno-undef -Wno-sign-conversion -I${MBEDTLS_OUTPUT_DIR}/include"
        CMAKE_CXX_FLAGS="-fembed-bitcode -Wno-undef -Wno-sign-conversion -I${MBEDTLS_OUTPUT_DIR}/include"
    else
        log_info "SSL disabled - building without mbedTLS"
        CMAKE_SSL_OPTIONS="-DLWS_WITH_MBEDTLS=OFF"
        CMAKE_C_FLAGS="-fembed-bitcode -Wno-undef -Wno-sign-conversion"
        CMAKE_CXX_FLAGS="-fembed-bitcode -Wno-undef -Wno-sign-conversion"
    fi

    # Configure with CMake
    cmake "${LWS_SOURCE}" \
        -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="${SDK_PATH}" \
        -DCMAKE_OSX_ARCHITECTURES="${ARCH}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET}" \
        -DCMAKE_INSTALL_PREFIX="${PLATFORM_OUTPUT_DIR}" \
        -DCMAKE_C_FLAGS="${CMAKE_C_FLAGS}" \
        -DCMAKE_CXX_FLAGS="${CMAKE_CXX_FLAGS}" \
        ${CMAKE_SSL_OPTIONS} \
        -DLWS_WITH_SSL=${ENABLE_SSL} \
        -DLWS_WITH_SHARED=OFF \
        -DLWS_WITH_STATIC=ON \
        -DLWS_WITHOUT_TESTAPPS=ON \
        -DLWS_WITHOUT_TEST_SERVER=ON \
        -DLWS_WITHOUT_TEST_SERVER_EXTPOLL=ON \
        -DLWS_WITHOUT_TEST_PING=ON \
        -DLWS_WITHOUT_TEST_CLIENT=ON \
        -DLWS_IPV6=${ENABLE_IPV6} \
        -DLWS_UNIX_SOCK=${ENABLE_UNIX_SOCK} \
        -DLWS_WITH_PLUGINS=OFF \
        -DLWS_WITH_LWSWS=OFF \
        -DLWS_WITH_MINIMAL_EXAMPLES=OFF \
        -DLWS_WITH_LIBUV=OFF \
        -DLWS_WITH_LIBEVENT=OFF \
        -DLWS_WITH_GLIB=OFF \
        -DLWS_WITH_LIBEV=OFF
    
    # Build
    cmake --build . --config ${BUILD_TYPE} -j$(sysctl -n hw.ncpu)
    
    # Install
    cmake --install . --config ${BUILD_TYPE}
    
    log_success "Built ${PLATFORM}"
    cd "${SCRIPT_DIR}"
}

#===============================================================================
# Create libwebsockets XCFramework (with mbedtls merged)
#===============================================================================
create_lws_xcframework() {
    log_info "Creating libwebsockets XCFramework (with mbedtls merged)..."

    local XCFRAMEWORK_PATH="${OUTPUT_DIR}/libwebsockets.xcframework"

    rm -rf "${XCFRAMEWORK_PATH}"
    mkdir -p "${OUTPUT_DIR}"

    # Merge directories for combined libraries
    local DEVICE_MERGED_DIR="${LWS_BUILD_DIR}/device-merged"
    local SIM_MERGED_DIR="${LWS_BUILD_DIR}/simulator-merged"
    mkdir -p "${DEVICE_MERGED_DIR}/lib"
    mkdir -p "${SIM_MERGED_DIR}/lib"

    # Merge libwebsockets + mbedtls libraries for device (arm64)
    log_info "Merging device libraries (arm64)..."
    libtool -static -o "${DEVICE_MERGED_DIR}/lib/libwebsockets.a" \
        "${LWS_BUILD_DIR}/OS64/output/lib/libwebsockets.a" \
        "${MBEDTLS_OUTPUT_DIR}/lib/device-libmbedtls.a" \
        "${MBEDTLS_OUTPUT_DIR}/lib/device-libmbedx509.a" \
        "${MBEDTLS_OUTPUT_DIR}/lib/device-libmbedcrypto.a"

    # Create fat libraries for simulator (arm64 + x86_64)
    log_info "Creating fat simulator libraries..."
    local SIM_ARM64_LWS="${LWS_BUILD_DIR}/SIMULATORARM64/output/lib/libwebsockets.a"
    local SIM_X64_LWS="${LWS_BUILD_DIR}/SIMULATOR64/output/lib/libwebsockets.a"
    local SIM_FAT_MBEDTLS="${MBEDTLS_OUTPUT_DIR}/lib/simulator-libmbedtls.a"
    local SIM_FAT_MBEDX509="${MBEDTLS_OUTPUT_DIR}/lib/simulator-libmbedx509.a"
    local SIM_FAT_MBEDCRYPTO="${MBEDTLS_OUTPUT_DIR}/lib/simulator-libmbedcrypto.a"

    # Extract specific architectures from fat mbedtls libraries
    local MBEDTLS_THIN_DIR="${LWS_BUILD_DIR}/mbedtls-thin"
    mkdir -p "${MBEDTLS_THIN_DIR}"

    # Extract arm64 versions
    lipo "${SIM_FAT_MBEDTLS}" -thin arm64 -output "${MBEDTLS_THIN_DIR}/arm64-libmbedtls.a"
    lipo "${SIM_FAT_MBEDX509}" -thin arm64 -output "${MBEDTLS_THIN_DIR}/arm64-libmbedx509.a"
    lipo "${SIM_FAT_MBEDCRYPTO}" -thin arm64 -output "${MBEDTLS_THIN_DIR}/arm64-libmbedcrypto.a"

    # Extract x86_64 versions
    lipo "${SIM_FAT_MBEDTLS}" -thin x86_64 -output "${MBEDTLS_THIN_DIR}/x86_64-libmbedtls.a"
    lipo "${SIM_FAT_MBEDX509}" -thin x86_64 -output "${MBEDTLS_THIN_DIR}/x86_64-libmbedx509.a"
    lipo "${SIM_FAT_MBEDCRYPTO}" -thin x86_64 -output "${MBEDTLS_THIN_DIR}/x86_64-libmbedcrypto.a"

    # Merge libwebsockets + mbedtls for each simulator architecture
    local SIM_ARM64_MERGED="${LWS_BUILD_DIR}/sim-arm64-merged.a"
    local SIM_X64_MERGED="${LWS_BUILD_DIR}/sim-x64-merged.a"

    libtool -static -o "${SIM_ARM64_MERGED}" \
        "${SIM_ARM64_LWS}" \
        "${MBEDTLS_THIN_DIR}/arm64-libmbedtls.a" \
        "${MBEDTLS_THIN_DIR}/arm64-libmbedx509.a" \
        "${MBEDTLS_THIN_DIR}/arm64-libmbedcrypto.a"

    libtool -static -o "${SIM_X64_MERGED}" \
        "${SIM_X64_LWS}" \
        "${MBEDTLS_THIN_DIR}/x86_64-libmbedtls.a" \
        "${MBEDTLS_THIN_DIR}/x86_64-libmbedx509.a" \
        "${MBEDTLS_THIN_DIR}/x86_64-libmbedcrypto.a"

    # Create fat library combining both simulator architectures
    lipo -create \
        "${SIM_ARM64_MERGED}" \
        "${SIM_X64_MERGED}" \
        -output "${SIM_MERGED_DIR}/lib/libwebsockets.a"

    # Copy headers (include both libwebsockets and mbedtls headers)
    cp -R "${LWS_BUILD_DIR}/OS64/output/include" "${DEVICE_MERGED_DIR}/"
    cp -R "${MBEDTLS_OUTPUT_DIR}/include/"* "${DEVICE_MERGED_DIR}/include/"

    cp -R "${LWS_BUILD_DIR}/OS64/output/include" "${SIM_MERGED_DIR}/"
    cp -R "${MBEDTLS_OUTPUT_DIR}/include/"* "${SIM_MERGED_DIR}/include/"

    # Create XCFramework
    xcodebuild -create-xcframework \
        -library "${DEVICE_MERGED_DIR}/lib/libwebsockets.a" \
        -headers "${DEVICE_MERGED_DIR}/include" \
        -library "${SIM_MERGED_DIR}/lib/libwebsockets.a" \
        -headers "${SIM_MERGED_DIR}/include" \
        -output "${XCFRAMEWORK_PATH}"

    # Clean up temporary directories
    rm -rf "${DEVICE_MERGED_DIR}" "${SIM_MERGED_DIR}" "${MBEDTLS_THIN_DIR}"
    rm -f "${SIM_ARM64_MERGED}" "${SIM_X64_MERGED}"

    log_success "Created merged libwebsockets XCFramework (includes mbedtls)"
}

#===============================================================================
# Create Module Map (for Swift/Objective-C)
#===============================================================================
create_module_map() {
    log_info "Creating module map..."
    
    local MODULEMAP_DIR="${OUTPUT_DIR}/libwebsockets.xcframework/ios-arm64/Headers"
    
    cat > "${MODULEMAP_DIR}/module.modulemap" << 'EOF'
framework module libwebsockets {
    umbrella header "libwebsockets.h"
    export *
    module * { export * }
}
EOF

    # Also add to simulator
    local SIM_MODULEMAP_DIR="${OUTPUT_DIR}/libwebsockets.xcframework/ios-arm64_x86_64-simulator/Headers"
    cp "${MODULEMAP_DIR}/module.modulemap" "${SIM_MODULEMAP_DIR}/"
    
    log_success "Created module map"
}

#===============================================================================
# Clean Build
#===============================================================================
clean() {
    log_info "Cleaning iOS build directories..."
    rm -rf "${LWS_BUILD_DIR}"
    rm -rf "${MBEDTLS_BUILD_DIR}"
    rm -rf "${SCRIPT_DIR}/output/ios"
    rm -rf "${MBEDTLS_SOURCE}"
    log_success "Clean complete"
}

#===============================================================================
# Main
#===============================================================================
main() {
    local CLEANUP=false

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --clean)
                clean
                exit 0
                ;;
            --cleanup)
                CLEANUP=true
                ;;
            --help)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --clean      Clean all build artifacts"
                echo "  --cleanup    Remove redundant files after XCFramework creation"
                echo "  --help       Show this help"
                echo ""
                echo "Builds mbedTLS and libwebsockets for iOS, creates XCFrameworks"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Run '$0 --help' for usage"
                exit 1
                ;;
        esac
        shift
    done

    log_info "=== Building libwebsockets + mbedTLS for iOS ==="
    log_info "libwebsockets source: ${LWS_SOURCE}"
    log_info "mbedTLS version: ${MBEDTLS_VERSION}"
    log_info "Output: ${OUTPUT_DIR}"
    log_info ""

    check_prerequisites
    patch_libwebsockets_cmake

    # Step 1: Build mbedTLS
    log_info "Step 1/3: Building mbedTLS..."
    download_mbedtls
    configure_mbedtls_for_arm
    build_mbedtls_platform "OS64" "arm64" "iphoneos"
    build_mbedtls_platform "SIMULATORARM64" "arm64" "iphonesimulator"
    build_mbedtls_platform "SIMULATOR64" "x86_64" "iphonesimulator"
    create_mbedtls_fat_libs
    # Note: mbedtls libraries are merged into libwebsockets.xcframework
    # create_mbedtls_xcframeworks "$CLEANUP"

    log_info ""
    log_info "Step 2/3: Building libwebsockets..."
    # Build libwebsockets for each platform
    build_lws_platform "OS64" "arm64" "iphoneos"
    build_lws_platform "SIMULATORARM64" "arm64" "iphonesimulator"
    build_lws_platform "SIMULATOR64" "x86_64" "iphonesimulator"

    log_info ""
    log_info "Step 3/3: Creating libwebsockets XCFramework..."
    create_lws_xcframework
    create_module_map

    log_info ""
    log_success "=== iOS build completed successfully ==="
    log_info ""
    log_info "Output locations:"
    log_info "  libwebsockets.xcframework (includes mbedtls): ${OUTPUT_DIR}/libwebsockets.xcframework"
    log_info ""
    log_info "Add to your podspec:"
    log_info "  s.vendored_frameworks = '3rdparty/output/ios/libwebsockets.xcframework'"
    log_info ""
    log_info "Note: mbedtls libraries are now merged into libwebsockets.xcframework"
    log_info ""
    if [ "$CLEANUP" = false ]; then
        log_info "Tip: Run '$0 --cleanup' to remove redundant files and save space"
    fi
    log_info "Tip: Run './build_all.sh --clean-build' to remove build/ intermediates"
}

main "$@"