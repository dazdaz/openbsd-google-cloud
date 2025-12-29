# OpenBSD GCP Troubleshooting Guide

This guide covers common issues and solutions for OpenBSD deployment and restoration on GCP.

---

## Tar Extraction Issues

### Problem: Extraction Failing with Apple Extended Attributes

```bash
tar: Ignoring unknown extended header keyword 'LIBARCHIVE.xattr.com.apple.provenance'
tar: disk.raw: Wrote only 8704 of 10240 bytes
tar: Exiting with failure status due to previous errors
```

**Cause**: The tar was created on macOS and contains Apple-specific extended attributes.

### Understanding disk.raw Files

If your tar.gz contains `disk.raw`, this is a **disk image** - not filesystem files:
```bash
# Check contents
tar -tzf /tmp/openbsd.tar.gz
# Output: disk.raw (this is a disk image!)
```

**Important**: Disk images require `dd`, not `tar -C /`:
- ❌ `tar -xzf openbsd.tar.gz -C /` - Wrong (tries to extract as files)
- ✅ `dd if=disk.raw of=/dev/sda bs=4M` - Correct (writes to disk)

### Solutions

#### Solution 1: Skip Apple Attributes
```bash
sudo tar --no-xattrs -xzf /tmp/openbsd.tar.gz -C /

# Or use bsdtar
sudo apt install -y bsdtar
sudo bsdtar -xzf /tmp/openbsd.tar.gz -C /
```

#### Solution 2: Extract to Different Location First
```bash
sudo mkdir -p /tmp/openbsd-extract
sudo tar -xzf /tmp/openbsd.tar.gz -C /tmp/openbsd-extract/
ls -la /tmp/openbsd-extract/
file /tmp/openbsd-extract/disk.raw
```

#### Solution 3: Re-download the File
```bash
rm /tmp/openbsd.tar.gz
gsutil cp gs://YOUR_BUCKET/openbsd-TIMESTAMP.tar.gz /tmp/openbsd.tar.gz
ls -lh /tmp/openbsd.tar.gz
```

### Diagnosis Commands
```bash
# Check file size
ls -lh /tmp/openbsd.tar.gz

# Test tar integrity
tar -tzf /tmp/openbsd.tar.gz | wc -l
tar -tzf /tmp/openbsd.tar.gz | grep disk.raw

# Check disk space
df -h /
```

---

## OpenBSD Restoration Script

### Script Configuration

The `restore-openbsd.sh` script uses these defaults:
```bash
readonly GCS_BUCKET="genosis-prod-images"
readonly TAR_FILE="openbsd-TIMESTAMP.tar.gz"
readonly NEW_USERNAME="aicoder"
```

### Usage Steps

#### Step 1: Copy Script to VM
```bash
scp restore-openbsd.sh root@VM_NAME:/root/
```

#### Step 2: Run the Script
```bash
# SSH into VM
gcloud compute ssh VM_NAME --zone=us-central1-a --project=your-project

# Become root and run
sudo su -
chmod +x /root/restore-openbsd.sh
./restore-openbsd.sh
```

#### Step 3: What the Script Does
1. ✅ Checks and installs tools (gsutil, python3-pip)
2. ✅ Downloads OpenBSD tar.gz from GCS
3. ✅ Extracts OpenBSD over the Debian system
4. ✅ Configures networking (hostname, DNS, hosts file)
5. ✅ Creates user with initial password
6. ✅ Configures SSH to remain accessible
7. ✅ Verifies the installation

#### Step 4: Post-Installation
```bash
# Test SSH with new user
ssh USERNAME@VM_NAME

# Change password immediately
passwd USERNAME

# Verify OpenBSD
uname -a
cat /etc/release
```

---

## Manual OpenBSD Restoration

If you prefer manual restoration without the script:

### Download with gsutil
```bash
gsutil cp gs://YOUR_BUCKET/openbsd-TIMESTAMP.tar.gz /tmp/openbsd.tar.gz
ls -lh /tmp/openbsd.tar.gz
sudo tar -xzf /tmp/openbsd.tar.gz -C /
```

### If gsutil is Not Installed
```bash
sudo apt update
sudo apt install -y python3-pip
pip3 install gsutil
```

### Configure Networking
```bash
# Set hostname
sudo bash -c 'echo "VM_NAME" > /etc/hostname.re0'

# Configure hosts
sudo bash -c 'cat > /etc/hosts <<EOF
127.0.0.1       localhost
INTERNAL_IP     VM_NAME
EOF'

# Configure DNS
sudo bash -c 'cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF'
```

### Set Up User Accounts
```bash
sudo useradd -m -G wheel -s /bin/ksh USERNAME
sudo passwd USERNAME
```

---

## Common GCP Issues

### Permission Denied
```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

### Zone Not Available
```bash
gcloud compute zones list | grep us-west
```

### Machine Type Not Available
```bash
gcloud compute machine-types list --filter="zone:(us-central1-a)"
```

### SSH Connection Issues
```bash
# Check firewall rules
gcloud compute firewall-rules list --filter="allowed[].ports:22"

# Add SSH rule if needed
gcloud compute firewall-rules create allow-ssh \
  --allow tcp:22 \
  --source-ranges 0.0.0.0/0
```

---

## Local Build Issues

### QEMU Installation Fails
```bash
# Check virtualization support (Linux)
kvm-ok

# macOS
brew install qemu
```

### Installation Times Out
```bash
# Use more resources
./01-qemu-deploy-openbsd.sh --memory 4G --cpus 4

# Check logs
tail -f build/logs/deploy.log
```

### Permission Errors
```bash
# Ensure scripts are executable
chmod +x *.sh

# Check directory permissions
ls -la build/
```

---

## Important Reminders

- ⚠️ **Run as Root**: Restoration scripts must run as root (`sudo su -`)
- ⚠️ **Keep SSH Open**: Don't disconnect until scripts complete and you test the new configuration
- ⚠️ **Change Passwords**: Default passwords should be changed immediately
- ⚠️ **Network Backup**: Test SSH connectivity before closing sessions
- ⚠️ **DO NOT REBOOT** until extraction completes successfully
