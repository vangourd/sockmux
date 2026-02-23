# Contributing to Claude Code Container Server

Thank you for your interest in contributing! This document provides guidelines and instructions for contributing.

## Development Setup

### Prerequisites

- Nix with flakes enabled
- Podman or Docker
- kubectl and helm (for Kubernetes testing)
- Git

### Local Development

1. Clone the repository:
```bash
git clone https://github.com/vangourd/sockmux.git
cd sockmux
```

2. Enter the Nix development shell:
```bash
nix develop
```

3. Build the container:
```bash
nix build .#container
```

4. Test locally:
```bash
./setup.sh
```

## Making Changes

### Modifying the Container

The container is defined in `flake.nix`. Key sections:

- **entrypoint**: Container startup script
- **tmux-attach**: SSH login script that launches Claude Code
- **sshd-config**: SSH server configuration
- **contents**: Packages included in the container

After modifying `flake.nix`:

1. Rebuild: `nix build .#container`
2. Test locally with podman
3. Verify SSH access and Claude Code startup

### Modifying the Helm Chart

Helm chart files are in `helm/claude-code-server/`:

- `Chart.yaml`: Chart metadata
- `values.yaml`: Default configuration
- `templates/`: Kubernetes manifests

After modifications:

1. Lint the chart:
```bash
helm lint helm/claude-code-server
```

2. Test template rendering:
```bash
helm template test helm/claude-code-server --debug
```

3. Install in a test cluster:
```bash
helm install test helm/claude-code-server --dry-run --debug
```

### Testing Changes

#### Local Container Testing

```bash
# Build
nix build .#container

# Load and run
podman load < result
podman run -d --name test-claude \
  -p 2222:2222 \
  -v ./claude-home:/home/claude \
  -v ./ssh-keys:/ssh-keys:ro \
  localhost/claude-code-server:latest

# Test SSH connection
ssh -p 2222 claude@localhost

# Check logs
podman logs test-claude

# Cleanup
podman stop test-claude && podman rm test-claude
```

#### Kubernetes Testing

```bash
# Create test namespace
kubectl create namespace claude-test

# Install with Helm
helm install test helm/claude-code-server \
  --namespace claude-test \
  --set sshKeys.authorizedKeys="$(cat ~/.ssh/id_rsa.pub)"

# Test connection
kubectl get svc -n claude-test
ssh -p 2222 claude@<EXTERNAL-IP>

# Cleanup
helm uninstall test -n claude-test
kubectl delete namespace claude-test
```

## Submitting Changes

### Pull Request Process

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make your changes
4. Test thoroughly (see Testing section)
5. Commit with clear messages
6. Push to your fork
7. Open a Pull Request

### Commit Messages

Use conventional commits format:

```
feat: add support for custom SSH port
fix: resolve host key persistence issue
docs: update Helm chart README
chore: update Nix dependencies
```

### PR Requirements

- [ ] Code builds successfully
- [ ] Tests pass (if applicable)
- [ ] Documentation updated
- [ ] Helm chart version bumped (if chart changed)
- [ ] Security scan passes (Trivy)

## Security

### Reporting Vulnerabilities

Please report security vulnerabilities privately to [security contact]. Do not open public issues for security problems.

### Security Best Practices

When contributing:

- Never commit secrets or API keys
- Keep dependencies up to date
- Follow principle of least privilege
- Use security scanning tools (Trivy)
- Review container security settings

## Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help others learn and grow
- Follow project conventions

## Questions?

- Open a GitHub Discussion for general questions
- Open an Issue for bugs or feature requests
- Check existing issues before creating new ones

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
