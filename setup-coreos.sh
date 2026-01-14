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
# VMID and VM_NAME will be set dynamically based on user selection
# (VMID generated inside VM creation loop for multi-node support)
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

# Function to display configuration menu and get user selection
show_configuration_menu() {
    echo ""
    echo "========================================="
    echo "  CoreOS VM Configuration Selection"
    echo "========================================="
    echo ""
    echo "Please select a configuration:"
    echo ""

    local options=(
        "Default CoreOS (basic configuration)"
        "Kubernetes Cluster (k3s) - Control Plane + Workers"
        "Nginx Web Server"
        "PostgreSQL Database"
        "Exit"
    )

    PS3=$'\nEnter selection number: '
    select opt in "${options[@]}"; do
        case $REPLY in
            1)
                echo "Selected: Default CoreOS configuration"
                CONFIG_TYPE="default"
                CONFIG_FILE="$REPO_DIR/ignition/ignition.bu"
                break
                ;;
            2)
                echo "Selected: Kubernetes Cluster (k3s)"
                CONFIG_TYPE="k8s-cluster"
                # Will handle both control plane and worker files
                break
                ;;
            3)
                echo "Selected: Nginx Web Server"
                CONFIG_TYPE="nginx"
                CONFIG_FILE="$REPO_DIR/examples/nginx/nginx.bu"
                break
                ;;
            4)
                echo "Selected: PostgreSQL Database"
                CONFIG_TYPE="postgresql"
                CONFIG_FILE="$REPO_DIR/examples/postgresql/postgresql.bu"
                break
                ;;
            5)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo "Invalid selection. Please try again."
                ;;
        esac
    done

    # Validate that the config file exists (except for k8s-cluster which sets files later)
    if [ "$CONFIG_TYPE" != "k8s-cluster" ] && [ ! -f "$CONFIG_FILE" ]; then
        echo "Error: Configuration file not found at $CONFIG_FILE"
        exit 1
    fi

    echo ""
}

