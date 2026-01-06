#!/bin/bash

# GCP Service Account Setup for OpenBSD Deployment
# Manages service account creation and permissions for VM Migration API

set -euo pipefail

# --- Configuration ---
PROJECT_ID="${PROJECT_ID:-your-project-id}"
SERVICE_ACCOUNT_NAME="openbsd-vm-migration"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
KEY_FILE="${HOME}/.gcp/openbsd-vm-migration-key.json"

# Auto-detect shell configuration file
if [ -n "${ZSH_VERSION:-}" ]; then
    SHELL_CONFIG="${HOME}/.zshrc"
elif [ -n "${BASH_VERSION:-}" ]; then
    if [ -f "${HOME}/.bashrc" ]; then
        SHELL_CONFIG="${HOME}/.bashrc"
    else
        SHELL_CONFIG="${HOME}/.bash_profile"
    fi
else
    SHELL_CONFIG="${HOME}/.profile"
fi

# Roles needed for OpenBSD VM deployment
ROLES=(
    "roles/vmmigration.admin"        # VM Migration API
    "roles/compute.instanceAdmin.v1"  # Create/manage VMs and images
    "roles/storage.admin"             # GCS bucket access
)

# APIs to enable
APIS=(
    "vmmigration.googleapis.com"
    "compute.googleapis.com"
    "storage-component.googleapis.com"
)

# Colors for output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

# --- Error Handling ---
error_exit() {
    echo -e "\n${RED}ERROR: $1${NC}" >&2
    exit 1
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v gcloud &>/dev/null; then
        error_exit "'gcloud' command not found. Install Google Cloud SDK."
    fi
    
    if [ "${PROJECT_ID}" == "your-project-id" ]; then
        error_exit "Set PROJECT_ID environment variable: export PROJECT_ID='your-gcp-project'"
    fi
    
    log_info "Using Project ID: ${PROJECT_ID}"
    gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project. Check project ID and permissions."
    echo "---"
}

