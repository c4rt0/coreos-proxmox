# Kubernetes Example Ignition Configurations

This directory contains example Ignition (Butane) configurations for setting up Kubernetes clusters on Fedora CoreOS VMs via Proxmox.

## Kubernetes with k3s

k3s is a lightweight, production-grade Kubernetes distribution that runs perfectly on Fedora CoreOS.

### Files

- **`kubernetes-control-plane.bu`** - Control plane/master node configuration
- **`kubernetes-worker.bu`** - Worker node configuration

### Architecture

```
Control Plane (k3s server)
        ↓ (kubeconfig + token)
    ↓       ↓       ↓
Worker1  Worker2  Worker3 (k3s agents)
```

### Prerequisites

- Proxmox VE host with setup-coreos.sh script
- At least 2GB RAM per VM (4GB+ recommended)
- Network connectivity between nodes
- SSH access configured

### Quick Start

#### 1. Deploy Control Plane Node

Use the setup script with the control plane configuration:

```bash
# Copy the control plane config to the standard location
cp examples/kubernetes-control-plane.bu ignition/ignition.bu

# Run the setup script
./setup-coreos.sh
```

The control plane will:
- Auto-install k3s server
- Enable IP forwarding
- Start the Kubernetes API server
- Generate a token for worker nodes to join

#### 2. Get Control Plane Token

Once the control plane VM boots and k3s is running:

```bash
ssh core@<control-plane-ip>
sudo /usr/local/bin/k3s kubectl get secret -n kube-system bootstrap-token-<token-id> -o json | jq '.data.token_secret' | base64 -d
```

Or check the k3s logs:
```bash
journalctl -u k3s.service -f
```

#### 3. Deploy Worker Nodes

For each worker node:

```bash
# Copy worker configuration
cp examples/kubernetes-worker.bu ignition/ignition.bu

# Run setup script
./setup-coreos.sh
```

Then configure the worker to join the cluster:

```bash
ssh core@<worker-ip>
export K3S_URL=https://<control-plane-ip>:6443
export K3S_TOKEN=<token-from-control-plane>
sudo /usr/local/bin/install-k3s-worker.sh
```

#### 4. Verify Cluster

From the control plane:

```bash
sudo /usr/local/bin/k3s kubectl get nodes
sudo /usr/local/bin/k3s kubectl get pods -A
```

### Configuration Details

#### Control Plane (`kubernetes-control-plane.bu`)

- **Hostname**: `k3s-control-plane`
- **Services**:
  - `k3s-network-setup.service` - Enables IP forwarding
  - `k3s-install.service` - Downloads and installs k3s
  - `k3s.service` - Runs the control plane server
- **Disabled Features**: Traefik (ingress controller), ServiceLB

#### Worker Node (`kubernetes-worker.bu`)

- **Hostname**: `k3s-worker`
- **Services**:
  - `k3s-network-setup.service` - Enables IP forwarding
  - `k3s-agent.service` - Worker agent (disabled by default, enable after joining)
- **Environment Variables**: `K3S_URL`, `K3S_TOKEN`

### Customization

#### Change Hostname

Edit the ignition files and modify:
```yaml
storage:
  files:
    - path: /etc/hostname
      mode: 0644
      contents:
        inline: your-custom-hostname
```

#### Change k3s Flags

Edit the systemd unit in the ignition file:
```yaml
ExecStart=/usr/local/bin/k3s server --disable=traefik --disable=servicelb --your-flag=value
```

#### Add Custom Users

Add more users to the `passwd.users` section:
```yaml
passwd:
  users:
    - name: myuser
      password_hash: "..."
      groups:
        - wheel
```

### Troubleshooting

#### k3s not starting

Check systemd logs:
```bash
journalctl -u k3s.service -n 100 -e
```

#### Worker nodes not joining

Verify network connectivity:
```bash
ping <control-plane-ip>
```

Check worker logs:
```bash
journalctl -u k3s-agent.service -n 100 -e
```

Verify token is correct and not expired.

#### Disk space issues

k3s stores data in `/var/lib/rancher/k3s/`. Monitor with:
```bash
df -h
```

### Security Considerations

⚠️ **Warning**: The default token `proxmox-k3s-default-token` in the control plane config is for demonstration only. For production:

1. Generate a secure token
2. Store it securely (preferably in a secrets vault)
3. Rotate tokens regularly
4. Restrict SSH access
5. Use firewall rules between nodes

### Next Steps

- Install ingress controller (nginx)
- Set up persistent storage (Ceph, NFS, etc.)
- Deploy monitoring (Prometheus, Grafana)
- Set up GitOps (ArgoCD, Flux)
- Configure network policies

### Resources

- [k3s Documentation](https://docs.k3s.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Fedora CoreOS Documentation](https://docs.fedoraproject.org/en-US/fedora-coreos/)
