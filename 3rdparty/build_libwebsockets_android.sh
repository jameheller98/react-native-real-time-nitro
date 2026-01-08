#!/bin/bash
#===============================================================================
# build_libwebsockets_android.sh - Build libwebsockets for Android (all ABIs)
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
OUTPUT_DIR="${SCRIPT_DIR}/output/android/libwebsockets"
MBEDTLS_VERSION="v3.5.2"  # Compatible with libwebsockets v4.3.3

# Android Settings
ANDROID_MIN_SDK=24
ANDROID_TARGET_SDK=34
BUILD_TYPE="Release"

# ABIs to build (can be overridden by command line)
ABIS=("armeabi-v7a" "arm64-v8a" "x86" "x86_64")

# Modern ABIs only (saves ~74MB of build artifacts)
MODERN_ABIS=("arm64-v8a" "x86_64")

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
        log_info "Cloning mbedTLS ${MBEDTLS_VERSION}..."
        git clone --depth 1 --branch "${MBEDTLS_VERSION}" \
            "https://github.com/Mbed-TLS/mbedtls.git" "${MBEDTLS_SOURCE}"

        log_info "Initializing submodules..."
        cd "${MBEDTLS_SOURCE}"
        git submodule update --init --recursive
        cd "${SCRIPT_DIR}"

        log_success "mbedTLS downloaded"
    else
        log_info "mbedTLS source already exists"
    fi
}

#===============================================================================
# Configure mbedTLS for Android/ARM (disable x86-specific features)
#===============================================================================
configure_mbedtls_for_android() {
    log_info "Configuring mbedTLS for Android/ARM..."

    local CONFIG_FILE="${MBEDTLS_SOURCE}/include/mbedtls/mbedtls_config.h"

    # Disable AESNI (Intel x86 AES instructions) - not needed for ARM
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
    configure_mbedtls_for_android

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
        -DUSE_STATIC_MBEDTLS_LIBRARY=ON \
        -DMBEDTLS_AESNI_C=OFF

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
        -DCMAKE_C_FLAGS="-Wno-sign-conversion" \
        -DCMAKE_CXX_FLAGS="-Wno-sign-conversion" \
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

    # Copy mbedtls headers to output (needed by libwebsockets.h)
    log_info "Copying mbedtls headers for ${ABI}..."
    mkdir -p "${ABI_OUTPUT_DIR}/include"
    cp -R "${MBEDTLS_OUTPUT_DIR}/include/"* "${ABI_OUTPUT_DIR}/include/"

    # Merge mbedtls libraries into libwebsockets.a
    log_info "Merging mbedtls libraries into libwebsockets.a for ${ABI}..."
    local MERGED_DIR="${BUILD_DIR}/${ABI}/merged"
    local LWS_LIB="${ABI_OUTPUT_DIR}/lib/libwebsockets.a"
    local MBEDTLS_LIBS=(
        "${MBEDTLS_OUTPUT_DIR}/lib/libmbedtls.a"
        "${MBEDTLS_OUTPUT_DIR}/lib/libmbedx509.a"
        "${MBEDTLS_OUTPUT_DIR}/lib/libmbedcrypto.a"
    )

    # Create temporary directory for extraction
    rm -rf "${MERGED_DIR}"
    mkdir -p "${MERGED_DIR}"
    cd "${MERGED_DIR}"

    # Extract all object files from all libraries
    log_info "Extracting object files..."
    ar x "${LWS_LIB}"
    for MBEDTLS_LIB in "${MBEDTLS_LIBS[@]}"; do
        ar x "${MBEDTLS_LIB}"
    done

    # Create new merged archive using find to get all .o files recursively
    log_info "Creating merged libwebsockets.a..."
    rm -f "${LWS_LIB}"
    find . -name "*.o" -exec ar crs "${LWS_LIB}" {} +

    # Verify merge was successful
    local LIB_SIZE=$(stat -f%z "${LWS_LIB}" 2>/dev/null || stat -c%s "${LWS_LIB}" 2>/dev/null)
    if [ "${LIB_SIZE}" -lt 1000000 ]; then
        log_error "Merged library is too small (${LIB_SIZE} bytes), merge may have failed!"
        cd "${SCRIPT_DIR}"
        exit 1
    fi
    log_info "Merged library size: ${LIB_SIZE} bytes"

    # Clean up
    cd "${SCRIPT_DIR}"
    rm -rf "${MERGED_DIR}"

    log_success "Built and merged ${ABI}"
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
    rm -rf "${SCRIPT_DIR}/output/android"
    log_success "Clean complete"
}

#===============================================================================
# Main
#===============================================================================
main() {
    local USE_MODERN_ONLY=false

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --clean)
                clean
                exit 0
                ;;
            --modern-only)
                USE_MODERN_ONLY=true
                ABIS=("${MODERN_ABIS[@]}")
                ;;
            --help)
                echo "Usage: $0 [options] [ABI]"
                echo ""
                echo "Options:"
                echo "  --clean         Clean build directory"
                echo "  --modern-only   Build only modern ABIs (arm64-v8a, x86_64)"
                echo "                  Saves ~37MB per legacy ABI"
                echo "  --help          Show this help"
                echo ""
                echo "Specify single ABI: armeabi-v7a, arm64-v8a, x86, x86_64"
                echo ""
                echo "Examples:"
                echo "  $0                    # Build all ABIs"
                echo "  $0 --modern-only      # Build only arm64-v8a and x86_64"
                echo "  $0 arm64-v8a          # Build only arm64-v8a"
                exit 0
                ;;
            armeabi-v7a|arm64-v8a|x86|x86_64)
                ABIS=("$1")
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Run '$0 --help' for usage"
                exit 1
                ;;
        esac
        shift
    done

    log_info "=== Building libwebsockets for Android ==="
    log_info "Source: ${LWS_SOURCE}"
    log_info "Output: ${OUTPUT_DIR}"
    log_info "ABIs: ${ABIS[*]}"
    if [ "$USE_MODERN_ONLY" = true ]; then
        log_info "(Modern ABIs only - legacy 32-bit ABIs excluded)"
    fi
    log_info ""

    check_prerequisites
    patch_libwebsockets_cmake

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
    log_info "  include(\${CMAKE_SOURCE_DIR}/../3rdparty/output/android/CMakeLists.txt)"
    log_info "  target_link_libraries(your_module libwebsockets)"
    log_info ""
    log_info "Tip: Use '$0 --modern-only' to skip legacy ABIs and save build time"
    log_info "Tip: Run '../build_all.sh --clean-build' to remove build/ intermediates"
}

main "$@"