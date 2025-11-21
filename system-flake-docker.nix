# Docker Image Build Flake
# Builds a Docker image from the Rails app flake

{
  description = "Docker image builder for Rails app";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Your Rails app (change this URL!)
    rails-app.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=v2.0.0";
    # Or: rails-app.url = "path:/path/to/rails-app";  # For local development
  };

  outputs = { self, nixpkgs, rails-app }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Get the Rails app package
      railsApp = rails-app.packages.${system}.default;

    in {
      packages.${system} = {
        # Default: web role
        default = self.packages.${system}.web;

        # Web server image
        web = pkgs.dockerTools.buildLayeredImage {
          name = "rails-app-web";
          tag = "latest";

          contents = [
            railsApp
            pkgs.coreutils
            pkgs.bash
            pkgs.which
            pkgs.cacert  # For HTTPS
          ];

          config = {
            WorkingDir = "${railsApp}";

            Env = [
              "PATH=${railsApp}/bin:${pkgs.coreutils}/bin:${pkgs.bash}/bin"
              "RAILS_ENV=production"
              "RAILS_LOG_TO_STDOUT=true"
              # Add more defaults as needed
            ];

            Cmd = [ "${railsApp}/bin/rails" "server" "-b" "0.0.0.0" ];

            ExposedPorts = {
              "3000/tcp" = {};
            };

            Labels = {
              "org.opencontainers.image.source" = "https://github.com/yourorg/rails-app";
              "org.opencontainers.image.description" = "Rails application - web";
            };
          };
        };

        # Worker image (Sidekiq, etc.)
        worker = pkgs.dockerTools.buildLayeredImage {
          name = "rails-app-worker";
          tag = "latest";

          contents = [
            railsApp
            pkgs.coreutils
            pkgs.bash
            pkgs.which
            pkgs.cacert
          ];

          config = {
            WorkingDir = "${railsApp}";

            Env = [
              "PATH=${railsApp}/bin:${pkgs.coreutils}/bin:${pkgs.bash}/bin"
              "RAILS_ENV=production"
              "RAILS_LOG_TO_STDOUT=true"
            ];

            # Assumes Procfile has "worker: bundle exec sidekiq"
            Cmd = [ "${railsApp}/bin/bundle" "exec" "sidekiq" ];

            Labels = {
              "org.opencontainers.image.source" = "https://github.com/yourorg/rails-app";
              "org.opencontainers.image.description" = "Rails application - worker";
            };
          };
        };

        # Scheduler image (if you have scheduled jobs)
        scheduler = pkgs.dockerTools.buildLayeredImage {
          name = "rails-app-scheduler";
          tag = "latest";

          contents = [
            railsApp
            pkgs.coreutils
            pkgs.bash
            pkgs.which
            pkgs.cacert
          ];

          config = {
            WorkingDir = "${railsApp}";

            Env = [
              "PATH=${railsApp}/bin:${pkgs.coreutils}/bin:${pkgs.bash}/bin"
              "RAILS_ENV=production"
              "RAILS_LOG_TO_STDOUT=true"
            ];

            # Customize based on your scheduler (clockwork, etc.)
            Cmd = [ "${railsApp}/bin/bundle" "exec" "clockwork" "config/schedule.rb" ];

            Labels = {
              "org.opencontainers.image.source" = "https://github.com/yourorg/rails-app";
              "org.opencontainers.image.description" = "Rails application - scheduler";
            };
          };
        };

        # All images at once
        all = pkgs.runCommand "all-docker-images" {} ''
          mkdir -p $out
          ln -s ${self.packages.${system}.web} $out/web.tar.gz
          ln -s ${self.packages.${system}.worker} $out/worker.tar.gz
          ln -s ${self.packages.${system}.scheduler} $out/scheduler.tar.gz
        '';
      };

      # Apps for easy running
      apps.${system} = {
        # Build and load web image
        build-web = {
          type = "app";
          program = toString (pkgs.writeShellScript "build-web" ''
            echo "Building web image..."
            ${pkgs.nix}/bin/nix build .#web
            echo "Loading into Docker..."
            ${pkgs.docker}/bin/docker load < result
            echo "✓ rails-app-web:latest"
          '');
        };

        # Build and load all images
        build-all = {
          type = "app";
          program = toString (pkgs.writeShellScript "build-all" ''
            for role in web worker scheduler; do
              echo "Building $role image..."
              ${pkgs.nix}/bin/nix build .#$role
              echo "Loading into Docker..."
              ${pkgs.docker}/bin/docker load < result
              echo "✓ rails-app-$role:latest"
            done
          '');
        };
      };
    };
}
