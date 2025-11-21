# Rails App Deployment Guide

This guide shows how to use `rails-app-flake.nix` across all deployment targets: EC2, Incus, bare metal, and Docker.

## Setup

### 1. Copy to Your Rails App

```bash
cd your-rails-app/
cp /path/to/rails-app-flake.nix flake.nix
```

### 2. Customize

Edit `flake.nix` and change these values:

```nix
# Line ~48
pname = "rails-app";  # ← Change to your app name
version = "1.0.0";    # ← Change to your version

# Line ~99
name = "rails-app";   # ← Docker image name

# Line ~159
config.services.rails-app = {  # ← Service name (2 places)
```

### 3. Generate Required Files

```bash
# Ensure you have these files:
# - .ruby-version
# - Gemfile
# - Gemfile.lock
# - Procfile

# Generate gemset.nix (required for git sources)
bundle lock
bundix -l
```

### 4. Test Build

```bash
# Build the app
nix build

# Test it
./result/bin/rails --version
```

## Deployment Targets

### 1. EC2 Instance (NixOS)

#### Infrastructure Flake

```nix
# infrastructure/flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rails-app.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=production";
  };

  outputs = { nixpkgs, rails-app, ... }: {
    nixosConfigurations.ec2-prod = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # Import Rails app module
        rails-app.nixosModules.default

        {
          # EC2-specific config
          ec2.hvm = true;

          # Rails app configuration
          services.rails-app = {
            enable = true;
            role = "web";

            environment = {
              RAILS_ENV = "production";
              DATABASE_URL = "postgresql://...";
              SECRET_KEY_BASE = "...";
            };
          };

          # Nginx reverse proxy
          services.nginx = {
            enable = true;
            virtualHosts."example.com" = {
              locations."/" = {
                proxyPass = "http://127.0.0.1:3000";
              };
            };
          };

          # Firewall
          networking.firewall.allowedTCPPorts = [ 80 443 ];
        }
      ];
    };
  };
}
```

#### Deploy to EC2

```bash
# Build locally and copy
nix build .#nixosConfigurations.ec2-prod.config.system.build.toplevel
nix copy --to ssh://root@ec2-instance ./result

# Or rebuild on instance
ssh root@ec2-instance "nixos-rebuild switch --flake github:yourorg/infrastructure#ec2-prod"
```

### 2. Incus Container

#### Container Configuration

```nix
# infrastructure/flake.nix
{
  nixosConfigurations.incus-worker = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      rails-app.nixosModules.default

      {
        # Incus container specifics
        boot.isContainer = true;

        # Rails worker
        services.rails-app = {
          enable = true;
          role = "worker";  # Sidekiq, etc.

          environment = {
            RAILS_ENV = "production";
            DATABASE_URL = "postgresql://...";
          };
        };
      }
    ];
  };
}
```

#### Create and Deploy Container

```bash
# Create container
incus launch images:nixos/unstable rails-worker

# Deploy configuration
nix build .#nixosConfigurations.incus-worker.config.system.build.toplevel
incus file push -r result/ rails-worker/nix/var/nix/profiles/system

# Activate
incus exec rails-worker -- /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

### 3. Bare Metal (NixOS)

#### Configuration

```nix
# /etc/nixos/configuration.nix or flake.nix
{
  inputs = {
    rails-app.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=v2.0.0";
  };

  outputs = { nixpkgs, rails-app, ... }: {
    nixosConfigurations.my-server = nixpkgs.lib.nixosSystem {
      modules = [
        ./hardware-configuration.nix
        rails-app.nixosModules.default

        {
          services.rails-app = {
            enable = true;
            role = "web";

            environment = {
              RAILS_ENV = "production";
              DATABASE_URL = "postgresql://localhost/rails_prod";
            };
          };

          # PostgreSQL
          services.postgresql = {
            enable = true;
            ensureDatabases = [ "rails_prod" ];
          };
        }
      ];
    };
  };
}
```

#### Deploy

```bash
nixos-rebuild switch --flake .#my-server
```

### 4. Docker

#### Build Docker Image

```bash
# Build the Docker image
nix build .#docker

# Load into Docker
docker load < result
# Output: Loaded image: rails-app:latest

# Run it
docker run -p 3000:3000 \
  -e DATABASE_URL=postgresql://... \
  -e SECRET_KEY_BASE=... \
  rails-app:latest
