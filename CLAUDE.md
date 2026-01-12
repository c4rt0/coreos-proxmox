# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an infrastructure automation project for deploying Fedora CoreOS VMs on Proxmox VE. It uses Butane configurations (.bu files) that get transpiled to Ignition format (.ign) for automated system provisioning.

## Key Commands

```bash
# Create a new CoreOS VM (must run on Proxmox host)
./setup-coreos.sh

# Convert Butane config to Ignition (done automatically by script)
butane --pretty --strict config.bu > config.ign

# Validate Ignition JSON
python3 -c "import json; json.load(open('config.ign'))"
```

## Architecture

**Core Components:**
- `setup-coreos.sh` - Main provisioning script that downloads CoreOS images, converts Butane configs, and creates Proxmox VMs using the `qm` CLI
- `ignition/ignition.bu` - Default Butane configuration applied to new VMs
- `examples/` - Production-ready Butane configurations for common services

**Butane/Ignition Pattern:**
All `.bu` files use Butane specification v1.6.0 with `fcos` variant. They define:
- `passwd.users` - System users with SSH keys
- `storage.files` - Configuration files, scripts, systemd units
- `systemd.units` - Service definitions for containers and system services

**Container Deployment Pattern:**
Examples use Podman with systemd integration:
1. Define container as systemd service in Butane
2. Use `podman run` with restart policies
3. Mount volumes for persistent data
4. Configure health checks where applicable

## Configuration Defaults (in setup-coreos.sh)

- VMID: 420 (auto-increments if taken)
- Memory: 4096MB
- Cores: 2
- Storage: local-lvm
- Network bridge: vmbr0
- CoreOS stream: stable

## File Conventions

- `.bu` files - Butane YAML configs (source of truth)
- `.ign` files - Generated Ignition JSON (gitignored, auto-generated)
- Example configs are organized by service type in `examples/`
