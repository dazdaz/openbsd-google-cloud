#!/bin/bash

# OpenBSD ISO Patching Script
# This script handles ISO download and patching for OpenBSD deployment

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEFAULT_OPENBSD_VERSION="7.8"
readonly DEFAULT_OUTPUT_DIR="${SCRIPT_DIR}/../build"

# Global variables
OPENBSD_VERSION="${DEFAULT_OPENBSD_VERSION}"
OUTPUT_DIR="${DEFAULT_OUTPUT_DIR}"
FORCE_REBUILD=false

# Colors for output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OpenBSD ISO Patching Script - Downloads and patches OpenBSD ISO for deployment

OPTIONS:
    --version VERSION       OpenBSD version (default: ${DEFAULT_OPENBSD_VERSION})
    --output DIR            Output directory (default: ${DEFAULT_OUTPUT_DIR})
    --force                 Force rebuild of existing ISO
    --help                  Show this help message

EXAMPLES:
    $0                                    # Basic patching
    $0 --version 7.8 --verbose           # Custom version with verbose output
    $0 --force --output /tmp/openbsd      # Force rebuild with custom output

EOF
}

# Parse arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                OPENBSD_VERSION="$2"
                shift 2
                ;;
            --output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --force)
                FORCE_REBUILD=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Download OpenBSD ISO
download_openbsd_iso() {
    local version="$1"
    local iso_url="https://cdn.openbsd.org/pub/OpenBSD/${version}/amd64/install${version//./}.iso"
    local iso_file="${OUTPUT_DIR}/cache/install${version//./}.iso"
    
    log_info "Downloading OpenBSD ${version} ISO..."
    
    # Create cache directory
    mkdir -p "${OUTPUT_DIR}/cache"
    
    # Check if ISO already exists
    if [[ -f "${iso_file}" && "${FORCE_REBUILD}" != "true" ]]; then
        local iso_size
        iso_size=$(stat -f%z "${iso_file}" 2>/dev/null || echo "0")
        if [[ "${iso_size}" -gt 300000000 ]]; then  # Greater than 300MB
            log_info "ISO already exists and is valid (${iso_size} bytes)"
            echo "${iso_file}"
            return 0
        else
            log_warning "ISO exists but seems too small (${iso_size} bytes), re-downloading..."
            rm -f "${iso_file}"
        fi
    fi
    
    # Download ISO
    if command -v curl >/dev/null 2>&1; then
        curl -L --progress-bar -o "${iso_file}" "${iso_url}"
    elif command -v wget >/dev/null 2>&1; then
        wget --progress=bar:force -O "${iso_file}" "${iso_url}"
    else
        log_error "Neither curl nor wget is available"
        return 1
    fi
    
    # Verify download
    if [[ ! -f "${iso_file}" ]]; then
        log_error "Failed to download ISO"
        return 1
    fi
    
    # Verify ISO size
    local iso_size
    iso_size=$(stat -f%z "${iso_file}" 2>/dev/null || echo "0")
    if [[ "${iso_size}" -lt 300000000 ]]; then
        log_error "Downloaded ISO is too small (${iso_size} bytes), may be corrupted"
        return 1
    fi
    
    log_success "OpenBSD ISO downloaded successfully: ${iso_file}"
    echo "${iso_file}"
}

# Main function
main() {
    # Parse arguments
    parse_arguments "$@"
    
    # Download ISO
    local iso_file
    iso_file=$(download_openbsd_iso "${OPENBSD_VERSION}")
    
    if [[ $? -eq 0 ]]; then
        log_success "ISO preparation completed successfully"
        log_info "ISO file: ${iso_file}"
        log_info "Size: $(stat -f%z "${iso_file}" 2>/dev/null || echo "unknown") bytes"
        log_info "Ready for deployment with: ./deploy-openbsd.sh --iso-file ${iso_file}"
    else
        log_error "ISO preparation failed"
        exit 1
    fi
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