# --- SETUP FUNCTION ---
setup() {
    check_prerequisites
    
    echo -e "\n${GREEN}--- SETTING UP SERVICE ACCOUNT FOR OPENBSD DEPLOYMENT ---${NC}"
    
    # 1. Enable required APIs
    log_info "Enabling required Google Cloud APIs..."
    for API in "${APIS[@]}"; do
        echo "   -> Enabling: ${API}"
        gcloud services enable "${API}" --project="${PROJECT_ID}" 2>/dev/null || \
            log_warning "Failed to enable ${API} (may already be enabled)"
    done
    log_info "APIs enabled successfully"
    echo "---"
    
    # 2. Create the Service Account
    log_info "Creating Service Account: ${SERVICE_ACCOUNT_NAME}..."
    if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" --project="${PROJECT_ID}" &>/dev/null; then
        log_info "Service Account already exists"
    else
        gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
            --display-name="OpenBSD VM Migration Service Account" \
            --project="${PROJECT_ID}" || error_exit "Failed to create service account"
        log_info "Service Account created successfully"
        
        log_info "Waiting 10 seconds for IAM resource propagation..."
        sleep 10
    fi
    echo "---"
    
    # 3. Grant Required Permissions
    log_info "Granting IAM Roles to Service Account..."
    for ROLE in "${ROLES[@]}"; do
        echo "   -> Granting role: ${ROLE}"
        MAX_RETRIES=3
        RETRY_COUNT=0
        
        while [ ${RETRY_COUNT} -lt ${MAX_RETRIES} ]; do
            if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
                --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
                --role="${ROLE}" \
                --condition=None \
                --no-user-output-enabled 2>/dev/null; then
                break
            else
                RETRY_COUNT=$((RETRY_COUNT + 1))
                if [ ${RETRY_COUNT} -lt ${MAX_RETRIES} ]; then
                    echo "      Retry ${RETRY_COUNT}/${MAX_RETRIES} after 5 seconds..."
                    sleep 5
                else
                    log_warning "Failed to grant ${ROLE} after ${MAX_RETRIES} attempts"
                fi
            fi
        done
    done
    log_info "All roles granted successfully"
    
    log_info "Waiting 15 seconds for IAM policy propagation..."
    sleep 15
    echo "---"
    
    # 4. Create and Download Service Account Key
    log_info "Creating and downloading key file to: ${KEY_FILE}..."
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "${KEY_FILE}")"
    
    # Delete old key file if it exists
    if [ -f "${KEY_FILE}" ]; then
        log_info "Removing old key file..."
        rm -f "${KEY_FILE}"
    fi
    
    gcloud iam service-accounts keys create "${KEY_FILE}" \
        --iam-account="${SERVICE_ACCOUNT_EMAIL}" \
        --project="${PROJECT_ID}" || error_exit "Failed to create and download key"
    
    # Set secure permissions on key file
    chmod 600 "${KEY_FILE}"
    log_info "Key downloaded successfully with secure permissions (600)"
    echo "---"
    
    # 5. Set Environment Variables
    log_info "Setting environment variables in ${SHELL_CONFIG}..."
    
    # Create backup
    cp "${SHELL_CONFIG}" "${SHELL_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    
    # Remove old entries to avoid duplicates
    if [ -f "${SHELL_CONFIG}" ]; then
        grep -v "^export GOOGLE_APPLICATION_CREDENTIALS=" "${SHELL_CONFIG}" > "${SHELL_CONFIG}.tmp" || true
        grep -v "^export GOOGLE_CLOUD_PROJECT=" "${SHELL_CONFIG}.tmp" > "${SHELL_CONFIG}.tmp2" || true
        mv "${SHELL_CONFIG}.tmp2" "${SHELL_CONFIG}"
        rm -f "${SHELL_CONFIG}.tmp"
    fi
    
    # Add new entries
    echo "" >> "${SHELL_CONFIG}"
    echo "# Google Cloud credentials for OpenBSD VM deployment" >> "${SHELL_CONFIG}"
    echo "export GOOGLE_APPLICATION_CREDENTIALS=\"${KEY_FILE}\"" >> "${SHELL_CONFIG}"
    echo "export GOOGLE_CLOUD_PROJECT=\"${PROJECT_ID}\"" >> "${SHELL_CONFIG}"
    
    # Set variables for current session
    export GOOGLE_APPLICATION_CREDENTIALS="${KEY_FILE}"
    export GOOGLE_CLOUD_PROJECT="${PROJECT_ID}"
    
    log_info "Environment variables set for current and future sessions"
    echo "---"
    
    # 6. Verify setup
    log_info "Verifying setup..."
    echo "   Service Account: ${SERVICE_ACCOUNT_EMAIL}"
    echo "   Key File: ${KEY_FILE}"
    echo "   Project ID: ${PROJECT_ID}"
    echo "   Shell Config: ${SHELL_CONFIG}"
    
    if [ -f "${KEY_FILE}" ]; then
        echo "   ✓ Key file exists and is readable"
    else
        error_exit "Key file was not created successfully"
    fi
    echo "---"
    
    # 7. Final Instructions
    echo -e "\n${GREEN}✓ SERVICE ACCOUNT SETUP COMPLETE! ✓${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT: You must now add the target project through the console:${NC}"
    echo ""
    echo "1. Go to: https://console.cloud.google.com/compute/instances/migrate?project=${PROJECT_ID}"
    echo "2. Click the 'Targets' tab"
    echo "3. Click 'Add Project'"
    echo "4. Select project '${PROJECT_ID}'"
    echo "5. Click 'Add'"
    echo "6. Wait 1-2 minutes for the project to be ready"
    echo ""
    echo "After completing the above steps, import OpenBSD to GCP:"
    echo ""
    echo "Step 1 - Upload VMDK to GCS:"
    echo -e "   ${YELLOW}./03-upload-to-gcs.sh --source-file build/artifacts/openbsd-7.8.vmdk --bucket ${PROJECT_ID}-images${NC}"
    echo ""
    echo "Step 2 - Import image and create VM:"
    echo -e "   ${YELLOW}./04-gcp-image-import.sh --source-file gs://${PROJECT_ID}-images/openbsd-7.8.vmdk --name openbsd-78 --create-vm${NC}"
    echo ""
    echo "Note: Target project setup is a one-time configuration per GCP project."
    echo ""
}

