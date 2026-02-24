<div align="center">
  <img src="sock.png" alt="sockmux logo" width="400"/>

  # sockmux

  **Claude Code Container Server**

  A containerized Claude Code environment with SSH access and shared tmux sessions, designed for multi-device access in Kubernetes.
</div>

## Features

- **Shared tmux session**: All SSH connections attach to the same Claude Code instance
- **SSH public key authentication**: Secure access using authorized_keys
- **Persistent home directory**: Mount `/home/claude` for code that persists across restarts
- **Multi-device support**: Connect from any device with SSH access
- **Claude Code pre-installed**: Auto-starts with dangerous permissions bypassed (container isolated)
- **Agent teams enabled**: Experimental multi-agent feature enabled by default
- **Automatic startup**: Claude Code starts immediately on SSH connection

## Building the Container

```bash
# Build the container image
nix build .#container

# Load into podman
podman load < result

# Tag for your registry
podman tag claude-code-server:latest ghcr.io/vangourd/sockmux:latest

# Push to registry
podman push ghcr.io/vangourd/sockmux:latest
```

## Local Testing

Create SSH keys directory:
```bash
mkdir -p ssh-keys claude-home
cp ~/.ssh/id_rsa.pub ssh-keys/authorized_keys
```

Run locally:
```bash
podman run -d \
  --name claude-code \
  -p 2222:2222 \
  -v ./claude-home:/home/claude \
  -v ./ssh-keys:/ssh-keys:ro \
  claude-code-server:latest
```

Connect:
```bash
ssh -p 2222 claude@localhost
```

## Kubernetes Deployment

### Quick Start with Helm (Recommended)

The easiest way to deploy on Kubernetes is using the Helm chart:

```bash
# Install from GitHub Container Registry
helm install claude-code-server oci://ghcr.io/vangourd/charts/claude-code-server \
  --set sshKeys.authorizedKeys="$(cat ~/.ssh/id_rsa.pub)"

# Or from source
helm install claude-code-server ./helm/claude-code-server \
  --set sshKeys.authorizedKeys="$(cat ~/.ssh/id_rsa.pub)"
```

Get the external IP:
```bash
kubectl get svc claude-code-server
```

Connect:
```bash
ssh -p 2222 claude@<EXTERNAL-IP>
```

See the [Helm chart README](./helm/claude-code-server/README.md) for advanced configuration options.

### Manual Deployment with kubectl

If you prefer to deploy manually without Helm:

#### Prerequisites

1. Create a ConfigMap or Secret with your SSH public keys:

```bash
kubectl create configmap claude-ssh-keys \
  --from-file=authorized_keys=~/.ssh/id_rsa.pub
```

2. Create a PersistentVolumeClaim for the workspace:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: claude-workspace
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

### Deployment Manifest

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: claude-code-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: claude-code-server
  template:
    metadata:
      labels:
        app: claude-code-server
    spec:
      containers:
      - name: claude-code
        image: ghcr.io/vangourd/sockmux:latest
        ports:
        - containerPort: 2222
          name: ssh
        volumeMounts:
        - name: workspace
          mountPath: /home/claude
        - name: ssh-keys
          mountPath: /ssh-keys
          readOnly: true
        - name: ssh-host-keys
          mountPath: /etc/ssh
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "2000m"
      volumes:
      - name: workspace
        persistentVolumeClaim:
          claimName: claude-workspace
      - name: ssh-keys
        configMap:
          name: claude-ssh-keys
      - name: ssh-host-keys
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: claude-code-server
spec:
  selector:
    app: claude-code-server
  ports:
  - port: 2222
    targetPort: 2222
    name: ssh
  type: LoadBalancer  # or ClusterIP with Ingress
```

Apply:
```bash
kubectl apply -f k8s-deployment.yaml
```

### Accessing from Multiple Devices

Get the external IP:
```bash
kubectl get svc claude-code-server
```

Connect from any device:
```bash
ssh -p 2222 claude@<EXTERNAL-IP>
```

## Usage

### First Connection

1. SSH into the container - Claude Code will start automatically
2. Authenticate with your Anthropic API key when prompted
3. Claude Code is now running in a shared tmux session

### Subsequent Connections

- All SSH sessions attach to the same tmux session
- You'll see the same Claude Code instance across all devices
- Changes made on one device are immediately visible on others

### Tmux Commands

- **Detach without stopping**: `Ctrl+B` then `D`
- **Split horizontally**: `Ctrl+B` then `"`
- **Split vertically**: `Ctrl+B` then `%`
- **Switch panes**: `Ctrl+B` then arrow keys
- **List sessions**: `tmux ls` (from shell)

### Managing the Session

If Claude Code exits or needs to be restarted:

```bash
# SSH in
ssh -p 2222 claude@<ip>

# The session will auto-reconnect or create a new one
# To manually start Claude Code in tmux:
tmux attach-session -t claude-code
# or if session doesn't exist:
tmux new-session -s claude-code claude
```

## Home Directory Persistence

The `/home/claude` directory is mounted from a Kubernetes PersistentVolume:
- Clone your repositories here
- All files persist across container restarts
- Shared across all SSH sessions
- Contains your shell config, nix profile, and SSH settings

## Security

