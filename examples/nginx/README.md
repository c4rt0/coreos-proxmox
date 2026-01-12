# nginx Web Server on Fedora CoreOS

This directory contains Ignition configuration for running a containerized nginx web server on Fedora CoreOS with automatic startup and persistent storage.

## Default Login Credentials

| User | Authentication | Details |
|------|----------------|---------|
| `core` | SSH key only | Primary admin user (use your SSH key) |
| `fcos-user` | Password: `coreos` | Alternative user for console/password login |

Both users have `sudo` access via the `wheel` group.

## Overview

This configuration provides:
- **nginx Container**: Latest official nginx Docker image running via Podman
- **Automatic Startup**: systemd services that start nginx on system boot
- **Persistent Storage**: Host directories for website content and configuration
- **HTTP/HTTPS Support**: Ports 80 and 443 exposed to the host
- **Health Integration**: systemd manages container lifecycle with automatic restart

## Quick Start

### 1. Generate Ignition Configuration

From the repository root:

```bash
butane examples/nginx/nginx.bu > examples/nginx/nginx.ign
```

### 2. Create VM with nginx Configuration

If using the main `setup-coreos.sh` script (requires customization for nginx):

```bash
# Option A: Using a custom ignition file
./setup-coreos.sh --ignition-file examples/nginx/nginx.ign --vmid 500

# Option B: Create VM manually in Proxmox with the nginx.ign file
```

Or create the VM manually in Proxmox:

```bash
qm create 500 --name nginx-vm --memory 2048 --cores 2 --scsihw virtio-scsi-pci
qm set 500 --scsi0 local-lvm:30 --ide2 local:iso/fedora-coreos.iso,media=cdrom
qm set 500 --boot c --bootdisk scsi0
qm set 500 --fw_cfg name=opt/com.coreos/config,file=examples/nginx/nginx.ign
qm start 500
```

### 3. Access nginx

Once the VM is running:

```bash
# SSH to the VM
ssh -i ~/.ssh/id_ed25519 core@<vm-ip>

# Check nginx service status (it's a containerized service, not a native package)
systemctl status nginx-container.service

# Check the Podman container
podman ps
podman logs nginx-server

# Access web server
curl http://<vm-ip>:80
```

**Important Note:** nginx runs as a **Podman container**, not as a native RPM package. Therefore:
- Use `systemctl status nginx-container.service` (not `nginx.service`)
- Use `podman ps` to see the running container
- Don't use `rpm -q nginx` (package is not installed)
- Don't use `systemctl status nginx` (wrong service name)

The service is called `nginx-container.service` because it manages nginx inside a container.

## Default Credentials

- **Username**: `core` or `fcos-user`
- **Password**: `coreos`
- **SSH Key**: Standard Fedora CoreOS public key (see ignition.bu)

## Configuration Details

### Web Server Root

Website content location: `/var/www/html/`

Default `index.html` is automatically created with basic welcome page.

### nginx Configuration

nginx configuration directory: `/etc/nginx/conf.d/`

To add custom configurations:

1. SSH into the VM
2. Create or edit files in `/etc/nginx/conf.d/`
3. Reload nginx:
   ```bash
   podman kill -s HUP nginx-server
   ```

### systemd Services

#### nginx-container.service
- Manages the nginx Podman container
- Automatically pulls latest nginx image
- Restarts on failure with 10-second delay
- Network mode: `host` (direct port access)

#### nginx-config-setup.service
- Runs once on first boot
- Creates necessary directories
- Generates default index.html if missing
- Must complete before nginx-container.service starts

## Customization

### Change Container Image

Edit `nginx.bu`, find the `ExecStartPre=/usr/bin/podman pull` line:

```yaml
ExecStartPre=/usr/bin/podman pull docker.io/library/nginx:alpine
```

Replace with desired image (e.g., `nginx:alpine` for smaller footprint).

### Modify Port Mappings

In `nginx-container.service`, change the port mapping:

```bash
-p 8080:80 \      # Host:Container mapping
-p 8443:443 \
```

### Add SSL/TLS Support

1. Copy certificates to the VM:
   ```bash
   scp -r certs/ core@<vm-ip>:/etc/nginx/ssl/
   ```

2. Create nginx config in `/etc/nginx/conf.d/ssl.conf`:
   ```nginx
   server {
       listen 443 ssl http2;
       ssl_certificate /etc/nginx/ssl/cert.pem;
       ssl_certificate_key /etc/nginx/ssl/key.pem;
   }
   ```

### Customize Welcome Page

SSH to VM and edit:

```bash
sudo vi /var/www/html/index.html
```

## Performance Tuning

### Increase Memory Allocation

When creating the VM:

```bash
qm set 500 --memory 4096    # 4GB RAM
```

