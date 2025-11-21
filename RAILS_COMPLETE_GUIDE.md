# Complete Rails Deployment Guide with Nix

This guide shows the complete architecture for deploying a Rails app across EC2, Incus, bare metal, and Docker using Nix flakes.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│ Rails App Repository                                        │
│ ├── flake.nix (rails-app-flake.nix)                        │
│ ├── .ruby-version                                           │
│ ├── Gemfile / Gemfile.lock / gemset.nix                    │
│ ├── Procfile (web, worker, scheduler roles)                │
│ └── app/ (your Rails code)                                 │
└─────────────────────────────────────────────────────────────┘
                           ↑
                     (referenced by)
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ Platform-Specific System Flakes                             │
│ ├── system-flake-ec2.nix (for EC2 instances)              │
│ ├── system-flake-incus.nix (for containers)               │
│ ├── system-flake-bare-metal.nix (for servers)             │
│ └── system-flake-docker.nix (for Docker images)           │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start (5 Minutes)

### 1. Add Flake to Rails App

```bash
cd your-rails-app/

# Copy the Rails app flake template
cp /path/to/rails-app-flake.nix flake.nix

# Customize (change pname, version)
vim flake.nix

# Generate gemset.nix (required for SSH private gems)
bundle lock
bundix -l

# Test build
nix build

# Commit
git add flake.nix .ruby-version Gemfile* gemset.nix
git commit -m "Add Nix flake for deployment"
git push
```

### 2. Deploy to Your Platform

Choose your platform and use the corresponding system flake:

#### EC2

```bash
# On EC2 instance
cp /path/to/system-flake-ec2.nix /etc/nixos/flake.nix

# Customize
vim /etc/nixos/flake.nix
# Change: rails-app.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=production"

# Deploy
nixos-rebuild switch --flake /etc/nixos#ec2-instance
```

#### Incus Container

```bash
# Build system
cp /path/to/system-flake-incus.nix flake.nix
vim flake.nix  # Customize
nix build .#nixosConfigurations.incus-container.config.system.build.toplevel

# Create and deploy
incus launch images:nixos/unstable rails-worker
incus file push -r result/ rails-worker/nix/var/nix/profiles/system
incus exec rails-worker -- /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

#### Docker

```bash
# Build images
cp /path/to/system-flake-docker.nix flake.nix
vim flake.nix  # Customize

nix build .#web && docker load < result
nix build .#worker && docker load < result

# Run
docker run -p 3000:3000 -e DATABASE_URL=... rails-app-web:latest
```

## File Structure

### Your Rails App Repository

```
rails-app/
├── flake.nix              ← From rails-app-flake.nix
├── .ruby-version          ← e.g., "3.3.0"
├── Gemfile
├── Gemfile.lock          ← bundle lock
├── gemset.nix            ← bundix -l (for git sources)
├── Procfile              ← web, worker, scheduler roles
├── app/
├── config/
├── db/
└── ...
```

### Your Infrastructure (Optional)

```
infrastructure/
├── production/
│   ├── flake.nix         ← Based on system-flake-ec2.nix
│   └── secrets/
├── staging/
│   └── flake.nix         ← Based on system-flake-incus.nix
└── docker/
    └── flake.nix         ← Based on system-flake-docker.nix
```

## Complete Example

### Rails App Flake

```nix
# your-rails-app/flake.nix
{
  description = "MyApp Rails Application";

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
        ruby = nixpkgs-ruby.lib.packageFromRubyVersionFile {
          file = ./.ruby-version;
          inherit system;
        };

        gemEnv = pkgs.bundlerEnv {
          name = "myapp-gems";
          inherit ruby;
          gemdir = ./.;
          gemset = ./gemset.nix;
        };

        myapp = pkgs.stdenv.mkDerivation {
          pname = "myapp";
          version = "1.0.0";
          src = ./.;
          buildInputs = [ gemEnv ruby ];

          installPhase = ''
            mkdir -p $out
            cp -r . $out/
            # Create wrapper scripts...
          '';
        };
      in {
        packages.default = myapp;

        # NixOS module
        nixosModules.default = { config, lib, ... }: {
          # Module definition (see rails-app-flake.nix)
        };
      }
    );
}
```

### EC2 System Flake

```nix
# infrastructure/production/flake.nix
{
  description = "Production EC2";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    myapp.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=v2.0.0";
  };

  outputs = { nixpkgs, myapp, ... }: {
    nixosConfigurations.prod-web = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        myapp.nixosModules.default
        {
          services.myapp = {
            enable = true;
            role = "web";
            environment = {
              DATABASE_URL = "postgresql://...";
              SECRET_KEY_BASE = "...";
            };
          };
        }
      ];
    };
  };
}
```

## Version Management

### Deploying Different Versions

The `?ref=` parameter controls which version is deployed:

```nix
# Production - pinned to release tag
myapp.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=v2.0.0";

# Staging - tracks staging branch
myapp.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=staging";

# Development - tracks main branch
myapp.url = "git+ssh://git@github.com/yourorg/rails-app.git?ref=main";
```

### Update Workflow

```bash
# Update to new version
vim flake.nix
# Change: ?ref=v2.0.0 to ?ref=v2.1.0

# Lock the new version
nix flake lock --update-input myapp

# Commit
git commit -am "Deploy v2.1.0"

# Deploy
nixos-rebuild switch --flake .#prod-web
```

## Multi-Role Deployment

### Procfile

```ruby
# Procfile in your Rails app
web: bundle exec puma -C config/puma.rb
worker: bundle exec sidekiq
scheduler: bundle exec clockwork config/schedule.rb
```

### Different Roles on Different Instances

```nix
# EC2 Web Server
services.myapp = {
  enable = true;
  role = "web";  # Runs: bundle exec puma
};

