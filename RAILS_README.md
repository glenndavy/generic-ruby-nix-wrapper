# Rails Deployment with Nix - Complete Template

This repository provides **production-ready templates** for deploying Rails applications across multiple platforms using Nix flakes.

## What's Included

### Rails App Flake Template
- **`rails-app-flake.nix`** - Complete Rails app flake with:
  - Ruby version from `.ruby-version`
  - Bundler + bundix for gem management
  - SSH private gem support
  - NixOS module for systemd services
  - Procfile role support
  - Development shell
  - Docker image builder

### Platform-Specific System Flakes
- **`system-flake-ec2.nix`** - For AWS EC2 instances
- **`system-flake-incus.nix`** - For Incus/LXD containers
- **`system-flake-bare-metal.nix`** - For physical servers
- **`system-flake-docker.nix`** - For building Docker images

### Documentation
- **`RAILS_COMPLETE_GUIDE.md`** - Complete deployment guide
- **`SYSTEM_FLAKES_USAGE.md`** - How to use each platform flake
- **`RAILS_DEPLOYMENT.md`** - Deployment examples

## Quick Start

### 1. Add Flake to Your Rails App

```bash
cd your-rails-app/

# Copy the template
cp /path/to/rails-app-flake.nix flake.nix

# Customize (search for "CUSTOMIZE" comments)
vim flake.nix
```

Customize these values:

```nix
pname = "my-rails-app";  # Line ~48
version = "1.0.0";       # Line ~49

# Docker image name (line ~99)
name = "my-rails-app";

# Service name (line ~159, appears twice)
config.services.my-rails-app = {
```

### 2. Generate Required Files

```bash
# For SSH private gems
bundle lock
bundix -l

# Test build
nix build

# Commit
git add flake.nix .ruby-version Gemfile* gemset.nix Procfile
git commit -m "Add Nix flake"
git push
```

### 3. Deploy to Your Platform

Choose your deployment target:

#### EC2 Instance

```bash
# On EC2 machine
cp /path/to/system-flake-ec2.nix /etc/nixos/flake.nix

# Customize
vim /etc/nixos/flake.nix
# Set: rails-app.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=production"

# Deploy
nixos-rebuild switch --flake /etc/nixos#ec2-instance
```

#### Incus Container

```bash
# Build
cp system-flake-incus.nix flake.nix
vim flake.nix  # Customize
nix build .#nixosConfigurations.incus-container.config.system.build.toplevel

# Deploy
incus launch images:nixos/unstable rails-worker
incus file push -r result/ rails-worker/nix/var/nix/profiles/system
incus exec rails-worker -- /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

#### Bare Metal

```bash
cp system-flake-bare-metal.nix /etc/nixos/flake.nix
nixos-generate-config --show-hardware-config > /etc/nixos/hardware-configuration.nix
vim /etc/nixos/flake.nix  # Customize
nixos-rebuild switch --flake /etc/nixos#bare-metal
```

#### Docker

```bash
cp system-flake-docker.nix flake.nix
vim flake.nix  # Customize

# Build images
nix build .#web && docker load < result
nix build .#worker && docker load < result
nix build .#scheduler && docker load < result

# Run
docker run -p 3000:3000 -e DATABASE_URL=... rails-app-web:latest
```

## Architecture

```
┌──────────────────────────┐
│ Your Rails App           │
│ ├── flake.nix           │  ← rails-app-flake.nix
│ ├── .ruby-version       │
│ ├── Gemfile.lock        │
│ ├── gemset.nix          │  ← bundix -l
│ └── Procfile            │
└──────────────────────────┘
           ↑
    (referenced by)
           ↓
┌──────────────────────────┐
│ Platform System Flakes   │
│ ├── EC2                  │  ← system-flake-ec2.nix
│ ├── Incus                │  ← system-flake-incus.nix
│ ├── Bare Metal           │  ← system-flake-bare-metal.nix
│ └── Docker               │  ← system-flake-docker.nix
└──────────────────────────┘
```

## Key Features

### ✅ Multi-Platform Support
- Same Rails app flake works everywhere
- Platform-specific system flakes handle deployment details

### ✅ SSH Private Gems
- Uses bundix for git sources
- Full support for `git@github.com:...`
- Works with `nix build --impure`

### ✅ Version Management
- Control versions with `?ref=` parameter
- Pin production to tags: `?ref=v2.0.0`
- Track branches: `?ref=staging`

### ✅ Procfile Support
- Multiple roles: web, worker, scheduler
- Different roles on different instances
- Automatically parses Procfile

### ✅ Complete Isolation
- Each deployment has its own Ruby version
- Each deployment has its own gems
- No conflicts between apps

### ✅ Atomic Deployments
- Builds complete before switching
- Automatic rollback on failure
- Zero-downtime updates possible

## File Overview

### Templates (Copy These)

| File | Purpose | Copy To |
|------|---------|---------|
| `rails-app-flake.nix` | Rails app flake | `your-rails-app/flake.nix` |
| `system-flake-ec2.nix` | EC2 system config | `/etc/nixos/flake.nix` on EC2 |
| `system-flake-incus.nix` | Incus container | Build machine |
| `system-flake-bare-metal.nix` | Server config | `/etc/nixos/flake.nix` on server |
| `system-flake-docker.nix` | Docker builder | Build machine |

### Documentation

| File | What It Explains |
|------|-----------------|
| `RAILS_COMPLETE_GUIDE.md` | Complete deployment walkthrough |
| `SYSTEM_FLAKES_USAGE.md` | How to use each platform flake |
| `RAILS_DEPLOYMENT.md` | Deployment examples and patterns |

## Example: Multi-Environment Setup

### Directory Structure

```
yourorg/
├── rails-app/                    # Your Rails app
│   ├── flake.nix                 # ← rails-app-flake.nix
│   ├── .ruby-version
│   ├── Gemfile
│   └── ...
│
└── infrastructure/               # Deployment configs
    ├── production/
    │   └── flake.nix             # ← system-flake-ec2.nix
    ├── staging/
    │   └── flake.nix             # ← system-flake-incus.nix
    └── docker/
        └── flake.nix             # ← system-flake-docker.nix
