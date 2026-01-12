# Kubernetes Usage Guide

This guide explains what your Kubernetes cluster can do and provides practical examples of deploying applications.

## Understanding Your Cluster

Your k3s cluster consists of:
- **Control Plane** (192.168.68.54): The "brain" that manages the cluster, schedules workloads, and maintains desired state
- **Worker Nodes**: The "muscles" that actually run your applications (containers/pods)

The control plane decides which worker runs which application. You tell the control plane what you want, and it makes it happen.

## Basic Concepts

- **Pod**: The smallest unit - one or more containers running together
- **Deployment**: Manages multiple identical pods (replicas) for high availability
- **Service**: Provides a stable network endpoint to access pods
- **Namespace**: Logical isolation for organizing resources

## Practical Examples

All commands should be run from the control plane:
```bash
ssh core@192.168.68.54
```

### Example 1: Deploy a Simple Web Server

Deploy nginx across your workers:

```bash
# Create a deployment with 3 replicas
sudo k3s kubectl create deployment web --image=nginx --replicas=3

# Check which workers are running the pods
sudo k3s kubectl get pods -o wide

# Expected output:
# NAME                   READY   STATUS    NODE
# web-xxxx-aaa          1/1     Running   k3s-worker-1
# web-xxxx-bbb          1/1     Running   k3s-worker-2
# web-xxxx-ccc          1/1     Running   k3s-worker-1

# Expose the deployment
sudo k3s kubectl expose deployment web --port=80 --type=NodePort

# Get the assigned port
sudo k3s kubectl get service web
# Access it: http://192.168.68.54:<NodePort>
```

### Example 2: Deploy a Database

Run PostgreSQL on a worker:

```bash
# Create a PostgreSQL deployment
sudo k3s kubectl create deployment postgres \
  --image=postgres:15 \
  -- -e POSTGRES_PASSWORD=mypassword

# Check it's running
sudo k3s kubectl get pods -l app=postgres -o wide

# Access the database
POD_NAME=$(sudo k3s kubectl get pods -l app=postgres -o jsonpath='{.items[0].metadata.name}')
sudo k3s kubectl exec -it $POD_NAME -- psql -U postgres
```

### Example 3: Multi-Tier Application

Deploy a complete web application with frontend, backend, and database:

```bash
# Deploy PostgreSQL database
sudo k3s kubectl create deployment db \
  --image=postgres:15

# Deploy a backend API (example: a simple API)
sudo k3s kubectl create deployment api \
  --image=traefik/whoami \
  --replicas=2

# Expose the API internally
sudo k3s kubectl expose deployment api --port=80 --name=api-service

# Deploy a frontend
sudo k3s kubectl create deployment frontend \
  --image=nginx \
  --replicas=2

# Expose frontend to outside world
sudo k3s kubectl expose deployment frontend \
  --port=80 \
  --type=NodePort \
  --name=frontend-service

# See the entire stack
sudo k3s kubectl get all
```

### Example 4: Homelab Services

Deploy common homelab applications:

#### Pi-hole (DNS Ad Blocker)
```bash
# Create a namespace for network services
sudo k3s kubectl create namespace network

# Deploy Pi-hole
cat <<EOF | sudo k3s kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pihole
  namespace: network
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pihole
  template:
    metadata:
      labels:
        app: pihole
    spec:
      containers:
      - name: pihole
        image: pihole/pihole:latest
        env:
        - name: TZ
          value: "America/New_York"
        - name: WEBPASSWORD
          value: "admin"
        ports:
        - containerPort: 80
        - containerPort: 53
---
apiVersion: v1
kind: Service
metadata:
  name: pihole
  namespace: network
spec:
  type: NodePort
  selector:
    app: pihole
  ports:
  - name: web
    port: 80
    targetPort: 80
  - name: dns
    port: 53
    targetPort: 53
EOF

# Get the web interface port
sudo k3s kubectl get service pihole -n network
# Access: http://192.168.68.54:<NodePort>
```

### Example 5: Load Balancing Test

See how Kubernetes distributes load across workers:

```bash
# Deploy 5 replicas
sudo k3s kubectl create deployment loadtest \
  --image=traefik/whoami \
  --replicas=5

# Expose it
sudo k3s kubectl expose deployment loadtest \
  --port=80 \
  --type=NodePort

# Check distribution across workers
sudo k3s kubectl get pods -l app=loadtest -o wide

# You'll see pods spread across your workers
# Worker-1: 3 pods
# Worker-2: 2 pods
```

