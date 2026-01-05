#!/bin/bash
#===============================================================================
# build_android.sh - Build libwebsockets for Android (all ABIs)
# Creates prebuilt libraries for React Native Nitro Module
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
MBEDTLS_SOURCE="${SCRIPT_DIR}/mbedtls"
BUILD_DIR="${SCRIPT_DIR}/build/android"
OUTPUT_DIR="${SCRIPT_DIR}/android"
MBEDTLS_VERSION="3.5.1"

# Android Settings
ANDROID_MIN_SDK=24
ANDROID_TARGET_SDK=34
BUILD_TYPE="Release"

# ABIs to build
ABIS=("armeabi-v7a" "arm64-v8a" "x86" "x86_64")

# Build Options
ENABLE_SSL=ON           # Enable SSL/TLS for wss:// support
ENABLE_IPV6=ON
ENABLE_UNIX_SOCK=OFF

#===============================================================================
# Find Android NDK
#===============================================================================
find_ndk() {
    # Check environment variables
    if [ -n "${ANDROID_NDK_HOME}" ]; then
        NDK_PATH="${ANDROID_NDK_HOME}"
    elif [ -n "${ANDROID_NDK}" ]; then
        NDK_PATH="${ANDROID_NDK}"
    elif [ -n "${ANDROID_HOME}" ]; then
        # Try to find NDK in Android SDK
        local NDK_DIR="${ANDROID_HOME}/ndk"
        if [ -d "${NDK_DIR}" ]; then
            # Get latest NDK version
            NDK_PATH=$(ls -d ${NDK_DIR}/*/ 2>/dev/null | sort -V | tail -1 | sed 's/\/$//')
        fi
    else
        # Try common locations
        local COMMON_PATHS=(
            "${HOME}/Library/Android/sdk/ndk"
            "${HOME}/Android/Sdk/ndk"
            "/opt/android-ndk"
            "/usr/local/android-ndk"
        )
        
        for path in "${COMMON_PATHS[@]}"; do
            if [ -d "${path}" ]; then
                NDK_PATH=$(ls -d ${path}/*/ 2>/dev/null | sort -V | tail -1 | sed 's/\/$//')
                break
            fi
        done
    fi
    
    if [ -z "${NDK_PATH}" ] || [ ! -d "${NDK_PATH}" ]; then
        log_error "Android NDK not found!"
        log_error "Please set ANDROID_NDK_HOME environment variable"
        log_error "Example: export ANDROID_NDK_HOME=\$HOME/Library/Android/sdk/ndk/26.1.10909125"
        exit 1
    fi
    
    # Verify NDK has toolchain
    if [ ! -f "${NDK_PATH}/build/cmake/android.toolchain.cmake" ]; then
        log_error "Invalid NDK: ${NDK_PATH}"
        log_error "android.toolchain.cmake not found"
        exit 1
    fi
    
    log_info "Using NDK: ${NDK_PATH}"
    export ANDROID_NDK_HOME="${NDK_PATH}"
}

#===============================================================================
# Download mbedTLS if needed
#===============================================================================
download_mbedtls() {
    if [ ! -d "${MBEDTLS_SOURCE}" ]; then
        log_info "Downloading mbedTLS ${MBEDTLS_VERSION}..."
        local TEMP_DIR="/tmp/mbedtls-download"
        rm -rf "${TEMP_DIR}"
        mkdir -p "${TEMP_DIR}"

        curl -L "https://github.com/Mbed-TLS/mbedtls/archive/refs/tags/v${MBEDTLS_VERSION}.tar.gz" \
            -o "${TEMP_DIR}/mbedtls.tar.gz"

        tar -xzf "${TEMP_DIR}/mbedtls.tar.gz" -C "${SCRIPT_DIR}"
        mv "${SCRIPT_DIR}/mbedtls-${MBEDTLS_VERSION}" "${MBEDTLS_SOURCE}"

        rm -rf "${TEMP_DIR}"
        log_success "mbedTLS downloaded"
    else
        log_info "mbedTLS source already exists"
    fi
}

#===============================================================================
# Check Prerequisites
#===============================================================================
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v cmake &> /dev/null; then
        log_error "cmake is required. Install with your package manager"
        exit 1
    fi

    if [ ! -d "${LWS_SOURCE}" ]; then
        log_error "libwebsockets source not found. Run ./download.sh first"
        exit 1
    fi

    find_ndk
    download_mbedtls

    log_success "Prerequisites OK"
}

#===============================================================================
# Build mbedTLS for a specific ABI
#===============================================================================
build_mbedtls_abi() {
    local ABI=$1

    log_info "Building mbedTLS for ${ABI}..."

    local MBEDTLS_BUILD_DIR="${BUILD_DIR}/${ABI}/mbedtls"
    local MBEDTLS_OUTPUT_DIR="${BUILD_DIR}/${ABI}/mbedtls-install"

    rm -rf "${MBEDTLS_BUILD_DIR}"
    mkdir -p "${MBEDTLS_BUILD_DIR}"
    mkdir -p "${MBEDTLS_OUTPUT_DIR}"

    cd "${MBEDTLS_BUILD_DIR}"

    cmake "${MBEDTLS_SOURCE}" \
        -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="${ABI}" \
        -DANDROID_PLATFORM="android-${ANDROID_MIN_SDK}" \
        -DANDROID_STL=c++_shared \
        -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
        -DCMAKE_INSTALL_PREFIX="${MBEDTLS_OUTPUT_DIR}" \
        -DENABLE_PROGRAMS=OFF \
        -DENABLE_TESTING=OFF \
        -DUSE_SHARED_MBEDTLS_LIBRARY=OFF \
        -DUSE_STATIC_MBEDTLS_LIBRARY=ON

    cmake --build . --config ${BUILD_TYPE} -j$(nproc 2>/dev/null || sysctl -n hw.ncpu)
    cmake --install . --config ${BUILD_TYPE}

    log_success "Built mbedTLS for ${ABI}"
    cd "${SCRIPT_DIR}"
}

