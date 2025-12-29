# Example Ignition Configurations

This directory contains example Ignition (Butane) configurations for various tools and services running on Fedora CoreOS VMs via Proxmox.

## Available Examples

### [Kubernetes with k3s](./kubernetes/)

Lightweight, production-grade Kubernetes cluster setup with control plane and worker nodes.

- Control plane configuration
- Worker node configuration  
- Token-based cluster joining
- Full deployment guide

### [nginx](./nginx/)

Containerized web server and reverse proxy configuration.

- nginx container via Podman
- Automatic startup and restart
- HTTP/HTTPS support
- Custom configuration examples
- SSL/TLS setup guide

### [PostgreSQL](./postgresql/) (Coming Soon)

Relational database configuration.

### [Docker Compose](./docker-compose/) (Coming Soon)

Multi-container application orchestration.

## General Usage

Each example includes:
- Butane configuration files (`.bu`)
- README with detailed setup instructions
- Pre-configured users and SSH access
- Systemd service definitions

### Basic Workflow

1. Choose an example directory
2. Copy the appropriate `.bu` file:
   ```bash
   cp examples/<service>/<config>.bu ignition/ignition.bu
   ```
3. Run the setup script:
   ```bash
   ./setup-coreos.sh
   ```
4. Follow the example's README for service-specific configuration

## Customization

Each example can be customized by editing:
- Hostnames
- Users and passwords
- Service ports
- Resource limits
- Network configuration

See individual example READMEs for customization details.

## Security Notes

- All examples use demo credentials - change them for production
- SSH keys should be updated to your own
- Firewall rules should be configured per your network policy
- Tokens and secrets should be stored securely

## Contributing

Feel free to add new examples! Create:
1. A new directory: `examples/<service>/`
2. Butane configuration files
3. README with setup and customization guide
4. Commit and submit PR

## Resources

- [Butane Documentation](https://coreos.github.io/butane/)
- [Fedora CoreOS Documentation](https://docs.fedoraproject.org/en-US/fedora-coreos/)
- [systemd Documentation](https://www.freedesktop.org/software/systemd/man/)

