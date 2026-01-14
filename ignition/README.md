# Ignition Directory

This directory contains the **default Butane configuration** used when selecting option 1 ("Default CoreOS") from the setup menu.

## What is this?

When you run `./setup-coreos.sh` and select "Default CoreOS (basic configuration)", the script uses `ignition.bu` to create a minimal Fedora CoreOS VM with basic user access.

## Configuration: `ignition.bu`

This is a **minimal, barebones** CoreOS configuration suitable for:
- Testing and experimentation
- Learning Fedora CoreOS
- Building your own custom configurations
- Quick VM deployments without services

### What it includes:

**Users:**
- `core` - Default CoreOS user with SSH key authentication
  - SSH key configured in the file
  - Member of `wheel` group (sudo access)

- `fcos-user` - Local user with password authentication
  - **Password: `coreos`** (for console/emergency access)
  - Member of `wheel` group (sudo access)
  - Useful for console login if SSH is unavailable

**System:**
- Hostname set to `fcos-user` (gets replaced with your chosen hostname)
- DHCP networking (automatic IP assignment)

### What it does NOT include:

- No services (nginx, postgresql, kubernetes, etc.)
- No containers
- No additional packages
- No custom networking configuration

## Usage

1. Run the setup script:
   ```bash
   ./setup-coreos.sh
   ```

2. Select option 1: "Default CoreOS (basic configuration)"

3. Choose a hostname (or accept default)

4. Wait for VM creation

5. Access your VM:
   ```bash
   # Via SSH (preferred)
   ssh core@<vm-ip>

   # Via console (if needed)
   # Username: fcos-user
   # Password: coreos
   ```

## Customizing

To customize the default configuration:

1. Edit `ignition.bu` to add your requirements
2. Follow the Butane specification v1.6.0 for FCOS
3. Test your changes with: `butane --strict ignition.bu`

**Common customizations:**
- Add more users
- Install additional packages via `rpm-ostree`
- Configure static IP addresses
- Add systemd services
- Mount additional storage

## Security Note

⚠️ **Important:** The `fcos-user` password is publicly known (`coreos`). This configuration is intended for:
- Local/internal testing
- Development environments
- Non-production use

**For production deployments:**
- Remove the password-based user
- Use SSH key authentication only
- Consider using the service-specific examples in `examples/` instead

## Comparison with Examples

| Feature | Default (`ignition/`) | Examples (`examples/`) |
|---------|----------------------|------------------------|
| Purpose | Minimal base system | Production-ready services |
| Services | None | nginx, postgresql, k3s, etc. |
| Networking | Basic DHCP | Service-specific configs |
| Packages | None extra | Service dependencies included |
| Use Case | Learning, testing | Production deployment |

For production workloads, see the [examples directory](../examples/) with pre-configured services.

## Related Files

- `ignition.bu` - Butane configuration (source of truth, human-editable YAML)
- `*.ign` files - Generated Ignition JSON (created automatically by script, not committed to git)

The script automatically converts `.bu` → `.ign` using the `butane` tool during VM creation.
