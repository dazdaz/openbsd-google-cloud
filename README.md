# OpenBSD QEMU Deployment Script

A comprehensive bash script that automates the deployment of QEMU and creates patched OpenBSD images for local use. This solution transforms the interactive OpenBSD installation process into a fully automated pipeline.

> ⚠️ **WARNING**: Google Cloud's VM Migration API does **not support OpenBSD**. The `03-gcp-image-import.sh` script will not work because OpenBSD is not recognized as a valid guest operating system by the VM Migration service. Alternative approaches for importing OpenBSD images to GCP are still being investigated.

## 🚀 Features

### Core Functionality
- **Automatic QEMU Installation** - Detects OS and installs QEMU with appropriate dependencies
- **OpenBSD ISO Patching** - Transforms interactive installer into unattended autoinstall
- **Automated Installation** - Boots QEMU with patched ISO for hands-off installation
- **Image Processing** - Extracts, optimizes, and compresses disk images for local use

### Advanced Features
- **Security Hardening** - SSH key injection, secure configurations, entropy generation
- **Build Optimization** - Parallel processing, intelligent caching, incremental updates
- **Development Tools** - Testing framework, debugging capabilities
- **Monitoring & Logging** - Progress tracking, detailed logging, error recovery

## 📋 Prerequisites

### System Requirements
- **Operating System**: Linux (Ubuntu, CentOS, RHEL, etc.) or macOS
- **Memory**: Minimum 4GB RAM
- **Storage**: 20GB free disk space
- **Network**: Internet connection for ISO downloads

### Software Dependencies
- **QEMU** (auto-installed by script)
- **curl/wget** for downloads
- **tar, gzip, xorriso** for ISO manipulation
- Standard Unix utilities

### Optional Dependencies
- **7z** for alternative ISO extraction
- **unzip** for alternative ISO extraction

## 🛠️ Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/your-org/gcp-openbsd.git
cd gcp-openbsd

# Make the scripts executable
chmod +x *.sh

# Run the main deployment script
./01-build-openbsd-image.sh
```

### Basic Usage

```bash
# Deploy with default OpenBSD 7.8
./01-build-openbsd-image.sh

# Deploy with verbose output
./01-build-openbsd-image.sh --verbose

# Custom configuration
./01-build-openbsd-image.sh --version 7.8 --memory 4G --cpus 4
```

### Dry Run Testing

```bash
# Test without making changes
./01-build-openbsd-image.sh --dry-run --verbose
```

## 📁 Project Structure

```
gcp-openbsd/
├── 01-build-openbsd-image.sh       # Main build script (start here)
├── 02-setup-gcp-service-account.sh # GCP service account manager
├── 03-gcp-image-import.sh          # GCP image import script
├── README.md                       # This file
├── PLAN.md                         # Project architecture and plan
├── DEPLOYMENT.md                   # GCP deployment guide
├── TROUBLESHOOTING.md              # Common issues and solutions
├── WHY-ISO-PATCHING.md             # Explanation of ISO patching
├── config/
│   └── default.conf                # Default configuration
├── manual/                         # Manual/advanced scripts
│   ├── prepare-iso.sh              # ISO preparation (rarely needed)
│   └── patch-iso.sh                # ISO patching (rarely needed)
├── templates/
│   ├── auto_install.conf           # Installation template
│   ├── disklabel.template          # Partitioning template
│   ├── boot.conf                   # Boot configuration
│   └── install.site                # Post-install script
└── build/                          # Build output directory
    ├── artifacts/                  # Generated images
    └── temp/                       # Temporary files
```

## 🔧 Configuration

### Default Configuration

The script uses `config/default.conf` for default settings. Key configuration options:

```bash
# OpenBSD Settings
OPENBSD_VERSION="7.8"
HOSTNAME="openbsd"
ROOT_PASSWORD="openbsd"

# QEMU Settings
MEMORY="2G"
CPUS="2"
DISK_SIZE="20G"

# Network Settings
NETWORK_INTERFACE="vio0"
IPV4_CONFIG="dhcp"
ENABLE_SSH="yes"

