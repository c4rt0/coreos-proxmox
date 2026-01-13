# Troubleshooting Guide

This document tracks common failures, their symptoms, root causes, and solutions for the CoreOS Proxmox deployment project.

## Table of Contents
1. [VM Boot Failures](#vm-boot-failures)
2. [Ignition Configuration Issues](#ignition-configuration-issues)
3. [Network Configuration Problems](#network-configuration-problems)

---

## VM Boot Failures

### Emergency Mode: Missing `overwrite: true` in Butane Files

**Date Identified:** 2026-01-13

**Severity:** Critical - VM completely fails to boot

**Symptoms:**
- VM boots into emergency mode
- Console shows repeating errors:
  ```
  Failed to start ignition-remount-sysroot.service - Remount /sysroot read-write for ignition
  Failed to start ostree-prepare-root.service - OSTree Prepare OS/
  ostree-prepare-root: failed to create /run/ostree: File exists
  ```
- System enters emergency mode and cannot proceed
- Other configurations (kubernetes, nginx, default) work fine but one specific config fails

**Root Cause:**
Butane configuration files **must** include `overwrite: true` for system files that already exist in the CoreOS base image, particularly:
- `/etc/hostname`
- `/etc/motd`
- Other files in `/etc/` that exist by default

When `overwrite: true` is missing, ignition attempts to write these files during early boot but fails because the files already exist. This causes cascading failures in the boot process:
1. Ignition cannot write system files
2. `ignition-remount-sysroot.service` fails
3. `ostree-prepare-root.service` fails
4. Boot process enters emergency mode

**Solution:**
Add `overwrite: true` to all file entries in the `storage.files` section that write to existing system paths:

```yaml
storage:
  files:
    - path: /etc/hostname
      mode: 0644
      overwrite: true  # ← REQUIRED for existing system files
      contents:
        inline: your-hostname

    - path: /etc/motd
      mode: 0644
      overwrite: true  # ← REQUIRED for existing system files
      contents:
        inline: |
          Your message
```

**How to Verify:**
Compare your butane file against working examples:
```bash
# Check if overwrite is present in working configs
grep -A 3 "path: /etc/hostname" examples/nginx/nginx.bu
grep -A 3 "path: /etc/hostname" examples/postgresql/postgresql.bu

# Validate butane syntax
butane --strict your-config.bu > /tmp/test.ign
```

**Files Affected:**
- `examples/postgresql/postgresql.bu` (fixed in commit XXXXXXX)

**Prevention:**
When creating new butane configurations:
1. Always include `overwrite: true` for paths in `/etc/`
2. Use existing working configurations as templates
3. Test new configurations in a VM before committing
4. Compare generated ignition JSON with working configs using `diff`

---

## Ignition Configuration Issues

### fw_cfg vs Config Drive Methods

**Context:**
There are multiple methods to deliver ignition configurations to CoreOS VMs:
1. **fw_cfg** - Passes config via QEMU firmware configuration
2. **Config Drive ISO** - Attaches config as a CD-ROM device
3. **Network URL** - Fetches config from a web server

**Current Implementation:**
This project uses the **fw_cfg** method for all configurations:
```bash
qm set "$VMID" --args "-fw_cfg name=opt/com.coreos/config,file=$IGNITION_FILE"
```

**Known Working Configurations:**
- Kubernetes (control plane and workers) - fw_cfg works perfectly
- Nginx - fw_cfg works perfectly
- PostgreSQL - fw_cfg works perfectly (after fixing overwrite issue)
- Default CoreOS - fw_cfg works perfectly

**When to Suspect fw_cfg Issues:**
If ALL configurations fail to boot (not just one), the fw_cfg delivery method may not be working. Symptoms would include:
- Ignition config not being applied at all
- VMs boot but have default hostname and no custom configuration
- No errors in console, but configuration is simply ignored

**Debugging Ignition Delivery:**
```bash
# On running VM, check if ignition ran
sudo journalctl -u ignition-fetch.service

# Check ignition status
systemctl status ignition-*

# Verify config was loaded
sudo cat /run/ignition.json
```

---

## Network Configuration Problems

### DHCP Not Working

**Symptoms:**
- VM boots successfully
- Cannot SSH to VM
- `qm guest cmd <VMID> network-get-interfaces` returns "No QEMU guest agent configured"
- VM has no IP address assigned

**Common Causes:**
1. Wrong network interface name in butane config
2. Network bridge (vmbr0) not configured correctly on Proxmox host
3. DHCP server not available on the network

**Solution:**
1. Check the actual interface name in the VM:
   ```bash
   # From Proxmox web console for the VM
   ip link
   ```
2. Update butane config with correct interface name (usually `ens18` or `eth0`)
3. Verify Proxmox bridge configuration:
   ```bash
   # On PVE host
   ip addr show vmbr0
   brctl show vmbr0
   ```

---

## Best Practices for Avoiding Failures

### Creating New Butane Configurations

1. **Always start from a working template**
   - Copy `examples/nginx/nginx.bu` or another working config
   - Don't create from scratch

2. **Required directives for system files:**
   ```yaml
   - path: /etc/hostname
     mode: 0644
     overwrite: true  # ← ALWAYS include this
   ```

3. **Validate before deploying:**
   ```bash
   # Validate butane syntax
   butane --strict your-config.bu > /tmp/test.ign

   # Validate generated JSON
   python3 -m json.tool /tmp/test.ign > /dev/null
   ```

4. **Test in a VM:**
   - Deploy the new configuration to a test VM
   - Verify it boots successfully
   - Check that all services start correctly
   - Only then commit to repository

### Debugging Workflow

When a VM fails to boot:

1. **Access the console** (Proxmox web UI → VM → Console)
2. **Identify the failing service** from error messages
3. **Check systemd logs** (if you can get to emergency shell):
   ```bash
   journalctl -xeu <service-name>
   ```
4. **Compare with working configuration:**
   ```bash
   diff working-config.bu broken-config.bu
   ```
5. **Validate ignition JSON structure:**
   ```bash
   diff <(butane working.bu | python3 -m json.tool) \
        <(butane broken.bu | python3 -m json.tool)
   ```

---

## Common Error Messages and Solutions

| Error Message | Likely Cause | Solution |
|--------------|--------------|----------|
| `Failed to start ignition-remount-sysroot.service` | Missing `overwrite: true` | Add `overwrite: true` to file entries |
| `ostree-prepare-root: failed to create /run/ostree: File exists` | Missing `overwrite: true` | Add `overwrite: true` to file entries |
| `No QEMU guest agent configured` | Normal - guest agent not installed | Use Proxmox web console or network scan |
| `unable to find a serial interface` | Serial console not configured | Use Proxmox web UI console or add serial with `qm set <VMID> -serial0 socket` |
| `systemd-tmpfiles-setup-dev-early.service: Failed` | Early boot failure, check previous errors | Look for ignition or ostree errors above this |

---

## Reporting New Issues

When you encounter a new failure:

1. **Document the symptoms** - exact error messages, console output
2. **Identify the root cause** - what configuration was wrong
3. **Document the solution** - what fixed it
4. **Add to this file** under the appropriate section
5. **Update CLAUDE.md** so future debugging follows the same patterns

### Template for New Issues:

```markdown
### Title of Issue

**Date Identified:** YYYY-MM-DD

**Severity:** [Critical/High/Medium/Low]

**Symptoms:**
- List of observable symptoms
- Error messages
- Console output

**Root Cause:**
Explanation of why this happens

**Solution:**
Step by step fix

**Prevention:**
How to avoid this in the future
```
