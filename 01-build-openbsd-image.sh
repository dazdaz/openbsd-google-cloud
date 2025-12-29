#!/bin/bash

# OpenBSD QEMU Deployment Script - Enhanced with Working Approach
# Based on golang/build and MengshiLi approaches
# Version: 2.0.8 - Final working version with complete fixes
# Author: OpenBSD Deployment Team

set -euo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEFAULT_OPENBSD_VERSION="7.8"
readonly DEFAULT_MEMORY="2G"
readonly DEFAULT_CPUS="2"
readonly DEFAULT_OUTPUT_DIR="${SCRIPT_DIR}/build"
readonly DEFAULT_DISK_SIZE="30G"

# Global variables
OPENBSD_VERSION="${DEFAULT_OPENBSD_VERSION}"
MEMORY="${DEFAULT_MEMORY}"
CPUS="${DEFAULT_CPUS}"
OUTPUT_DIR="${DEFAULT_OUTPUT_DIR}"
DISK_SIZE="${DEFAULT_DISK_SIZE}"
CONFIG_FILE=""
VERBOSE=false
DEBUG=false
FORCE_REBUILD=false
AUTO_INSTALL=false
SKIP_INSTALL=false

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Detect operating system
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get >/dev/null 2>&1; then
            echo "debian"
        elif command -v yum >/dev/null 2>&1; then
            echo "rhel"
        elif command -v dnf >/dev/null 2>&1; then
            echo "fedora"
        else
            echo "linux"
        fi
    else
        echo "unknown"
    fi
}

# Install QEMU and dependencies
install_qemu() {
    local os_type=$(detect_os)
    
    log_info "Detected OS: ${os_type}"
    log_info "Installing QEMU and dependencies..."
    
    case "${os_type}" in
        macos)
            # Check if Homebrew is installed
            if ! command -v brew >/dev/null 2>&1; then
                log_error "Homebrew is not installed. Installing Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            
            log_info "Installing QEMU via Homebrew..."
            brew install qemu expect xorriso || {
                log_error "Failed to install QEMU via Homebrew"
                return 1
            }
            ;;
            
        debian)
            log_info "Installing QEMU via apt-get..."
            if [[ $EUID -ne 0 ]]; then
                log_warning "Not running as root, using sudo..."
                sudo apt-get update
                sudo apt-get install -y qemu-system-x86 qemu-utils expect xorriso || {
                    log_error "Failed to install QEMU via apt-get"
                    return 1
                }
            else
                apt-get update
                apt-get install -y qemu-system-x86 qemu-utils expect xorriso || {
                    log_error "Failed to install QEMU"
                    return 1
                }
            fi
            ;;
            
        rhel|fedora)
            log_info "Installing QEMU via yum/dnf..."
            local pkg_manager="yum"
            if command -v dnf >/dev/null 2>&1; then
                pkg_manager="dnf"
            fi
            
            if [[ $EUID -ne 0 ]]; then
                log_warning "Not running as root, using sudo..."
                sudo ${pkg_manager} install -y qemu-kvm qemu-img expect xorriso || {
                    log_error "Failed to install QEMU via ${pkg_manager}"
                    return 1
                }
            else
                ${pkg_manager} install -y qemu-kvm qemu-img expect xorriso || {
                    log_error "Failed to install QEMU"
                    return 1
                }
            fi
            ;;
            
        *)
            log_error "Unsupported operating system: ${os_type}"
            log_error "Please install QEMU manually:"
            log_error "  - qemu-system-x86_64"
            log_error "  - qemu-img"
            log_error "  - expect"
            log_error "  - xorriso"
            return 1
            ;;
    esac
    
    log_success "QEMU and dependencies installed successfully"
    return 0
}

