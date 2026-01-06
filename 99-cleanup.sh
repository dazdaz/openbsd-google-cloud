#!/bin/bash

# Cleanup script for OpenBSD GCP resources
# Deletes VMs, images, and GCS files created by the deployment scripts
#
# Usage: ./99-cleanup.sh [OPTIONS]

set -euo pipefail

# Configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly DEFAULT_PROJECT_ID="genosis-prod"
readonly DEFAULT_ZONE="us-central1-a"
readonly DEFAULT_BUCKET="genosis-prod-images"

# Global variables
PROJECT_ID="${DEFAULT_PROJECT_ID}"
ZONE="${DEFAULT_ZONE}"
BUCKET="${DEFAULT_BUCKET}"
VM_NAME=""
IMAGE_NAME=""
DELETE_VM=false
DELETE_IMAGE=false
DELETE_GCS=false
DELETE_ALL=false
DRY_RUN=false

# Colors for output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "$*"; }
log_warning() { echo -e "${YELLOW}WARNING:${NC} $*"; }
log_error() { echo -e "${RED}ERROR:${NC} $*"; }
log_success() { echo -e "${GREEN}SUCCESS:${NC} $*"; }

show_usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Cleanup OpenBSD GCP resources (VMs, images, GCS files).

OPTIONS:
    --vm NAME                Delete specified VM
    --image NAME             Delete specified image
    --gcs-file FILENAME      Delete file from GCS bucket
    --bucket BUCKET          GCS bucket name (default: ${DEFAULT_BUCKET})
    --all                    Delete all (VM, image, and GCS file)
    --project-id PROJECT     GCP project ID (default: ${DEFAULT_PROJECT_ID})
    --zone ZONE              GCP zone (default: ${DEFAULT_ZONE})
    --dry-run                Show what would be deleted without deleting
    --help                   Show this help message

EXAMPLES:
    # Delete VM only
    ${SCRIPT_NAME} --vm openbsd-server

    # Delete image only
    ${SCRIPT_NAME} --image openbsd-78

    # Delete GCS file
    ${SCRIPT_NAME} --gcs-file openbsd-7.8.vmdk

    # Delete everything
    ${SCRIPT_NAME} --vm openbsd-server --image openbsd-78 --gcs-file openbsd-7.8.vmdk

    # Dry run to see what would be deleted
    ${SCRIPT_NAME} --vm openbsd-server --image openbsd-78 --dry-run

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --vm)
                VM_NAME="$2"
                DELETE_VM=true
                shift 2
                ;;
            --image)
                IMAGE_NAME="$2"
                DELETE_IMAGE=true
                shift 2
                ;;
            --gcs-file)
                GCS_FILE="$2"
                DELETE_GCS=true
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
            --zone)
                ZONE="$2"
                shift 2
                ;;
            --all)
                DELETE_ALL=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
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

    if [[ "${DELETE_VM}" == "false" && "${DELETE_IMAGE}" == "false" && "${DELETE_GCS}" == "false" ]]; then
        log_error "No resources specified. Use --vm, --image, or --gcs-file."
        show_usage
        exit 1
    fi
}

delete_vm() {
    local vm="$1"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete VM: ${vm}"
        return
    fi

    log_info "Deleting VM: ${vm}..."
    
    if gcloud compute instances describe "${vm}" --zone="${ZONE}" --project="${PROJECT_ID}" &>/dev/null; then
        gcloud compute instances delete "${vm}" \
            --zone="${ZONE}" \
            --project="${PROJECT_ID}" \
            --quiet
        log_success "VM deleted: ${vm}"
    else
        log_warning "VM not found: ${vm}"
    fi
}

delete_image() {
    local image="$1"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete image: ${image}"
        return
    fi

    log_info "Deleting image: ${image}..."
    
    if gcloud compute images describe "${image}" --project="${PROJECT_ID}" &>/dev/null; then
        gcloud compute images delete "${image}" \
            --project="${PROJECT_ID}" \
            --quiet
        log_success "Image deleted: ${image}"
    else
        log_warning "Image not found: ${image}"
    fi
}

delete_gcs_file() {
    local file="$1"
    local gcs_path="gs://${BUCKET}/${file}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete GCS file: ${gcs_path}"
        return
    fi

    log_info "Deleting GCS file: ${gcs_path}..."
    
    if gsutil ls "${gcs_path}" &>/dev/null; then
        gsutil rm "${gcs_path}"
        log_success "GCS file deleted: ${gcs_path}"
    else
        log_warning "GCS file not found: ${gcs_path}"
    fi
}

main() {
    echo -e "${BLUE}"
    echo "============================================"
    echo "     OpenBSD GCP Cleanup"
    echo "============================================"
    echo -e "${NC}"

    parse_arguments "$@"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be deleted"
        log_info ""
    fi

    log_info "Project: ${PROJECT_ID}"
    log_info "Zone: ${ZONE}"
    log_info ""

    if [[ "${DELETE_VM}" == "true" && -n "${VM_NAME}" ]]; then
        delete_vm "${VM_NAME}"
    fi

    if [[ "${DELETE_IMAGE}" == "true" && -n "${IMAGE_NAME}" ]]; then
        delete_image "${IMAGE_NAME}"
    fi

    if [[ "${DELETE_GCS}" == "true" && -n "${GCS_FILE:-}" ]]; then
        delete_gcs_file "${GCS_FILE}"
    fi

    log_info ""
    log_info "Done."
}

main "$@"
