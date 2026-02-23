# Welcome to sockmux - Claude Code Container

This is a containerized Claude Code environment with persistent storage and Nix package management.

## Quick Start

You're connected via SSH to a shared tmux session. All devices connecting here see the same Claude Code instance.

### Tmux Commands

- **Detach without stopping**: `Ctrl+B` then `D`
- **Split horizontally**: `Ctrl+B` then `"`
- **Split vertically**: `Ctrl+B` then `%`
- **Switch panes**: `Ctrl+B` then arrow keys
- **Create new window**: `Ctrl+B` then `C`
- **Switch windows**: `Ctrl+B` then `0-9`

## Installing Software with Nix

This container uses Nix for package management. You can install any software without root access.

### Method 1: Quick Install with nix-shell (Temporary)

For one-off commands or testing:

```bash
# Try a package without installing
nix-shell -p python3 nodejs

# You'll get a shell with python3 and nodejs available
# Exit the shell and they're gone
```

### Method 2: home-manager (Persistent)

For permanent installations, use home-manager:

```bash
# Edit your home-manager config
nano ~/.config/home-manager/home.nix
```

Add packages to the `home.packages` list:

```nix
{ config, pkgs, ... }:

{
  home.username = "claude";
  home.homeDirectory = "/home/claude";
  home.stateVersion = "24.05";

  home.packages = with pkgs; [
    # Add your packages here
    python3
    nodejs
    ripgrep
    fd
    docker-compose
    kubectl
    terraform
    # ... any package from nixpkgs
  ];

  programs.home-manager.enable = true;
}
```

Then apply the changes:

```bash
home-manager switch
```

### Method 3: Nix Flakes (Project-specific)

For project-specific dependencies, create a `flake.nix` in your project:

```nix
{
  description = "My project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          python311
          nodejs_20
          postgresql
        ];

        shellHook = ''
          echo "Development environment loaded!"
        '';
      };
    };
}
```

Then use it:

```bash
nix develop
```

### Finding Packages

Search for packages:

```bash
# Search nixpkgs
nix search nixpkgs python

# Or use the web interface
# https://search.nixos.org/packages
```

## Security Considerations

### Container Isolation

**IMPORTANT**: This container runs Claude Code with `--dangerously-skip-permissions` flag.

**What this means**:
- Claude bypasses all permission prompts
- Claude can read, write, and execute ANY file in `/home/claude`
- Claude can run ANY command as the `claude` user
- Claude can install packages and modify your environment

**Why it's (relatively) safe**:
- Container is isolated from your host system
- Claude user has NO root/sudo access
- Cannot access files outside the container
- Cannot modify the host system
- Network access can be restricted via Kubernetes NetworkPolicies

**Risks to be aware of**:
1. **Data loss**: Claude can delete files in `/home/claude` (use git!)
2. **Network access**: Claude can make outbound connections
3. **Shared session**: All SSH connections share the same Claude instance
4. **API costs**: Claude operations consume your Anthropic API credits

### Best Practices

1. **Use version control**: Always commit important work
   ```bash
   jj init  # or git init
   jj describe -m "checkpoint"
   ```

2. **Don't store secrets**: Use Kubernetes secrets for API keys
   - Never commit credentials to git
   - Use environment variables for secrets
   - Add sensitive files to `.gitignore`

3. **Review before running**: Check Claude's suggestions before executing
   - Large file operations
   - Network requests
   - Package installations
   - Database modifications

4. **Backup regularly**: The `/home/claude` volume persists, but backup important projects externally

5. **Monitor costs**: Claude Code operations use your Anthropic API credits

## Persistence

### What Persists

The `/home/claude` directory is mounted from a Kubernetes PersistentVolume:
- All your files and projects
- Shell configuration (`.bashrc`, `.zshrc`, etc.)
- Nix profile and installed packages
- Git repositories and history
- SSH keys and config

### What Doesn't Persist

- Running processes (killed on container restart)
- Temporary files in `/tmp`
- Anything outside `/home/claude`

## Nix Environment

### Pre-installed Tools

The container comes with:
- `claude` - Claude Code CLI
- `jj` - Jujutsu version control (preferred over git)
- `nu` - Nushell (default shell)
- `yq` - YAML/JSON processor
- `git`, `curl`, `wget`, `grep`, `sed`, `find`

### Setting up home-manager (First Time)

If home-manager isn't set up yet:

```bash
# Create config directory
mkdir -p ~/.config/home-manager

# Create initial config
cat > ~/.config/home-manager/home.nix <<'EOF'
{ config, pkgs, ... }:

{
  home.username = "claude";
  home.homeDirectory = "/home/claude";
  home.stateVersion = "24.05";

  home.packages = with pkgs; [
    # Add your favorite packages here
    htop
    tmux
    neovim
  ];

  programs.home-manager.enable = true;
}
EOF

# Install home-manager
nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
nix-channel --update
nix-shell '<home-manager>' -A install

# Apply the configuration
home-manager switch
```

### Updating Packages

```bash
# Update channel
nix-channel --update

# Rebuild home-manager
home-manager switch

# Or upgrade everything
home-manager switch --upgrade
```

## Troubleshooting

### "Permission denied" errors

The `claude` user cannot use `sudo`. Use Nix to install software instead.

### Nix commands not found

Make sure your profile is loaded:
```bash
source ~/.nix-profile/etc/profile.d/nix.sh
```

### home-manager not found

Install it first (see "Setting up home-manager" above).

### Disk space issues

Clean up old Nix generations:
```bash
nix-collect-garbage -d
home-manager expire-generations "-7 days"
```

### tmux session issues

```bash
# List sessions
tmux ls

# Attach to claude-code session
tmux attach-session -t claude-code

# Kill a frozen session
tmux kill-session -t claude-code
```

## Resources

- **Nix Package Search**: https://search.nixos.org/packages
- **Home Manager Options**: https://nix-community.github.io/home-manager/options.html
- **Nix Pills** (tutorial): https://nixos.org/guides/nix-pills/
- **Claude Code Docs**: https://github.com/anthropics/claude-code
- **Jujutsu Tutorial**: https://github.com/martinvonz/jj/blob/main/docs/tutorial.md

## Getting Help

- Check Claude Code docs: `claude --help`
- Search Nix packages: `nix search nixpkgs <query>`
- Ask Claude! Claude can help you with Nix, tmux, and general development questions.

---

**Remember**: This is YOUR development environment. Customize it, break it, rebuild it. That's what containers are for!
