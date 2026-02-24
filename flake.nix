{
  description = "Claude Code container with SSH and tmux for multi-device access";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, home-manager }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        # Default home-manager configuration
        home-manager-config = pkgs.writeText "home.nix" ''
          { config, pkgs, ... }:

          {
            home.username = "claude";
            home.homeDirectory = "/home/claude";
            home.stateVersion = "24.05";

            # Default packages for Claude Code development
            home.packages = with pkgs; [
              htop
              ripgrep
              fd
              bat
              eza
              neovim
            ];

            programs.home-manager.enable = true;

            # Git configuration
            programs.git = {
              enable = true;
              userName = "Claude Code";
              userEmail = "claude@sockmux.container";
            };
          }
        '';

        # Entrypoint script that sets up SSH and tmux (runs as user claude)
        entrypoint = pkgs.writeShellScript "entrypoint" ''
          set -e

          PATH=/bin:/usr/bin:$PATH

          # Setup persistent SSH host keys in /home/claude/.ssh-host-keys
          # This ensures the same host keys are used across container restarts
          mkdir -p /home/claude/.ssh-host-keys

          # Generate SSH host keys if they don't exist in persistent storage
          if [ ! -f /home/claude/.ssh-host-keys/ssh_host_rsa_key ]; then
            echo "Generating persistent SSH host keys..."
            ssh-keygen -t rsa -b 4096 -f /home/claude/.ssh-host-keys/ssh_host_rsa_key -N "" -q
            ssh-keygen -t ed25519 -f /home/claude/.ssh-host-keys/ssh_host_ed25519_key -N "" -q
            ssh-keygen -t ecdsa -f /home/claude/.ssh-host-keys/ssh_host_ecdsa_key -N "" -q
          fi

          # Link persistent host keys to /etc/ssh (pre-created writable dir)
          ln -sf /home/claude/.ssh-host-keys/ssh_host_rsa_key /etc/ssh/ssh_host_rsa_key
          ln -sf /home/claude/.ssh-host-keys/ssh_host_rsa_key.pub /etc/ssh/ssh_host_rsa_key.pub
          ln -sf /home/claude/.ssh-host-keys/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key
          ln -sf /home/claude/.ssh-host-keys/ssh_host_ed25519_key.pub /etc/ssh/ssh_host_ed25519_key.pub
          ln -sf /home/claude/.ssh-host-keys/ssh_host_ecdsa_key /etc/ssh/ssh_host_ecdsa_key
          ln -sf /home/claude/.ssh-host-keys/ssh_host_ecdsa_key.pub /etc/ssh/ssh_host_ecdsa_key.pub

          # Copy authorized_keys if provided via mount
          if [ -f /ssh-keys/authorized_keys ]; then
            mkdir -p /home/claude/.ssh
            cp /ssh-keys/authorized_keys /home/claude/.ssh/
            chmod 600 /home/claude/.ssh/authorized_keys
          fi

          # Copy CLAUDE.md guide if it doesn't exist
          if [ ! -f /home/claude/CLAUDE.md ]; then
            cp /etc/CLAUDE.md /home/claude/CLAUDE.md
          fi

          # Setup default home-manager config if it doesn't exist
          if [ ! -d /home/claude/.config/home-manager ]; then
            mkdir -p /home/claude/.config/home-manager
            cp ${home-manager-config} /home/claude/.config/home-manager/home.nix
          fi

          echo "Starting SSH server..."
          exec /bin/sshd -D -e -f /etc/sshd_config
        '';

        # SSH daemon configuration
        sshd-config = pkgs.writeText "sshd_config" ''
          Port 2222
          PermitRootLogin no
          PubkeyAuthentication yes
          PasswordAuthentication no
          ChallengeResponseAuthentication no
          UsePAM no
          UsePrivilegeSeparation no
          StrictModes no
          HostKey /etc/ssh/ssh_host_rsa_key
          HostKey /etc/ssh/ssh_host_ed25519_key
          HostKey /etc/ssh/ssh_host_ecdsa_key

          # Force command to attach to tmux session
          Match User claude
            ForceCommand ${tmux-attach}
        '';

        # Script that gets executed on SSH login - attaches to or creates tmux session
        tmux-attach = pkgs.writeShellScript "tmux-attach" ''
          set -e

          # Set environment
          export HOME=/home/claude
          export USER=claude
          export SHELL=/bin/nu
          export PATH=/home/claude/.nix-profile/bin:/bin:/usr/bin:$PATH
          export SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
          export NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
          export CURL_CA_BUNDLE=/etc/ssl/certs/ca-bundle.crt
          export LOCALE_ARCHIVE=/usr/lib/locale/locale-archive
          export LANG=en_US.UTF-8
          export LC_ALL=en_US.UTF-8
          export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

          # Source nix profile if it exists
          [ -f /home/claude/.nix-profile/etc/profile.d/hm-session-vars.sh ] && \
            source /home/claude/.nix-profile/etc/profile.d/hm-session-vars.sh

          cd /home/claude

          # Initialize home-manager on first login if not already done
          if [ ! -f /home/claude/.config/home-manager/.initialized ]; then
            echo "First time setup: Initializing home-manager..."
            echo "This may take a few minutes..."
            nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager 2>/dev/null || true
            nix-channel --update 2>/dev/null || true
            export NIX_PATH="$HOME/.nix-defexpr/channels:$NIX_PATH"
            nix-shell '<home-manager>' -A install --run "echo 'home-manager installed'" 2>/dev/null || true
            home-manager switch 2>/dev/null || echo "Note: Run 'home-manager switch' to activate your configuration"
            touch /home/claude/.config/home-manager/.initialized
            echo ""
            echo "Setup complete! Read CLAUDE.md for usage instructions."
            echo ""
          fi

          # Session name for shared instance
          SESSION_NAME="sockmux"

          # Check if tmux session exists
          if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
            echo "Attaching to existing sockmux session..."
            echo "Press Ctrl+B then D to detach without closing the session"
            sleep 1
            exec tmux attach-session -t "$SESSION_NAME"
          else
            echo "Creating new shared tmux session..."
            echo "All SSH connections will share this session"
            echo ""
            echo "Starting nushell..."
            echo "Run 'claude' to start Claude Code"
            echo "Press Ctrl+C in Claude to return to shell"
            echo "Press Ctrl+B then D to detach tmux"
            echo ""
            sleep 2
            exec tmux new-session -s "$SESSION_NAME" /bin/nu
          fi
        '';

        # Container image
        container = pkgs.dockerTools.streamLayeredImage {
          name = "claude-code-server";
          tag = "latest";

          contents = [
            pkgs.bash
            pkgs.coreutils
            pkgs.openssh
            pkgs.tmux
            pkgs.git
            pkgs.shadow  # for useradd/groupadd
            pkgs.glibc   # for locale support
            pkgs.glibcLocales  # locale data
            pkgs.cacert  # SSL certificates

            # Nix for home-manager
            pkgs.nix

            # Default development tools
            pkgs.claude-code
            pkgs.jujutsu  # jj version control
            pkgs.yq-go    # yq YAML processor
            pkgs.nushell  # nu shell

            # Common utilities
            pkgs.curl
            pkgs.wget
            pkgs.gnugrep
            pkgs.gnused
            pkgs.findutils
            pkgs.which
          ];

          extraCommands = ''
            # Create necessary directories
            mkdir -p etc/ssh tmp home/claude
            mkdir -p var/empty run/sshd bin usr/bin sbin
            mkdir -p nix/var/nix/profiles/per-user/claude nix/var/nix/gcroots/per-user
            chmod 1777 tmp
            chmod 755 etc/ssh var/empty run/sshd
            chmod 755 nix/var/nix/profiles/per-user/claude

            # Create basic system files
            echo "root:x:0:0:System Administrator:/root:/bin/bash" > etc/passwd
            echo "sshd:x:74:74:SSH Daemon:/var/empty:/bin/false" >> etc/passwd
            echo "claude:x:1000:1000:Claude User:/home/claude:/bin/bash" >> etc/passwd
            echo "root:x:0:" > etc/group
            echo "sshd:x:74:" >> etc/group
            echo "claude:x:1000:" >> etc/group

            # Setup locale
            mkdir -p usr/lib/locale
            ln -sf ${pkgs.glibcLocales}/lib/locale/locale-archive usr/lib/locale/locale-archive

            # Setup SSL certificates
            mkdir -p etc/ssl/certs
            ln -sf ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt etc/ssl/certs/ca-bundle.crt

            # Create symlinks for common binaries
            for pkg in ${pkgs.lib.concatStringsSep " " [
              "${pkgs.openssh}"
              "${pkgs.shadow}"
              "${pkgs.coreutils}"
              "${pkgs.bash}"
              "${pkgs.tmux}"
              "${pkgs.git}"
              "${pkgs.nix}"
              "${pkgs.claude-code}"
              "${pkgs.jujutsu}"
              "${pkgs.yq-go}"
              "${pkgs.nushell}"
              "${pkgs.gnugrep}"
              "${pkgs.gnused}"
              "${pkgs.findutils}"
              "${pkgs.wget}"
              "${pkgs.curl}"
              "${pkgs.which}"
            ]}; do
              if [ -d "$pkg/bin" ]; then
                for binary in "$pkg/bin"/*; do
                  [ -f "$binary" ] && ln -sf "$binary" "bin/$(basename "$binary")" || true
                done
              fi
              if [ -d "$pkg/sbin" ]; then
                for binary in "$pkg/sbin"/*; do
                  [ -f "$binary" ] && ln -sf "$binary" "bin/$(basename "$binary")" || true
                done
              fi
            done

            # Create sshd_config
            cp ${sshd-config} etc/sshd_config

            # Copy CLAUDE.md guide
            cp ${./CLAUDE.md} etc/CLAUDE.md
          '';

          config = {
            Cmd = [ "${entrypoint}" ];
            ExposedPorts = {
              "2222/tcp" = {};
            };
            User = "1000:1000";
            WorkingDir = "/home/claude";
            Env = [
              "PATH=/bin:/usr/bin"
              "LANG=en_US.UTF-8"
              "LC_ALL=en_US.UTF-8"
              "NIX_PATH=nixpkgs=${pkgs.path}"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "LOCALE_ARCHIVE=/usr/lib/locale/locale-archive"
              "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
            ];
            Volumes = {
              "/home/claude" = {};
              "/ssh-keys" = {};
            };
          };
        };

      in {
        packages = {
          default = container;
          container = container;
        };

        # Development shell for testing
        devShells.default = pkgs.mkShell {
          buildInputs = [ pkgs.podman pkgs.kubectl ];

          shellHook = ''
            echo "Claude Code Container Development Environment"
            echo ""
            echo "Build container: nix build .#container"
            echo "Load into podman: podman load < result"
            echo "Run locally: podman run -p 2222:2222 -v ./workspace:/workspace -v ./ssh-keys:/ssh-keys claude-code-server:latest"
          '';
        };
      }
    );
}
