#!/bin/bash
#===============================================================================
# download.sh - Download third-party library sources
# Similar to SingTown/react-native-webrtc-nitro pattern
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
# Library Versions - Update these as needed
#===============================================================================
LIBWEBSOCKETS_VERSION="v4.3.3"
LIBWEBSOCKETS_REPO="https://github.com/warmcat/libwebsockets.git"

# Optional: OpenSSL for TLS support
OPENSSL_VERSION="openssl-3.2.0"
OPENSSL_URL="https://github.com/openssl/openssl/releases/download/${OPENSSL_VERSION}/${OPENSSL_VERSION}.tar.gz"

#===============================================================================
# Download libwebsockets
#===============================================================================
download_libwebsockets() {
    local FORCE=$1
    log_info "Downloading libwebsockets ${LIBWEBSOCKETS_VERSION}..."

    if [ -d "libwebsockets" ]; then
        if [ "$FORCE" = "true" ]; then
            log_info "Force mode: Removing existing libwebsockets directory"
            rm -rf libwebsockets
        else
            log_info "libwebsockets already exists (use --force to re-download)"
            return 0
        fi
    fi

    git clone --depth 1 --branch "${LIBWEBSOCKETS_VERSION}" "${LIBWEBSOCKETS_REPO}" libwebsockets
    log_success "Downloaded libwebsockets ${LIBWEBSOCKETS_VERSION}"
}

#===============================================================================
# Download OpenSSL (optional - for TLS support)
#===============================================================================
download_openssl() {
    local FORCE=$1
    log_info "Downloading OpenSSL ${OPENSSL_VERSION}..."

    if [ -d "openssl" ]; then
        if [ "$FORCE" = "true" ]; then
            log_info "Force mode: Removing existing openssl directory"
            rm -rf openssl
        else
            log_info "openssl already exists (use --force to re-download)"
            return 0
        fi
    fi

    curl -L "${OPENSSL_URL}" -o openssl.tar.gz
    tar -xzf openssl.tar.gz
    mv "${OPENSSL_VERSION}" openssl
    rm openssl.tar.gz
    log_success "Downloaded OpenSSL ${OPENSSL_VERSION}"
}

#===============================================================================
# Main
#===============================================================================
main() {
    local FORCE=false

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --force)
                FORCE=true
                ;;
            --help)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --force    Force re-download even if sources exist"
                echo "  --help     Show this help"
                echo ""
                echo "Downloads libwebsockets ${LIBWEBSOCKETS_VERSION}"
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

    log_info "=== Downloading 3rd Party Libraries ==="
    log_info "Working directory: ${SCRIPT_DIR}"

    # Create output directories
    mkdir -p ios android

    # Download libraries
    download_libwebsockets "$FORCE"

    # Uncomment if you need TLS support
    # download_openssl "$FORCE"

    log_success "=== All downloads completed ==="
    log_info ""
    log_info "Next steps:"
    log_info "  1. Build for all:     ./build_all.sh"
    log_info "  2. Build for iOS:     ./build_libwebsockets_ios.sh"
    log_info "  3. Build for Android: ./build_libwebsockets_android.sh"
}

main "$@"