```

#### With Specific Procfile Role

You need to override the CMD:

```bash
# Build base image
nix build .#docker
docker load < result

# Run web role (default)
docker run -p 3000:3000 rails-app:latest

# Run worker role
docker run \
  -e DATABASE_URL=postgresql://... \
  rails-app:latest \
  /nix/store/.../bin/bundle exec sidekiq

# Run scheduler role
docker run rails-app:latest \
  /nix/store/.../bin/bundle exec clockwork config/schedule.rb
```

#### Docker Compose

```yaml
# docker-compose.yml
version: '3.8'

services:
  web:
    image: rails-app:latest
    ports:
      - "3000:3000"
    environment:
      RAILS_ENV: production
      DATABASE_URL: postgresql://db/rails_prod
      SECRET_KEY_BASE: ${SECRET_KEY_BASE}
    depends_on:
      - db

  worker:
    image: rails-app:latest
    command: ["/nix/store/.../bin/bundle", "exec", "sidekiq"]
    environment:
      RAILS_ENV: production
      DATABASE_URL: postgresql://db/rails_prod
    depends_on:
      - db
      - redis

  db:
    image: postgres:15
    environment:
      POSTGRES_DB: rails_prod
      POSTGRES_PASSWORD: ${DB_PASSWORD}

  redis:
    image: redis:7
```

Note: You'll need to find the exact bundle path from the built image:

```bash
docker run rails-app:latest which bundle
```

#### Custom Docker Image Per Role

Better approach - create separate Docker images per role:

```nix
# In your Rails app flake.nix, add:
packages = {
  # ... existing packages ...

  docker-web = pkgs.dockerTools.buildLayeredImage {
    name = "rails-app-web";
    tag = "latest";
    contents = [ railsApp pkgs.coreutils pkgs.bash ];
    config = {
      Cmd = [ "${railsApp}/bin/rails" "server" "-b" "0.0.0.0" ];
      ExposedPorts = { "3000/tcp" = {}; };
    };
  };

  docker-worker = pkgs.dockerTools.buildLayeredImage {
    name = "rails-app-worker";
    tag = "latest";
    contents = [ railsApp pkgs.coreutils pkgs.bash ];
    config = {
      Cmd = [ "${railsApp}/bin/bundle" "exec" "sidekiq" ];
    };
  };

  docker-scheduler = pkgs.dockerTools.buildLayeredImage {
    name = "rails-app-scheduler";
    tag = "latest";
    contents = [ railsApp pkgs.coreutils pkgs.bash ];
    config = {
      Cmd = [ "${railsApp}/bin/bundle" "exec" "clockwork" "config/schedule.rb" ];
    };
  };
};
```

Then build each:

```bash
nix build .#docker-web && docker load < result
nix build .#docker-worker && docker load < result
nix build .#docker-scheduler && docker load < result
```

## Multi-Environment Setup

### Directory Structure

```
yourorg/
├── rails-app/              # Rails app with flake.nix
│   ├── flake.nix
│   ├── .ruby-version
│   ├── Gemfile
│   ├── Procfile
│   └── ...
│
└── infrastructure/         # Infrastructure configs
    ├── flake.nix
    ├── production/
    │   ├── ec2-web-1.nix
    │   ├── ec2-worker-1.nix
    │   └── secrets.nix
    ├── staging/
    │   └── ec2-staging.nix
    └── development/
        └── incus-dev.nix
```

### Infrastructure Flake with Environments

```nix
# infrastructure/flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Production - pinned version
    rails-app-prod.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=v2.0.0";

    # Staging - tracks staging branch
    rails-app-staging.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=staging";

    # Development - tracks main
    rails-app-dev.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=main";
  };

  outputs = { nixpkgs, rails-app-prod, rails-app-staging, rails-app-dev, ... }: {
    nixosConfigurations = {
      # Production
      prod-web = nixpkgs.lib.nixosSystem {
        modules = [
          rails-app-prod.nixosModules.default
          ./production/ec2-web-1.nix
        ];
      };

      prod-worker = nixpkgs.lib.nixosSystem {
        modules = [
          rails-app-prod.nixosModules.default
          ./production/ec2-worker-1.nix
        ];
      };

      # Staging
      staging = nixpkgs.lib.nixosSystem {
        modules = [
          rails-app-staging.nixosModules.default
          ./staging/ec2-staging.nix
        ];
      };

      # Development
      dev-incus = nixpkgs.lib.nixosSystem {
        modules = [
          rails-app-dev.nixosModules.default
          ./development/incus-dev.nix
        ];
      };
    };
  };
}
```

## Deployment Scripts

### Deploy to All Production Servers

```bash
#!/usr/bin/env bash
# deploy-production.sh

