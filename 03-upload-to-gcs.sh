#!/bin/bash

# Upload OpenBSD VMDK to GCS
# VMDK format supports sparse files for efficient upload
#
# Usage: ./03-upload-to-gcs.sh --source-file build/artifacts/openbsd-7.8.vmdk --bucket my-bucket

set -euo pipefail

# Configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly DEFAULT_PROJECT_ID="genosis-prod"
readonly DEFAULT_BUCKET="genosis-prod-images"

# Global variables
SOURCE_FILE=""
BUCKET="${DEFAULT_BUCKET}"
PROJECT_ID="${DEFAULT_PROJECT_ID}"

# Colors for output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

show_usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Upload OpenBSD VMDK image to GCS bucket.

OPTIONS:
    --source-file PATH       Local VMDK file (e.g., build/artifacts/openbsd-7.8.vmdk)
    --bucket BUCKET          GCS bucket name (default: ${DEFAULT_BUCKET})
    --project-id PROJECT     GCP project ID (default: ${DEFAULT_PROJECT_ID})
    --help                   Show this help message

EXAMPLES:
    ${SCRIPT_NAME} --source-file build/artifacts/openbsd-7.8.vmdk
    ${SCRIPT_NAME} --source-file build/artifacts/openbsd-7.8.vmdk --bucket my-bucket

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --source-file)
                SOURCE_FILE="$2"
                shift 2
                ;;
            --bucket)
                BUCKET="$2"
                shift 2
                ;;
            --project-id)
                PROJECT_ID="$2"
                shift 2
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

    if [[ -z "${SOURCE_FILE}" ]]; then
        log_error "Source file is required. Use --source-file option."
        exit 1
    fi

    if [[ ! -f "${SOURCE_FILE}" ]]; then
        log_error "File not found: ${SOURCE_FILE}"
        exit 1
    fi
}

upload_to_gcs() {
    local filename
    filename=$(basename "${SOURCE_FILE}")
    local gcs_path="gs://${BUCKET}/${filename}"

    log_info "Uploading VMDK to GCS..."
    log_info "  Local file: ${SOURCE_FILE}"
    log_info "  Destination: ${gcs_path}"
    log_info ""

    # Create bucket if it doesn't exist
    if ! gsutil ls "gs://${BUCKET}" &>/dev/null; then
        log_info "Creating bucket: gs://${BUCKET}"
        gsutil mb -p "${PROJECT_ID}" "gs://${BUCKET}" || {
            log_error "Failed to create bucket."
            exit 1
        }
    fi

    gsutil cp "${SOURCE_FILE}" "${gcs_path}" || {
        log_error "Failed to upload file."
        exit 1
    }

    log_info ""
    log_info "Upload complete!"
    log_info "  GCS path: ${gcs_path}"
    log_info ""
    log_info "Next step - import the image:"
    log_info "  ./04-gcp-image-import.sh --source-file ${gcs_path} --name openbsd-78"
}

main() {
    echo -e "${BLUE}"
    echo "============================================"
    echo "       Upload VMDK to GCS"
    echo "============================================"
    echo -e "${NC}"

    parse_arguments "$@"
    upload_to_gcs

    log_info ""
    log_info "Done."
}

main "$@"
