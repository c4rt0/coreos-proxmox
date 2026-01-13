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
- `TROUBLESHOOTING.md` - Detailed failure documentation and solutions

## Failure Documentation Protocol

**IMPORTANT:** When the user reports a VM boot failure or configuration issue:

1. **ALWAYS update TROUBLESHOOTING.md** with the failure details
2. **Use the standardized template** (defined in TROUBLESHOOTING.md)
3. **Document BEFORE committing** the fix

### Required Information to Collect

When user reports a failure, gather:
- Console output / error messages (usually from Proxmox web UI screenshots)
- Which configuration is failing (k8s, nginx, postgresql, etc.)
- Which configurations are working (to identify the pattern)
- The butane file content causing the issue

### Debugging Approach

1. **Compare with working configs** - Use diff to find differences
2. **Validate butane syntax** - Run `butane --strict` on the problematic file
3. **Compare generated ignition JSON** - Structural differences reveal issues
4. **Check for missing required directives** - Like `overwrite: true`

### Adding to TROUBLESHOOTING.md

Once root cause is identified, add a new section using this structure:

```markdown
### Descriptive Title

**Date Identified:** YYYY-MM-DD

**Severity:** Critical/High/Medium/Low

**Symptoms:**
- Bullet points of observable issues
- Error messages from console
- Which configs work vs fail

**Root Cause:**
Technical explanation of WHY the failure occurs

**Solution:**
Code example showing the fix

**Prevention:**
Guidelines to avoid this in future configs
```

### Critical Butane Requirements

**Known required directives:**
- `overwrite: true` - MUST be present for any file in `/etc/` that exists in base CoreOS image
  - Required for: `/etc/hostname`, `/etc/motd`
  - Failure symptom: Emergency mode, "File exists" errors, ignition-remount-sysroot fails

### Validation Commands

Always validate butane files before deployment:
```bash
butane --strict config.bu > /tmp/test.ign
python3 -m json.tool /tmp/test.ign > /dev/null
```