set -e

VERSION=$1

if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>"
  exit 1
fi

echo "Deploying version $VERSION to production..."

# Update infrastructure flake
cd infrastructure/
sed -i "s|rails-app-prod.url = \".*\"|rails-app-prod.url = \"git+ssh://git@github.com/yourorg/rails-app.git?ref=$VERSION\"|" flake.nix

# Lock the version
nix flake lock --update-input rails-app-prod

# Commit
git add flake.nix flake.lock
git commit -m "Deploy $VERSION to production"
git push

# Deploy to servers
for server in prod-web prod-worker; do
  echo "Deploying to $server..."
  ssh root@$server "nixos-rebuild switch --flake github:yourorg/infrastructure#$server"

  if [ $? -ne 0 ]; then
    echo "Deployment to $server failed! Rolling back..."
    ssh root@$server "nixos-rebuild switch --rollback"
    exit 1
  fi
done

echo "✓ Production deployment complete!"
```

### Build Docker Images for All Roles

```bash
#!/usr/bin/env bash
# build-docker-images.sh

set -e

VERSION=${1:-latest}

cd rails-app/

echo "Building Docker images for version $VERSION..."

# Build each role
for role in web worker scheduler; do
  echo "Building $role..."
  nix build .#docker-$role
  docker load < result
  docker tag rails-app-$role:latest rails-app-$role:$VERSION
  echo "✓ rails-app-$role:$VERSION"
done

echo "✓ All images built!"
echo ""
echo "Push to registry:"
echo "  docker push registry.example.com/rails-app-web:$VERSION"
echo "  docker push registry.example.com/rails-app-worker:$VERSION"
echo "  docker push registry.example.com/rails-app-scheduler:$VERSION"
```

## Environment Variables

### In NixOS Module

```nix
services.rails-app = {
  environment = {
    RAILS_ENV = "production";
    DATABASE_URL = "postgresql://...";
    SECRET_KEY_BASE = config.age.secrets.rails-secret-key.path;
    REDIS_URL = "redis://localhost:6379/0";
  };
};
```

### In Docker

```bash
docker run \
  -e RAILS_ENV=production \
  -e DATABASE_URL=postgresql://... \
  -e SECRET_KEY_BASE=... \
  rails-app:latest
```

## Secrets Management

### With agenix (Recommended for NixOS)

```nix
{
  inputs.agenix.url = "github:ryantm/agenix";

  outputs = { agenix, ... }: {
    nixosConfigurations.prod-web = nixpkgs.lib.nixosSystem {
      modules = [
        agenix.nixosModules.default

        {
          age.secrets.rails-secret-key = {
            file = ./secrets/rails-secret-key.age;
            owner = "rails";
          };

          services.rails-app = {
            environment = {
              SECRET_KEY_BASE_FILE = config.age.secrets.rails-secret-key.path;
            };
          };
        }
      ];
    };
  };
}
```

### With Docker Secrets

```yaml
# docker-compose.yml
secrets:
  rails_secret_key:
    file: ./secrets/rails_secret_key.txt

services:
  web:
    secrets:
      - rails_secret_key
    environment:
      SECRET_KEY_BASE_FILE: /run/secrets/rails_secret_key
```

## Summary

This single flake works across:

✅ **EC2** - Full NixOS deployment with systemd service
✅ **Incus** - Containerized with NixOS module
✅ **Bare Metal** - Direct NixOS installation
✅ **Docker** - Layered image for containerization

All from one `flake.nix` in your Rails app repository!

## Next Steps

1. Copy `rails-app-flake.nix` to your Rails app as `flake.nix`
2. Customize the service name and app details
3. Run `bundle lock && bundix -l`
4. Test: `nix build`
5. Deploy to your chosen target

For infrastructure setup, see the infrastructure flake examples above!
