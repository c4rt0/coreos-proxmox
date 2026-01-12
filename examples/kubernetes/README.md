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

Then configure the worker to join. First, get the token from the control plane:

```bash
ssh core@192.168.68.54
sudo cat /var/lib/rancher/k3s/server/node-token
```

Now on the worker node:

```bash
ssh core@<worker-ip>
export K3S_URL=https://192.168.68.54:6443
export K3S_TOKEN=<token-from-control-plane>
sudo /usr/local/bin/install-k3s-worker.sh
```

### 3. Verify Cluster

#### Check Node Status

From the control plane, verify both nodes are present and Ready:

```bash
ssh core@192.168.68.54
sudo /usr/local/bin/k3s kubectl get nodes
```

Expected output:
```
NAME                 STATUS   ROLES                  AGE   VERSION
k3s-control-plane    Ready    control-plane,master   5m    v1.28.x+k3s1
k3s-worker           Ready    <none>                 2m    v1.28.x+k3s1
```

Both nodes should show `STATUS: Ready`. If a node shows `NotReady`, wait a minute and check again, or see troubleshooting below.

#### Verify Worker Communication

Check that the worker node is actively reporting to the control plane:

```bash
sudo /usr/local/bin/k3s kubectl get nodes -o wide
```

This shows IP addresses and confirms network connectivity between nodes.

#### Check System Pods

Verify essential cluster components are running:

```bash
sudo /usr/local/bin/k3s kubectl get pods -A
```

Expected output should show pods in `kube-system` namespace all with `Running` status:
```
NAMESPACE     NAME                                     READY   STATUS    RESTARTS   AGE
kube-system   coredns-xxx                              1/1     Running   0          5m
kube-system   local-path-provisioner-xxx               1/1     Running   0          5m
kube-system   metrics-server-xxx                       1/1     Running   0          5m
```

#### Test Pod Scheduling on Worker

Deploy a test pod and verify it schedules on the worker node:

```bash
sudo /usr/local/bin/k3s kubectl run test-nginx --image=nginx --restart=Never
sudo /usr/local/bin/k3s kubectl get pods -o wide
```

The `NODE` column should show the pod running on `k3s-worker`, confirming the control plane can schedule workloads on the worker.

Clean up the test pod:

```bash
sudo /usr/local/bin/k3s kubectl delete pod test-nginx
```

#### Troubleshooting

If worker node shows `NotReady`:
```bash
# On worker node, check k3s-agent service status
ssh core@<worker-ip>
sudo systemctl status k3s-agent

# Check logs for errors
sudo journalctl -u k3s-agent -f
```

If worker isn't appearing in node list:
- Verify K3S_URL and K3S_TOKEN were set correctly
- Check network connectivity: `ping 192.168.68.54` from worker
- Verify port 6443 is accessible from worker to control plane

## Configuration Details

### Control Plane

- **Hostname**: `k3s-control-plane`
- **Network**: Static IP `192.168.68.54/24`
- **Services**:
  - `k3s-network-setup.service` - Enables IP forwarding
  - `k3s-install.service` - Downloads and installs k3s
  - `k3s.service` - Runs the control plane server (created by k3s installer)
- **Disabled Features**: Traefik (ingress controller), ServiceLB

### Worker Node

- **Hostname**: `k3s-worker`
- **Network**: DHCP (automatically assigned)
- **Services**:
  - `k3s-network-setup.service` - Enables IP forwarding
  - `k3s-agent.service` - Worker agent (created by k3s installer)

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