#===============================================================================
# Build for a specific ABI
#===============================================================================
build_abi() {
    local ABI=$1

    log_info "Building LibWebSockets for ${ABI}..."

    # Build mbedTLS first
    build_mbedtls_abi "${ABI}"

    local ABI_BUILD_DIR="${BUILD_DIR}/${ABI}/libwebsockets"
    local ABI_OUTPUT_DIR="${OUTPUT_DIR}/${ABI}"
    local MBEDTLS_OUTPUT_DIR="${BUILD_DIR}/${ABI}/mbedtls-install"

    rm -rf "${ABI_BUILD_DIR}"
    mkdir -p "${ABI_BUILD_DIR}"
    mkdir -p "${ABI_OUTPUT_DIR}"

    cd "${ABI_BUILD_DIR}"

    # Configure with CMake
    cmake "${LWS_SOURCE}" \
        -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="${ABI}" \
        -DANDROID_PLATFORM="android-${ANDROID_MIN_SDK}" \
        -DANDROID_STL=c++_shared \
        -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
        -DCMAKE_INSTALL_PREFIX="${ABI_OUTPUT_DIR}" \
        -DLWS_WITH_SSL=${ENABLE_SSL} \
        -DLWS_WITH_MBEDTLS=ON \
        -DLWS_MBEDTLS_LIBRARIES="${MBEDTLS_OUTPUT_DIR}/lib/libmbedtls.a;${MBEDTLS_OUTPUT_DIR}/lib/libmbedx509.a;${MBEDTLS_OUTPUT_DIR}/lib/libmbedcrypto.a" \
        -DLWS_MBEDTLS_INCLUDE_DIRS="${MBEDTLS_OUTPUT_DIR}/include" \
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
    cmake --build . --config ${BUILD_TYPE} -j$(nproc 2>/dev/null || sysctl -n hw.ncpu)
    
    # Install
    cmake --install . --config ${BUILD_TYPE}
    
    log_success "Built ${ABI}"
    cd "${SCRIPT_DIR}"
}

#===============================================================================
# Create CMakeLists.txt for Android integration
#===============================================================================
create_cmake_config() {
    log_info "Creating CMake configuration for Android..."
    
    cat > "${OUTPUT_DIR}/CMakeLists.txt" << 'EOF'
# CMakeLists.txt for libwebsockets Android integration
# Include this in your React Native module's CMakeLists.txt

cmake_minimum_required(VERSION 3.22)

# Get the directory where this file is located
get_filename_component(LWS_DIR ${CMAKE_CURRENT_LIST_FILE} DIRECTORY)

# Create imported library
add_library(libwebsockets STATIC IMPORTED)

# Set library path based on ABI
set_target_properties(libwebsockets PROPERTIES
    IMPORTED_LOCATION "${LWS_DIR}/${ANDROID_ABI}/lib/libwebsockets.a"
)

# Set include directories
target_include_directories(libwebsockets INTERFACE
    "${LWS_DIR}/${ANDROID_ABI}/include"
)

# Export as alias for easier use
add_library(websockets::websockets ALIAS libwebsockets)
EOF

    log_success "Created CMake configuration"
}

#===============================================================================
# Copy headers to common location
#===============================================================================
copy_headers() {
    log_info "Copying headers..."
    
    # Copy headers from first ABI (they're the same for all)
    local FIRST_ABI="${ABIS[0]}"
    mkdir -p "${OUTPUT_DIR}/include"
    cp -R "${OUTPUT_DIR}/${FIRST_ABI}/include/"* "${OUTPUT_DIR}/include/"
    
    log_success "Copied headers to ${OUTPUT_DIR}/include"
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
    log_info "=== Building libwebsockets for Android ==="
    log_info "Source: ${LWS_SOURCE}"
    log_info "Output: ${OUTPUT_DIR}"
    log_info "ABIs: ${ABIS[*]}"
    log_info ""
    
    # Parse arguments
    if [ "$1" == "--clean" ]; then
        clean
        exit 0
    fi
    
    # Allow building single ABI
    if [ -n "$1" ] && [ "$1" != "--clean" ]; then
        ABIS=("$1")
        log_info "Building single ABI: $1"
    fi
    
    check_prerequisites
    
    # Build for each ABI
    for ABI in "${ABIS[@]}"; do
        build_abi "${ABI}"
    done
    
    # Create integration files
    create_cmake_config
    copy_headers
    
    log_success "=== Android build completed ==="
    log_info ""
    log_info "Library locations:"
    for ABI in "${ABIS[@]}"; do
        log_info "  ${ABI}: ${OUTPUT_DIR}/${ABI}/lib/libwebsockets.a"
    done
    log_info ""
    log_info "Headers: ${OUTPUT_DIR}/include"
    log_info ""
    log_info "Add to your CMakeLists.txt:"
    log_info "  include(\${CMAKE_SOURCE_DIR}/../3rdparty/android/CMakeLists.txt)"
    log_info "  target_link_libraries(your_module libwebsockets)"
}

main "$@"