# PostgreSQL Database on Fedora CoreOS

This directory contains Ignition configuration for running PostgreSQL database server on Fedora CoreOS with persistent storage, automatic initialization, and comprehensive database management.

## Default Login Credentials

### System Users

| User | Authentication | Details |
|------|----------------|---------|
| `core` | SSH key only | Primary admin user (use your SSH key) |
| `fcos-user` | Password: `coreos` | Alternative user for console/password login |

Both users have `sudo` access via the `wheel` group.

### PostgreSQL Users

| User | Password | Database |
|------|----------|----------|
| `postgres` | `postgres_secure_password_change_me` | Superuser |
| `app_user` | `app_password_change_me` | `app_db` |

**Warning:** Change these passwords before production use!

## Overview

This configuration provides:
- **PostgreSQL Container**: Official PostgreSQL Docker image running via Podman
- **Automatic Startup**: systemd services that manage container lifecycle
- **Persistent Storage**: Named volumes for database data durability
- **Health Checks**: Built-in health monitoring with automatic restarts
- **Initialization Script**: Automatic database and user creation on first boot
- **Unix Sockets**: Support for both network and local connections
- **Performance Tuning**: Configurable shared buffers and connection limits

## Quick Start

### 1. Generate Ignition Configuration

From the repository root:

```bash
butane examples/postgresql/postgresql.bu > examples/postgresql/postgresql.ign
```

### 2. Create VM with PostgreSQL Configuration

If using the main `setup-coreos.sh` script (requires customization for PostgreSQL):

```bash
# Option A: Using a custom ignition file
./setup-coreos.sh --ignition-file examples/postgresql/postgresql.ign --vmid 510

# Option B: Create VM manually in Proxmox
```

Or create the VM manually in Proxmox:

```bash
qm create 510 --name postgresql-vm --memory 4096 --cores 4 --scsihw virtio-scsi-pci
qm set 510 --scsi0 local-lvm:50 --ide2 local:iso/fedora-coreos.iso,media=cdrom
qm set 510 --boot c --bootdisk scsi0
qm set 510 --fw_cfg name=opt/com.coreos/config,file=examples/postgresql/postgresql.ign
qm start 510
```

### 3. Connect to PostgreSQL

Once the VM is running:

```bash
# SSH to the VM
ssh -i ~/.ssh/id_ed25519 core@<vm-ip>

# Connect to PostgreSQL using alias (configured in profile)
pg-shell

# Or manually:
podman exec -it postgresql-server psql -U postgres
```

## Default Credentials

**Superuser (postgres)**:
- **Username**: `postgres`
- **Password**: `postgres_secure_password_change_me` (⚠️ CHANGE THIS!)

**Application User (created on first boot)**:
- **Username**: `app_user`
- **Password**: `app_password_change_me` (⚠️ CHANGE THIS!)
- **Default Database**: `app_db`

**SSH Access**:
- **Username**: `core` or `fcos-user`
- **Password**: `coreos`

## Configuration Details

### Database Storage

PostgreSQL data location: `/var/lib/postgresql/data/`

This is a persistent volume that survives container restarts and updates.

### Connection Details

- **Host**: `localhost` (local) or VM IP (remote)
- **Port**: `5432` (standard PostgreSQL port)
- **Unix Socket**: `/var/run/postgresql/` (local connections only)

### systemd Services

#### postgresql-container.service
- Manages the PostgreSQL Podman container
- Automatically pulls latest PostgreSQL image
- Configures shared buffers (256MB) and max connections (200)
- Health checks every 10 seconds
- Restarts on failure with 30-second graceful shutdown

#### postgresql-init.service
- Runs once on first boot
- Waits for PostgreSQL to be ready (up to 30 seconds)
- Creates application user and database automatically
- Creates initialization marker file to prevent re-running

### Environment Variables

Configured in `postgresql-container.service`:

```bash
POSTGRES_PASSWORD=postgres_secure_password_change_me
POSTGRES_INITDB_ARGS="-c shared_buffers=256MB -c max_connections=200"
```

## Customization

### Change PostgreSQL Version

Edit `postgresql.bu`, find the `ExecStartPre=/usr/bin/podman pull` line:

```yaml
ExecStartPre=/usr/bin/podman pull docker.io/library/postgres:15
```

Replace with specific version (e.g., `postgres:14`, `postgres:16`).

### Modify Superuser Password

In `postgresql.bu`, update:

1. Container environment variable:
   ```yaml
   -e POSTGRES_PASSWORD=your_secure_password_here \
   ```

2. `.pgpass` file for password-less connections:
   ```
   localhost:5432:*:postgres:your_secure_password_here
   ```

### Change Application User Credentials