# --- CLEANUP FUNCTION ---
cleanup() {
    check_prerequisites
    
    echo -e "\n${RED}--- CLEANING UP SERVICE ACCOUNT ---${NC}"
    echo "This will remove the service account and all associated resources."
    read -p "Are you sure? (yes/no): " -r
    if [[ ! ${REPLY} =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
    
    # 1. Delete all keys for the service account
    log_info "Deleting service account keys..."
    KEYS=$(gcloud iam service-accounts keys list \
        --iam-account="${SERVICE_ACCOUNT_EMAIL}" \
        --project="${PROJECT_ID}" \
        --filter="keyType:USER_MANAGED" \
        --format="value(name)" 2>/dev/null || true)
    
    if [ -n "${KEYS}" ]; then
        while IFS= read -r KEY; do
            echo "   -> Deleting key: ${KEY}"
            gcloud iam service-accounts keys delete "${KEY}" \
                --iam-account="${SERVICE_ACCOUNT_EMAIL}" \
                --project="${PROJECT_ID}" \
                --quiet 2>/dev/null || log_warning "Failed to delete key"
        done <<< "${KEYS}"
    else
        log_info "No keys found to delete"
    fi
    echo "---"
    
    # 2. Remove IAM Roles
    log_info "Removing IAM Roles from Service Account..."
    for ROLE in "${ROLES[@]}"; do
        echo "   -> Removing role: ${ROLE}"
        gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
            --role="${ROLE}" \
            --all 2>/dev/null || log_warning "Role may not exist"
    done
    log_info "IAM roles removal attempted"
    echo "---"
    
    # 3. Delete local key file
    log_info "Deleting local key file: ${KEY_FILE}..."
    if [ -f "${KEY_FILE}" ]; then
        rm -f "${KEY_FILE}"
        log_info "Key file deleted"
    else
        log_info "Key file not found, skipping"
    fi
    echo "---"
    
    # 4. Delete the Service Account
    log_info "Deleting Service Account: ${SERVICE_ACCOUNT_NAME}..."
    gcloud iam service-accounts delete "${SERVICE_ACCOUNT_EMAIL}" \
        --project="${PROJECT_ID}" \
        --quiet 2>/dev/null || log_warning "Service account may not exist"
    log_info "Service Account deletion attempted"
    echo "---"
    
    # 5. Clean up Shell Configuration
    log_info "Removing environment variables from ${SHELL_CONFIG}..."
    
    if [ -f "${SHELL_CONFIG}" ]; then
        # Create backup
        cp "${SHELL_CONFIG}" "${SHELL_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Remove the Google Cloud credentials section
        grep -v "^export GOOGLE_APPLICATION_CREDENTIALS=" "${SHELL_CONFIG}" > "${SHELL_CONFIG}.tmp" || true
        grep -v "^export GOOGLE_CLOUD_PROJECT=" "${SHELL_CONFIG}.tmp" > "${SHELL_CONFIG}.tmp2" || true
        grep -v "^# Google Cloud credentials for OpenBSD VM deployment" "${SHELL_CONFIG}.tmp2" > "${SHELL_CONFIG}" || true
        rm -f "${SHELL_CONFIG}.tmp" "${SHELL_CONFIG}.tmp2"
    fi
    
    # Unset variables for current session
    unset GOOGLE_APPLICATION_CREDENTIALS
    unset GOOGLE_CLOUD_PROJECT
    
    log_info "Environment variables removed"
    echo "---"
    
    echo -e "\n${GREEN}✓ CLEANUP COMPLETE! ✓${NC}"
    echo ""
    echo "To finalize cleanup in your current terminal:"
    echo -e "${YELLOW}source ${SHELL_CONFIG}${NC}"
    echo ""
}

# --- CHECK FUNCTION ---
check() {
    check_prerequisites
    
    echo -e "\n${GREEN}--- CHECKING OPENBSD VM MIGRATION SETUP ---${NC}"
    
    local all_good=true
    
    # 1. Check if APIs are enabled
    log_info "Checking required APIs..."
    for API in "${APIS[@]}"; do
        if gcloud services list --enabled --project="${PROJECT_ID}" --filter="name:${API}" --format="value(name)" 2>/dev/null | grep -q "${API}"; then
            echo "   ✓ ${API}"
        else
            echo "   ✗ ${API} (not enabled)"
            all_good=false
        fi
    done
    echo "---"
    
    # 2. Check if service account exists
    log_info "Checking service account..."
    if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" --project="${PROJECT_ID}" &>/dev/null; then
        echo "   ✓ Service Account exists: ${SERVICE_ACCOUNT_EMAIL}"
    else
        echo "   ✗ Service Account not found"
        all_good=false
    fi
    echo "---"
    
    # 3. Check if service account has required roles
    log_info "Checking IAM roles..."
    for ROLE in "${ROLES[@]}"; do
        if gcloud projects get-iam-policy "${PROJECT_ID}" \
            --flatten="bindings[].members" \
            --filter="bindings.role:${ROLE}" \
            --format="value(bindings.members)" 2>/dev/null | grep -q "${SERVICE_ACCOUNT_EMAIL}"; then
            echo "   ✓ ${ROLE}"
        else
            echo "   ✗ ${ROLE} (not granted)"
            all_good=false
        fi
    done
    echo "---"
    
    # 4. Check if key file exists
    log_info "Checking credentials file..."
    if [ -f "${KEY_FILE}" ]; then
        echo "   ✓ Key file exists: ${KEY_FILE}"
        local perms=$(stat -f "%OLp" "${KEY_FILE}" 2>/dev/null || stat -c "%a" "${KEY_FILE}" 2>/dev/null)
        if [ "${perms}" == "600" ]; then
            echo "   ✓ Permissions are secure (600)"
        else
            echo "   ⚠ Permissions are ${perms} (should be 600)"
            log_warning "Run: chmod 600 ${KEY_FILE}"
        fi
    else
        echo "   ✗ Key file not found"
        all_good=false
    fi
    echo "---"
    
    # 5. Check environment variables
    log_info "Checking environment variables..."
    local env_vars_in_shell_config=false
    
    # Check if variables are in shell config
    if [ -f "${SHELL_CONFIG}" ]; then
        if grep -q "GOOGLE_APPLICATION_CREDENTIALS" "${SHELL_CONFIG}" && \
           grep -q "GOOGLE_CLOUD_PROJECT" "${SHELL_CONFIG}"; then
            env_vars_in_shell_config=true
        fi
    fi
    
    if [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]; then
        echo "   ✓ GOOGLE_APPLICATION_CREDENTIALS is set"
        if [ "${GOOGLE_APPLICATION_CREDENTIALS}" == "${KEY_FILE}" ]; then
            echo "   ✓ Points to correct key file"
        else
            echo "   ⚠ Points to: ${GOOGLE_APPLICATION_CREDENTIALS}"
            echo "   ⚠ Expected: ${KEY_FILE}"
        fi
    else
        if [ "$env_vars_in_shell_config" = true ]; then
            echo "   ⚠ GOOGLE_APPLICATION_CREDENTIALS not set in current session"
            echo "   → Variables are in ${SHELL_CONFIG}"
            echo "   → Load them with: source ${SHELL_CONFIG}"
        else
            echo "   ✗ GOOGLE_APPLICATION_CREDENTIALS not set"
            echo "   Run: export GOOGLE_APPLICATION_CREDENTIALS=\"${KEY_FILE}\""
            all_good=false
        fi
    fi
    
    if [ -n "${GOOGLE_CLOUD_PROJECT:-}" ]; then
        echo "   ✓ GOOGLE_CLOUD_PROJECT is set: ${GOOGLE_CLOUD_PROJECT}"
    else
        if [ "$env_vars_in_shell_config" = true ]; then
            echo "   ⚠ GOOGLE_CLOUD_PROJECT not set in current session"
            echo "   → Variables are in ${SHELL_CONFIG}"
            echo "   → Load them with: source ${SHELL_CONFIG}"
        else
            echo "   ✗ GOOGLE_CLOUD_PROJECT not set"
            echo "   Run: export GOOGLE_CLOUD_PROJECT=\"${PROJECT_ID}\""
            all_good=false
        fi
    fi
    echo "---"
    
    # 6. Final status
    if [ "$all_good" = true ]; then
        echo -e "\n${GREEN}✓ ALL CHECKS PASSED! ✓${NC}"
        echo ""
        echo "Your GCP setup is complete. You can now import:"
        echo ""
        echo "Step 1 - Upload VMDK to GCS:"
        echo -e "   ${YELLOW}./03-upload-to-gcs.sh --source-file build/artifacts/openbsd-7.8.vmdk --bucket ${PROJECT_ID}-images${NC}"
        echo ""
        echo "Step 2 - Import image and create VM:"
        echo -e "   ${YELLOW}./04-gcp-image-import.sh --source-file gs://${PROJECT_ID}-images/openbsd-7.8.vmdk --name openbsd-78 --create-vm${NC}"
        echo ""
        return 0
    else
        # Check if the only issue is environment variables not loaded in current session
        if [ "$env_vars_in_shell_config" = true ] && \
           [ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]; then
            echo -e "\n${YELLOW}⚠ SETUP COMPLETE - Environment Variables Not Loaded${NC}"
            echo ""
            echo "Your setup is complete, but environment variables are not active in this session."
            echo ""
            echo "Load them now:"
            echo -e "   ${YELLOW}source ${SHELL_CONFIG}${NC}"
            echo ""
            echo "Then verify:"
            echo -e "   ${YELLOW}./02-setup-gcp-service-account.sh check${NC}"
            echo ""
            return 1
        else
            echo -e "\n${RED}✗ SOME CHECKS FAILED${NC}"
            echo ""
            echo "Please run setup to fix issues:"
            echo -e "   ${YELLOW}./02-setup-gcp-service-account.sh setup${NC}"
            echo ""
            return 1
        fi
    fi
}

# --- Script Entry Point ---
show_usage() {
    cat << EOF
Usage: $(basename "$0") [setup|check|cleanup]

GCP Service Account Manager for OpenBSD VM Deployment

Commands:
  setup   - Create service account and configure credentials
  check   - Verify that setup completed successfully
  cleanup - Remove service account and all associated resources

Environment Variables:
  PROJECT_ID - Your Google Cloud Project ID (required)

Example:
  export PROJECT_ID="my-gcp-project"
  ./02-setup-gcp-service-account.sh setup
  ./02-setup-gcp-service-account.sh check

EOF
}

if [ -z "${1:-}" ]; then
    show_usage
    exit 1
fi

case "$1" in
    setup)
        setup
        ;;
    check)
        check
        ;;
    cleanup)
        cleanup
        ;;
    *)
        echo "Invalid argument: $1"
        show_usage
        exit 1
        ;;
esac