# Security Settings
SECURELEVEL="2"
ENABLE_ROOT_SSH="yes"
```

### Custom Configuration

Create a custom configuration file:

```bash
# production.conf
OPENBSD_VERSION="7.8"
HOSTNAME="prod-openbsd"
ROOT_PASSWORD="your-secure-password"
MEMORY="4G"
CPUS="4"
ENABLE_ROOT_SSH="no"
```

Use it with:

```bash
./01-build-openbsd-image.sh --config production.conf
```

## 🧪 Testing

### Testing Your Build

```bash
# Run with debug and verbose output
./01-build-openbsd-image.sh --debug --verbose

# Dry run to validate configuration
./01-build-openbsd-image.sh --dry-run --verbose
```

## 📊 Command Line Options

### Core Options
- `--version VERSION`: OpenBSD version (default: 7.8)
- `--config FILE`: Custom configuration file
- `--output DIR`: Output directory (default: ./build)
- `--verbose`: Verbose logging
- `--quiet`: Silent operation
- `--help`: Show help message

### QEMU Options
- `--remove`: Remove QEMU after completion
- `--memory SIZE`: VM memory size (default: 2G)
- `--cpus COUNT`: CPU count (default: 2)

### Build Options
- `--parallel`: Parallel build support
- `--cache`: Enable build caching (default)
- `--no-cache`: Disable caching
- `--force`: Force rebuild

### Development Options
- `--dev`: Development mode
- `--debug`: Debug mode
- `--dry-run`: Dry run simulation

## 🔄 Script Workflow & Usage Guide

### **Understanding the Script Pipeline**

The scripts are designed as a **modular pipeline** with different use cases:

### **Recommended Usage Patterns**

#### **Pattern 1: Complete Local Deployment (Recommended)**
```bash
# Single command for complete deployment
./01-build-openbsd-image.sh --verbose
```
- **Duration**: ~30 minutes
- **Output**: Ready-to-use OpenBSD VM images
- **Includes**: ISO download, patching, VM creation, installation, image processing

#### **Pattern 2: Cloud Deployment**
```bash
# Step 1: Create local images
./01-build-openbsd-image.sh

# Step 2: Set up GCP service account (one-time setup)
export PROJECT_ID="your-gcp-project"
./02-setup-gcp-service-account.sh setup

