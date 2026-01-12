# Fedora CoreOS Automated VM Setup for Proxmox

This project provides an automated script to deploy Fedora CoreOS virtual machines on Proxmox VE with pre-configured services and minimal manual intervention.

## Overview

The `setup-coreos.sh` script automates the entire process of creating a Fedora CoreOS VM on Proxmox, including:
- Downloading the latest Fedora CoreOS stable image
- Configuring users and SSH access via Ignition
- Creating and configuring the VM with proper UEFI boot
- Automatically assigning available VM IDs starting from 420

**Plus:** Ready-to-use example configurations for [Kubernetes clusters](#kubernetes-with-k3s), [nginx web servers](#nginx-web-server), and [PostgreSQL databases](#postgresql-database)!

## Features

### Core Features
- **Automatic Dependency Installation**: Prompts to install missing tools (butane, curl, python3) if not present
- **Automatic VMID Assignment**: Finds the next available VMID starting from 420
- **Latest CoreOS Image**: Downloads the latest stable Fedora CoreOS QCOW2 image
- **Ignition Configuration**: Uses Butane to generate Ignition configs for automated provisioning
- **Pre-configured Users**:
  - `core`: Default CoreOS user with SSH key authentication
  - `fcos-user`: Admin user with sudo access and password `coreos`
- **Dynamic Hostname**: Each VM gets a unique hostname based on its VMID (e.g., `fcos-420`, `fcos-421`)
- **UEFI Boot**: Configured with OVMF BIOS for modern boot support

### Ready-to-Deploy Examples
- **Kubernetes Cluster (k3s)**: Multi-node cluster with automatic worker joining
- **nginx Web Server**: Containerized with persistent storage and host networking
- **PostgreSQL Database**: Containerized with automatic initialization and health checks

All examples include comprehensive documentation and follow production best practices.

## Prerequisites

The script must run on a **Proxmox VE host**. It will automatically offer to install missing dependencies:
- `butane` (Fedora CoreOS Ignition config transpiler)
- `curl` (for downloading images)
- `python3` (for JSON validation)

## Installation

1. Clone this repository to your Proxmox host (choose one option):

   **Option A: Clone to a new directory**
   ```bash
   git clone https://github.com/c4rt0/coreos-proxmox.git
   cd coreos-proxmox
   ```

   **Option B: Update existing repository**
   ```bash
   cd /var/coreos
   git remote add origin https://github.com/c4rt0/coreos-proxmox.git
   git pull origin main
   ```

   **Option C: Fresh clone to /var/coreos (remove existing content first)**
   ```bash
   rm -rf /var/coreos
   git clone https://github.com/c4rt0/coreos-proxmox.git /var/coreos
   cd /var/coreos
   ```

2. Update the SSH key in `setup-coreos.sh`:
   ```bash
   SSH_KEY="your-ssh-public-key-here"
   ```

3. (Optional) Customize the Ignition configuration in `ignition/ignition.bu` if needed.

## Usage

### Basic Deployment

Run the script on your Proxmox host:

```bash
./setup-coreos.sh
```

The script will:
1. Find the next available VMID (starting from 420)
2. Download Fedora CoreOS if not already present
3. Generate the Ignition configuration from `ignition/ignition.bu`
4. Create and configure the VM
5. Start the VM automatically

### Using Example Configurations

To deploy pre-configured services, copy an example to `ignition/ignition.bu` before running the setup script:

```bash
# Deploy a Kubernetes control plane
cp examples/kubernetes/kubernetes-control-plane.bu ignition/ignition.bu
./setup-coreos.sh

# Or deploy nginx
cp examples/nginx/nginx.bu ignition/ignition.bu
./setup-coreos.sh

# Or deploy PostgreSQL
cp examples/postgresql/postgresql.bu ignition/ignition.bu
./setup-coreos.sh
```

See the [Example Configurations](#example-configurations) section below for detailed information.

## Default Configuration

- **Memory**: 4096 MB
- **CPU Cores**: 2
- **Storage**: local-lvm
- **Network Bridge**: vmbr0
- **Starting VMID**: 420

You can modify these values in the `CONFIGURATION` section of the script.

## Login Credentials

After the VM boots (wait 30-60 seconds), you can login with:

- **Username**: `fcos-user`
- **Password**: `coreos`

Or via SSH using the `core` user with your configured SSH key:
```bash
ssh core@<VM_IP>
```

## File Structure

```
.
├── setup-coreos.sh           # Main setup script
├── ignition/
│   └── ignition.bu           # Butane configuration file (copy examples here)
├── examples/                 # Pre-built example configurations
│   ├── README.md             # Examples overview
│   ├── kubernetes/           # Kubernetes cluster with k3s
│   │   ├── kubernetes-control-plane.bu
│   │   ├── kubernetes-worker.bu
│   │   ├── README.md
│   │   └── KUBERNETES_USAGE.md
│   ├── nginx/                # nginx web server
│   │   ├── nginx.bu
│   │   └── README.md
│   └── postgresql/           # PostgreSQL database
│       ├── postgresql.bu
│       └── README.md
├── .gitignore                # Git ignore rules
└── README.md                 # This file
```

## Example Configurations

The `examples/` directory contains production-ready Butane configurations for common services. Each example includes detailed setup instructions and best practices.

### Kubernetes with k3s

Deploy a lightweight Kubernetes cluster with automatic worker joining.

**Features:**
- Control plane with static IP (192.168.68.54)
- Workers with automatic cluster joining (no manual token copying!)
- Comprehensive usage guide with practical examples

**Quick Start:**
```bash
# Deploy control plane
cp examples/kubernetes/kubernetes-control-plane.bu ignition/ignition.bu
./setup-coreos.sh

# Wait ~2 minutes, then deploy worker
cp examples/kubernetes/kubernetes-worker.bu ignition/ignition.bu
./setup-coreos.sh

# Verify cluster
ssh core@192.168.68.54
sudo k3s kubectl get nodes
```

**[internal k3s Documentation](examples/kubernetes/README.md)** | **[Usage Examples](examples/kubernetes/KUBERNETES_USAGE.md)**

### nginx Web Server

Deploy containerized nginx with persistent storage.

**Features:**
- nginx container via Podman
- Automatic startup and health monitoring
- Host networking for direct port access
- Persistent storage for web content and configuration

**Quick Start:**
```bash
cp examples/nginx/nginx.bu ignition/ignition.bu
./setup-coreos.sh
# Access at http://<VM_IP>
```

**[internal nginx Documentation](examples/nginx/README.md)**

### PostgreSQL Database

Deploy PostgreSQL with persistent storage and automatic initialization.

**Features:**
- PostgreSQL container with health checks
- Persistent data storage
- Automatic user and database creation
- Pre-configured connection aliases

**Quick Start:**
```bash
cp examples/postgresql/postgresql.bu ignition/ignition.bu
./setup-coreos.sh
# Connect: ssh core@<VM_IP>, then: pg-shell
```

**[internal PostgreSQL Documentation](examples/postgresql/README.md)**

---

## Customization

### Changing Default Users

Edit `ignition/ignition.bu` to modify user configurations. After making changes, the script will automatically convert the Butane config to Ignition format.

### Changing VM Resources

Modify the following variables in `setup-coreos.sh`:
- `MEMORY`: RAM in MB
- `CORES`: Number of CPU cores
- `STORAGE`: Proxmox storage pool
- `BRIDGE`: Network bridge

### Changing Starting VMID

Change the initial `VMID` value in the script (default is 420).

## Troubleshooting

### VM fails to start
- Check that the storage pool has enough space
- Verify UEFI/OVMF is available on your Proxmox host

### Cannot login
- Wait at least 60 seconds for Ignition to complete first boot provisioning
- Check VM console: `qm terminal <VMID>`
- Verify the Ignition config was applied: check `/var/lib/vz/snippets/vm-<VMID>-ignition.ign`

### Image download fails
- Check internet connectivity
- Verify the Fedora CoreOS build server is accessible
- Try manually downloading from: https://builds.coreos.fedoraproject.org/

## Cleaning Up VMs

To remove a CoreOS VM:

```bash
qm stop <VMID> && qm destroy <VMID> --purge
```

Example to remove VM 420:
```bash
qm stop 420 && qm destroy 420 --purge
```

To list all CoreOS VMs:
```bash
qm list | grep fcos
```

To remove multiple VM's:
```
for vmid in {420..428}; do qm stop $vmid 2>/dev/null; qm destroy $vmid 2>/dev/null; done; echo "Done"
```

## License

This project is provided as-is for educational and automation purposes.

## Contributing

Feel free to submit issues or pull requests for improvements.
