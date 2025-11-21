# Minimal Rails App Flake
# Works for: EC2, Incus, bare metal, Docker
#
# Usage:
#   1. Copy to your Rails app root as flake.nix
#   2. Customize the pname, version, and description
#   3. Run: bundle lock && bundix -l
#   4. Run: nix build

{
  description = "Rails Application - Deployable everywhere";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-ruby.url = "github:bobvanderlinden/nixpkgs-ruby";
    nixpkgs-ruby.inputs.nixpkgs.follows = "nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixpkgs-ruby, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Ruby from .ruby-version
        ruby = nixpkgs-ruby.lib.packageFromRubyVersionFile {
          file = ./.ruby-version;
          inherit system;
        };

        # Check for required files
        hasGemfile = builtins.pathExists ./Gemfile;
        hasGemset = builtins.pathExists ./gemset.nix;
        hasProcfile = builtins.pathExists ./Procfile;

        # Gem environment (only if Gemfile exists)
        gemEnv = if hasGemfile then pkgs.bundlerEnv ({
          name = "rails-app-gems";
          inherit ruby;
          gemdir = ./.;

          # Use gemset.nix if available (required for git sources)
          # Generate with: bundix -l
        } // (if hasGemset then {
          gemset = ./gemset.nix;
        } else {})) else null;

        # The Rails application package
        railsApp = pkgs.stdenv.mkDerivation {
          pname = "rails-app";  # CUSTOMIZE: Your app name
          version = "1.0.0";    # CUSTOMIZE: Your version

          src = ./.;

          buildInputs = [ gemEnv ruby ];

          installPhase = ''
            mkdir -p $out

            # Copy application files
            cp -r . $out/

            # Create bin directory with wrapper scripts
            mkdir -p $out/bin

            # Rails wrapper
            cat > $out/bin/rails <<'EOF'
#!/bin/sh
export GEM_HOME="${gemEnv}/${ruby.gemPath}"
export GEM_PATH="${gemEnv}/${ruby.gemPath}"
cd $out
exec ${ruby}/bin/bundle exec rails "$@"
EOF
            chmod +x $out/bin/rails

            # Rake wrapper
            cat > $out/bin/rake <<'EOF'
#!/bin/sh
export GEM_HOME="${gemEnv}/${ruby.gemPath}"
export GEM_PATH="${gemEnv}/${ruby.gemPath}"
cd $out
exec ${ruby}/bin/bundle exec rake "$@"
EOF
            chmod +x $out/bin/rake

            # Bundle wrapper
            cat > $out/bin/bundle <<'EOF'
#!/bin/sh
export GEM_HOME="${gemEnv}/${ruby.gemPath}"
export GEM_PATH="${gemEnv}/${ruby.gemPath}"
cd $out
exec ${ruby}/bin/bundle "$@"
EOF
            chmod +x $out/bin/bundle
          '';

          meta = with pkgs.lib; {
            description = "Rails application";  # CUSTOMIZE
            platforms = platforms.linux;
          };
        };

      in {
        packages = {
          default = railsApp;

          # Docker image
          docker = pkgs.dockerTools.buildLayeredImage {
            name = "rails-app";  # CUSTOMIZE
            tag = "latest";

            contents = [
              railsApp
              pkgs.coreutils
              pkgs.bash
              pkgs.which
            ];

            config = {
              WorkingDir = "${railsApp}";

              Env = [
                "GEM_HOME=${gemEnv}/${ruby.gemPath}"
                "GEM_PATH=${gemEnv}/${ruby.gemPath}"
                "PATH=${railsApp}/bin:${ruby}/bin:${gemEnv}/bin:/usr/bin:/bin"
                "RAILS_ENV=production"
                "RAILS_LOG_TO_STDOUT=true"
              ];

              # Default to web role (customize if needed)
              Cmd = [ "${railsApp}/bin/rails" "server" "-b" "0.0.0.0" ];

              ExposedPorts = {
                "3000/tcp" = {};
              };
            };
          };
        };

        # Development shell
        devShells.default = pkgs.mkShell {
          buildInputs = [
            ruby
            pkgs.bundix
            pkgs.git
            pkgs.openssh
          ] ++ pkgs.lib.optionals hasGemfile [ gemEnv ];

          shellHook = ''
            # SSH check for private gems
            if [ -z "$SSH_AUTH_SOCK" ]; then
              echo "⚠️  No SSH agent - private gems may fail"
              echo "   Run: eval \$(ssh-agent) && ssh-add"
            fi

            # Isolated gem environment
            export GEM_HOME="$PWD/.nix-gems"
            mkdir -p "$GEM_HOME"

            ${if hasGemfile then ''
              export GEM_PATH="${gemEnv}/${ruby.gemPath}:$GEM_HOME"
              export PATH="$GEM_HOME/bin:${gemEnv}/bin:$PATH"
            '' else ''
              export GEM_PATH="$GEM_HOME"
              export PATH="$GEM_HOME/bin:$PATH"
            ''}

            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Rails Development Environment"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            ruby --version
            ${if hasGemset then ''
              echo "✓ gemset.nix found"
            '' else ''
              echo "⚠️  No gemset.nix - run 'bundix -l' for git sources"
            ''}
            echo ""
            echo "Commands:"
            echo "  rails server    - Start dev server"
            echo "  rails console   - Rails console"
            echo "  bundix -l       - Generate gemset.nix"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          '';
        };
      }
    ) // {
      # NixOS module for EC2, Incus, bare metal
      nixosModules.default = { config, lib, pkgs, ... }:
        with lib;
        let
          cfg = config.services.rails-app;  # CUSTOMIZE service name

          # Helper to parse Procfile
          parseProcfile = role:
            let
              procfilePath = "${cfg.package}/Procfile";
              procfileContent = builtins.readFile procfilePath;
              lines = splitString "\n" procfileContent;

              # Find line matching "role:"
              matchingLines = filter (line:
                let trimmed = trim line;
                in hasPrefix "${role}:" trimmed
              ) lines;
            in
              if length matchingLines > 0
              then
                let
                  line = head matchingLines;
                  # Extract command after "role: "
                  parts = splitString ":" line;
                  commandPart = concatStringsSep ":" (tail parts);
                in
                  trim commandPart
              else
                throw "Role '${role}' not found in Procfile at ${procfilePath}";
        in {
          options.services.rails-app = {  # CUSTOMIZE service name
            enable = mkEnableOption "Rails application";

            package = mkOption {
              type = types.package;
              default = self.packages.${pkgs.system}.default;
              description = "The Rails application package";
            };

            role = mkOption {
              type = types.str;
              default = "web";
              example = "web, worker, scheduler";
              description = "Procfile role to run";
            };

            workingDirectory = mkOption {
              type = types.path;
              default = cfg.package;
              description = "Working directory for the app";
            };

            user = mkOption {
              type = types.str;
              default = "rails";
              description = "User to run the app as";
            };

            group = mkOption {
              type = types.str;
              default = "rails";
              description = "Group to run the app as";
            };

            environment = mkOption {
              type = types.attrsOf types.str;
              default = {
                RAILS_ENV = "production";
                RAILS_LOG_TO_STDOUT = "true";
              };
              description = "Environment variables";
            };

            extraServiceConfig = mkOption {
              type = types.attrs;
              default = {};
              example = {
                LimitNOFILE = 65536;
                TimeoutStartSec = 600;
              };
              description = "Extra systemd service config";
            };
          };

          config = mkIf cfg.enable {
            # Create user and group
            users.users.${cfg.user} = {
              isSystemUser = true;
              group = cfg.group;
              description = "Rails application user";
              home = cfg.workingDirectory;
            };

            users.groups.${cfg.group} = {};

            # Systemd service
            systemd.services."rails-app-${cfg.role}" = {
              description = "Rails Application - ${cfg.role}";
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];

              environment = cfg.environment;

              serviceConfig = {
                Type = "simple";
                User = cfg.user;
                Group = cfg.group;
                WorkingDirectory = cfg.workingDirectory;

                # Execute the Procfile command
                ExecStart = "${pkgs.bash}/bin/bash -c '${parseProcfile cfg.role}'";

                Restart = "on-failure";
                RestartSec = "10s";

                # Security hardening
                NoNewPrivileges = true;
                PrivateTmp = true;
                ProtectSystem = "strict";
                ProtectHome = true;
                ReadWritePaths = [ cfg.workingDirectory ];
              } // cfg.extraServiceConfig;
            };

            # Make the package available system-wide
            environment.systemPackages = [ cfg.package ];
          };
        };
    };
}
