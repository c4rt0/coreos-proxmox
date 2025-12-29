#!/bin/bash
set -euo pipefail

# Check if we're running from the correct directory or handle existing repository
if [ ! -f "setup-coreos.sh" ]; then
    echo "Error: This script must be run from the repository root directory"
    echo "Please run: cd /path/to/coreos-proxmox && ./setup-coreos.sh"
    exit 1
fi

# Verify this is a git repository
if [ ! -d ".git" ]; then
    echo "Error: This directory is not a git repository"
    echo "Please clone the repository first:"
    echo "  git clone https://github.com/c4rt0/coreos-proxmox.git /var/coreos"
    exit 1
fi

# Get the absolute path of this script's directory
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -------------------------------
# CONFIGURATION
# -------------------------------
# Find next available VMID starting from 420
VMID=420
while qm status "$VMID" &>/dev/null; do
    VMID=$((VMID + 1))
done
echo "Using VMID: $VMID"

VM_NAME="fcos-$VMID"
MEMORY=4096
CORES=2
STORAGE="local-lvm"
BRIDGE="vmbr0"
IMAGE_DIR="/var/coreos/images"
IGNITION_DIR="/var/coreos/ignition"
SSH_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGnKNJUQdGdd8jwuOoI/BHjCvxn0GEctbgVqOPn6GAzo c4rt0gr4ph3r@gmail.com"
QCOW2_FILE="$IMAGE_DIR/fedora-coreos.qcow2"

# Configuration for CoreOS image download
COREOS_STREAM="stable"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install missing dependencies
install_dependencies() {
    local missing_deps=()
    
    # Check each required dependency
    if ! command_exists qm; then
        echo "Error: 'qm' not found. This script must run on a Proxmox VE host."
        exit 1
    fi
    
    if ! command_exists curl; then
        missing_deps+=("curl")
    fi
    
    if ! command_exists butane; then
        missing_deps+=("butane")
    fi
    
    if ! command_exists python3; then
        missing_deps+=("python3")
    fi
    
    # If there are missing dependencies, ask to install
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "Missing dependencies: ${missing_deps[*]}"
        read -p "Would you like to install missing dependencies? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Installing dependencies..."
            apt-get update
            
            for dep in "${missing_deps[@]}"; do
                if [ "$dep" = "butane" ]; then
                    # Install butane from GitHub releases
                    echo "Installing butane..."
                    BUTANE_VERSION="v0.21.0"
                    curl -L "https://github.com/coreos/butane/releases/download/${BUTANE_VERSION}/butane-x86_64-unknown-linux-gnu" -o /usr/local/bin/butane
                    chmod +x /usr/local/bin/butane
                else
                    apt-get install -y "$dep"
                fi
            done
            
            echo "Dependencies installed successfully."
        else
            echo "Cannot proceed without required dependencies."
            exit 1
        fi
    fi
}

# Check for required dependencies
echo "Checking dependencies..."
install_dependencies

# Validate SSH key is configured
if [[ "$SSH_KEY" == *"REPLACE_WITH_YOUR_PUBLIC_KEY"* ]]; then
    echo "Error: SSH_KEY is not configured. Please update the SSH_KEY variable with your public key."
    exit 1
fi

# -------------------------------
# 1. Prepare directories
# -------------------------------
mkdir -p "$IMAGE_DIR"
mkdir -p "$IGNITION_DIR"

