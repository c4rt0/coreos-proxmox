# Kubernetes with k3s

k3s is a lightweight, production-grade Kubernetes distribution that runs perfectly on Fedora CoreOS.

## Files

- **`kubernetes-control-plane.bu`** - Control plane/master node configuration
- **`kubernetes-worker.bu`** - Worker node configuration
- **`KUBERNETES_USAGE.md`** - Practical examples and usage guide (start here after setup!)

## Architecture

```
Control Plane (k3s server)
  Static IP: 192.168.68.54:6443
        ↓ (kubeconfig + token)
    ↓       ↓       ↓
Worker1  Worker2  Worker3 (k3s agents)
  DHCP IPs, unique hostnames required
```

**Important:** Each worker must have a unique hostname. Kubernetes identifies nodes by hostname, so duplicate hostnames will cause nodes to overwrite each other in the cluster.

## Quick Start

> **Note:** This configuration uses hardcoded values and automatic joining to make the setup process easier to understand and follow. In production environments, you should use unique tokens per cluster, secure token distribution methods (like HashiCorp Vault or Kubernetes Secrets), and implement proper authentication/authorization. This simplified approach helps you learn the cluster deployment flow without getting bogged down in secrets management initially.

### 1. Deploy Control Plane Node

```bash
cp kubernetes/kubernetes-control-plane.bu ../../ignition/ignition.bu
cd ../..
./setup-coreos.sh
```

**Wait ~2 minutes** for k3s to fully start on the control plane.

### 2. Deploy Worker Nodes

Worker nodes automatically join the cluster on first boot:

```bash
cp kubernetes/kubernetes-worker.bu ../../ignition/ignition.bu
cd ../..
./setup-coreos.sh
```

The worker will automatically connect to the control plane at `192.168.68.54:6443`.

**Important for Multiple Workers:** If you want to deploy additional worker nodes, you **must** change the hostname in `kubernetes-worker.bu` before deploying each one. Otherwise, Kubernetes will think they're all the same node and replace the previous worker.

To deploy multiple workers:

```bash
# Edit the hostname for each worker
# Change line 24: inline: k3s-worker
# To: inline: k3s-worker-1 (or k3s-worker-2, k3s-worker-3, etc.)

# For example, for the second worker:
sed -i 's/inline: k3s-worker/inline: k3s-worker-2/' kubernetes/kubernetes-worker.bu

# Then deploy
cp kubernetes/kubernetes-worker.bu ../../ignition/ignition.bu
cd ../..
./setup-coreos.sh

# Remember to change it back or increment for the next worker!
```

### 3. Verify Cluster

#### Check Node Status

From the control plane, verify both nodes are present and Ready:

```bash
ssh core@192.168.68.54
sudo /usr/local/bin/k3s kubectl get nodes
```

Expected output (single worker):
```
NAME                 STATUS   ROLES                  AGE   VERSION
k3s-control-plane    Ready    control-plane,master   5m    v1.34.x+k3s1
k3s-worker           Ready    <none>                 2m    v1.34.x+k3s1
```

Expected output (multiple workers with unique hostnames):
```
NAME                 STATUS   ROLES                  AGE   VERSION
k3s-control-plane    Ready    control-plane,master   10m   v1.34.x+k3s1
k3s-worker-1         Ready    <none>                 5m    v1.34.x+k3s1
k3s-worker-2         Ready    <none>                 2m    v1.34.x+k3s1
```

All nodes should show `STATUS: Ready`. If a node shows `NotReady`, wait a minute and check again, or see troubleshooting below.

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

---

**Next Steps:** Your cluster is now ready! See [KUBERNETES_USAGE.md](./KUBERNETES_USAGE.md) for practical examples of deploying real applications, including web servers, databases, homelab services, and more.

---

#### Troubleshooting

If worker node shows `NotReady`:
```bash
# On worker node, check k3s-agent service status
ssh core@<worker-ip>
sudo systemctl status k3s-agent

# Check logs for errors
sudo journalctl -u k3s-agent -f

# Check the installation service
sudo systemctl status k3s-worker-install.service
sudo journalctl -u k3s-worker-install.service
```

If worker isn't appearing in node list:
- Ensure control plane was deployed first and is fully running
- Check network connectivity from worker: `ping 192.168.68.54`
- Verify port 6443 is accessible from worker to control plane: `curl -k https://192.168.68.54:6443`
- Check if the worker install service ran: `sudo journalctl -u k3s-worker-install.service`

If you see a worker with old AGE but you just deployed it:
```bash
# This happens when deploying multiple workers with the same hostname
# Kubernetes thinks it's the same node and shows stale data

# Delete the stale node from the control plane
ssh core@192.168.68.54
sudo k3s kubectl delete node k3s-worker

# Restart the agent on the new worker
ssh core@<worker-ip>
sudo systemctl restart k3s-agent.service

# The worker will re-register with fresh data
```

**Prevention:** Always use unique hostnames for each worker (see "Important for Multiple Workers" above).

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
- **Auto-join**: Automatically connects to control plane at `192.168.68.54:6443` using hardcoded token
- **Services**:
  - `k3s-network-setup.service` - Enables IP forwarding
  - `k3s-worker-install.service` - Automatically installs and joins cluster on first boot
  - `k3s-agent.service` - Worker agent (created by k3s installer)

## Security Considerations

⚠️ **This configuration uses hardcoded credentials for ease of use in demo/lab environments.**

The cluster token (`proxmox-k3s-default-token`) is hardcoded in both control plane and worker configurations for automatic joining. **This simplifies the learning experience but is NOT secure for production.**

### Production Best Practices

In real-world deployments, you should:
1. **Generate unique tokens** - Use `k3s token create` on the control plane to generate tokens per worker
2. **Secure token distribution** - Use secrets management systems:
   - HashiCorp Vault for dynamic secret injection
   - Kubernetes External Secrets Operator
   - Sealed Secrets for encrypted storage in git
3. **Network security**:
   - Separate networks for control plane and worker traffic
   - Firewall rules restricting access to port 6443
   - mTLS for node-to-node communication
4. **Access control**:
   - Rotate tokens regularly (quarterly or when compromised)
   - Use RBAC to limit pod permissions
   - Implement Pod Security Standards
   - Restrict SSH access with jump hosts/bastion servers

The hardcoded approach here is intentionally simplified so you can focus on understanding how Kubernetes nodes communicate and join clusters without the complexity of secret management infrastructure.

## Resources

- [k3s Documentation](https://docs.k3s.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Fedora CoreOS Documentation](https://docs.fedoraproject.org/en-US/fedora-coreos/)
