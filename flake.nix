{
  description = "Generic Ruby application flake with isolated environment";

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

        # Read .ruby-version file if it exists, otherwise use default
        rubyVersionFile = ./.ruby-version;
        rubyVersion =
          if builtins.pathExists rubyVersionFile
          then builtins.replaceStrings ["\n"] [""] (builtins.readFile rubyVersionFile)
          else "3.3.0";  # Default fallback version

        # Get Ruby from bobvanderlinden's nixpkgs-ruby
        ruby = nixpkgs-ruby.lib.packageFromRubyVersionFile {
          file = rubyVersionFile;
          inherit system;
        };

        # Extract bundler version from Gemfile.lock if it exists
        gemfileLockPath = ./Gemfile.lock;
        bundlerVersion =
          if builtins.pathExists gemfileLockPath
          then
            let
              lockContent = builtins.readFile gemfileLockPath;
              # Extract BUNDLED WITH section - it's at the end of Gemfile.lock
              match = builtins.match ".*BUNDLED WITH[[:space:]]+([0-9]+\\.[0-9]+\\.[0-9]+).*" lockContent;
            in
              if match != null
              then builtins.head match
              else null
          else null;

        # Get the appropriate bundler
        bundler =
          if bundlerVersion != null
          then
            # Use the specific bundler version from Gemfile.lock
            ruby.withPackages (ps: [ (ps.bundler.override { version = bundlerVersion; }) ])
          else
            # Fall back to default bundler that comes with Ruby
            ruby;

        # Check if Gemfile exists to decide whether to build gems
        hasGemfile = builtins.pathExists ./Gemfile;
        hasGemset = builtins.pathExists ./gemset.nix;

        # Build the gem environment using bundlerEnv
        #
        # IMPORTANT: This flake uses bundix for gem management!
        #
        # Workflow:
        #   1. Edit Gemfile (including git sources for private gems)
        #   2. Run: bundle lock
        #   3. Run: bundix -l  (generates gemset.nix)
        #   4. Run: nix build --impure  (--impure needed for SSH git sources)
        #
        # bundix converts Gemfile.lock → gemset.nix with:
        #   - Public gems: fetched from rubygems.org
        #   - Git sources: fetched via SSH (git@github.com:...)
        #
        # Fetching happens BEFORE sandbox (SSH access available),
        # then build uses cached sources from /nix/store.
        gemEnv = if hasGemfile then pkgs.bundlerEnv ({
          name = "ruby-app-gems";
          inherit ruby;
          gemdir = ./.;  # Directory with Gemfile, Gemfile.lock

          # IMPORTANT: If gems have native extensions (pg, mysql2, nokogiri, etc.),
          # add the required system libraries here:
          # buildInputs = with pkgs; [ postgresql mysql80 libxml2 libxslt ];

          # Optional: Build only specific groups
          # groups = [ "default" "production" ];
        } // (if hasGemset then {
          # Use gemset.nix if it exists (required for git sources!)
          # Generate with: bundix -l
          gemset = ./gemset.nix;
        } else {})) else null;

        # Create wrapper for the main application/utility
        # Customize the 'pname' and 'mainScript' for your specific utility
        wrappedApp = pkgs.stdenv.mkDerivation {
          pname = "my-ruby-utility";  # CUSTOMIZE THIS
          version = "0.1.0";  # CUSTOMIZE THIS

          src = ./.;

          buildInputs = [ gemEnv ruby ];

          installPhase = ''
            mkdir -p $out/bin

            # Copy your Ruby scripts/application
            cp -r . $out/lib

            # Create wrapper script
            # CUSTOMIZE: Replace 'main.rb' with your entry point
            cat > $out/bin/my-ruby-utility <<EOF
#!/bin/sh
export GEM_HOME="${gemEnv}/${ruby.gemPath}"
export GEM_PATH="${gemEnv}/${ruby.gemPath}"
exec ${ruby}/bin/ruby $out/lib/main.rb "\$@"
EOF

            chmod +x $out/bin/my-ruby-utility
          '';

          meta = {
            description = "Ruby utility with isolated environment";
            maintainers = [ ];
          };
        };

      in {
        packages = {
          default = wrappedApp;
          gemEnv = gemEnv;
        };

        apps.default = {
          type = "app";
          program = "${wrappedApp}/bin/my-ruby-utility";
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            ruby
            bundler
            pkgs.bundix  # For generating gemset.nix
            pkgs.git     # For git sources
            pkgs.openssh # For SSH git access
          ] ++ pkgs.lib.optionals hasGemfile [ gemEnv ];

          shellHook = ''
            # Check for SSH agent (needed for private gem access)
            if [ -z "$SSH_AUTH_SOCK" ]; then
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo "⚠️  WARNING: No SSH agent detected!"
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo ""
              echo "Private gems with git sources require SSH access."
              echo ""
              echo "To fix, run:"
              echo "  eval \$(ssh-agent)"
              echo "  ssh-add ~/.ssh/id_ed25519"
              echo ""
              echo "Then re-enter this shell: nix develop"
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo ""
            else
              echo "✓ SSH agent available at $SSH_AUTH_SOCK"
            fi

            # Create isolated gem environment for development
            export GEM_HOME="$PWD/.nix-gems"
            mkdir -p "$GEM_HOME"

            # If we have a built gemEnv, use it; otherwise use empty path
            ${if hasGemfile then ''
              export GEM_PATH="${gemEnv}/${ruby.gemPath}:$GEM_HOME"
            '' else ''
              export GEM_PATH="$GEM_HOME"
            ''}

            # Add gem binaries to PATH
            # This includes both built gems and any gems installed during development
            export PATH="$GEM_HOME/bin:${if hasGemfile then "${gemEnv}/bin:" else ""}$PATH"

            # Ensure bundler uses our isolated GEM_HOME
            export BUNDLE_PATH="$GEM_HOME"

            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Ruby Development Environment (with bundix)"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Ruby version: ${rubyVersion}"
            echo "Ruby binary:  ${ruby}/bin/ruby"
            ${if bundlerVersion != null then ''
              echo "Bundler:      ${bundlerVersion} (from Gemfile.lock)"
            '' else ''
              echo "Bundler:      default (no Gemfile.lock)"
            ''}
            echo ""
            echo "Isolation:"
            echo "  GEM_HOME:   $GEM_HOME"
            echo "  GEM_PATH:   $GEM_PATH"
            ${if hasGemfile then ''
              echo "  Built gems: ${gemEnv}/${ruby.gemPath}"
            '' else ''
              echo "  No Gemfile found - run 'bundle init' to create one"
            ''}
            echo ""
            ${if hasGemset then ''
              echo "✓ gemset.nix found (git sources supported)"
            '' else ''
              echo "⚠️  No gemset.nix - run 'bundix -l' to generate"
            ''}
            echo ""
            echo "Workflow for updating gems:"
            echo "  1. Edit Gemfile"
            echo "  2. bundle lock"
            echo "  3. bundix -l       (generates gemset.nix)"
            echo "  4. nix build --impure"
            echo ""
            echo "All gem binaries are in PATH"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

            ruby --version
            bundler --version 2>/dev/null || echo "Note: Run 'gem install bundler' if needed"
          '';
        };
      }
    ) // {
      # NixOS module for deploying Rails application
      nixosModules.default = { config, lib, pkgs, ... }:
        with lib;
        let
          cfg = config.services.rails-app;

          # Function to parse Procfile and extract command for a given role
          parseProcfile = procfilePath: role:
            let
              procfileContent = builtins.readFile procfilePath;
              lines = lib.splitString "\n" procfileContent;
              # Find the line that starts with "role:"
              matchingLines = builtins.filter (line:
                let
                  trimmed = lib.removePrefix " " line;
                  prefix = "${role}:";
                in
                  lib.hasPrefix prefix trimmed
              ) lines;
            in
              if builtins.length matchingLines > 0
              then
                let
                  line = builtins.head matchingLines;
                  # Extract command after "role: "
                  parts = lib.splitString ":" line;
                  commandPart = lib.concatStringsSep ":" (lib.tail parts);
                in
                  lib.trim commandPart
              else
                throw "Role '${role}' not found in Procfile at ${toString procfilePath}";
        in {
          options.services.rails-app = {
            enable = mkEnableOption "Rails application service";

            package = mkOption {
              type = types.package;
              default = self.packages.${pkgs.system}.default;
              description = "The Rails application package to use";
            };

            role = mkOption {
              type = types.str;
              example = "web";
              description = "The role from Procfile to run (e.g., 'web', 'worker', 'scheduler')";
            };

            procfilePath = mkOption {
              type = types.path;
              default = ./Procfile;
              description = "Path to the Procfile to read roles from";
            };

            workingDirectory = mkOption {
              type = types.path;
              description = "Working directory for the Rails application";
            };

            user = mkOption {
              type = types.str;
              default = "rails";
              description = "User account under which the Rails app runs";
            };

            group = mkOption {
              type = types.str;
              default = "rails";
              description = "Group under which the Rails app runs";
            };

            environment = mkOption {
              type = types.attrsOf types.str;
              default = {
                RAILS_ENV = "production";
                RAILS_LOG_TO_STDOUT = "true";
              };
              description = "Environment variables for the Rails application";
            };

            extraServiceConfig = mkOption {
              type = types.attrsOf types.str;
              default = {};
              example = {
                LimitNOFILE = "65536";
                TimeoutStartSec = "600";
              };
              description = "Additional systemd service configuration";
            };
          };

          config = mkIf cfg.enable {
            users.users.${cfg.user} = {
              isSystemUser = true;
              group = cfg.group;
              description = "Rails application user";
            };

            users.groups.${cfg.group} = {};

            environment.systemPackages = [ cfg.package ];

            systemd.services."rails-app-${cfg.role}" = {
              description = "Rails Application - ${cfg.role}";
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];

              environment = cfg.environment // {
                GEM_HOME = "${cfg.package}";
                GEM_PATH = "${cfg.package}";
              };

              serviceConfig = {
                Type = "simple";
                User = cfg.user;
                Group = cfg.group;
                WorkingDirectory = cfg.workingDirectory;
                ExecStart = parseProcfile cfg.procfilePath cfg.role;
                Restart = "on-failure";
                RestartSec = "10s";

                # Security hardening
                NoNewPrivileges = true;
                PrivateTmp = true;
                ProtectSystem = "strict";
                ReadWritePaths = [ cfg.workingDirectory ];
              } // cfg.extraServiceConfig;
            };
          };
        };
    };
}