# EC2 Worker
services.myapp = {
  enable = true;
  role = "worker";  # Runs: bundle exec sidekiq
};

# Incus Container for Scheduler
services.myapp = {
  enable = true;
  role = "scheduler";  # Runs: bundle exec clockwork
};
```

## Environment-Specific Configuration

### Using Secrets

```nix
{
  # Option 1: Plain text (NOT recommended for production!)
  services.myapp.environment = {
    SECRET_KEY_BASE = "hardcoded-secret";  # DON'T DO THIS
  };

  # Option 2: Read from file
  services.myapp.environment = {
    SECRET_KEY_BASE = builtins.readFile /run/secrets/rails-secret;
  };

  # Option 3: Use agenix
  age.secrets.rails-secret.file = ./secrets/rails-secret.age;
  services.myapp.environment = {
    SECRET_KEY_BASE = config.age.secrets.rails-secret.path;
  };
}
```

### Database Configuration

```nix
{
  # External database
  services.myapp.environment = {
    DATABASE_URL = "postgresql://prod-db.internal/myapp_prod";
  };

  # Local database
  services.postgresql = {
    enable = true;
    ensureDatabases = [ "myapp_prod" ];
    ensureUsers = [{
      name = "myapp";
      ensureDBOwnership = true;
    }];
  };

  services.myapp.environment = {
    DATABASE_URL = "postgresql:///myapp_prod";
  };
}
```

## Deployment Strategies

### Blue-Green Deployment

```bash
# Build new version
nix build .#nixosConfigurations.prod-web-new.config.system.build.toplevel

# Test on separate instance
ssh prod-web-new "nixos-rebuild switch --flake .#prod-web-new"

# Verify it works
curl https://prod-web-new.internal/health

# Switch traffic (load balancer config)
# ...

# Update main instance
ssh prod-web "nixos-rebuild switch --flake .#prod-web"
```

### Rolling Updates

```bash
#!/usr/bin/env bash
# rolling-update.sh

INSTANCES=("web-1" "web-2" "web-3")

for instance in "${INSTANCES[@]}"; do
  echo "Updating $instance..."
  ssh "root@$instance" "nixos-rebuild switch --flake github:org/infra#$instance"

  # Wait for health check
  sleep 10

  if ! curl -f "https://$instance.internal/health"; then
    echo "Health check failed on $instance!"
    ssh "root@$instance" "nixos-rebuild switch --rollback"
    exit 1
  fi
done
```

## Monitoring and Debugging

### Check Service Status

```bash
# On the server
systemctl status myapp-web
journalctl -u myapp-web -f

# View Rails logs
journalctl -u myapp-web -n 100
```

### Rollback

```bash
# Rollback to previous generation
nixos-rebuild switch --rollback

# Or boot into specific generation
nixos-rebuild boot --rollback
reboot
```

### List Generations

```bash
# See all generations
nixos-rebuild list-generations

# Output:
#  101  2024-01-15 10:00:00
#  102  2024-01-16 14:30:00  (current)
```

## Advanced Topics

### Custom NixOS Module Options

Add to your Rails app flake:

```nix
options.services.myapp = {
  # ... existing options ...

  maxConnections = mkOption {
    type = types.int;
    default = 100;
    description = "Maximum database connections";
  };

  logLevel = mkOption {
    type = types.enum [ "debug" "info" "warn" "error" ];
    default = "info";
    description = "Rails log level";
  };
};

config = mkIf cfg.enable {
  services.myapp.environment = {
    DB_POOL = toString cfg.maxConnections;
    LOG_LEVEL = cfg.logLevel;
  };
};
```

Then use in system flake:

```nix
services.myapp = {
  enable = true;
  maxConnections = 200;
  logLevel = "warn";
};
```

### Multiple Apps on One Server

```nix
{
  imports = [
    myapp.nixosModules.default
    otherapp.nixosModules.default
  ];

  services.myapp = {
    enable = true;
    role = "web";
  };

  services.otherapp = {
    enable = true;
    role = "api";
  };
}
```

## Troubleshooting

### Build Fails with Hash Mismatch

```bash
# Regenerate gemset.nix
bundix -l

# Or fix specific gem hash
nix-prefetch-url https://rubygems.org/downloads/gem-name-1.0.0.gem
# Update hash in gemset.nix
```

### SSH Private Gems Fail

```bash
# Ensure SSH agent is running
eval $(ssh-agent)
ssh-add ~/.ssh/id_ed25519

# Build with --impure for SSH access
nix build --impure
```

### Service Won't Start

```bash
# Check logs
journalctl -u myapp-web -n 50

# Common issues:
# - DATABASE_URL incorrect
# - SECRET_KEY_BASE missing
# - Procfile role not found
# - Working directory permissions
```

## Summary

**You now have:**

✅ **Rails app flake** (`rails-app-flake.nix`)
  - Builds Rails app with isolated Ruby/gems
  - Provides NixOS module
  - Works with SSH private gems (bundix)

✅ **4 Platform-specific system flakes**
  - EC2: `system-flake-ec2.nix`
  - Incus: `system-flake-incus.nix`
  - Bare metal: `system-flake-bare-metal.nix`
  - Docker: `system-flake-docker.nix`

✅ **Deployment workflow**
  - Change `?ref=` to deploy versions
  - Run `nix flake lock --update-input`
  - Deploy with `nixos-rebuild switch`

✅ **Complete isolation**
  - Each app has its own Ruby version
  - Each app has its own gems
  - No conflicts between deployments

**This is a production-ready Rails deployment system!**