# Check and install dependencies
check_dependencies() {
    local missing_deps=()
    local os_type=$(detect_os)
    
    log_info "Checking dependencies..."
    
    # Check for QEMU
    if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
        missing_deps+=("qemu-system-x86_64")
    fi
    
    # Check for qemu-img
    if ! command -v qemu-img >/dev/null 2>&1; then
        missing_deps+=("qemu-img")
    fi
    
    # Check for expect
    if ! command -v expect >/dev/null 2>&1; then
        missing_deps+=("expect")
    fi
    
    # Check for xorriso
    if ! command -v xorriso >/dev/null 2>&1; then
        missing_deps+=("xorriso")
    fi
    
    # Check for extraction tools
    if ! command -v 7z >/dev/null 2>&1 && ! command -v bsdtar >/dev/null 2>&1; then
        if [[ "${os_type}" == "macos" ]]; then
            missing_deps+=("p7zip")
        else
            missing_deps+=("p7zip-full or bsdtar")
        fi
    fi
    
    if [[ ${#missing_deps[@]} -eq 0 ]]; then
        log_success "All dependencies are installed ✓"
        return 0
    fi
    
    log_warning "Missing dependencies: ${missing_deps[*]}"
    
    if [[ "${SKIP_INSTALL}" == "true" ]]; then
        log_error "Missing dependencies and --skip-install specified. Exiting."
        return 1
    fi
    
    if [[ "${AUTO_INSTALL}" == "true" ]]; then
        log_info "Auto-installing missing dependencies..."
        install_qemu
        return $?
    fi
    
    # Prompt user
    echo ""
    log_warning "The following dependencies are missing:"
    for dep in "${missing_deps[@]}"; do
        echo "  - ${dep}"
    done
    echo ""
    echo -e "${YELLOW}Would you like to install them now? (y/N)${NC}"
    read -r response
    
    if [[ "${response}" =~ ^[Yy]$ ]]; then
        install_qemu
        return $?
    else
        log_error "Dependencies required. Exiting."
        log_info "To auto-install next time, use: $0 --auto-install"
        return 1
    fi
}

# Working directory setup
setup_directories() {
    log_info "Setting up directories..."
    mkdir -p "${OUTPUT_DIR}/"{artifacts,cache,temp,logs}
    log_success "Directories created successfully"
}

# Download OpenBSD ISO
download_iso() {
    local version="$1"
    local iso_url="https://cdn.openbsd.org/pub/OpenBSD/${version}/amd64/install${version//./}.iso"
    local iso_file="${OUTPUT_DIR}/cache/install${version//./}.iso"
    
    if [[ -f "${iso_file}" && "${FORCE_REBUILD}" != "true" ]]; then
        log_info "ISO already exists, skipping download"
        return 0
    fi
    
    log_info "Downloading OpenBSD ${version} ISO..."
    curl -L -o "${iso_file}" "${iso_url}"
    log_success "ISO downloaded successfully"
}

# Create site package (based on golang/build approach)
create_site_package() {
    local version="$1"
    local work_dir="$2"
    local site_dir="${work_dir}/site"
    
    log_info "Creating site package..."
    
    mkdir -p "${site_dir}/"{etc,usr/local/bin}
    
    # install.site - runs after installation
    cat >"${site_dir}/install.site" <<'INSTALLSITE'
#!/bin/sh
echo "Running post-installation setup..."

# Configure serial console
echo 'set tty com0' > /etc/boot.conf

# Configure package repository
echo "https://cdn.openbsd.org/pub/OpenBSD" > /etc/installurl

# Install essential packages
pkg_add -I bash curl git vim htop

# Configure network
echo "dhcp" > /etc/hostname.vio0

# Enable SSH
rcctl enable sshd
rcctl start sshd

# Configure system limits
cat > /etc/login.conf.d/moreres <<EOLOGIN
moreres:\\
  :datasize-max=infinity: \\
  :datasize-cur=infinity: \\
  :vmemoryuse-max=infinity: \\
  :vmemoryuse-cur=infinity: \\
  :memoryuse-max=infinity: \\
  :memoryuse-cur=infinity: \\
  :maxproc-max=2048: \\
  :maxproc-cur=2048: \\
  :openfiles-max=4096: \\
  :openfiles-cur=4096: \\
  :tc=default:
EOLOGIN

# Configure sysctl
cat > /etc/sysctl.conf <<EOSYSCTL
hw.smt=1
kern.timecounter.hardware=tsc
EOSYSCTL

# Configure rc.local for startup
cat > /etc/rc.local <<EORC
echo "OpenBSD system started successfully"
EORC

# Basic security setup
echo "root ALL=(ALL:ALL) ALL" >> /etc/sudoers
chmod 700 /root

echo "Post-installation setup completed"
INSTALLSITE

    chmod +x "${site_dir}/install.site"
    
    # Create site package
    tar -C "${site_dir}" -zcf "${work_dir}/site${version//./}.tgz" .
    log_success "Site package created"
}

# Create autoinstall configuration (based on golang/build approach)
create_autoinstall_config() {
    local version="$1"
    local work_dir="$2"
    
    log_info "Creating autoinstall configuration..."
    
    cat >"${work_dir}/auto_install.conf" <<EOF
System hostname = openbsd-${version}
Which network interface = vio0
IPv4 address for vio0 = dhcp
IPv6 address for vio0 = none
Password for root account = root
Do you expect to run the X Window System = no
Change the default console to com0 = yes
Which speed should com0 use = 115200
Setup a user = swarming
Full name for user swarming = Swarming User
Password for user swarming = swarming
Allow root ssh login = yes
What timezone = UTC
Which disk = sd0
Use (W)hole disk or (E)dit the MBR = whole
Use (A)uto layout, (E)dit auto layout, or create (C)ustom layout = auto
URL to autopartitioning template for disklabel = file://disklabel.template
Location of sets = cd1
Set name(s) = +* -x* -game* -man*
Directory does not contain SHA256.sig. Continue without verification = yes
EOF

    cat >"${work_dir}/disklabel.template" <<EOF
/	5G-*	95%
swap	2G
EOF

    cat >"${work_dir}/boot.conf" <<EOF
set tty com0
set timeout 5
boot bsd.rd
EOF

    dd if=/dev/urandom of="${work_dir}/random.seed" bs=4096 count=1
    log_success "Autoinstall configuration created"
}

# Patch ISO with working approach
patch_iso() {
    local original_iso="$1"
    local patched_iso="$2"
    local work_dir="$3"
    local version="$4"
    
    log_info "Patching ISO with working approach..."
    
    # Create site package
    create_site_package "${version}" "${work_dir}"
    
    # Create autoinstall files
    create_autoinstall_config "${version}" "${work_dir}"
    
    # Extract ISO contents
    local iso_extract="${work_dir}/iso_extract"
    mkdir -p "${iso_extract}"
    
    if command -v 7z >/dev/null 2>&1; then
        7z x -o"${iso_extract}" "${original_iso}" >/dev/null
    elif command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xf "${original_iso}" -C "${iso_extract}"
    else
        log_error "Neither 7z nor bsdtar available for ISO extraction"
        return 1
    fi
    
    # Add our files to the extracted ISO
    mkdir -p "${iso_extract}/${version}/amd64"
    cp "${work_dir}/site${version//./}.tgz" "${iso_extract}/${version}/amd64/"
    cp "${work_dir}/auto_install.conf" "${iso_extract}/"
    cp "${work_dir}/disklabel.template" "${iso_extract}/"
    mkdir -p "${iso_extract}/etc"
    cp "${work_dir}/boot.conf" "${iso_extract}/etc/"
    cp "${work_dir}/random.seed" "${iso_extract}/etc/"
    
    # Find and prepare boot file - must be at root for El Torito
    local boot_file="cdbr"
    local source_boot=""
    
    if [[ -f "${iso_extract}/cdbr" ]]; then
        source_boot="${iso_extract}/cdbr"
    elif [[ -f "${iso_extract}/${version}/amd64/cdbr" ]]; then
        source_boot="${iso_extract}/${version}/amd64/cdbr"
        # Copy to root for El Torito
        cp "${source_boot}" "${iso_extract}/cdbr"
    elif [[ -f "${iso_extract}/cdboot" ]]; then
        boot_file="cdboot"
        source_boot="${iso_extract}/cdboot"
    elif [[ -f "${iso_extract}/${version}/amd64/cdboot" ]]; then
        boot_file="cdboot"
        source_boot="${iso_extract}/${version}/amd64/cdboot"
        # Copy to root for El Torito
        cp "${source_boot}" "${iso_extract}/cdboot"
    else
        log_error "Cannot find boot file in extracted ISO"
        log_info "Contents of iso_extract:"
        ls -la "${iso_extract}/" || true
        return 1
    fi
    
    log_info "Using boot file: ${boot_file} (from ${source_boot})"
    
    # Rebuild ISO with xorriso preserving boot structure
    if command -v xorriso >/dev/null 2>&1; then
        xorriso -as mkisofs \
            -o "${patched_iso}" \
            -R -J -l \
            -V "OpenBSD_${version}" \
            -c boot.catalog \
            -b "${boot_file}" \
            -no-emul-boot \
            -boot-load-size 4 \
            -boot-info-table \
            "${iso_extract}"
    else
        log_error "xorriso not available for ISO creation"
        return 1
    fi
    
    log_success "ISO patched successfully"
}

# Create disk image with working approach
create_disk_image() {
    local version="$1"
    local work_dir="$2"
    
    log_info "Creating disk image..."
    
    local disk_raw="${work_dir}/disk.raw"
    local disk_qcow2="${OUTPUT_DIR}/artifacts/openbsd-${version}.qcow2"
    
    # Create raw disk
    qemu-img create -f raw "${disk_raw}" "${DISK_SIZE}"
    
    # Use original unmodified ISO
    local original_iso="${OUTPUT_DIR}/cache/install${version//./}.iso"
    
    # Create site package and config files
    create_site_package "${version}" "${work_dir}"
    create_autoinstall_config "${version}" "${work_dir}"
    
    # Create a config ISO with our files
    local config_dir="${work_dir}/config_iso"
    mkdir -p "${config_dir}/${version}/amd64"
    cp "${work_dir}/site${version//./}.tgz" "${config_dir}/${version}/amd64/"
    cp "${work_dir}/auto_install.conf" "${config_dir}/"
    cp "${work_dir}/disklabel.template" "${config_dir}/"
    mkdir -p "${config_dir}/etc"
    cp "${work_dir}/boot.conf" "${config_dir}/etc/"
    cp "${work_dir}/random.seed" "${config_dir}/etc/"
    
    # Debug: Check what files we're about to put on the ISO
    log_info "Files in config_dir before ISO creation:"
    ls -laR "${config_dir}" >&2 || log_error "Failed to list config_dir"
    
    local config_iso="${work_dir}/config.iso"
    if command -v xorriso >/dev/null 2>&1; then
        log_info "Creating config ISO with xorriso..."
        xorriso -as mkisofs -o "${config_iso}" -R -J "${config_dir}" 2>&1 | tee "${OUTPUT_DIR}/logs/xorriso.log" || {
            log_error "Failed to create config ISO"
            return 1
        }
    else
        log_error "xorriso not available for creating config ISO"
        return 1
    fi
    
    # Verify ISO was created
    if [[ -f "${config_iso}" ]]; then
        log_info "Config ISO created: $(ls -lh "${config_iso}")"
    else
        log_error "Config ISO was not created!"
        return 1
    fi
    
    log_info "Starting OpenBSD installation (this will take 15-30 minutes)..."
    
    # Use expect for automated installation
    if ! command -v expect >/dev/null 2>&1; then
        log_error "expect is required for automated installation"
        return 1
    fi
    
    log_info "QEMU command: qemu-system-x86_64 -nographic -smp ${CPUS} -m ${MEMORY} -drive if=virtio,file=${disk_raw},format=raw -cdrom ${original_iso} -drive file=${config_iso},media=cdrom,readonly=on"
    
    log_info "Starting expect script..."
    expect <<EOF 2>&1 | tee "${OUTPUT_DIR}/logs/expect.log"
set timeout 1800
log_user 1

spawn qemu-system-x86_64 -nographic -smp ${CPUS} -m ${MEMORY} \
  -drive if=virtio,file=${disk_raw},format=raw \
  -cdrom "${original_iso}" \
  -drive file=${config_iso},media=cdrom,readonly=on \
  -net nic,model=virtio -net user -boot once=d

# Wait for boot prompt and set console, then boot
expect {
    timeout { 
        send_user "Timeout waiting for boot prompt\n"
        exit 1 
    }
    "boot>"
}
send "stty com0\n"
expect "boot>"
send "set tty com0\n"
expect "boot>"
send "boot\n"

# Wait for kernel to load and installer menu to appear
expect {
    timeout { 
        send_user "Timeout waiting for installer menu\n"
        exit 1 
    }
    "\\(I\\)nstall, \\(U\\)pgrade, \\(A\\)utoinstall or \\(S\\)hell\\?"
}
send "s\n"

# Wait for shell prompt
expect {
    timeout { 
        send_user "Timeout waiting for shell prompt\n"
        exit 1 
    }
    "# "
}

# Create device nodes and mount config ISO (cd0 based on QEMU device order)
send "cd /dev && sh MAKEDEV cd0\n"
expect "# "
send "mkdir -p /mnt2\n"
expect "# "
send "mount -t cd9660 /dev/cd0c /mnt2\n"
expect "# "
send "ls /mnt2/\n"
expect "# "
send "cp /mnt2/auto_install.conf /mnt2/disklabel.template /\n"
expect "# "
send "chmod a+r /disklabel.template\n"
expect "# "
send "ls -la /auto_install.conf /disklabel.template\n"
expect "# "
send "umount /mnt2\n"
expect "# "
send "exit\n"

# Wait for installer menu and manually select Autoinstall
expect {
    timeout { 
        send_user "Timeout waiting for installer menu after exit\n"
        exit 1 
    }
    "\\(I\\)nstall, \\(U\\)pgrade, \\(A\\)utoinstall or \\(S\\)hell\\?"
}
send "a\n"

# Wait for installation to complete
expect {
    timeout { 
        send_user "Timeout waiting for installation to complete\n"
        exit 1 
    }
    -re "(CONGRATULATIONS!|failed)" {
        if {\$expect_out(0,string) == "failed"} {
            send_user "Autoinstall failed, checking error log...\\n"
            send "s\n"
            expect "# "
            send "cat /tmp/ai/ai.log\n"
            expect "# "
            send "exit\n"
            exit 1
        }
    }
}

# Wait for system to reboot and login prompt
expect "login:"
send_user "Installation completed successfully, system has rebooted\\n"
send "root\\r"

expect "Password:"
send "root\\r"

expect {
    "# " { send_user "Logged in successfully\\n" }
    timeout { send_user "Login timeout\\n"; exit 1 }
}

send "halt -p\\r"

# Wait for system to shut down (with timeout)
expect {
    eof { send_user "System shut down successfully\\n" }
    timeout { send_user "Shutdown timeout, but installation completed successfully\\n" }
}

EOF
    
    # Convert to QCOW2 for local use
    qemu-img convert -f raw -O qcow2 "${disk_raw}" "${disk_qcow2}"
    
    # Create GCP-compatible tar.gz (following golang/build approach)
    local gce_targz="${OUTPUT_DIR}/artifacts/openbsd-${version}-gce.tar.gz"
    log_info "Creating GCP-compatible image (tar.gz with disk.raw)..."
    tar -C "${work_dir}" -Szcf "${gce_targz}" disk.raw
    
    log_success "Disk image created successfully"
    log_info "Generated files:"
    log_info "  - QCOW2 (for local testing): ${disk_qcow2}"
    log_info "  - GCP image (tar.gz): ${gce_targz}"
    log_info ""
    log_info "To upload to GCP:"
    log_info "  gsutil cp ${gce_targz} gs://YOUR_BUCKET/openbsd-${version}.tar.gz"
    log_info "  gcloud compute images create openbsd-${version} --source-uri=gs://YOUR_BUCKET/openbsd-${version}.tar.gz"
}

# Main deployment function
deploy_openbsd() {
    log_info "Starting OpenBSD deployment..."
    
    # Check and install dependencies
    if ! check_dependencies; then
        log_error "Failed to install dependencies"
        return 1
    fi
    
    # Setup directories
    setup_directories
    
    # Download ISO
    download_iso "${OPENBSD_VERSION}"
    
    # Create disk image
    local work_dir
    work_dir=$(mktemp -d)
    trap "rm -rf ${work_dir}" EXIT
    
    create_disk_image "${OPENBSD_VERSION}" "${work_dir}"
    
    log_success "OpenBSD deployment completed successfully!"
    log_info "Artifacts available in: ${OUTPUT_DIR}/artifacts"
}

# Main execution
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                OPENBSD_VERSION="$2"
                shift 2
                ;;
            --memory)
                MEMORY="$2"
                shift 2
                ;;
            --cpus)
                CPUS="$2"
                shift 2
                ;;
            --disk-size)
                DISK_SIZE="$2"
                shift 2
                ;;
            --output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --debug)
                DEBUG=true
                shift
                ;;
            --force)
                FORCE_REBUILD=true
                shift
                ;;
            --auto-install)
                AUTO_INSTALL=true
                shift
                ;;
            --skip-install)
                SKIP_INSTALL=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --version VERSION    OpenBSD version (default: 7.8)"
                echo "  --memory SIZE        VM memory size (default: 2G)"
                echo "  --cpus COUNT         CPU count (default: 2)"
                echo "  --disk-size SIZE     Disk size (default: 30G)"
                echo "  --output DIR         Output directory (default: ./build)"
                echo "  --auto-install       Automatically install QEMU if missing"
                echo "  --skip-install       Skip dependency installation (fail if missing)"
                echo "  --verbose            Verbose output"
                echo "  --debug              Debug output"
                echo "  --force              Force rebuild"
                echo ""
                echo "Dependency Installation:"
                echo "  By default, the script will prompt to install missing dependencies."
                echo "  Use --auto-install to skip the prompt and install automatically."
                echo "  Use --skip-install to exit immediately if dependencies are missing."
                echo ""
                echo "Supported Platforms:"
                echo "  - macOS (via Homebrew)"
                echo "  - Debian/Ubuntu (via apt-get)"
                echo "  - RHEL/CentOS/Fedora (via yum/dnf)"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Set verbose/debug flags
    if [[ "${VERBOSE}" == "true" ]]; then
        set -x
    fi
    
    deploy_openbsd
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