# Function to get custom hostname from user
get_custom_hostname() {
    local default_hostname="$1"
    local custom_hostname

    echo "" >&2
    read -p "Enter hostname (or press Enter for default '$default_hostname'): " custom_hostname

    # If empty, use default
    if [ -z "$custom_hostname" ]; then
        custom_hostname="$default_hostname"
    fi

    # Validate hostname format (alphanumeric, hyphens, no spaces)
    if ! [[ "$custom_hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
        echo "Error: Invalid hostname format. Use only alphanumeric characters and hyphens."
        echo "Hostname must start and end with alphanumeric character."
        exit 1
    fi

    echo "$custom_hostname"
}

# Function to get worker count for Kubernetes workers
get_worker_count() {
    local count

    echo ""
    read -p "How many worker nodes to create? (1-10): " count

    # Validate input is numeric and in range
    if ! [[ "$count" =~ ^[0-9]+$ ]] || [ "$count" -lt 1 ] || [ "$count" -gt 10 ]; then
        echo "Error: Invalid count. Must be a number between 1 and 10."
        exit 1
    fi

    echo "$count"
}

# Function to setup configuration file for processing
setup_configuration() {
    local source_file="$1"
    local dest_file="$IGNITION_DIR/selected-config.bu"

    echo "Copying configuration from $source_file to $dest_file" >&2
    cp "$source_file" "$dest_file"

    echo "$dest_file"
}

# Function to apply hostname to configuration file
apply_hostname_to_config() {
    local config_file="$1"
    local hostname="$2"

    echo "Setting hostname in config to $hostname"

    # Use awk to precisely replace only the hostname inline value
    # This finds "path: /etc/hostname" and replaces the next "inline:" value
    awk -v new_hostname="$hostname" '
        /path: \/etc\/hostname/ { in_hostname_section = 1 }
        in_hostname_section && /inline:/ && !replaced {
            sub(/inline: .*/, "inline: " new_hostname)
            replaced = 1
        }
        { print }
    ' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"

    # Verify the replacement occurred
    if ! grep -q "inline: $hostname" "$config_file"; then
        echo "Warning: Hostname replacement may not have succeeded"
    fi
}

# Function to detect VM IP address via QEMU guest agent
detect_vm_ip() {
    local vmid="$1"
    local max_attempts="${2:-60}"
    local attempt=0

    echo "Waiting for VM $vmid to boot and get IP address (max ${max_attempts}s)..." >&2

    while [ $attempt -lt $max_attempts ]; do
        # Try to get network interfaces from guest agent
        local ip=$(qm guest cmd "$vmid" network-get-interfaces 2>/dev/null | \
                   grep -oP '"ip-address"\s*:\s*"\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
                   grep -v "127.0.0.1" | head -1)

        if [ -n "$ip" ]; then
            echo "VM $vmid received IP: $ip" >&2
            echo "$ip"
            return 0
        fi

        attempt=$((attempt + 1))
        sleep 1
    done

    echo "Error: Could not detect IP for VM $vmid after ${max_attempts}s" >&2
    echo "The VM may not have booted yet or qemu-guest-agent may not be running" >&2
    return 1
}

# Function to inject control plane IP into kubernetes worker config
inject_control_plane_ip() {
    local config_file="$1"
    local control_plane_ip="$2"

    echo "Configuring worker to connect to control plane at $control_plane_ip" >&2

    # Replace CONTROL_PLANE_IP placeholder with actual IP
    sed -i "s/CONTROL_PLANE_IP/$control_plane_ip/g" "$config_file"

    # Verify the replacement
    if grep -q "https://$control_plane_ip:6443" "$config_file"; then
        return 0
    else
        echo "Error: Failed to update control plane IP in $config_file" >&2
        return 1
    fi
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
# Configuration Menu and Setup
# -------------------------------
# Show menu and get user's configuration choice
show_configuration_menu

# Handle Kubernetes cluster configuration
if [ "$CONFIG_TYPE" = "k8s-cluster" ]; then
    echo ""
    echo "Kubernetes Cluster Setup"
    echo "------------------------"
    echo "This will create:"
    echo "  - 1 Control Plane node (k3s-control-plane)"

    # Get number of workers
    K8S_WORKER_COUNT=$(get_worker_count)

    echo "  - $K8S_WORKER_COUNT Worker node(s) (k3s-worker-1, k3s-worker-2, ...)"
    echo ""
    echo "Note: Control plane will be created first, then workers will join using its DHCP IP"
    echo ""
    read -p "Continue with cluster creation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi

    # Total VMs = 1 control plane + N workers
    TOTAL_VMS=$((1 + K8S_WORKER_COUNT))

# For non-Kubernetes configs
else
    # Set default hostname based on configuration type
    case "$CONFIG_TYPE" in
        "default")
            # For default, we'll use fcos-$VMID but need VMID first
            TEMP_VMID=420
            while qm status "$TEMP_VMID" &>/dev/null; do
                TEMP_VMID=$((TEMP_VMID + 1))
            done
            DEFAULT_HOSTNAME="fcos-$TEMP_VMID"
            ;;
        "nginx")
            DEFAULT_HOSTNAME="fcos-nginx"
            ;;
        "postgresql")
            DEFAULT_HOSTNAME="fcos-postgresql"
            ;;
    esac

    # Get hostname from user
    VM_NAME=$(get_custom_hostname "$DEFAULT_HOSTNAME")
    TOTAL_VMS=1
fi

echo ""
echo "Configuration Summary:"
echo "  Type: $CONFIG_TYPE"
if [ "$CONFIG_TYPE" = "k8s-cluster" ]; then
    echo "  Total VMs: $TOTAL_VMS (1 control plane + $K8S_WORKER_COUNT workers)"
    echo "  Control Plane: k3s-control-plane (IP will be detected via DHCP)"
    echo "  Workers: k3s-worker-1 through k3s-worker-$K8S_WORKER_COUNT"
else
    echo "  Hostname: $VM_NAME"
fi
echo ""

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
# 3. VM Creation Loop
# -------------------------------
# Create one or more VMs based on configuration type
# For Kubernetes workers, create multiple VMs with unique hostnames

echo ""
echo "========================================="
echo "  Creating VM(s)"
echo "========================================="
echo ""

# Arrays to track created VMs
declare -a CREATED_VMIDS=()
declare -a CREATED_VMNAMES=()