In `postgresql-init.service`, modify the CREATE USER command:

```bash
CREATE USER your_app_user WITH PASSWORD 'your_app_password';
CREATE DATABASE your_app_db OWNER your_app_user;
```

### Adjust Performance Parameters

In `postgresql-container.service`, modify `POSTGRES_INITDB_ARGS`:

```bash
-c shared_buffers=512MB \      # For 4GB+ RAM systems
-c max_connections=300 \        # For more concurrent users
-c effective_cache_size=2GB \   # For caching
-c work_mem=32MB \              # For complex queries
```

### Enable Remote Connections

By default, PostgreSQL listens on all interfaces. To restrict access:

1. Create `postgresql.conf` file:
   ```bash
   scp postgresql.conf core@<vm-ip>:/var/lib/postgresql/
   ```

2. Mount in container:
   ```yaml
   -v /var/lib/postgresql/postgresql.conf:/etc/postgresql/postgresql.conf \
   ```

3. Add to startup:
   ```bash
   -c config_file=/etc/postgresql/postgresql.conf
   ```

### Enable Extensions

Connect to PostgreSQL and enable extensions:

```bash
pg-shell

# Inside PostgreSQL
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS uuid-ossp;
CREATE EXTENSION IF NOT EXISTS postgis;  # For geographic data
```

## Performance Tuning

### Memory Allocation

When creating the VM, allocate appropriate memory:

```bash
qm set 510 --memory 8192    # 8GB RAM for production
```

Adjust shared_buffers to 25% of available RAM:
```yaml
-c shared_buffers=2GB \      # For 8GB system
```

### Disk I/O

For better performance, use faster storage:

```bash
qm set 510 --scsi0 local-lvm:100,ssd=1 \  # Mark as SSD
```

### Connection Pooling

For applications with many connections, use PgBouncer (separate container):

```bash
podman run -d \
  --name pgbouncer \
  --network host \
  -e DATABASES_HOST=localhost \
  -e DATABASES_PORT=5432 \
  -e DATABASES_USER=postgres \
  -e DATABASES_PASSWORD=postgres_secure_password_change_me \
  edoburu/pgbouncer:latest
```

### Query Performance

Enable query logging and statistics:

```bash
pg-shell

CREATE EXTENSION pg_stat_statements;
SELECT query, calls, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;
```

## Monitoring & Maintenance

### Check Container Status

```bash
# Quick status
pg-status

# Detailed container info
podman ps -a --filter name=postgresql-server

# Resource usage
podman stats postgresql-server
```

### View Logs

```bash
# Follow real-time logs
pg-logs

# View last 50 lines
podman logs -n 50 postgresql-server
```

### Database Size

```bash
pg-shell

SELECT datname, pg_size_pretty(pg_database_size(datname)) as size
FROM pg_database
ORDER BY pg_database_size(datname) DESC;
```

### Active Connections

```bash
pg-shell

SELECT pid, usename, application_name, state, query
FROM pg_stat_activity
WHERE state != 'idle';
```

## Backup & Restore

### Automated Backup Script

Create `/root/backup-postgresql.sh`:

```bash
#!/bin/bash

BACKUP_DIR="/var/lib/postgresql/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Full backup
podman exec postgresql-server pg_dump -U postgres -b -v -F d -j 4 -f /var/lib/postgresql/backups/full_${DATE}

# Compressed SQL backup
podman exec postgresql-server pg_dump -U postgres -Fc postgres > ${BACKUP_DIR}/postgres_${DATE}.dump

echo "Backup completed: ${BACKUP_DIR}"
```

Make it executable:
```bash
chmod +x /root/backup-postgresql.sh
```

### Schedule Backups with cron

```bash
# Add to crontab (runs daily at 2 AM)
0 2 * * * /root/backup-postgresql.sh
```

### Restore from Backup

```bash
# From custom format backup
pg-shell
\q

podman exec postgresql-server pg_restore -U postgres -d app_db /var/lib/postgresql/backups/full_DATE/

# From compressed SQL backup
podman exec postgresql-server psql -U postgres -d app_db < backup.sql
```

## Troubleshooting

### Container Won't Start

Check the logs:
```bash
podman logs postgresql-server
journalctl -u postgresql-container.service -n 50
```

### Connection Refused

Verify container is running:
```bash
podman ps | grep postgresql-server
podman inspect postgresql-server
```

Check network:
```bash
podman port postgresql-server
```

### Slow Queries

Enable and check slow query log:

```bash
pg-shell

SELECT * FROM pg_stat_statements 
ORDER BY mean_exec_time DESC 
LIMIT 10;
```

### Out of Disk Space

