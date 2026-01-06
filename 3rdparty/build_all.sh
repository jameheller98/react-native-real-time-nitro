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
    echo "  --ios              Build only for iOS"
    echo "  --android          Build only for Android"
    echo "  --clean            Clean all build directories and outputs"
    echo "  --clean-build      Clean only build/ intermediate files"
    echo "  --clean-sources    Clean only source directories (libwebsockets, mbedtls)"
    echo "  --download         Download sources only"
    echo "  --auto-cleanup     Auto-remove build/ directory after successful build"
    echo "  --size-report      Show directory sizes"
    echo "  --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                       # Download and build for all platforms"
    echo "  $0 --ios --auto-cleanup  # Build iOS and auto-cleanup intermediates"
    echo "  $0 --android             # Build only for Android"
    echo "  $0 --clean-build         # Remove build/ directory to save space"
    echo "  $0 --size-report         # Show current directory sizes"
}

get_dir_size() {
    local dir=$1
    if [ -d "$dir" ]; then
        du -sh "$dir" 2>/dev/null | cut -f1 || echo "N/A"
    else
        echo "0"
    fi
}

show_size_report() {
    log_info "=== Directory Size Report ==="
    echo ""
    [ -d "build" ] && echo "  build/:         $(get_dir_size build)"
    [ -d "ios" ] && echo "  ios/:           $(get_dir_size ios)"
    [ -d "android" ] && echo "  android/:       $(get_dir_size android)"
    [ -d "libwebsockets" ] && echo "  libwebsockets/: $(get_dir_size libwebsockets)"
    [ -d "mbedtls" ] && echo "  mbedtls/:       $(get_dir_size mbedtls)"
    echo ""
    echo "Tip: Run '$0 --clean-build' to remove build/ intermediates (~100MB)"
}

main() {
    local BUILD_IOS=false
    local BUILD_ANDROID=false
    local CLEAN=false
    local CLEAN_BUILD=false
    local CLEAN_SOURCES=false
    local DOWNLOAD_ONLY=false
    local AUTO_CLEANUP=false
    local SIZE_REPORT=false

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
            --clean-build)
                CLEAN_BUILD=true
                ;;
            --clean-sources)
                CLEAN_SOURCES=true
                ;;
            --download)
                DOWNLOAD_ONLY=true
                ;;
            --auto-cleanup)
                AUTO_CLEANUP=true
                ;;
            --size-report)
                SIZE_REPORT=true
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

    # Show size report if requested
    if [ "$SIZE_REPORT" = true ]; then
        show_size_report
        exit 0
    fi

    # Clean if requested
    if [ "$CLEAN" = true ]; then
        log_info "Cleaning all build artifacts and outputs..."
        ./build_mbedtls.sh --clean 2>/dev/null || true
        rm -rf build ios android
        log_success "Clean complete"
        exit 0
    fi

    # Clean build directory only
    if [ "$CLEAN_BUILD" = true ]; then
        log_info "Cleaning build/ intermediate files..."
        rm -rf build
        log_success "Removed build/ directory (saves ~100MB)"
        exit 0
    fi

    # Clean source directories only
    if [ "$CLEAN_SOURCES" = true ]; then
        log_info "Cleaning source directories..."
        rm -rf libwebsockets mbedtls
        log_success "Removed source directories (saves ~90MB)"
        log_info "Note: Sources will be re-downloaded on next build"
        exit 0
    fi

    # Download sources
    log_info "Step 1: Downloading sources..."
    ./download.sh

    if [ "$DOWNLOAD_ONLY" = true ]; then
        log_success "Download complete"
        exit 0
    fi

    # Build for iOS (includes mbedTLS + libwebsockets + XCFrameworks)
    if [ "$BUILD_IOS" = true ]; then
        log_info ""
        log_info "Step 3: Building for iOS (mbedTLS + libwebsockets)..."
        if [ "$AUTO_CLEANUP" = true ]; then
            ./build_libwebsockets_ios.sh --cleanup
        else
            ./build_libwebsockets_ios.sh
        fi
    fi

    # Build for Android (includes mbedTLS)
    if [ "$BUILD_ANDROID" = true ]; then
        log_info ""
        log_info "Step 4: Building for Android (mbedTLS + libwebsockets)..."
        ./build_libwebsockets_android.sh
    fi
    
    log_info ""
    log_success "=== All builds completed successfully ==="

    # Auto-cleanup if requested
    if [ "$AUTO_CLEANUP" = true ]; then
        log_info ""
        log_info "Auto-cleanup: Removing build/ intermediate files..."
        local BUILD_SIZE=$(get_dir_size build)
        rm -rf build
        log_success "Removed build/ directory (freed: ${BUILD_SIZE})"
    fi

    log_info ""
    log_info "Output locations:"
    if [ "$BUILD_IOS" = true ]; then
        log_info "  iOS libwebsockets: ${SCRIPT_DIR}/ios/libwebsockets.xcframework"
        log_info "  iOS mbedTLS XCFrameworks:"
        log_info "    - ${SCRIPT_DIR}/ios/mbedtls.xcframework"
        log_info "    - ${SCRIPT_DIR}/ios/mbedx509.xcframework"
        log_info "    - ${SCRIPT_DIR}/ios/mbedcrypto.xcframework"
    fi
    if [ "$BUILD_ANDROID" = true ]; then
        log_info "  Android:           ${SCRIPT_DIR}/android/"
    fi

    if [ "$AUTO_CLEANUP" = false ]; then
        log_info ""
        log_info "Tip: Run '$0 --clean-build' to remove build/ intermediates and save space"
    fi
}

main "$@"