# Step 3: Deploy to GCP (after 01 completes)
./03-gcp-image-import.sh --image-file build/artifacts/openbsd-7.8.raw.gz --project-id ${PROJECT_ID}
```

#### **Pattern 3: Manual/Modular Workflow (Advanced)**
```bash
# Only use these if you need granular control (located in manual/ directory)
./manual/prepare-iso.sh   # Download ISO only (~2-3 min)
./manual/patch-iso.sh     # Patch ISO with autoinstall (~3-5 min)
# Then manually use the patched ISO
```

### **Why 01-build-openbsd-image.sh Takes 30 Minutes**

The 30-minute runtime is because it performs a **complete OpenBSD installation from scratch**:

1. **Setup Phase (2-3 min)**: ISO download, patching, VM creation
2. **Installation Phase (25-27 min)**: Full OS installation including:
   - Disk partitioning and filesystem creation
   - Package installation (~2GB of data)
   - Network configuration
   - Security hardening
   - Post-installation setup
3. **Processing Phase (1-2 min)**: Image optimization and compression

### **Script Relationship Explained**

| Script | Purpose | Duration | When to Use |
|--------|---------|----------|-------------|
| **01-build-openbsd-image.sh** | Complete deployment | ~30 min | **Start here** - includes everything |
| **02-setup-gcp-service-account.sh** | GCP service account setup | ~2 min | One-time setup before GCP deployment |
| **03-gcp-image-import.sh** | Cloud deployment | ~5-10 min | After 01 completes, for GCP |
| **manual/prepare-iso.sh** | ISO download only | ~2-3 min | Advanced: Manual ISO work only |
| **manual/patch-iso.sh** | ISO patching only | ~3-5 min | Advanced: Manual ISO patching only |

### **⚠️ Important Notes**

- **01-build-openbsd-image.sh is complete and standalone** - includes ISO download, configuration, installation, and image creation
- **manual/ scripts are for advanced users** - not required when using the main script
- **03-gcp-image-import.sh requires 01 to complete first** - it uploads the final images to Google Cloud

### **Quick Decision Guide**

- **"I want OpenBSD VMs locally"** → Use `./01-build-openbsd-image.sh`
- **"I want OpenBSD on GCP"** → Use `./01-build-openbsd-image.sh`, then `./02-setup-gcp-service-account.sh setup`, then `./03-gcp-image-import.sh`
- **"I just need the ISO"** → Use `./manual/prepare-iso.sh` (advanced)
- **"I want to patch my own ISO"** → Use `./manual/patch-iso.sh` (advanced)

## 🔍 How It Works

### **ISO Patching Process**

1. **Download Official ISO**: Fetches standard OpenBSD installation ISO
2. **Extract Contents**: Extracts ISO files for modification
3. **Add Autoinstall Config**: Injects `auto_install.conf` with installation answers
4. **Add Disk Layout**: Includes `disklabel.template` for automated partitioning
5. **Configure Serial Console**: Adds `boot.conf` for cloud console access
6. **Add Post-Install Script**: Includes `install.site` for final configuration
7. **Rebuild ISO**: Creates patched ISO with automation support

### **Automated Installation**

The deployment process follows these automated steps:

1. **Boot the original OpenBSD ISO**
2. **Configure serial console for kernel output**
3. **Enter shell mode in the installer**
4. **Mount the config ISO from `/dev/cd1a`**
5. **Copy autoinstall configuration files**
6. **Exit to start automated installation**
7. **Complete installation and create disk images**

The entire process should take 15-30 minutes and produce:

- `build/artifacts/openbsd-7.8.qcow2` (QCOW2 image)
- `build/artifacts/openbsd-7.8.raw.gz` (Compressed raw image)

### **CD-ROM Device Mapping**

QEMU assigns CD-ROM devices in the order they appear in the command:
- **cd0** = Config ISO (auto_install.conf, disklabel.template)
- **cd1** = Install ISO (OpenBSD sets: base78.tgz, comp78.tgz, etc.)

### **Post-Installation Processing**

After the OpenBSD installation completes, the script automatically:

1. **Convert disk to QCOW2** - Creates a compressed QCOW2 image
2. **Create compressed raw image** - Generates a gzipped raw disk image
3. **Save to `build/artifacts/`** - Stores both formats for deployment

### **Technical Implementation Details**

1. **QEMU Boot**: Launches QEMU with original unmodified ISO
2. **Config Delivery**: Mounts separate config ISO as second CD-ROM
3. **Autoinstall Detection**: OpenBSD installer finds autoinstall configuration
4. **Unattended Installation**: Proceeds without user interaction
5. **Post-Install Configuration**: Runs `install.site` script
6. **Image Extraction**: Extracts and compresses disk images

## ☁️ GCP Deployment

### **Prerequisites for GCP Deployment**

Before deploying to GCP, you need to set up a service account with the required permissions:

```bash
# One-time setup
export PROJECT_ID="your-gcp-project"
./02-setup-gcp-service-account.sh setup
```

This script will:
1. Enable required Google Cloud APIs (VM Migration, Compute, Storage)
2. Create a service account with appropriate roles
3. Generate and download service account credentials
4. Configure environment variables for deployment

To remove the service account later:
```bash
export PROJECT_ID="your-gcp-project"
./02-setup-gcp-service-account.sh cleanup
```

### **GCP Deployment with VM Migration API**

> ⚠️ **WARNING**: Google Cloud's VM Migration API does **not support OpenBSD**. The `03-gcp-image-import.sh` script will not work because OpenBSD is not recognized as a valid guest operating system by the VM Migration service. Alternative approaches for importing OpenBSD images to GCP are still being investigated.

The `03-gcp-image-import.sh` script uses Google Cloud's **VM Migration API** instead of standard image creation commands. Here's why:

#### **Why VM Migration API?**

OpenBSD is not one of Google Cloud's officially supported operating systems. The VM Migration API is specifically designed to import **foreign** or **custom** disk images from other platforms into GCP, making it the appropriate tool for this use case.

#### **Technical Advantages**

1. **Better Raw Disk Format Handling**
   - Built to handle raw disk images from various sources (on-premises, VMware, etc.)
   - Properly converts raw disk formats into GCP's native image format
   - More robust than standard image creation for non-standard OSes

2. **Non-Standard OS Support**
   - Designed for importing operating systems not in GCP's standard catalog
   - Handles boot configurations and disk layouts that differ from standard GCP images
   - Better compatibility with custom partitioning schemes (like OpenBSD's disklabel)

3. **Proper Disk Structure Requirements**
   - Creates `tar.gz` containing `disk.raw` (GCP requirement)
   - API handles conversion to GCP's image format automatically
   - Provides robust import validation and error handling

#### **Deployment Process**

```bash
# 1. Check if VM Migration API is enabled
gcloud services enable vmmigration.googleapis.com

