# OpenBSD GCP Deployment Guide

This guide covers deploying OpenBSD to Google Cloud Platform, including command-line options, workflow explanations, and best practices.

## Quick Start

```bash
# Step 1: Create local images (~30 min)
./01-qemu-deploy-openbsd.sh --verbose

# Step 2: Set up GCP service account (one-time)
export PROJECT_ID="your-gcp-project"
./02-setup-gcp-service-account.sh setup

# Step 3: Deploy to GCP
./03-deploy-gcp.sh --image-file build/artifacts/openbsd-7.8.raw.gz --project-id ${PROJECT_ID}
```

---

## Command Line Options

The deployment scripts support comprehensive command-line options:

| Option | Description | Example |
|--------|-------------|---------|
| `-z, --zone ZONE` | GCP zone to deploy in | `--zone us-west1-a` |
| `-r, --region REGION` | GCP region | `--region us-west1` |
| `-m, --machine-type TYPE` | VM machine type | `--machine-type n1-standard-2` |
| `-p, --project PROJECT_ID` | GCP project ID | `--project my-project` |
| `-b, --bucket BUCKET_NAME` | GCS bucket name | `--bucket my-images` |
| `-t, --tar-file FILENAME` | OpenBSD tar.gz filename | `--tar-file custom-openbsd.tar.gz` |
| `-s, --disk-size SIZE` | Boot disk size in GB | `--disk-size 50` |
| `-d, --disk-type TYPE` | Boot disk type | `--disk-type pd-ssd` |
| `-n, --name NAME` | VM name prefix | `--name my-openbsd-vm` |
| `-i, --image-family FAMILY` | Base image family | `--image-family ubuntu-2204-lts` |
| `-h, --help` | Show help message | `--help` |

---

## Deployment Patterns

### Development Environment
```bash
./03-deploy-gcp.sh \
  --zone us-west1-a \
  --machine-type n1-standard-2 \
  --disk-size 50 \
  --disk-type pd-standard \
  --name dev-openbsd
```

### Production Environment
```bash
./03-deploy-gcp.sh \
  --zone us-east1-b \
  --machine-type n1-standard-4 \
  --disk-size 100 \
  --disk-type pd-ssd \
  --name prod-openbsd
```

### Cost-Optimized
```bash
./03-deploy-gcp.sh \
  --zone us-central1-a \
  --machine-type e2-micro \
  --disk-size 20 \
  --disk-type pd-standard \
  --name budget-openbsd
```

---

## SSH Access

### Method 1: Automatic (Recommended)
The script provides the SSH command after successful deployment:
```bash
gcloud compute ssh openbsd-vm-TIMESTAMP --zone=us-central1-a --project=your-project
```

### Method 2: Manual
```bash
gcloud compute ssh VM_NAME --zone=ZONE --project=PROJECT_ID
```

### Method 3: Via External IP
```bash
gcloud compute instances describe VM_NAME --zone=ZONE \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)"
gcloud compute ssh VM_NAME --zone=ZONE --project=PROJECT_ID --tunnel-through-iap
```

---

## Script Workflow

### Understanding the Pipeline

| Script | Purpose | Duration |
|--------|---------|----------|
| `01-qemu-deploy-openbsd.sh` | Complete local deployment | ~30 min |
| `02-setup-gcp-service-account.sh` | GCP service account setup | ~2 min |
| `03-deploy-gcp.sh` | Cloud deployment | ~5-10 min |

### Why 01-qemu-deploy-openbsd.sh Takes 30 Minutes

It performs a **complete OpenBSD installation from scratch**:

1. **Setup Phase (2-3 min)**: ISO download, patching, VM creation
2. **Installation Phase (25-27 min)**: Full OS installation including disk partitioning, package installation (~2GB), network configuration, and security hardening
3. **Processing Phase (1-2 min)**: Image optimization and compression

---

## Efficient Deployment Strategy

### The Problem with Large Uploads
Uploading a full 30GB uncompressed disk image defeats the purpose of compression.

### Recommended Approach
Use the existing compressed tar.gz (~695MB) in GCS:

```bash
# Direct image creation (if GCP supports tar.gz)
gcloud compute images create openbsd-from-tar \
  --source-uri=gs://YOUR_BUCKET/openbsd-TIMESTAMP.tar.gz \
  --project=your-project

gcloud compute instances create openbsd-vm \
  --image=openbsd-from-tar \
  --zone=us-central1-a \
  --project=your-project
```

### Alternative: Direct Pipeline
```bash
# Stream decompress and upload in one step
gunzip -c build/artifacts/openbsd-7.8.raw.gz | \
  gsutil cp - gs://YOUR_BUCKET/openbsd.raw

gcloud compute images create openbsd-$(date +%Y%m%d) \
  --source-uri=gs://YOUR_BUCKET/openbsd.raw \
  --project=your-project

gcloud compute instances create openbsd-vm \
  --image=openbsd-$(date +%Y%m%d) \
  --zone=us-central1-a \
  --project=your-project
```

---

## Why VM Migration API?

OpenBSD is not one of Google Cloud's officially supported operating systems. The VM Migration API is specifically designed to import **foreign** or **custom** disk images.

### Technical Advantages

1. **Better Raw Disk Format Handling** - Built to handle raw disk images from various sources
2. **Non-Standard OS Support** - Designed for importing operating systems not in GCP's standard catalog
3. **Proper Disk Structure Requirements** - Creates `tar.gz` containing `disk.raw` (GCP requirement)

### Deployment via VM Migration API

```bash
# Enable API
gcloud services enable vmmigration.googleapis.com

# Prepare disk image
gunzip -c openbsd-7.8.raw.gz > disk.raw
tar -czf openbsd.tar.gz disk.raw

# Upload to GCS
gsutil cp openbsd.tar.gz gs://bucket/

# Import using Migration API
gcloud compute migration image-imports create openbsd-image \
    --source-file=gs://bucket/openbsd.tar.gz \
    --location=us-central1
```

---

## Key Benefits

- **Flexible Deployment**: Deploy anywhere, any size, any configuration
- **No 30GB Upload**: Uses existing compressed tar.gz (~700MB)
- **Multiple Image Options**: Debian, Ubuntu, COS, etc. as base
- **Cost Control**: Choose machine type and disk size based on needs
- **Regional Flexibility**: Deploy in any GCP zone/region
- **Easy SSH**: Automatic SSH commands provided
- **Production Ready**: Full configuration control
