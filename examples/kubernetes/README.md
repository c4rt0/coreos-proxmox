# Kubernetes with k3s

k3s is a lightweight, production-grade Kubernetes distribution that runs perfectly on Fedora CoreOS.

## Files

- **`kubernetes-control-plane.bu`** - Control plane/master node configuration
- **`kubernetes-worker.bu`** - Worker node configuration

## Architecture

```
Control Plane (k3s server)
        ↓ (kubeconfig + token)
    ↓       ↓       ↓
Worker1  Worker2  Worker3 (k3s agents)
```

## Quick Start

### 1. Deploy Control Plane Node

```bash
cp kubernetes/kubernetes-control-plane.bu ../../ignition/ignition.bu
cd ../..
./setup-coreos.sh
```

### 2. Deploy Worker Nodes

For each worker node:

```bash
cp kubernetes/kubernetes-worker.bu ../../ignition/ignition.bu
cd ../..
./setup-coreos.sh
```

Then configure the worker to join:

```bash
ssh core@<worker-ip>
export K3S_URL=https://<control-plane-ip>:6443
export K3S_TOKEN=<token-from-control-plane>
sudo /usr/local/bin/install-k3s-worker.sh
```

### 3. Verify Cluster

From the control plane:

```bash
sudo /usr/local/bin/k3s kubectl get nodes
sudo /usr/local/bin/k3s kubectl get pods -A
```

## Configuration Details

### Control Plane

- **Hostname**: `k3s-control-plane`
- **Services**:
  - `k3s-network-setup.service` - Enables IP forwarding
  - `k3s-install.service` - Downloads and installs k3s
  - `k3s.service` - Runs the control plane server
- **Disabled Features**: Traefik (ingress controller), ServiceLB

### Worker Node

- **Hostname**: `k3s-worker`
- **Services**:
  - `k3s-network-setup.service` - Enables IP forwarding
  - `k3s-agent.service` - Worker agent

## Security Considerations

⚠️ The default token in control plane config is for demonstration only. For production:
- Generate secure tokens
- Store them securely
- Rotate tokens regularly
- Restrict SSH access
- Use firewall rules

## Resources

- [k3s Documentation](https://docs.k3s.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Fedora CoreOS Documentation](https://docs.fedoraproject.org/en-US/fedora-coreos/)
