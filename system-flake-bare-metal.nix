# Bare Metal System Flake
# Minimal NixOS configuration for bare metal server that imports a Rails app

{
  description = "Bare metal NixOS system with Rails app";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Your Rails app (change this URL!)
    rails-app.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=v2.0.0";
    # Or: rails-app.url = "path:/path/to/rails-app";  # For local development
  };

  outputs = { self, nixpkgs, rails-app }: {
    nixosConfigurations.bare-metal = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      modules = [
        # Hardware configuration (generate with: nixos-generate-config)
        # ./hardware-configuration.nix  # UNCOMMENT after generating

        # Import Rails app NixOS module
        rails-app.nixosModules.default

        {
          # Boot loader (UEFI)
          boot.loader.systemd-boot.enable = true;
          boot.loader.efi.canTouchEfiVariables = true;

          # Or GRUB (BIOS)
          # boot.loader.grub.enable = true;
          # boot.loader.grub.device = "/dev/sda";

          # Networking
          networking.hostName = "rails-server";
          networking.networkmanager.enable = true;

          # Firewall
          networking.firewall.allowedTCPPorts = [ 22 80 443 ];

          # Time zone
          time.timeZone = "America/New_York";  # CUSTOMIZE

          # Locale
          i18n.defaultLocale = "en_US.UTF-8";

          # Enable SSH
          services.openssh = {
            enable = true;
            settings.PermitRootLogin = "no";
          };

          # Create admin user
          users.users.admin = {  # CUSTOMIZE
            isNormalUser = true;
            extraGroups = [ "wheel" "networkmanager" ];
            openssh.authorizedKeys.keys = [
              # "ssh-ed25519 AAAA... your-key"  # CUSTOMIZE
            ];
          };

          # Allow wheel group to sudo
          security.sudo.wheelNeedsPassword = false;

          # Rails app configuration
          services.rails-app = {
            enable = true;
            role = "web";

            environment = {
              RAILS_ENV = "production";
              RAILS_LOG_TO_STDOUT = "true";
              # DATABASE_URL = "postgresql://localhost/rails_prod";
            };
          };

          # Optional: PostgreSQL (if running database locally)
          services.postgresql = {
            enable = true;
            package = nixpkgs.legacyPackages.x86_64-linux.postgresql_15;

            ensureDatabases = [ "rails_prod" ];
            ensureUsers = [{
              name = "rails";
              ensureDBOwnership = true;
            }];
          };

          # Optional: Redis (if needed)
          services.redis.servers.rails = {
            enable = true;
            port = 6379;
          };

          # Optional: Nginx
          services.nginx = {
            enable = true;
            recommendedProxySettings = true;
            recommendedTlsSettings = true;
            recommendedGzipSettings = true;

            virtualHosts."example.com" = {  # CUSTOMIZE
              # enableACME = true;
              # forceSSL = true;

              locations."/" = {
                proxyPass = "http://127.0.0.1:3000";
                proxyWebsockets = true;
              };

              # Static assets (if Rails serves them)
              locations."/assets/" = {
                alias = "${rails-app.packages.x86_64-linux.default}/public/assets/";
                extraConfig = ''
                  expires 1y;
                  add_header Cache-Control "public, immutable";
                '';
              };
            };
          };

          # System packages
          environment.systemPackages = with nixpkgs.legacyPackages.x86_64-linux; [
            vim
            git
            htop
            tmux
            wget
            curl
          ];

          # Automatic garbage collection
          nix.gc = {
            automatic = true;
            dates = "weekly";
            options = "--delete-older-than 30d";
          };

          # Enable flakes
          nix.settings.experimental-features = [ "nix-command" "flakes" ];

          system.stateVersion = "24.05";
        }
      ];
    };
  };
}