```

### Production Flake

```nix
# infrastructure/production/flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rails-app.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=v2.0.0";
  };

  outputs = { rails-app, ... }: {
    nixosConfigurations.prod-web = {
      modules = [
        rails-app.nixosModules.default
        {
          services.rails-app = {
            enable = true;
            role = "web";
          };
        }
      ];
    };
  };
}
```

Deploy:

```bash
ssh root@prod-web "nixos-rebuild switch --flake github:yourorg/infrastructure/production#prod-web"
```

## Version Updates

### Update Production to New Version

```bash
# Edit infrastructure flake
vim infrastructure/production/flake.nix
# Change: ?ref=v2.0.0 to ?ref=v2.1.0

# Lock new version
cd infrastructure/production
nix flake lock --update-input rails-app

# Commit
git commit -am "Deploy v2.1.0 to production"
git push

# Deploy
ssh root@prod-web "nixos-rebuild switch --flake github:yourorg/infrastructure/production#prod-web"
```

## Procfile Roles

Your `Procfile` defines different roles:

```ruby
# Procfile
web: bundle exec puma -C config/puma.rb
worker: bundle exec sidekiq
scheduler: bundle exec clockwork config/schedule.rb
```

Deploy different roles to different instances:

```nix
# EC2 web server
services.rails-app.role = "web";

# Incus worker container
services.rails-app.role = "worker";

# Dedicated scheduler
services.rails-app.role = "scheduler";
```

## Common Workflows

### New Feature Deployment

```bash
# 1. Develop in Rails app
cd rails-app/
# ... make changes ...
bundle lock
bundix -l
git commit -am "New feature"
git push

# 2. Tag release
git tag v2.1.0
git push --tags

# 3. Update infrastructure
cd ../infrastructure/production
vim flake.nix  # Change ?ref=v2.1.0
nix flake lock --update-input rails-app
git commit -am "Deploy v2.1.0"

# 4. Deploy
nixos-rebuild switch --flake .#prod-web --target-host root@prod-web
```

### Rollback

```bash
# On the server
ssh root@prod-web "nixos-rebuild switch --rollback"

# Or change infrastructure flake back
vim flake.nix  # Change ?ref=v2.1.0 back to ?ref=v2.0.0
nix flake lock --update-input rails-app
nixos-rebuild switch --flake .#prod-web --target-host root@prod-web
```

### Test in Staging First

```bash
# Update staging flake
cd infrastructure/staging
vim flake.nix  # Change ?ref=staging (or ?ref=v2.1.0-rc1)
nix flake lock --update-input rails-app

# Deploy to staging
nix build .#nixosConfigurations.staging.config.system.build.toplevel
incus file push -r result/ staging/nix/var/nix/profiles/system
incus exec staging -- /nix/var/nix/profiles/system/bin/switch-to-configuration switch

# Test it
curl https://staging.example.com/health

# If good, deploy to production
```

## Troubleshooting

### Build Fails - Hash Mismatch

```bash
# Regenerate gemset.nix
cd rails-app/
bundix -l
git commit -am "Update gemset.nix"
```

### SSH Private Gems Fail

```bash
# Ensure SSH agent is running
eval $(ssh-agent)
ssh-add ~/.ssh/id_ed25519

# Build with --impure
nix build --impure
```

### Service Won't Start

```bash
# Check logs on server
ssh server "journalctl -u rails-app-web -n 50"

# Common issues:
# - Missing DATABASE_URL
# - Missing SECRET_KEY_BASE
# - Procfile role typo
```

## Migration from Ubuntu

If you're currently running Rails on Ubuntu and want to migrate to NixOS:

1. **Add flake to your Rails app** (30 minutes)
2. **Set up one NixOS instance** (2 hours)
3. **Test deployment** (1 hour)
4. **Deploy to production** (plan maintenance window)

See `RAILS_COMPLETE_GUIDE.md` for detailed migration guide.

## Support

- **Generic Ruby**: See main `README.md` and `INDEX.md`
- **Rails Deployment**: See `RAILS_COMPLETE_GUIDE.md`
- **Platform Usage**: See `SYSTEM_FLAKES_USAGE.md`
- **SSH Private Gems**: See `SSH_PRIVATE_GEMS.md`

## Summary

This template provides **everything you need** to deploy Rails apps with Nix:

✅ Rails app flake with bundix support
✅ Platform-specific system flakes (EC2, Incus, bare metal, Docker)
✅ SSH private gem support
✅ Procfile multi-role support
✅ Version management via git refs
✅ Complete isolation
✅ Atomic deployments with rollback

**Get started in 5 minutes!**
