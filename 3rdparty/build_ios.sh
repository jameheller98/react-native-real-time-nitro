#!/bin/bash
#===============================================================================
# build_ios.sh - Build libwebsockets for iOS (Device + Simulator)
# Creates XCFramework for easy integration with React Native Nitro Module
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
LWS_SOURCE="${SCRIPT_DIR}/libwebsockets"
BUILD_DIR="${SCRIPT_DIR}/build/ios"
OUTPUT_DIR="${SCRIPT_DIR}/ios"

# iOS Settings
IOS_DEPLOYMENT_TARGET="13.0"
BUILD_TYPE="Release"

# Build Options
ENABLE_SSL=ON           # Enable SSL/TLS for wss:// support
ENABLE_IPV6=ON
ENABLE_UNIX_SOCK=OFF

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
# Build for a specific platform
#===============================================================================
build_platform() {
    local PLATFORM=$1
    local ARCH=$2
    local SDK=$3
    
    log_info "Building for ${PLATFORM} (${ARCH})..."
    
    local PLATFORM_BUILD_DIR="${BUILD_DIR}/${PLATFORM}"
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
        # Find mbedTLS built for iOS
        local MBEDTLS_IOS_ROOT="${SCRIPT_DIR}/ios/mbedtls"

        # Verify mbedTLS is available
        if [ ! -d "${MBEDTLS_IOS_ROOT}/include/mbedtls" ]; then
            log_error "mbedTLS for iOS not found. Build it first with: ./build_mbedtls.sh"
            exit 1
        fi

        # Select appropriate library variant based on platform
        local MBEDTLS_LIB_PREFIX
        if [ "${PLATFORM}" == "OS64" ]; then
            MBEDTLS_LIB_PREFIX="device"
        else
            MBEDTLS_LIB_PREFIX="simulator"
        fi

        log_info "Using mbedTLS from: ${MBEDTLS_IOS_ROOT} (${MBEDTLS_LIB_PREFIX})"

        CMAKE_SSL_OPTIONS="-DLWS_WITH_MBEDTLS=ON -DLWS_MBEDTLS_LIBRARIES=${MBEDTLS_IOS_ROOT}/lib/${MBEDTLS_LIB_PREFIX}-libmbedtls.a;${MBEDTLS_IOS_ROOT}/lib/${MBEDTLS_LIB_PREFIX}-libmbedx509.a;${MBEDTLS_IOS_ROOT}/lib/${MBEDTLS_LIB_PREFIX}-libmbedcrypto.a -DLWS_MBEDTLS_INCLUDE_DIRS=${MBEDTLS_IOS_ROOT}/include -DCMAKE_C_FLAGS=-fembed-bitcode -Wno-undef -Wno-sign-conversion -I${MBEDTLS_IOS_ROOT}/include -DCMAKE_CXX_FLAGS=-fembed-bitcode -Wno-undef -Wno-sign-conversion -I${MBEDTLS_IOS_ROOT}/include"
    else
        log_info "SSL disabled - building without mbedTLS"
        CMAKE_SSL_OPTIONS="-DLWS_WITH_MBEDTLS=OFF -DCMAKE_C_FLAGS=-fembed-bitcode -Wno-undef -Wno-sign-conversion -DCMAKE_CXX_FLAGS=-fembed-bitcode -Wno-undef -Wno-sign-conversion"
    fi

    # Configure with CMake
    cmake "${LWS_SOURCE}" \
        -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="${SDK_PATH}" \
        -DCMAKE_OSX_ARCHITECTURES="${ARCH}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET}" \
        -DCMAKE_INSTALL_PREFIX="${PLATFORM_OUTPUT_DIR}" \
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
# Create XCFramework
#===============================================================================
create_xcframework() {
    log_info "Creating XCFramework..."
    
    local XCFRAMEWORK_PATH="${OUTPUT_DIR}/libwebsockets.xcframework"
    
    rm -rf "${XCFRAMEWORK_PATH}"
    mkdir -p "${OUTPUT_DIR}"
    
    # Create fat library for simulator (arm64 + x86_64)
    local SIM_FAT_DIR="${BUILD_DIR}/simulator-fat"
    mkdir -p "${SIM_FAT_DIR}"
    
    lipo -create \
        "${BUILD_DIR}/SIMULATORARM64/output/lib/libwebsockets.a" \
        "${BUILD_DIR}/SIMULATOR64/output/lib/libwebsockets.a" \
        -output "${SIM_FAT_DIR}/libwebsockets.a"
    
    # Copy headers
    cp -R "${BUILD_DIR}/OS64/output/include" "${SIM_FAT_DIR}/"
    
    # Create XCFramework
    xcodebuild -create-xcframework \
        -library "${BUILD_DIR}/OS64/output/lib/libwebsockets.a" \
        -headers "${BUILD_DIR}/OS64/output/include" \
        -library "${SIM_FAT_DIR}/libwebsockets.a" \
        -headers "${SIM_FAT_DIR}/include" \
        -output "${XCFRAMEWORK_PATH}"
    
    log_success "Created XCFramework: ${XCFRAMEWORK_PATH}"
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
    log_info "Cleaning build directory..."
    rm -rf "${BUILD_DIR}"
    rm -rf "${OUTPUT_DIR}"
    log_success "Clean complete"
}

#===============================================================================
# Main
#===============================================================================
main() {
    log_info "=== Building libwebsockets for iOS ==="
    log_info "Source: ${LWS_SOURCE}"
    log_info "Output: ${OUTPUT_DIR}"
    log_info ""
    
    # Parse arguments
    if [ "$1" == "--clean" ]; then
        clean
        exit 0
    fi
    
    check_prerequisites
    
    # Build for each platform
    # Platform, Architecture, SDK
    build_platform "OS64" "arm64" "iphoneos"
    build_platform "SIMULATORARM64" "arm64" "iphonesimulator"
    build_platform "SIMULATOR64" "x86_64" "iphonesimulator"
    
    # Create XCFramework
    create_xcframework
    
    # Create module map for Swift compatibility
    create_module_map
    
    log_success "=== iOS build completed ==="
    log_info ""
    log_info "XCFramework location: ${OUTPUT_DIR}/libwebsockets.xcframework"
    log_info ""
    log_info "Add to your podspec:"
    log_info "  s.vendored_frameworks = '3rdparty/ios/libwebsockets.xcframework'"
}

main "$@"