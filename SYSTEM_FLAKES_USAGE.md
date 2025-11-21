# System Flakes Usage Guide

This guide shows how to use the platform-specific system flakes that reference your Rails app flake as an input.

## Architecture

```
Rails App Flake (rails-app/flake.nix)
    ↑ referenced by
    ├── system-flake-ec2.nix
    ├── system-flake-incus.nix
    ├── system-flake-bare-metal.nix
    └── system-flake-docker.nix
```

Each system flake imports the Rails app via flake inputs and configures it for that platform.

## Setup

### 1. Your Rails App Has a Flake

```bash
cd your-rails-app/
# Copy rails-app-flake.nix as flake.nix
cp /path/to/rails-app-flake.nix flake.nix

# Customize it (see RAILS_DEPLOYMENT.md)
# Then generate gemset.nix
bundle lock
bundix -l

# Test build
nix build
```

### 2. Push to Git

```bash
git add flake.nix .ruby-version Gemfile Gemfile.lock gemset.nix
git commit -m "Add Nix flake"
git push
```

## Platform-Specific Deployments

### EC2 Instance

#### Setup

```bash
# Copy the EC2 system flake
cp system-flake-ec2.nix /etc/nixos/flake.nix

# Customize
vim /etc/nixos/flake.nix
# Change:
#   - rails-app.url to your repo
#   - hostName, firewall, SSH keys
#   - Rails environment variables
```

Example customization:

```nix
{
  inputs = {
    rails-app.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=production";
  };

  outputs = { rails-app, ... }: {
    nixosConfigurations.ec2-instance = {
      modules = [
        rails-app.nixosModules.default
        {
          # Your SSH key
          users.users.root.openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3... your-key"
          ];

          # Rails config
          services.rails-app = {
            enable = true;
            role = "web";
            environment = {
              DATABASE_URL = "postgresql://prod-db.internal/rails";
              SECRET_KEY_BASE = builtins.readFile /run/secrets/rails-secret;
            };
          };

          # Domain
          services.nginx.virtualHosts."yourapp.com" = {
            enableACME = true;
            forceSSL = true;
            locations."/".proxyPass = "http://127.0.0.1:3000";
          };
        }
      ];
    };
  };
}
```

#### Deploy

```bash
# First time (on EC2 instance)
nixos-rebuild switch --flake /etc/nixos#ec2-instance

# Or from remote machine
nixos-rebuild switch --flake /etc/nixos#ec2-instance \
  --target-host root@ec2-instance \
  --build-host root@ec2-instance
```

#### Update to New Version

```bash
# SSH into EC2
ssh root@ec2-instance

# Update flake.nix to new version
sed -i 's/?ref=v2.0.0/?ref=v2.1.0/' /etc/nixos/flake.nix

# Update the lock
nix flake lock --update-input rails-app

# Deploy
nixos-rebuild switch --flake /etc/nixos#ec2-instance

# Or rollback if needed
nixos-rebuild switch --rollback
```

### Incus Container

#### Setup

```bash
# Copy the Incus system flake
mkdir -p ~/containers/rails-worker
cp system-flake-incus.nix ~/containers/rails-worker/flake.nix

# Customize
vim ~/containers/rails-worker/flake.nix
# Change:
#   - rails-app.url
#   - role (usually worker, sidekiq, etc.)
#   - environment variables
```

Example customization:

```nix
{
  inputs = {
    rails-app.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=staging";
  };

  outputs = { rails-app, ... }: {
    nixosConfigurations.incus-container = {
      modules = [
        rails-app.nixosModules.default
        {
          services.rails-app = {
            enable = true;
            role = "worker";  # Sidekiq worker
            environment = {
              DATABASE_URL = "postgresql://host.incus.internal/rails_staging";
              REDIS_URL = "redis://host.incus.internal:6379/0";
            };
          };
        }
      ];
    };
  };
}
```

#### Build and Deploy

```bash
# Build the system
cd ~/containers/rails-worker
nix build .#nixosConfigurations.incus-container.config.system.build.toplevel

# Create container
incus launch images:nixos/unstable rails-worker

# Copy system closure
incus file push -r result/ rails-worker/nix/var/nix/profiles/system

# Activate
incus exec rails-worker -- /nix/var/nix/profiles/system/bin/switch-to-configuration switch

# Check status
incus exec rails-worker -- systemctl status rails-app-worker
```