for ((vm_index=1; vm_index<=TOTAL_VMS; vm_index++)); do
    echo "--- Processing VM $vm_index of $TOTAL_VMS ---"
    echo ""

    # Generate unique VMID for this VM
    VMID=420
    while qm status "$VMID" &>/dev/null; do
        VMID=$((VMID + 1))
    done
    echo "Using VMID: $VMID"

    # Determine configuration file and VM name based on type
    if [ "$CONFIG_TYPE" = "k8s-cluster" ]; then
        if [ "$vm_index" -eq 1 ]; then
            # First VM is the control plane
            VM_NAME="k3s-control-plane"
            CURRENT_CONFIG_FILE="$REPO_DIR/examples/kubernetes/kubernetes-control-plane.bu"
            echo "Creating Kubernetes Control Plane"
        else
            # Remaining VMs are workers
            worker_num=$((vm_index - 1))
            VM_NAME="k3s-worker-$worker_num"
            CURRENT_CONFIG_FILE="$REPO_DIR/examples/kubernetes/kubernetes-worker.bu"
            echo "Creating Kubernetes Worker #$worker_num"
        fi
    else
        # For non-Kubernetes configs, use the selected config file
        CURRENT_CONFIG_FILE="$CONFIG_FILE"
    fi

    echo "VM Name: $VM_NAME"
    echo ""

    # Validate config file exists
    if [ ! -f "$CURRENT_CONFIG_FILE" ]; then
        echo "Error: Configuration file not found at $CURRENT_CONFIG_FILE"
        exit 1
    fi

    # Setup configuration file for this VM
    IGNITION_SOURCE=$(setup_configuration "$CURRENT_CONFIG_FILE")

    # Apply hostname to this VM's configuration
    apply_hostname_to_config "$IGNITION_SOURCE" "$VM_NAME"

    # For Kubernetes workers, inject the control plane IP
    if [ "$CONFIG_TYPE" = "k8s-cluster" ] && [ "$vm_index" -gt 1 ]; then
        inject_control_plane_ip "$IGNITION_SOURCE" "$K8S_CONTROL_PLANE_IP"
    fi

    # Convert Butane -> Ignition
    echo "Converting Butane config to Ignition..."
    if ! butane --pretty --strict "$IGNITION_SOURCE" > "$IGNITION_DIR/ignition.ign"; then
        echo "Error: Failed to convert Butane config to Ignition for $VM_NAME"
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
        --net0 virtio,bridge="$BRIDGE" \
        --agent 1

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

        # Track this VM for summary
        CREATED_VMIDS+=("$VMID")
        CREATED_VMNAMES+=("$VM_NAME")

        # For Kubernetes control plane, wait for IP and store it
        if [ "$CONFIG_TYPE" = "k8s-cluster" ] && [ "$vm_index" -eq 1 ]; then
            echo ""
            echo "Detecting control plane IP address..."
            echo "Note: First boot installs qemu-guest-agent, this may take 2-3 minutes..."
            K8S_CONTROL_PLANE_IP=$(detect_vm_ip "$VMID" 180)
            if [ $? -ne 0 ] || [ -z "$K8S_CONTROL_PLANE_IP" ]; then
                echo "Error: Failed to detect control plane IP address"
                echo "Workers will not be able to join the cluster"
                exit 1
            fi
            echo "Control plane IP: $K8S_CONTROL_PLANE_IP"
        fi

        echo ""
    else
        echo "Error: Failed to start VM $VM_NAME (ID $VMID)"
        exit 1
    fi

done  # End of VM creation loop

# -------------------------------
# 8. Summary
# -------------------------------
echo ""
echo "========================================="
echo "  VM Creation Complete!"
echo "========================================="
echo ""
echo "Created $TOTAL_VMS VM(s):"
for i in "${!CREATED_VMIDS[@]}"; do
    echo "  - ${CREATED_VMNAMES[$i]} (VMID: ${CREATED_VMIDS[$i]})"
done
echo ""
echo "Next steps:"
echo "  1. Wait 30-60 seconds for the VM(s) to boot"
echo "  2. Find VM IP(s): qm guest cmd <VMID> network-get-interfaces"
echo "  3. SSH into a VM: ssh core@<VM_IP>"
echo ""
if [ "$CONFIG_TYPE" = "k8s-cluster" ]; then
    echo "Kubernetes Cluster Setup:"
    echo "  - Control plane: k3s-control-plane (${CREATED_VMIDS[0]}) at $K8S_CONTROL_PLANE_IP"
    echo "  - Workers configured to join control plane at $K8S_CONTROL_PLANE_IP:6443"
    echo "  - Once all nodes are up, check cluster: ssh core@$K8S_CONTROL_PLANE_IP 'sudo kubectl get nodes'"
    echo ""
fi
echo "To monitor a VM: qm terminal <VMID>"
echo ""

