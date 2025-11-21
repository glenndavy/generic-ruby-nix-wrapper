# EC2 System Flake
# Minimal NixOS configuration for EC2 that imports a Rails app

{
  description = "EC2 NixOS system with Rails app";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Your Rails app (change this URL!)
    rails-app.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=production";
    # Or: rails-app.url = "path:/path/to/rails-app";  # For local development
  };

  outputs = { self, nixpkgs, rails-app }:  {
    nixosConfigurations.ec2-instance = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      modules = [
        # Import Rails app NixOS module
        rails-app.nixosModules.default

        {
          # EC2-specific settings
          ec2.hvm = true;
          ec2.efi = true;

          # Boot
          boot.loader.grub.device = "nodev";
          boot.loader.efi.canTouchEfiVariables = true;

          # Networking
          networking.hostName = "rails-ec2";
          networking.firewall.allowedTCPPorts = [ 22 80 443 ];

          # Enable SSH
          services.openssh.enable = true;
          users.users.root.openssh.authorizedKeys.keys = [
            # "ssh-ed25519 AAAA... your-key"  # CUSTOMIZE
          ];

          # Rails app configuration
          services.rails-app = {
            enable = true;
            role = "web";  # Can be: web, worker, scheduler, etc.

            environment = {
              RAILS_ENV = "production";
              RAILS_LOG_TO_STDOUT = "true";
              # DATABASE_URL = "postgresql://...";  # CUSTOMIZE
              # SECRET_KEY_BASE = "...";  # CUSTOMIZE (use secrets manager!)
            };

            # Optional: Custom systemd config
            extraServiceConfig = {
              LimitNOFILE = "65536";
              TimeoutStartSec = "600";
            };
          };

          # Optional: Nginx reverse proxy
          services.nginx = {
            enable = true;
            recommendedProxySettings = true;
            recommendedTlsSettings = true;

            virtualHosts."example.com" = {  # CUSTOMIZE
              # enableACME = true;
              # forceSSL = true;

              locations."/" = {
                proxyPass = "http://127.0.0.1:3000";
                proxyWebsockets = true;
              };
            };
          };

          # System packages
          environment.systemPackages = with nixpkgs.legacyPackages.x86_64-linux; [
            vim
            git
            htop
          ];

          # Automatic updates (optional)
          # system.autoUpgrade.enable = true;

          system.stateVersion = "24.05";
        }
      ];
    };
  };
}
