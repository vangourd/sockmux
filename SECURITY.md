# Security Model

This document describes the security architecture and best practices for deploying sockmux (Claude Code Container Server).

## Overview

sockmux is designed with defense-in-depth security principles:

1. **Container Security**: Restrictive security contexts
2. **Network Isolation**: Namespace-level segmentation
3. **Egress Filtering**: Domain allowlisting via Squid proxy
4. **Authentication**: SSH public key only
5. **Least Privilege**: No root access, minimal capabilities

## Threat Model

### What We Protect Against

- **Unauthorized Access**: SSH public key authentication only
- **Container Escape**: Non-root user, no capabilities, seccomp filtering
- **Lateral Movement**: NetworkPolicy isolates to namespace
- **Data Exfiltration**: Squid proxy restricts egress to approved domains
- **Supply Chain**: Reproducible Nix builds

### Known Risks

⚠️ **Claude Code runs with `--dangerously-skip-permissions`**
- Bypasses all permission prompts
- Can read/write/execute ANY file in `/home/claude`
- Can run ANY command as the `claude` user
- Cannot escalate to root or access host system

**Mitigation**: Container isolation + NetworkPolicy + Squid proxy

## Security Features

### 1. Container Security

**Security Context (enabled by default):**
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  capabilities:
    drop:
    - ALL
  allowPrivilegeEscalation: false
  privileged: false
  seccompProfile:
    type: RuntimeDefault
```

**What this prevents:**
- Running as root
- Gaining additional privileges
- Using dangerous syscalls (seccomp)
- Container escape via capabilities

**Pod-level hardening:**
- `automountServiceAccountToken: false` - No Kubernetes API access
- `fsGroup: 1000` - Files created with correct ownership

### 2. Network Isolation

**NetworkPolicy (enabled by default):**

**Ingress:**
- Allows SSH (port 2222) from anywhere*
- Blocks all other inbound traffic
- *Can be restricted to specific namespaces/IPs

**Egress:**
- **With Squid**: Only to Squid proxy → Squid filters domains
- **Without Squid**: Direct HTTPS allowed (less secure)
- Always allows DNS (kube-system namespace)
- Always allows same-namespace communication
- **Blocks all other namespaces**

### 3. Squid Proxy (Domain Allowlisting)

When enabled, provides Layer 7 filtering:

**Default allowlist:**
- `api.anthropic.com` - Claude API
- `*.github.com` - Git operations
- `*.nixos.org` - Package management

**Security benefits:**
- Blocks access by domain name (not just IP)
- Denies direct IP access (forces DNS)
- Logs all requests for audit
- Prevents data exfiltration to unauthorized sites

**Configuration:**
```yaml
squidProxy:
  enabled: true
  allowedDomains:
    - .anthropic.com
    - .github.com
    - .nixos.org
    - .yourdomain.com  # Add trusted domains
  denyDirectIP: true
```

### 4. No Service Account Access

```yaml
automountServiceAccountToken: false
```

Claude Code cannot:
- Access Kubernetes API
- List/modify other pods
- Read secrets from other namespaces

## Deployment Recommendations

### Minimal Setup (Good)

```bash
helm install claude-code-server ./helm/claude-code-server \
  --set sshKeys.authorizedKeys="$(cat ~/.ssh/id_rsa.pub)"
```

✅ NetworkPolicy enabled (namespace isolation)
✅ Container security hardening
❌ No egress filtering (direct internet access)

### Recommended Setup (Better)

```bash
helm install claude-code-server ./helm/claude-code-server \
  --set sshKeys.authorizedKeys="$(cat ~/.ssh/id_rsa.pub)" \
  --set squidProxy.enabled=true
```

✅ NetworkPolicy enabled
✅ Container security hardening
✅ Egress filtered to approved domains

### Hardened Setup (Best)

```yaml
# values.yaml
sshKeys:
  authorizedKeys: |
    ssh-ed25519 AAAAC3... user@host

squidProxy:
  enabled: true
  allowedDomains:
    - api.anthropic.com
    - github.com
    - cache.nixos.org
  denyDirectIP: true

networkPolicy:
  enabled: true
  ingress:
    allowedSources:
      # Only allow from specific namespace
      - namespaceSelector:
          matchLabels:
            name: trusted-namespace

# Use dedicated namespace
```

✅ NetworkPolicy with ingress restrictions
✅ Container security hardening
✅ Minimal domain allowlist
✅ Separate namespace

## Namespace Isolation

### Why It Matters

By default, Kubernetes allows pods to communicate across namespaces. NetworkPolicy blocks this:

```yaml
# Blocked:
❌ Pod in namespace-a → sockmux in namespace-b
❌ sockmux → API in kube-system (except DNS)
❌ sockmux → Database in production namespace