**Default security features (enabled out of the box):**
- ✅ **NetworkPolicy**: Isolates to namespace, blocks lateral movement
- ✅ **Squid proxy**: Domain allowlisting for egress traffic (Anthropic, GitHub, NixOS)
- ✅ **Container hardening**: Non-root, no capabilities, seccomp filtering
- ✅ **SSH key auth only**: No password authentication
- ✅ **No service account access**: Cannot access Kubernetes API
- ⚠️ **Dangerous mode**: Claude Code bypasses permission prompts (container isolated)

**Optional enhancements:**
- 🔒 **Ingress restrictions**: Limit SSH access to specific IPs/namespaces
- 🔒 **Custom domain allowlist**: Add/remove allowed domains

### Quick Security Setup

**Default (Good - Secure by Default):**
```bash
helm install claude-code-server oci://ghcr.io/vangourd/charts/claude-code-server \
  --set sshKeys.authorizedKeys="$(cat ~/.ssh/id_rsa.pub)"
```
Includes: NetworkPolicy, Squid proxy, container hardening

**Hardened (Best):**
```bash
# Create dedicated namespace
kubectl create namespace claude-code

# Install in isolated namespace
helm install claude-code-server oci://ghcr.io/vangourd/charts/claude-code-server \
  --namespace claude-code \
  --set sshKeys.authorizedKeys="$(cat ~/.ssh/id_rsa.pub)"
```
Adds: Namespace isolation

📖 **See [SECURITY.md](./SECURITY.md) for complete security documentation**

## Troubleshooting

### Can't connect via SSH

```bash
# Check if container is running
kubectl get pods -l app=claude-code-server

# Check SSH service
kubectl logs -l app=claude-code-server

# Test SSH from within cluster
kubectl run -it --rm debug --image=alpine --restart=Never -- \
  sh -c "apk add openssh-client && ssh -p 2222 claude@claude-code-server"
```

### Session not shared

- Verify all connections use the same pod (single replica)
- Check tmux session: `tmux ls`
- Reattach: `tmux attach-session -t claude-code`

### Home directory permissions

```bash
# Fix ownership if needed
kubectl exec -it <pod-name> -- chown -R claude:claude /home/claude
```

## Observability

### OpenTelemetry Support

Claude Code supports OpenTelemetry for distributed tracing and metrics. Configure an OTLP endpoint:

```bash
helm install claude-code-server oci://ghcr.io/vangourd/charts/claude-code-server \
  --set sshKeys.authorizedKeys="$(cat ~/.ssh/id_rsa.pub)" \
  --set opentelemetry.enabled=true \
  --set opentelemetry.endpoint="http://otel-collector:4318"
```

Supports popular backends:
- **Honeycomb**: Full distributed tracing
- **Grafana Cloud**: Metrics and traces
- **Jaeger**: Self-hosted tracing
- **Prometheus**: Metrics collection
- Any OTLP-compatible backend

**Note**: When using Squid proxy, add your OTLP endpoint domain to the allowlist:
```yaml
squidProxy:
  allowedDomains:
    - api.honeycomb.io  # for Honeycomb
    - .grafana.net      # for Grafana Cloud
```

## CI/CD and Security

### GitHub Actions Workflow

This repository includes a comprehensive CI/CD pipeline that:

1. **Builds the container** using Nix for reproducible builds
2. **Runs Trivy security scans** to detect vulnerabilities
3. **Pushes to GitHub Container Registry** (ghcr.io)
4. **Packages and publishes Helm charts**

The workflow runs on:
- Push to `main` branch (tags as `latest`)
- Git tags (e.g., `v1.0.0`)
- Pull requests (build and scan only, no push)

### Security Scanning

Every build is scanned with [Trivy](https://github.com/aquasecurity/trivy) for:
- **Vulnerabilities** in OS packages and dependencies
- **Security misconfigurations**
- **Exposed secrets**

Scan results are:
- Uploaded to GitHub Security tab
- Printed in workflow logs
- Used to gate releases if critical vulnerabilities are found

### Using the Public Image

Pull the pre-built image from ghcr.io:

```bash
docker pull ghcr.io/vangourd/sockmux:latest
# or specific version
docker pull ghcr.io/vangourd/sockmux:v1.0.0
```

### Building Locally

For development or custom builds:

```bash
# Build with Nix
nix build .#container

# Load into podman/docker
podman load < result
```

## Development

Enter the development shell:
```bash
nix develop
```

This provides `podman` and `kubectl` for local development and testing.

## Architecture

```
┌─────────────────────────────────────────┐
│         Kubernetes Cluster              │
│  ┌───────────────────────────────────┐ │
│  │     claude-code-server Pod        │ │
│  │  ┌─────────────────────────────┐  │ │
│  │  │   SSH Server (port 2222)    │  │ │
│  │  │                              │  │ │
│  │  │   ┌─────────────────────┐   │  │ │
│  │  │   │   tmux session      │   │  │ │
│  │  │   │  (claude-code)      │   │  │ │
│  │  │   │                     │   │  │ │
│  │  │   │   Claude Code CLI   │   │  │ │
│  │  │   │   /home/claude      │   │  │ │
│  │  │   └─────────────────────┘   │  │ │
│  │  └─────────────────────────────┘  │ │
│  └───────────────────────────────────┘ │
│         ↓                    ↓          │
│  ┌────────────┐      ┌──────────────┐  │
│  │ ConfigMap  │      │ PVC          │  │
│  │ (SSH keys) │      │ (workspace)  │  │
│  └────────────┘      └──────────────┘  │
└─────────────────────────────────────────┘
        ↑               ↑
    Device 1        Device 2
   (SSH client)   (SSH client)
```

## License

MIT
