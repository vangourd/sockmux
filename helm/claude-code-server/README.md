# Claude Code Server Helm Chart

A Helm chart for deploying Claude Code server with SSH access and shared tmux sessions on Kubernetes.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PersistentVolume provisioner support (if persistence is enabled)

## Installing the Chart

### From OCI Registry (Recommended)

```bash
# Install from GitHub Container Registry
helm install claude-code-server oci://ghcr.io/vangourd/charts/claude-code-server \
  --set sshKeys.authorizedKeys="$(cat ~/.ssh/id_rsa.pub)"
```

### From Source

```bash
# Clone the repository
git clone https://github.com/vangourd/sockmux.git
cd sockmux

# Install the chart
helm install claude-code-server ./helm/claude-code-server \
  --set sshKeys.authorizedKeys="$(cat ~/.ssh/id_rsa.pub)"
```

## Security Features

This chart deploys with security hardening enabled by default:

- ✅ **NetworkPolicy**: Isolates to namespace, blocks cross-namespace traffic
- ✅ **Restricted Security Context**: Non-root, no capabilities, seccomp filtering
- ✅ **No Service Account**: `automountServiceAccountToken: false`
- ✅ **SSH Key Auth Only**: No password authentication
- 🔒 **Optional Squid Proxy**: Domain-based egress filtering

See [SECURITY.md](../../../SECURITY.md) for complete security documentation.

## Configuration

The following table lists the configurable parameters and their default values.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas (keep at 1 for shared session) | `1` |
| `image.repository` | Container image repository | `ghcr.io/vangourd/sockmux` |
| `image.tag` | Container image tag | `latest` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `service.type` | Kubernetes service type | `LoadBalancer` |
| `service.port` | SSH service port | `2222` |
| `persistence.enabled` | Enable persistent storage | `true` |
| `persistence.size` | Size of persistent volume | `10Gi` |
| `persistence.storageClass` | Storage class name | `""` |
| `sshKeys.authorizedKeys` | SSH public keys for authentication | `""` |
| `sshKeys.existingSecret` | Use existing secret for SSH keys | `""` |
| `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | Enable agent teams | `"1"` |
| `resources.requests.memory` | Memory request | `512Mi` |
| `resources.requests.cpu` | CPU request | `500m` |
| `resources.limits.memory` | Memory limit | `2Gi` |
| `resources.limits.cpu` | CPU limit | `2000m` |
| `squidProxy.enabled` | Enable Squid proxy for domain filtering | `false` |
| `squidProxy.allowedDomains` | List of allowed domains (with wildcards) | See values.yaml |
| `squidProxy.denyDirectIP` | Deny direct IP access (force domain names) | `true` |
| `networkPolicy.enabled` | Enable Kubernetes NetworkPolicy | `true` |
| `opentelemetry.enabled` | Enable OpenTelemetry tracing/metrics | `false` |
| `opentelemetry.endpoint` | OTLP endpoint URL | `""` |
| `opentelemetry.protocol` | OTLP protocol (http/protobuf or grpc) | `"http/protobuf"` |
| `opentelemetry.serviceName` | Service name for traces | `"claude-code-server"` |
| `opentelemetry.headers` | OTLP headers for authentication | `{}` |

### Example: Install with Custom Values

Create a `values.yaml` file:

```yaml
sshKeys:
  authorizedKeys: |
    ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB... user@host

persistence:
  size: 20Gi
  storageClass: fast-ssd

resources:
  requests:
    memory: 1Gi
    cpu: 1000m
  limits:
    memory: 4Gi
    cpu: 4000m

service:
  type: ClusterIP
```

Install the chart:

```bash
helm install claude-code-server ./helm/claude-code-server -f values.yaml
```

### Example: Using Existing Secret for SSH Keys

Create a secret:

```bash
kubectl create secret generic claude-ssh-keys \
  --from-file=authorized_keys=~/.ssh/id_rsa.pub
```

Install with existing secret:

```bash
helm install claude-code-server ./helm/claude-code-server \
  --set sshKeys.existingSecret=claude-ssh-keys
```

### Example: Adding Anthropic API Key

Create a secret:

```bash
kubectl create secret generic claude-api-key \
  --from-literal=api-key=your-api-key-here