# Allowed:
✅ sockmux → Squid (same namespace)
✅ sockmux → DNS (kube-system)
✅ External → sockmux SSH (port 2222)
```

### Create Dedicated Namespace

```bash
# Create namespace with label
kubectl create namespace claude-code
kubectl label namespace claude-code name=claude-code

# Install in dedicated namespace
helm install claude-code-server ./helm/claude-code-server \
  --namespace claude-code \
  --set sshKeys.authorizedKeys="$(cat ~/.ssh/id_rsa.pub)" \
  --set squidProxy.enabled=true
```

## Monitoring & Auditing

### View Squid Logs (Egress Audit)

```bash
# See all outbound requests
kubectl logs -l app.kubernetes.io/component=squid-proxy -f
```

### View SSH Activity

```bash
# SSH connection logs
kubectl logs -l app.kubernetes.io/name=claude-code-server | grep SSH
```

### NetworkPolicy Verification

```bash
# Test blocked connection from another namespace
kubectl run test --rm -it --image=alpine -n other-namespace -- \
  wget -O- http://claude-code-server.claude-code:2222
# Should timeout (blocked by NetworkPolicy)
```

## Known Limitations

### 1. Claude Code Permission Bypass

**Risk**: Claude can execute arbitrary code without prompts

**Mitigation**:
- Container isolation (cannot escape)
- NetworkPolicy (cannot reach other namespaces)
- Squid proxy (cannot exfiltrate to unauthorized domains)

### 2. Persistent Volume Access

**Risk**: Claude can read/write all files in `/home/claude`

**Mitigation**:
- Use dedicated PersistentVolume
- Don't store secrets in the volume
- Use Kubernetes secrets for sensitive data
- Regular backups with version control

### 3. SSH Brute Force

**Risk**: SSH port exposed to internet

**Mitigation**:
- Public key authentication only (no passwords)
- Use strong SSH keys (ed25519, 4096-bit RSA)
- Consider IP allowlisting via NetworkPolicy
- Monitor connection logs

### 4. Resource Exhaustion

**Risk**: Claude could consume all CPU/memory

**Mitigation**:
```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "2000m"
```

## Compliance Considerations

### SOC 2 / ISO 27001

✅ Network segmentation (NetworkPolicy)
✅ Least privilege (no root, no capabilities)
✅ Audit logging (Squid logs, SSH logs)
✅ Authentication (SSH keys only)
⚠️ Consider adding external audit log aggregation

### PCI-DSS

⚠️ **Not recommended for PCI environments**

If you must:
- Deploy in separate namespace
- Enable all security features
- Restrict ingress to specific IPs
- Implement log forwarding
- Regular security audits

### HIPAA

⚠️ **Not recommended for PHI processing**

Claude Code has broad file access and network permissions. Do not use for processing protected health information.

## Incident Response

### Suspected Compromise

```bash
# 1. Isolate - scale to 0
kubectl scale deployment claude-code-server --replicas=0

# 2. Collect logs
kubectl logs deployment/claude-code-server > incident-$(date +%s).log
kubectl logs -l app.kubernetes.io/component=squid-proxy > squid-$(date +%s).log

# 3. Backup volume
kubectl get pvc  # Note the PVC name
# Use your backup solution to snapshot the volume

# 4. Analyze
# Review logs for suspicious activity
# Check Squid logs for unexpected domains
# Review SSH connection logs

# 5. Remediate
# Delete namespace
kubectl delete namespace claude-code
# Restore from known-good backup if needed
```

## Security Checklist

Before deploying to production:

- [ ] Deploy in dedicated namespace
- [ ] Enable NetworkPolicy (`networkPolicy.enabled=true`)
- [ ] Enable Squid proxy (`squidProxy.enabled=true`)
- [ ] Review and minimize domain allowlist
- [ ] Set resource limits
- [ ] Configure ingress restrictions (if needed)
- [ ] Setup log forwarding/monitoring
- [ ] Document authorized SSH keys
- [ ] Test NetworkPolicy isolation
- [ ] Review security context settings
- [ ] Plan incident response procedures
- [ ] Regular security updates (`image.tag` version pinning)

## Reporting Security Issues

If you discover a security vulnerability, please email: [your-security-contact]

**Do not** open public GitHub issues for security problems.

## References

- [Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Squid Configuration](http://www.squid-cache.org/Doc/config/)
- [Claude Code Documentation](https://github.com/anthropics/claude-code)