# 2. Prepare disk image (decompress and repackage)
gunzip -c openbsd-7.8.raw.gz > disk.raw
tar -czf openbsd.tar.gz disk.raw

# 3. Upload to Google Cloud Storage
gsutil cp openbsd.tar.gz gs://bucket/

# 4. Import using Migration API
gcloud compute migration image-imports create openbsd-image \
    --source-file=gs://bucket/openbsd.tar.gz \
    --location=us-central1
```

#### **Why Not Standard Image Creation?**

The standard approach (`gcloud compute images create --source-uri=...`) is designed for supported operating systems and may not properly handle:
- OpenBSD's unique boot configuration
- Custom disk partitioning schemes
- Non-standard filesystem layouts

The VM Migration API provides the proper import validation and conversion needed for foreign operating systems.

## 🛡️ Security Features

### Built-in Security

- **Secure File Permissions**: Proper file and directory permissions
- **SSH Hardening**: Configures SSH for secure access
- **Kernel Security**: Sets appropriate security levels and parameters
- **Random Seed Generation**: Creates secure entropy for cryptographic operations
- **Access Control**: Configurable user permissions and access controls

### Security Best Practices

- **No Hardcoded Secrets**: Uses configuration files for sensitive data
- **Secure Temporary Files**: Proper cleanup of temporary data
- **Input Validation**: Validates and sanitizes all user inputs
- **Error Handling**: Secure error handling without information leakage

## 🚀 Performance Optimization

### Build Performance

- **Parallel Processing**: Multi-threaded build support
- **Intelligent Caching**: Avoids unnecessary rebuilds
- **Resource Management**: Optimized memory and CPU usage
- **Incremental Updates**: Smart rebuild detection

### Resource Optimization

- **Dynamic Memory Allocation**: Efficient memory usage
- **CPU Affinity**: Optimized CPU utilization
- **Disk Space Management**: Efficient storage usage
- **Network Optimization**: Optimized download and transfer operations

## 🧪 Testing

### Testing Your Build

```bash
# Run with debug and verbose output
./01-build-openbsd-image.sh --debug --verbose

# Dry run to validate configuration
./01-build-openbsd-image.sh --dry-run --verbose
```

## 📚 Documentation

- **[PLAN.md](PLAN.md)**: Project architecture and comprehensive plan
- **[DEPLOYMENT.md](DEPLOYMENT.md)**: GCP deployment guide with CLI options
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**: Common issues and solutions
- **[WHY-ISO-PATCHING.md](WHY-ISO-PATCHING.md)**: Explanation of ISO patching requirements
- **[config/default.conf](config/default.conf)**: Configuration reference

## 🤝 Support

### Getting Help

1. **Check Documentation**: Review the usage guide and troubleshooting section
2. **Enable Debug Mode**: Use `--debug --verbose` for detailed output
3. **Check Logs**: Review logs in `build/logs/` directory

### Reporting Issues

When reporting issues, please include:

- Operating system and version
- Script version and options used
- Error messages and logs
- Steps to reproduce the issue

### Community

- **GitHub Issues**: Report bugs and request features
- **Discussions**: Ask questions and share experiences
- **Wiki**: Community-maintained documentation

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **OpenBSD Project**: For the excellent operating system and autoinstall feature
- **QEMU Team**: For the powerful virtualization platform
- **Community Contributors**: For feedback, testing, and improvements

## 🗺️ Roadmap

### Planned Features

- **GUI Interface**: Web-based configuration and management
- **Container Support**: Docker-based builds and deployment
- **Plugin System**: Extensible architecture for custom features

### Future Enhancements

- **Performance Monitoring**: Real-time build metrics and optimization
- **Advanced Security**: Enhanced security features and compliance
- **Multi-Architecture**: Support for ARM and other architectures
- **Enterprise Features**: Advanced features for enterprise deployments

---

**Built with ❤️ for the OpenBSD and local virtualization communities**
