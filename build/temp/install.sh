#!/bin/bash
# Enhanced installation with debugging

set -x  # Enable debugging

echo "=== Starting OpenBSD Installation ==="
echo "Date: $(date)"
echo "Working directory: $(pwd)"
echo "QEMU command: $*"

# Run QEMU with enhanced logging
exec qemu-system-x86_64 "$@" 2>&1 | tee -a "${OUTPUT_DIR}/logs/install.log"