### Example 6: High Availability Demo

Demonstrate automatic pod recovery:

```bash
# Deploy with 3 replicas
sudo k3s kubectl create deployment ha-demo \
  --image=nginx \
  --replicas=3

# Watch the pods
sudo k3s kubectl get pods -l app=ha-demo -o wide -w

# In another terminal, delete a pod
POD_NAME=$(sudo k3s kubectl get pods -l app=ha-demo -o jsonpath='{.items[0].metadata.name}')
sudo k3s kubectl delete pod $POD_NAME

# Watch as Kubernetes automatically creates a replacement pod!
# This is the "self-healing" feature of Kubernetes
```

## Common Operations

### Scaling Applications

```bash
# Scale up to 5 replicas
sudo k3s kubectl scale deployment web --replicas=5

# Scale down to 2 replicas
sudo k3s kubectl scale deployment web --replicas=2
```

### Updating Applications

```bash
# Update to a new image version
sudo k3s kubectl set image deployment/web nginx=nginx:alpine

# Kubernetes performs a rolling update - old pods are replaced one at a time
# Zero downtime!
```

### Viewing Logs

```bash
# Get logs from a specific pod
sudo k3s kubectl logs <pod-name>

# Follow logs in real-time
sudo k3s kubectl logs -f <pod-name>

# Get logs from all pods in a deployment
sudo k3s kubectl logs -l app=web --tail=20
```

### Debugging

```bash
# Describe a pod to see events and status
sudo k3s kubectl describe pod <pod-name>

# Execute commands inside a pod
sudo k3s kubectl exec -it <pod-name> -- /bin/bash

# Check resource usage
sudo k3s kubectl top nodes
sudo k3s kubectl top pods
```

### Cleaning Up

```bash
# Delete a deployment (and its pods)
sudo k3s kubectl delete deployment web

# Delete a service
sudo k3s kubectl delete service web

# Delete everything in a namespace
sudo k3s kubectl delete all --all -n network
```

## Real-World Use Cases

### 1. Development Environment
- **Scenario**: Run dev, staging, and production environments on separate workers
- **Workers**: 3+ workers, each hosting a full application stack
- **Benefits**: Isolated environments, easy to reset, version control your configs

### 2. Home Media Server
- **Services**: Plex/Jellyfin (media), Sonarr/Radarr (management), Transmission (downloads)
- **Workers**: Dedicate one worker with lots of storage for media
- **Benefits**: All services managed by Kubernetes, automatic restarts

### 3. Self-Hosted Apps
- **Services**: Nextcloud (files), Gitea (git), Bitwarden (passwords), Uptime Kuma (monitoring)
- **Workers**: Spread across workers for redundancy
- **Benefits**: One cluster manages all your self-hosted services

### 4. CI/CD Pipeline
- **Services**: GitLab or Jenkins runners on workers
- **Workers**: Dedicated build workers with lots of CPU
- **Benefits**: Parallel builds, automatic scaling during high load

### 5. Learning Platform
- **Scenario**: Learn Docker, Kubernetes, DevOps practices
- **Workers**: Experiment without fear - tear down and rebuild easily
- **Benefits**: Safe sandbox, matches production Kubernetes patterns

## Why Use Multiple Workers?

1. **High Availability**: If one worker fails, pods automatically move to healthy workers
2. **Load Distribution**: Spread CPU/memory intensive apps across multiple machines
3. **Resource Isolation**: Keep incompatible or resource-hungry apps on separate workers
4. **Scaling**: Add more workers to handle more applications
5. **Rolling Updates**: Update workers one at a time without downtime

## Next Steps

1. **Learn kubectl**: `sudo k3s kubectl --help`
2. **Explore Helm**: Package manager for Kubernetes applications
3. **Try Persistent Storage**: Learn about PersistentVolumes for databases
4. **Set up Ingress**: Use a reverse proxy (like Traefik or nginx-ingress) for routing
5. **Monitor Your Cluster**: Deploy Prometheus + Grafana for metrics

## Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [k3s Documentation](https://docs.k3s.io/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Kubernetes by Example](https://kubernetesbyexample.com/)
