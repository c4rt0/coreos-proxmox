# Fedora CoreOS Automated VM Setup for Proxmox

This project provides an automated script to deploy Fedora CoreOS virtual machines on Proxmox VE with minimal manual intervention.

## Overview

The `setup-coreos.sh` script automates the entire process of creating a Fedora CoreOS VM on Proxmox, including:
- Downloading the latest Fedora CoreOS stable image
- Configuring users and SSH access via Ignition
- Creating and configuring the VM with proper UEFI boot
- Automatically assigning available VM IDs starting from 420

## Features

- **Automatic Dependency Installation**: Prompts to install missing tools (butane, curl, python3) if not present
- **Automatic VMID Assignment**: Finds the next available VMID starting from 420
- **Latest CoreOS Image**: Downloads the latest stable Fedora CoreOS QCOW2 image
- **Ignition Configuration**: Uses Butane to generate Ignition configs for automated provisioning
- **Pre-configured Users**:
  - `core`: Default CoreOS user with SSH key authentication and password `coreos`
  - `fcos-user`: Admin user with sudo access and password `coreos`
- **Dynamic Hostname**: Each VM gets a unique hostname based on its VMID (e.g., `fcos-420`, `fcos-421`)
- **UEFI Boot**: Configured with OVMF BIOS for modern boot support

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

Run the script on your Proxmox host:

```bash
./setup-coreos.sh
```

The script will:
1. Find the next available VMID (starting from 420)
2. Download Fedora CoreOS if not already present
3. Generate the Ignition configuration
4. Create and configure the VM
5. Start the VM automatically

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
├── setup-coreos.sh        # Main setup script
├── ignition/
│   └── ignition.bu            # Butane configuration file
├── .gitignore                 # Git ignore rules (excludes *.ign files)
└── README.md                  # This file
```

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

## License

This project is provided as-is for educational and automation purposes.

## Contributing

Feel free to submit issues or pull requests for improvements.