### Enable nginx Caching

Add to `/etc/nginx/conf.d/cache.conf`:

```nginx
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=my_cache:10m;

server {
    proxy_cache my_cache;
}
```

### Resource Limits (systemd)

Edit `nginx.bu` ExecStart section to add limits:

```yaml
MemoryLimit=1G
CPUQuota=50%
```

## Monitoring & Logs

### View nginx Logs

```bash
# Follow real-time logs
podman logs -f nginx-server

# View container events
podman events --filter container=nginx-server
```

### Check Container Status

```bash
podman ps -a --filter name=nginx-server
podman stats nginx-server
```

### System Metrics

```bash
# Disk usage
df -h /var/www/html /etc/nginx/conf.d

# Container resource usage
podman top nginx-server
```

## Troubleshooting

### Container Won't Start

Check the logs:
```bash
podman logs nginx-server
journalctl -u nginx-container.service -n 50
```

### Port Already in Use

If ports 80/443 are occupied:
1. Identify the process: `sudo netstat -tlnp | grep :80`
2. Modify port mappings in nginx.bu
3. Regenerate Ignition: `butane examples/nginx/nginx.bu > examples/nginx/nginx.ign`
4. Create new VM with updated config

### Cannot Access Web Server

1. Verify container is running: `podman ps | grep nginx`
2. Check network: `ip addr` (verify VM has IP)
3. Verify firewall: `sudo firewall-cmd --list-all` (or disable temporarily)
4. Test locally: `curl http://localhost:80`

### Network Connectivity Issues

With `network host` mode:
- Container shares host network stack
- No need to map ports if using bridge network
- If using bridge, modify network section in systemd unit

## Security Considerations

### File Permissions

- Website files mounted read-only from host: `-v /var/www/html:/usr/share/nginx/html:ro`
- Configuration directory mounted read-only: `-v /etc/nginx/conf.d:/etc/nginx/conf.d:ro`

### SELinux Integration

Fedora CoreOS uses SELinux. If facing permission issues:

```bash
# Check SELinux context for volumes
ls -Z /var/www/html /etc/nginx/conf.d

# Run container with appropriate context
podman run --security-opt label=type:svirt_sandbox_file_t ...
```

### SSL/TLS

- Use strong cipher suites in ssl.conf
- Keep certificates updated
- Enable HTTP/2 with `http2` directive
- Consider HSTS headers

### Container Security

```yaml
# In nginx-container.service, add:
--read-only \                    # Read-only filesystem
--cap-drop=ALL \                 # Drop all capabilities
--cap-add=NET_BIND_SERVICE \     # Only add what's needed
--ulimit nofile=65536:65536 \    # File descriptor limit
```

## Integration with Other Services

### Reverse Proxy to Other Containers

Create `/etc/nginx/conf.d/upstream.conf`:

```nginx
upstream backend {
    server 127.0.0.1:3000;
}

server {
    location /api {
        proxy_pass http://backend;
    }
}
```

### Multi-Domain Setup

Create separate server blocks in `/etc/nginx/conf.d/`:

```nginx
# api.example.com.conf
server {
    server_name api.example.com;
    location / {
        proxy_pass http://api_backend;
    }
}

# www.example.com.conf
server {
    server_name www.example.com;
    root /var/www/www.example.com;
}
```

## Advanced Topics

### Rolling Updates

To update nginx without downtime:

```bash
# Pull new image
podman pull docker.io/library/nginx:latest

# Reload with minimal downtime
podman exec nginx-server nginx -s reload
```

### Backup & Restore

```bash
# Backup website content
tar czf nginx-backup.tar.gz /var/www/html /etc/nginx/conf.d

# Restore on new VM
tar xzf nginx-backup.tar.gz -C /
```

### Multi-container Orchestration

For complex setups with nginx + app servers, see the Docker Compose examples.

## Related Documentation

- [Fedora CoreOS Documentation](https://docs.fedoraproject.org/en-US/fedora-coreos/)
- [Ignition Specification](https://coreos.com/ignition/docs/latest/examples.html)
- [Podman Container Runtime](https://podman.io/docs)
- [nginx Official Documentation](https://nginx.org/en/docs/)

## Support & Updates

To update this configuration:

1. Pull latest from repository: `git pull origin examples/ignition-configs`
2. Review changes: `git diff HEAD~1 examples/nginx/nginx.bu`
3. Regenerate Ignition: `butane examples/nginx/nginx.bu > examples/nginx/nginx.ign`
4. Create new VM or update existing one with new Ignition config

---

**Last Updated**: 2024
**Example Type**: Web Server (Containerized)
**Base Image**: Fedora CoreOS (latest stable)
**Container Runtime**: Podman
