
> What I'm wanting is to use a flake to define the system behaviour of a) ec2 instances, b) incus containers, and maybe even c) docker containers. I'm hoping the deployment scripting can essentially
be: step 1. tweak the flake, step 2. rebuild switch.  Given the above, specifying the correct branch to deploy is an issue of tweaking the ?ref=thing on the input of the flake. Is that correct ?  So
if my deployment process is sshing in, templating a replacement system flake with the currect ?ref=thing (or for that matter, just applying sed to the file, then `nixos-rebuild switch
--flake=...path..to..flake` (and I imagine path to flake could actually be another controlling git repo) - then rebuild switch should simply trigger a rebuild of the app using the apps flake? which
will just roll back if failed ?

⏺ YES! You've got it exactly right!

  This is a very clean deployment strategy. Let me break down how it works:

  Your Deployment Flow

  # Step 1: SSH into instance
  ssh ec2-instance

  # Step 2: Update the flake (change ?ref=...)
  sed -i 's/?ref=old-version/?ref=new-version/' /etc/nixos/flake.nix

  # Step 3: Rebuild
  nixos-rebuild switch --flake /etc/nixos#ec2-instance

  OR (even cleaner):

  # Your infrastructure flake in a separate repo
  # controls all instances

  # Step 1: Update infrastructure flake locally
  vim infrastructure-flake/flake.nix
  # Change: my-app.url = "git+ssh://...?ref=v2.0.0"

  # Step 2: Commit and push
  git commit -am "Deploy v2.0.0 to production"
  git push

  # Step 3: Deploy to instance
  ssh ec2-prod "nixos-rebuild switch --flake github:yourorg/infrastructure-flake#ec2-prod"

  How It Works

  The Infrastructure Flake

  # infrastructure-flake/flake.nix (separate git repo)
  {
    inputs = {
      nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

      # Your Rails app - change ?ref= to deploy different versions
      rails-app.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=v2.0.0";
    };

    outputs = { nixpkgs, rails-app, ... }: {
      nixosConfigurations = {
        # Production EC2
        ec2-prod = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            rails-app.nixosModules.default
            {
              services.rails-app = {
                enable = true;
                role = "web";
                workingDirectory = "/var/lib/rails-app";
                environment.RAILS_ENV = "production";
              };
            }
          ];
        };

        # Staging EC2
        ec2-staging = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            rails-app.nixosModules.default
            {
              services.rails-app = {
                enable = true;
                role = "web";
                workingDirectory = "/var/lib/rails-app";
                environment.RAILS_ENV = "staging";
              };
            }
          ];
        };

        # Incus container
        incus-worker = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            rails-app.nixosModules.default
            {
              services.rails-app = {
                enable = true;
                role = "worker";  # Different Procfile role
                workingDirectory = "/var/lib/rails-app";
              };
            }
          ];
        };
      };
    };
  }

  Deployment Workflow

  # Deploy new version to production
  vim flake.nix
  # Change: rails-app.url = "...?ref=v2.1.0"

  git commit -am "Deploy v2.1.0 to production"
  git push

  # Rebuild on target (automatically pulls latest infrastructure flake)
  ssh ec2-prod "nixos-rebuild switch --flake github:yourorg/infrastructure#ec2-prod"

  Automatic Rollback

  YES! NixOS automatically supports rollback:

  # If deployment fails or service doesn't start
  ssh ec2-prod "nixos-rebuild switch --rollback"

  # Or boot into previous generation
  ssh ec2-prod "nixos-rebuild boot --rollback && reboot"

  # List available generations
  ssh ec2-prod "nixos-rebuild list-generations"

  The system atomically switches to the new configuration. If it fails:
  - The old configuration remains bootable
  - Systemd services that fail to start don't prevent rollback
  - You can always go back to previous generation

  Different Strategies

  Strategy 1: Templating (Your Sed Idea)

  #!/bin/bash
  # deploy.sh

  VERSION=$1
  INSTANCE=$2

  ssh $INSTANCE "sed -i 's|rails-app.url = \".*\"|rails-app.url = \"git+ssh://git@github.com/org/app.git?ref=${VERSION}\"|' /etc/nixos/flake.nix"
  ssh $INSTANCE "nixos-rebuild switch --flake /etc/nixos#$INSTANCE"

  Pros:
  - Simple
  - Direct control

  Cons:
  - Flake is on remote machine (harder to version control)
  - Must update flake.lock on remote

  Strategy 2: Centralized Infrastructure Flake (Recommended)

  #!/bin/bash
  # deploy.sh

  VERSION=$1
  INSTANCE=$2

  # Update infrastructure flake locally
  sed -i "s|rails-app.url = \".*\"|rails-app.url = \"git+ssh://git@github.com/org/app.git?ref=${VERSION}\"|" flake.nix
  nix flake lock --update-input rails-app
  git commit -am "Deploy $VERSION to $INSTANCE"
  git push

  # Deploy to instance (pulls from git)
  ssh $INSTANCE "nixos-rebuild switch --flake github:yourorg/infrastructure#$INSTANCE"

  Pros:
  - Infrastructure as code (flake in git)
  - Can review changes before deploy
  - Same flake defines all instances
  - Easy to see what's deployed where

  Cons:
  - Requires infrastructure repo

  Strategy 3: Multiple Branches in Infrastructure Flake

  # infrastructure-flake/flake.nix on 'production' branch
  {
    inputs = {
      rails-app.url = "git+ssh://...?ref=v2.0.0";
    };
  }

  # infrastructure-flake/flake.nix on 'staging' branch
  {
    inputs = {
      rails-app.url = "git+ssh://...?ref=staging";
    };
  }

  Deploy:
  # Production uses production branch
  ssh ec2-prod "nixos-rebuild switch --flake github:yourorg/infrastructure/production#ec2-prod"

  # Staging uses staging branch
  ssh ec2-staging "nixos-rebuild switch --flake github:yourorg/infrastructure/staging#ec2-staging"

  Docker Containers

  For Docker, you'd build the container from the flake:

  # In your app's flake.nix
  {
    outputs = { nixpkgs, ... }: {
      packages.x86_64-linux = {
        docker = pkgs.dockerTools.buildImage {
          name = "my-rails-app";
          tag = "latest";

          contents = [ self.packages.x86_64-linux.default ];

          config = {
            Cmd = [ "${self.packages.x86_64-linux.default}/bin/rails" "server" ];
            ExposedPorts = {
              "3000/tcp" = {};
            };
          };
        };
      };
    };
  }

  Build and deploy:
  # Build docker image
  nix build .#docker

  # Load and run
  docker load < result
  docker run -p 3000:3000 my-rails-app:latest

  Complete Deployment Example

  infrastructure/flake.nix

  {
    inputs = {
      nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
      rails-app.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=production";
    };

    outputs = { nixpkgs, rails-app, ... }: {
      nixosConfigurations = {
        ec2-web-1 = nixpkgs.lib.nixosSystem {
          modules = [
            ./hardware/ec2.nix
            rails-app.nixosModules.default
            {
              services.rails-app = {
                enable = true;
                role = "web";
              };
            }
          ];
        };

        ec2-worker-1 = nixpkgs.lib.nixosSystem {
          modules = [
            ./hardware/ec2.nix
            rails-app.nixosModules.default
            {
              services.rails-app = {
                enable = true;
                role = "worker";
              };
            }
          ];
        };

        incus-sidekiq = nixpkgs.lib.nixosSystem {
          modules = [
            ./hardware/incus.nix
            rails-app.nixosModules.default
            {
              services.rails-app = {
                enable = true;
                role = "sidekiq";
              };
            }
          ];
        };
      };
    };
  }

  deploy.sh

  #!/usr/bin/env bash
  set -e

  VERSION=$1
  INSTANCES=("ec2-web-1" "ec2-worker-1" "incus-sidekiq")

  if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    exit 1
  fi

  echo "Deploying version: $VERSION"

  # Update infrastructure flake
  sed -i "s|rails-app.url = \".*\"|rails-app.url = \"git+ssh://git@github.com/yourorg/rails-app.git?ref=${VERSION}\"|" flake.nix

  # Lock the new version
  nix flake lock --update-input rails-app

  # Commit
  git add flake.nix flake.lock
  git commit -m "Deploy $VERSION"
  git push

  # Deploy to each instance
  for instance in "${INSTANCES[@]}"; do
    echo "Deploying to $instance..."
    ssh $instance "nixos-rebuild switch --flake github:yourorg/infrastructure#$instance"

    if [ $? -ne 0 ]; then
      echo "Deployment to $instance failed!"
      echo "Rolling back $instance..."
      ssh $instance "nixos-rebuild switch --rollback"
      exit 1
    fi
  done

  echo "Deployment complete!"

  Rollback Strategy

  #!/usr/bin/env bash
  # rollback.sh

  INSTANCE=$1

  if [ -z "$INSTANCE" ]; then
    echo "Usage: $0 <instance>"
    exit 1
  fi

  echo "Rolling back $INSTANCE to previous generation..."
  ssh $INSTANCE "nixos-rebuild switch --rollback"

  echo "Rollback complete!"
  echo "Current configuration:"
  ssh $INSTANCE "nixos-rebuild list-generations | tail -5"

  Summary

  Yes, your understanding is correct:

  1. ✅ Change ?ref= in flake input to deploy different versions
  2. ✅ Can template/sed the flake file
  3. ✅ nixos-rebuild switch pulls app flake and rebuilds
  4. ✅ Automatic rollback if failed
  5. ✅ Works for EC2, Incus, Docker
  6. ✅ Infrastructure flake can be in separate git repo
  7. ✅ Same pattern for all deployment targets

  The workflow you described is exactly how many people deploy NixOS systems in production!