Check usage:
```bash
df -h /var/lib/postgresql/data
```

Clean up old backups:
```bash
rm -rf /var/lib/postgresql/backups/old_backups/
```

### Permission Issues

Fix data directory permissions:
```bash
sudo chown 999:999 /var/lib/postgresql/data
sudo chmod 700 /var/lib/postgresql/data
```

## Security Considerations

### Change Default Passwords

⚠️ **CRITICAL**: Change passwords before production deployment!

```bash
pg-shell

ALTER USER postgres WITH PASSWORD 'your_secure_password';
ALTER USER app_user WITH PASSWORD 'another_secure_password';
```

### Network Access Control

Restrict connections in `postgresql.conf`:

```
listen_addresses = 'localhost'  # Only local connections
# or
listen_addresses = '0.0.0.0'    # All interfaces (use with firewall)
```

### Firewall Rules

On the Proxmox host:

```bash
# Only allow from specific network
ufw allow from 10.0.0.0/24 to any port 5432

# Or in Proxmox via Web UI:
# Configure network rules for VM
```

### SSL/TLS Connections

Enable SSL certificates:

1. Create certificates:
   ```bash
   openssl req -new -x509 -days 365 -nodes -out /etc/postgresql/server.crt -keyout /etc/postgresql/server.key
   chmod 600 /etc/postgresql/server.key
   ```

2. Mount in container:
   ```yaml
   -v /etc/postgresql/server.crt:/var/lib/postgresql/server.crt:ro \
   -v /etc/postgresql/server.key:/var/lib/postgresql/server.key:ro \
   ```

3. Configure in `postgresql.conf`:
   ```
   ssl = on
   ssl_cert_file = '/var/lib/postgresql/server.crt'
   ssl_key_file = '/var/lib/postgresql/server.key'
   ```

### User Permissions

Create restricted users:

```bash
pg-shell

-- Read-only user
CREATE USER read_only WITH PASSWORD 'password';
GRANT CONNECT ON DATABASE app_db TO read_only;
GRANT USAGE ON SCHEMA public TO read_only;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO read_only;

-- Application user (limited privileges)
CREATE USER app_user WITH PASSWORD 'password';
GRANT CONNECT ON DATABASE app_db TO app_user;
GRANT USAGE, CREATE ON SCHEMA public TO app_user;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO app_user;
```

## Advanced Topics

### Replication Setup

For high availability, set up streaming replication:

1. Configure primary with `wal_level = replica`
2. Create replication user
3. Set up standby with `primary_conninfo`
4. Use tools like pg_basebackup

### Partitioning Large Tables

For tables exceeding 1GB:

```bash
pg-shell

-- Range partitioning by date
CREATE TABLE orders (id int, order_date date, amount numeric)
PARTITION BY RANGE (EXTRACT(YEAR FROM order_date));

CREATE TABLE orders_2024 PARTITION OF orders
  FOR VALUES FROM (2024) TO (2025);
```

### Full-Text Search

Enable full-text search for advanced queries:

```bash
pg-shell

CREATE EXTENSION pg_trgm;
CREATE INDEX idx_search ON documents USING gin(to_tsvector('english', content));
```

## Integration with Other Services

### From nginx Reverse Proxy

Configure nginx to forward requests to PostgreSQL-backed API:

```nginx
upstream api_backend {
    server 127.0.0.1:3000;  # API server connecting to PostgreSQL
}

server {
    location /api {
        proxy_pass http://api_backend;
    }
}
```

### Container-to-Container Networking

Connect from application container to PostgreSQL:

```bash
podman network create app-network
podman run --network app-network --name app myapp:latest
podman run --network app-network -p 5432:5432 postgres:latest
```

## Related Documentation

- [PostgreSQL Official Documentation](https://www.postgresql.org/docs/)
- [Fedora CoreOS Documentation](https://docs.fedoraproject.org/en-US/fedora-coreos/)
- [Podman Container Runtime](https://podman.io/docs)
- [Ignition Specification](https://coreos.com/ignition/docs/latest/examples.html)
- [PostgreSQL Docker Image](https://hub.docker.com/_/postgres)

## Support & Updates

To update this configuration:

1. Pull latest from repository: `git pull origin examples/ignition-configs`
2. Review changes: `git diff HEAD~1 examples/postgresql/postgresql.bu`
3. Regenerate Ignition: `butane examples/postgresql/postgresql.bu > examples/postgresql/postgresql.ign`
4. Create new VM or update existing one with new Ignition config

---

**Last Updated**: 2024
**Example Type**: Database Server (Containerized)
**Base Image**: Fedora CoreOS (latest stable)
**Database**: PostgreSQL (latest)
**Container Runtime**: Podman
