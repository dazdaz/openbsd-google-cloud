#!/bin/bash

# OpenBSD GCP Image Import and VM Creation
# Imports VMDK from GCS and optionally creates a VM
#
# The --data-disk flag skips "OS adaptation" - won't install Linux drivers or modify config files
# Ignore the warning "This is a data disk" - it's expected for OpenBSD
#
# Usage: ./04-gcp-image-import.sh --source-file gs://bucket/openbsd.vmdk --name openbsd-78

set -euo pipefail

# Configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly DEFAULT_PROJECT_ID="genosis-prod"
readonly DEFAULT_ZONE="us-central1-a"
readonly DEFAULT_MACHINE_TYPE="e2-micro"

# Global variables
SOURCE_FILE=""
IMAGE_NAME=""
PROJECT_ID="${DEFAULT_PROJECT_ID}"
ZONE="${DEFAULT_ZONE}"
MACHINE_TYPE="${DEFAULT_MACHINE_TYPE}"
CREATE_VM=false
VM_NAME=""

# Colors for output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "$*"; }
log_warning() { echo -e "${YELLOW}WARNING:${NC} $*"; }
log_error() { echo -e "${RED}ERROR:${NC} $*"; }

show_usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Import OpenBSD VMDK image from GCS and optionally create a VM.

OPTIONS:
    --source-file GS_PATH    GCS path to VMDK (e.g., gs://bucket/openbsd.vmdk)
    --name NAME              Image name (required)
    --project-id PROJECT     GCP project ID (default: ${DEFAULT_PROJECT_ID})
    --zone ZONE              GCP zone (default: ${DEFAULT_ZONE})
    --create-vm              Also create a VM after importing
    --vm-name NAME           VM name (default: <image-name>-vm)
    --machine-type TYPE      Machine type (default: ${DEFAULT_MACHINE_TYPE})
    --help                   Show this help message

EXAMPLES:
    # Import image only
    ${SCRIPT_NAME} --source-file gs://my-bucket/openbsd-7.8.vmdk --name openbsd-78

    # Import and create VM
    ${SCRIPT_NAME} --source-file gs://my-bucket/openbsd-7.8.vmdk --name openbsd-78 --create-vm

NOTES:
    - VMDK format allows sparse files, converted into GCE-compatible disk
    - --data-disk flag skips OS adaptation (no Linux drivers installed)
    - Ignore the warning "This is a data disk" - expected for OpenBSD

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --source-file)
                SOURCE_FILE="$2"
                shift 2
                ;;
            --name)
                IMAGE_NAME="$2"
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
            --create-vm)
                CREATE_VM=true
                shift
                ;;
            --vm-name)
                VM_NAME="$2"
                shift 2
                ;;
            --machine-type)
                MACHINE_TYPE="$2"
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

    if [[ "${SOURCE_FILE}" != gs://* ]]; then
        log_error "Source file must be a GCS path (gs://...)"
        log_error "Use 03-upload-to-gcs.sh first to upload your local file."
        exit 1
    fi

    if [[ -z "${IMAGE_NAME}" ]]; then
        log_error "Image name is required. Use --name option."
        exit 1
    fi

    if [[ -z "${VM_NAME}" ]]; then
        VM_NAME="${IMAGE_NAME}-vm"
    fi
}

import_image() {
    log_info "Importing OpenBSD image to GCP..."
    log_info "  Source: ${SOURCE_FILE}"
    log_info "  Image name: ${IMAGE_NAME}"
    log_info "  Project: ${PROJECT_ID}"
    log_info "  Zone: ${ZONE}"
    log_info ""
    log_warning "Note: You will see a warning 'This is a data disk' - this is expected."
    log_info ""

    # Import VMDK as data disk (skips OS adaptation)
    # --cmd-deprecated is required as this command is being deprecated
    gcloud compute images import "${IMAGE_NAME}" \
        --cmd-deprecated \
        --source-file="${SOURCE_FILE}" \
        --data-disk \
        --project="${PROJECT_ID}" \
        --zone="${ZONE}"

    log_info ""
    log_info "Image imported successfully: ${IMAGE_NAME}"
}

create_vm() {
    log_info ""
    log_info "Creating VM from imported image..."
    log_info "  VM name: ${VM_NAME}"
    log_info "  Image: ${IMAGE_NAME}"
    log_info "  Machine type: ${MACHINE_TYPE}"
    log_info "  Zone: ${ZONE}"
    log_info ""

    gcloud compute instances create "${VM_NAME}" \
        --image="${IMAGE_NAME}" \
        --zone="${ZONE}" \
        --machine-type="${MACHINE_TYPE}" \
        --project="${PROJECT_ID}"

    log_info ""
    log_info "VM created successfully: ${VM_NAME}"
    log_info ""
    log_info "Connect with:"
    log_info "  gcloud compute ssh ${VM_NAME} --zone=${ZONE} --project=${PROJECT_ID}"
}

main() {
    echo -e "${BLUE}"
    echo "============================================"
    echo "     OpenBSD GCP Image Import"
    echo "============================================"
    echo -e "${NC}"

    parse_arguments "$@"

    import_image

    if [[ "${CREATE_VM}" == "true" ]]; then
        create_vm
    else
        log_info ""
        log_info "To create a VM from this image:"
        log_info "  gcloud compute instances create openbsd-server \\"
        log_info "    --image=${IMAGE_NAME} \\"
        log_info "    --zone=${ZONE} \\"
        log_info "    --machine-type=${MACHINE_TYPE} \\"
        log_info "    --project=${PROJECT_ID}"
    fi

    log_info ""
    log_info "If SSH connection is refused, ensure firewall allows port 22:"
    log_info "  gcloud compute firewall-rules create allow-ssh \\"
    log_info "    --allow=tcp:22 \\"
    log_info "    --source-ranges=0.0.0.0/0 \\"
    log_info "    --project=${PROJECT_ID}"
    log_info ""
    log_info "To check VM boot status via serial console:"
    log_info "  gcloud compute instances get-serial-port-output openbsd-server \\"
    log_info "    --zone=${ZONE} --project=${PROJECT_ID}"
    log_info ""
    log_info "To delete the VM:"
    log_info "  gcloud compute instances delete openbsd-server \\"
    log_info "    --zone=${ZONE} --project=${PROJECT_ID} --quiet"
    log_info ""
    log_info "To delete the image:"
    log_info "  gcloud compute images delete ${IMAGE_NAME} \\"
    log_info "    --project=${PROJECT_ID} --quiet"

    log_info ""
    log_info "Done."
}

main "$@"