#### Update Container

```bash
# Update flake.nix
sed -i 's/?ref=staging/?ref=main/' flake.nix
nix flake lock --update-input rails-app

# Rebuild and deploy
nix build .#nixosConfigurations.incus-container.config.system.build.toplevel
incus file push -r result/ rails-worker/nix/var/nix/profiles/system
incus exec rails-worker -- /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

### Bare Metal

#### Setup

```bash
# On the bare metal machine
cp system-flake-bare-metal.nix /etc/nixos/flake.nix

# Generate hardware config
nixos-generate-config --root /mnt  # During installation
# Or if already installed:
nixos-generate-config --show-hardware-config > /etc/nixos/hardware-configuration.nix

# Customize flake.nix
vim /etc/nixos/flake.nix
# Uncomment the hardware-configuration.nix import
# Change rails-app.url, hostName, users, etc.
```

Example customization:

```nix
{
  inputs = {
    rails-app.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=v2.0.0";
  };

  outputs = { rails-app, ... }: {
    nixosConfigurations.bare-metal = {
      modules = [
        ./hardware-configuration.nix  # ← UNCOMMENT
        rails-app.nixosModules.default
        {
          # Your hostname
          networking.hostName = "rails-prod-1";

          # Admin user
          users.users.admin = {
            isNormalUser = true;
            extraGroups = [ "wheel" ];
            openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3... your-key"
            ];
          };

          # Rails with local database
          services.rails-app = {
            enable = true;
            role = "web";
            environment = {
              DATABASE_URL = "postgresql://localhost/rails_prod";
            };
          };

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
# First install (from installer)
nixos-install --flake /mnt/etc/nixos#bare-metal

# After installation
nixos-rebuild switch --flake /etc/nixos#bare-metal
```

#### Update

```bash
# Update to new Rails version
vim /etc/nixos/flake.nix
# Change ?ref=v2.0.0 to ?ref=v2.1.0

nix flake lock --update-input rails-app
nixos-rebuild switch --flake /etc/nixos#bare-metal
```

### Docker Images

#### Setup

```bash
# Copy the Docker build flake
mkdir -p ~/docker-builds/rails-app
cp system-flake-docker.nix ~/docker-builds/rails-app/flake.nix

# Customize
vim ~/docker-builds/rails-app/flake.nix
# Change rails-app.url
```

Example customization:

```nix
{
  inputs = {
    rails-app.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=v2.0.0";
  };
  # Rest stays the same
}
```

#### Build Images

```bash
cd ~/docker-builds/rails-app

# Build web image
nix build .#web
docker load < result
# Output: Loaded image: rails-app-web:latest

# Build worker image
nix build .#worker
docker load < result

# Build scheduler image
nix build .#scheduler
docker load < result

# Or build all at once
nix run .#build-all
```

#### Run Containers

```bash
# Web server
docker run -d \
  --name rails-web \
  -p 3000:3000 \
  -e DATABASE_URL=postgresql://... \
  -e SECRET_KEY_BASE=... \
  rails-app-web:latest

# Worker
docker run -d \
  --name rails-worker \
  -e DATABASE_URL=postgresql://... \
  -e REDIS_URL=redis://... \
  rails-app-worker:latest

# Scheduler
docker run -d \
  --name rails-scheduler \
  -e DATABASE_URL=postgresql://... \
  rails-app-scheduler:latest
```

#### Docker Compose

```yaml
# docker-compose.yml
version: '3.8'

services:
  web:
    image: rails-app-web:latest
    ports:
      - "3000:3000"
    environment:
      DATABASE_URL: postgresql://db/rails_prod
      SECRET_KEY_BASE: ${SECRET_KEY_BASE}
      REDIS_URL: redis://redis:6379/0
    depends_on:
      - db
      - redis

  worker:
    image: rails-app-worker:latest
    environment:
      DATABASE_URL: postgresql://db/rails_prod
      REDIS_URL: redis://redis:6379/0
    depends_on:
      - db
      - redis

  scheduler:
    image: rails-app-scheduler:latest
    environment:
      DATABASE_URL: postgresql://db/rails_prod
    depends_on:
      - db

  db:
    image: postgres:15
    environment:
      POSTGRES_DB: rails_prod
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7
    volumes:
      - redis_data:/data

volumes:
  postgres_data:
  redis_data:
```

Run:

```bash
docker-compose up -d
```

#### Update Docker Images

```bash
# Update flake to new version
vim flake.nix
# Change ?ref=v2.0.0 to ?ref=v2.1.0

nix flake lock --update-input rails-app

# Rebuild images
nix run .#build-all

# Recreate containers
docker-compose up -d --force-recreate
```

## Multi-Environment Setup

### Directory Structure

```
~/infrastructure/
├── production/
│   ├── ec2-web.nix          (uses system-flake-ec2.nix)
│   └── ec2-worker.nix       (uses system-flake-ec2.nix)
├── staging/
│   └── incus-staging.nix    (uses system-flake-incus.nix)
├── development/
│   └── incus-dev.nix        (uses system-flake-incus.nix)
└── docker/
    └── flake.nix            (uses system-flake-docker.nix)
```

### Example: Multi-Environment Flake

```nix
# ~/infrastructure/flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Rails app at different versions per environment
    rails-app-prod.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=v2.0.0";
    rails-app-staging.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=staging";
    rails-app-dev.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=main";
  };

  outputs = { nixpkgs, rails-app-prod, rails-app-staging, rails-app-dev, ... }: {
    nixosConfigurations = {
      # Production EC2 instances
      prod-web = import ./production/ec2-web.nix { inherit nixpkgs; rails-app = rails-app-prod; };
      prod-worker = import ./production/ec2-worker.nix { inherit nixpkgs; rails-app = rails-app-prod; };

      # Staging Incus container
      staging = import ./staging/incus-staging.nix { inherit nixpkgs; rails-app = rails-app-staging; };

      # Development Incus container
      dev = import ./development/incus-dev.nix { inherit nixpkgs; rails-app = rails-app-dev; };
    };
  };
}
```

Then deploy with:

```bash
# Production
nixos-rebuild switch --flake ~/infrastructure#prod-web --target-host root@prod-web
nixos-rebuild switch --flake ~/infrastructure#prod-worker --target-host root@prod-worker

# Staging
nix build ~/infrastructure#nixosConfigurations.staging.config.system.build.toplevel
incus file push -r result/ staging/nix/var/nix/profiles/system

# Development
nix build ~/infrastructure#nixosConfigurations.dev.config.system.build.toplevel
incus file push -r result/ dev/nix/var/nix/profiles/system
```

## Deployment Automation

### Simple Deploy Script

```bash
#!/usr/bin/env bash
# deploy.sh <environment> <version>

ENV=$1
VERSION=$2

case $ENV in
  prod)
    sed -i "s|rails-app-prod.url = \".*\"|rails-app-prod.url = \"git+ssh://git@github.com/yourorg/rails-app.git?ref=$VERSION\"|" flake.nix
    nix flake lock --update-input rails-app-prod
    nixos-rebuild switch --flake .#prod-web --target-host root@prod-web
    nixos-rebuild switch --flake .#prod-worker --target-host root@prod-worker
    ;;
  staging)
    sed -i "s|rails-app-staging.url = \".*\"|rails-app-staging.url = \"git+ssh://git@github.com/yourorg/rails-app.git?ref=$VERSION\"|" flake.nix
    nix flake lock --update-input rails-app-staging
    nix build .#nixosConfigurations.staging.config.system.build.toplevel
    incus file push -r result/ staging/nix/var/nix/profiles/system
    incus exec staging -- /nix/var/nix/profiles/system/bin/switch-to-configuration switch
    ;;
  *)
    echo "Unknown environment: $ENV"
    exit 1
    ;;
esac
```

Usage:

```bash
./deploy.sh prod v2.1.0
./deploy.sh staging staging
```

## Summary

You now have **4 minimal system flakes**:

1. **system-flake-ec2.nix** - For EC2 instances
2. **system-flake-incus.nix** - For Incus containers
3. **system-flake-bare-metal.nix** - For bare metal servers
4. **system-flake-docker.nix** - For building Docker images

Each one:
- ✅ References your Rails app flake as an input
- ✅ Minimal, focused configuration
- ✅ Easy to customize
- ✅ Version controlled via `?ref=...`
- ✅ Deployable with standard NixOS tools

**Next steps:**
1. Ensure your Rails app has a flake (use `rails-app-flake.nix`)
2. Copy the appropriate system flake for each platform
3. Customize inputs and configuration
4. Deploy!
