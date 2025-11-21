# Incus Container System Flake
# Minimal NixOS configuration for Incus container that imports a Rails app

{
  description = "Incus container with Rails app";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Your Rails app (change this URL!)
    rails-app.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=staging";
    # Or: rails-app.url = "path:/path/to/rails-app";  # For local development
  };

  outputs = { self, nixpkgs, rails-app }: {
    nixosConfigurations.incus-container = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      modules = [
        # Import Rails app NixOS module
        rails-app.nixosModules.default

        {
          # Container-specific settings
          boot.isContainer = true;

          # Networking (Incus handles this)
          networking.hostName = "rails-incus";
          networking.useDHCP = true;

          # No firewall in container (host handles it)
          networking.firewall.enable = false;

          # Rails app configuration
          services.rails-app = {
            enable = true;
            role = "worker";  # Common for containers: worker, sidekiq, etc.

            environment = {
              RAILS_ENV = "production";
              RAILS_LOG_TO_STDOUT = "true";
              # DATABASE_URL = "postgresql://host.incus.internal/rails_prod";
              # REDIS_URL = "redis://host.incus.internal:6379/0";
            };
          };

          # Minimal system packages (containers should be light)
          environment.systemPackages = with nixpkgs.legacyPackages.x86_64-linux; [
            vim
            htop
          ];

          # Logging to stdout for container
          services.journald.extraConfig = ''
            Storage=volatile
            ForwardToConsole=yes
          '';

          system.stateVersion = "24.05";
        }
      ];
    };
  };
}