```

Install with API key:

```bash
helm install claude-code-server ./helm/claude-code-server \
  --set existingApiKeySecret.name=claude-api-key \
  --set sshKeys.authorizedKeys="$(cat ~/.ssh/id_rsa.pub)"
```

### Example: OpenTelemetry Integration

Claude Code supports OpenTelemetry for traces and metrics. Configure an OTLP endpoint:

```bash
helm install claude-code-server ./helm/claude-code-server \
  --set sshKeys.authorizedKeys="$(cat ~/.ssh/id_rsa.pub)" \
  --set opentelemetry.enabled=true \
  --set opentelemetry.endpoint="http://otel-collector:4318"
```

**With Honeycomb:**
```yaml
opentelemetry:
  enabled: true
  endpoint: "https://api.honeycomb.io:443"
  headers:
    x-honeycomb-team: "your-api-key"
  resourceAttributes:
    environment: "production"
    service.namespace: "claude-code"
```

**With Grafana Cloud:**
```yaml
opentelemetry:
  enabled: true
  endpoint: "https://otlp-gateway-prod-us-central-0.grafana.net/otlp"
  headers:
    authorization: "Basic <base64-encoded-instanceid:apikey>"
```

**Secure headers with secret:**
```bash
# Create secret with OTLP headers
kubectl create secret generic otel-headers \
  --from-literal=headers="x-honeycomb-team=your-api-key"

# Install with secret reference
helm install claude-code-server ./helm/claude-code-server \
  --set sshKeys.authorizedKeys="$(cat ~/.ssh/id_rsa.pub)" \
  --set opentelemetry.enabled=true \
  --set opentelemetry.endpoint="https://api.honeycomb.io:443" \
  --set opentelemetry.existingSecret.name=otel-headers
```

### Squid Proxy for Domain Filtering

**Squid proxy is enabled by default** to control which domains Claude Code can access.

The default configuration allows:
- Anthropic API (api.anthropic.com)
- GitHub (for git operations)
- NixOS cache (for package downloads)

To add custom domains, create a `values.yaml`:

```yaml
squidProxy:
  enabled: true
  allowedDomains:
    - .anthropic.com
    - .github.com
    - .nixos.org
    # Add your allowed domains
    - .yourdomain.com
    - api.example.com
```

**Benefits:**
- Layer 7 filtering by domain name
- Block access to unauthorized services
- Logs all outbound requests
- Prevents data exfiltration

**To disable Squid proxy** (not recommended):
```bash
helm install claude-code-server oci://ghcr.io/vangourd/charts/claude-code-server \
  --set squidProxy.enabled=false \
  --set sshKeys.authorizedKeys="$(cat ~/.ssh/id_rsa.pub)"
```

## Accessing the Server

After installation, get the external IP:

```bash
kubectl get svc claude-code-server
```

Connect via SSH:

```bash
ssh -p 2222 claude@<EXTERNAL-IP>
```

## Uninstalling the Chart

```bash
helm uninstall claude-code-server
```

This will remove all resources created by the chart, except for PersistentVolumeClaims (to prevent data loss). To remove PVCs:

```bash
kubectl delete pvc -l app.kubernetes.io/instance=claude-code-server
```

## Security Considerations

- **Dangerous mode**: Claude Code runs with `--dangerously-skip-permissions` (safe in containerized environment)
- **Agent teams**: Experimental feature enabled by default
- **Network policies**: Consider enabling `networkPolicy.enabled` to restrict egress traffic
- **SSH keys only**: Password authentication is disabled
- **Non-root user**: Runs as UID 1000

## Troubleshooting

### Can't connect via SSH

```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=claude-code-server

# Check logs
kubectl logs -l app.kubernetes.io/name=claude-code-server

# Test connection from within cluster
kubectl run -it --rm debug --image=alpine --restart=Never -- \
  sh -c "apk add openssh-client && ssh -p 2222 claude@claude-code-server"
```

### Permission issues

```bash
# Fix home directory ownership
kubectl exec -it <pod-name> -- chown -R claude:claude /home/claude
```

## License

MIT
