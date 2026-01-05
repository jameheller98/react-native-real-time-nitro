#!/bin/bash
#===============================================================================
# build_all.sh - Build libwebsockets for all platforms
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

print_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --ios        Build only for iOS"
    echo "  --android    Build only for Android"
    echo "  --clean      Clean all build directories"
    echo "  --download   Download sources only"
    echo "  --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Download and build for all platforms"
    echo "  $0 --ios              # Build only for iOS"
    echo "  $0 --android          # Build only for Android"
    echo "  $0 --clean            # Clean all builds"
}

main() {
    local BUILD_IOS=false
    local BUILD_ANDROID=false
    local CLEAN=false
    local DOWNLOAD_ONLY=false
    
    # Parse arguments
    if [ $# -eq 0 ]; then
        BUILD_IOS=true
        BUILD_ANDROID=true
    fi
    
    while [ $# -gt 0 ]; do
        case "$1" in
            --ios)
                BUILD_IOS=true
                ;;
            --android)
                BUILD_ANDROID=true
                ;;
            --clean)
                CLEAN=true
                ;;
            --download)
                DOWNLOAD_ONLY=true
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
        shift
    done
    
    log_info "=== libwebsockets Build System ==="
    log_info ""
    
    # Clean if requested
    if [ "$CLEAN" = true ]; then
        log_info "Cleaning..."
        ./build_mbedtls.sh --clean 2>/dev/null || true
        rm -rf build ios android
        log_success "Clean complete"
        exit 0
    fi

    # Download sources
    log_info "Step 1: Downloading sources..."
    ./download.sh

    if [ "$DOWNLOAD_ONLY" = true ]; then
        log_success "Download complete"
        exit 0
    fi

    # Build mbedTLS (required for SSL support on iOS; Android builds it internally)
    if [ "$BUILD_IOS" = true ]; then
        log_info ""
        log_info "Step 2: Building mbedTLS..."
        ./build_mbedtls.sh --ios
    fi

    # Build for iOS
    if [ "$BUILD_IOS" = true ]; then
        log_info ""
        log_info "Step 3: Building libwebsockets for iOS..."
        ./build_ios.sh
    fi

    # Build for Android (includes mbedTLS)
    if [ "$BUILD_ANDROID" = true ]; then
        log_info ""
        log_info "Step 4: Building for Android..."
        ./build_android.sh
    fi
    
    log_info ""
    log_success "=== All builds completed successfully ==="
    log_info ""
    log_info "Output locations:"
    if [ "$BUILD_IOS" = true ]; then
        log_info "  iOS libwebsockets: ${SCRIPT_DIR}/ios/libwebsockets.xcframework"
        log_info "  iOS mbedTLS:       ${SCRIPT_DIR}/ios/mbedtls/"
    fi
    if [ "$BUILD_ANDROID" = true ]; then
        log_info "  Android:           ${SCRIPT_DIR}/android/"
    fi
}

main "$@"