# Get the latest build metadata
echo "Fetching latest CoreOS build info for $COREOS_STREAM stream..."
BUILD_INFO=$(curl -s https://builds.coreos.fedoraproject.org/prod/streams/$COREOS_STREAM/builds/builds.json) || { echo "Error: Failed to fetch build info"; exit 1; }

if [ -z "$BUILD_INFO" ]; then
    echo "Error: No build info returned from API"
    exit 1
fi

# Extract the latest build version using jq (more reliable than grep)
if command -v jq &>/dev/null; then
    COREOS_VERSION=$(echo "$BUILD_INFO" | jq -r '.builds[0].id' 2>/dev/null)
else
    # Fallback to grep - extract the first "id" value from the builds array
    # The JSON structure is: "builds":[{"id":"43.20251120.3.0",...},...
    COREOS_VERSION=$(echo "$BUILD_INFO" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
fi

COREOS_BUILD_ID="$COREOS_VERSION"

if [ -z "$COREOS_VERSION" ] || [ "$COREOS_VERSION" = "null" ]; then
    echo "Error: Could not determine latest CoreOS version"
    echo "DEBUG: BUILD_INFO first 500 chars:"
    echo "$BUILD_INFO" | head -c 500
    exit 1
fi

echo "Found CoreOS version: $COREOS_VERSION"

COREOS_IMAGE_URL="https://builds.coreos.fedoraproject.org/prod/streams/$COREOS_STREAM/builds/$COREOS_BUILD_ID/x86_64/fedora-coreos-$COREOS_VERSION-qemu.x86_64.qcow2.xz"
COREOS_IMAGE_XZ="$IMAGE_DIR/fedora-coreos-$COREOS_VERSION-qemu.x86_64.qcow2.xz"

# -------------------------------
# 2. Download Fedora CoreOS image
# -------------------------------
echo "Downloading Fedora CoreOS..."
if [ -f "$QCOW2_FILE" ]; then
    echo "Image already exists at $QCOW2_FILE, skipping download"
else
    echo "Downloading from: $COREOS_IMAGE_URL"
    curl -L -o "$COREOS_IMAGE_XZ" "$COREOS_IMAGE_URL" || { echo "Error: Failed to download Fedora CoreOS image"; exit 1; }
    
    # Decompress the image
    echo "Decompressing image..."
    xz -d "$COREOS_IMAGE_XZ" || { echo "Error: Failed to decompress image"; exit 1; }
    
    # Move and rename to standard name
    COREOS_IMAGE_QCOW2="${COREOS_IMAGE_XZ%.xz}"
    if ! mv "$COREOS_IMAGE_QCOW2" "$QCOW2_FILE" 2>/dev/null; then
        echo "Error: Could not find or rename downloaded QCOW2 image"
        exit 1
    fi
fi

if [ ! -f "$QCOW2_FILE" ]; then
    echo "Error: QCOW2 file not found at $QCOW2_FILE"
    exit 1
fi

# -------------------------------
# 3. Use Butane Ignition config from repository
# -------------------------------
# Check for ignition file in multiple possible locations
REPO_IGNITION_FILE="$(dirname "$0")/ignition/ignition.bu"
DIRECT_IGNITION_FILE="$IGNITION_DIR/ignition.bu"

# First check if ignition file already exists in the destination
if [ -f "$DIRECT_IGNITION_FILE" ]; then
    echo "Using existing ignition file at: $DIRECT_IGNITION_FILE"
    IGNITION_SOURCE="$DIRECT_IGNITION_FILE"
# Otherwise check if it exists in the repository location
elif [ -f "$REPO_IGNITION_FILE" ]; then
    echo "Using ignition file from repository: $REPO_IGNITION_FILE"
    # Only copy if source and destination aren't the same file
    if [ "$REPO_IGNITION_FILE" != "$DIRECT_IGNITION_FILE" ]; then
        cp "$REPO_IGNITION_FILE" "$DIRECT_IGNITION_FILE"
    fi
    IGNITION_SOURCE="$DIRECT_IGNITION_FILE"
else
    echo "Error: Ignition file not found at $REPO_IGNITION_FILE or $DIRECT_IGNITION_FILE"
    exit 1
fi

# Update hostname in the ignition config to match VM_NAME
echo "Setting hostname in ignition config to $VM_NAME"
sed -i "s/inline: fcos-user/inline: $VM_NAME/g" "$IGNITION_SOURCE"

# Convert Butane -> Ignition
echo "Converting Butane config to Ignition..."
if ! butane --pretty --strict "$IGNITION_DIR/ignition.bu" > "$IGNITION_DIR/ignition.ign"; then
    echo "Error: Failed to convert Butane config to Ignition"
    exit 1
fi
echo "Ignition file created at $IGNITION_DIR/ignition.ign"

# Verify Ignition file was created and is valid JSON
if [ ! -f "$IGNITION_DIR/ignition.ign" ]; then
    echo "Error: Ignition file was not created"
    exit 1
fi

# Validate it's valid JSON
if ! python3 -m json.tool "$IGNITION_DIR/ignition.ign" > /dev/null 2>&1; then
    echo "Warning: Ignition file may not be valid JSON"
fi

# -------------------------------
# 4. Create VM shell
# -------------------------------
qm create "$VMID" \
    --name "$VM_NAME" \
    --memory "$MEMORY" \
    --cores "$CORES" \
    --cpu host \
    --machine q35 \
    --bios ovmf \
    --net0 virtio,bridge="$BRIDGE"

# Set SCSI controller first (before adding disks)
qm set "$VMID" --scsihw virtio-scsi-pci

# -------------------------------
# 5. Import Fedora CoreOS disk
# -------------------------------
echo "Importing CoreOS disk..."
qm importdisk "$VMID" "$QCOW2_FILE" "$STORAGE"

# Attach the imported disk to scsi0
qm set "$VMID" --scsi0 "$STORAGE":vm-"$VMID"-disk-0,discard=on,ssd=1

# Add EFI disk for UEFI boot (this will be disk-1)
qm set "$VMID" --efidisk0 "$STORAGE":1,pre-enrolled-keys=1

# Set boot configuration
qm set "$VMID" --boot order=scsi0
qm set "$VMID" --bootdisk scsi0

# -------------------------------
# 6. Attach Ignition config via fw_cfg
# -------------------------------
# Save Ignition config to a persistent location
IGNITION_FILE="/var/lib/vz/snippets/vm-$VMID-ignition.ign"
mkdir -p "$(dirname "$IGNITION_FILE")"
cp "$IGNITION_DIR/ignition.ign" "$IGNITION_FILE"
echo "Ignition config saved to $IGNITION_FILE"

# Use qm set --args to pass Ignition config via firmware
qm set "$VMID" --args "-fw_cfg name=opt/com.coreos/config,file=$IGNITION_FILE"
echo "Ignition configuration attached via fw_cfg"

# -------------------------------
# 7. Start VM
# -------------------------------
echo "Starting VM $VM_NAME (ID $VMID)..."
if qm start "$VMID"; then
    echo "✓ VM $VM_NAME (ID $VMID) started successfully."
    echo ""
    echo "Next steps:"
    echo "  1. Wait 30-60 seconds for the VM to boot"
    echo "  2. Find the VM's IP: qm terminal $VMID"
    echo "  3. SSH into the VM: ssh core@<VM_IP>"
    echo ""
    echo "To monitor VM startup: qm terminal $VMID"
else
    echo "Error: Failed to start VM"
    exit 1
fi

