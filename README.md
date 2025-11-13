# Generic Ruby Flake Template

This repository provides a generic template for packaging Ruby applications and utilities for NixOS with isolated Ruby and gem environments.

## Features

- ✅ Isolated Ruby environment (no conflicts with system Ruby or other projects)
- ✅ Ruby version from `.ruby-version` file (using bobvanderlinden/nixpkgs-ruby)
- ✅ Gem management via bundlerEnv + bundix
- ✅ **SSH git sources supported** (private gems work!)
- ✅ Wrapper scripts for utilities
- ✅ NixOS module for declarative configuration
- ✅ Compatible with standard bundler workflow

## Quick Start

### 1. Copy this template to your Ruby project

```bash
cp flake.nix /path/to/your/ruby/project/
cd /path/to/your/ruby/project/
```

### 2. Customize the flake

Edit `flake.nix` and update:
- `pname = "my-ruby-utility"` → your utility name
- `version = "0.1.0"` → your version
- `main.rb` → your entry point script
- Service name `ruby-utility` → your service name (appears in 3 places)

### 3. Ensure you have required files

```
your-project/
├── flake.nix
├── .ruby-version          # e.g., "3.3.0"
├── Gemfile                # Can include git sources!
├── Gemfile.lock           # Run: bundle lock
├── gemset.nix             # Run: bundix -l
└── main.rb (or your entry point)
```

### 4. Generate gemset.nix (required for git sources)

```bash
# If your Gemfile has git sources (including SSH private gems):
bundle lock    # Update Gemfile.lock
bundix -l      # Generate gemset.nix
```

### 5. Build and test

```bash
# For projects with SSH git sources (private gems):
eval $(ssh-agent)
ssh-add ~/.ssh/id_ed25519
nix build --impure

# For projects with only public gems:
nix build

# Run the utility
nix run

# Enter development shell
nix develop
```

## Usage in NixOS Configuration

### Option 1: Add to flake-based configuration

In your system's `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    my-ruby-utility.url = "path:/path/to/your/ruby/project";
    # or: my-ruby-utility.url = "github:yourname/your-ruby-utility";
  };

  outputs = { nixpkgs, my-ruby-utility, ... }: {
    nixosConfigurations.my-ec2-instance = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        my-ruby-utility.nixosModules.default
        {
          services.ruby-utility.enable = true;  # CUSTOMIZE: Use your service name

          # Optionally configure
          # services.ruby-utility.user = "myuser";
          # services.ruby-utility.package = my-ruby-utility.packages.x86_64-linux.default;
        }
      ];
    };
  };
}
```

### Option 2: Just install the utility (no service)

```nix
{
  inputs.my-ruby-utility.url = "path:/path/to/your/ruby/project";

  outputs = { nixpkgs, my-ruby-utility, ... }: {
    nixosConfigurations.my-ec2-instance = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [{
        environment.systemPackages = [
          my-ruby-utility.packages.x86_64-linux.default
        ];
      }];
    };
  };
}
```

### Option 3: Traditional configuration.nix

If using traditional configuration.nix (not flakes), you can still import the package:

```nix
{ config, pkgs, ... }:
let
  my-ruby-utility = (import /path/to/your/ruby/project {
    inherit (pkgs) system;
  }).packages.${pkgs.system}.default;
in {
  environment.systemPackages = [ my-ruby-utility ];
}
```

## How It Works

### Isolation

Each Ruby utility gets:
- Its own Ruby version (from `.ruby-version`)
- Its own gem environment (from `Gemfile.lock`)
- Proper `GEM_HOME` and `GEM_PATH` isolation via wrapper scripts

This prevents the Ruby 3.1.0 vs 3.1.2 linking issues you experienced on Ubuntu.

### bundlerEnv + bundix

This template uses `bundlerEnv` with `bundix`:
- **bundlerEnv**: Nix function that builds gems and creates isolated environment
- **bundix**: Tool that converts `Gemfile.lock` → `gemset.nix` for bundlerEnv

**Why bundix?** It enables support for git sources (including SSH private gems) in your Gemfile.

See `BUNDIX_WORKFLOW.md` for detailed workflow documentation.

### Ruby Versions

Ruby versions come from [bobvanderlinden/nixpkgs-ruby](https://github.com/bobvanderlinden/nixpkgs-ruby), which provides:
- Many Ruby versions (including patch versions)
- Automatic reading from `.ruby-version`
- Regular updates

## Customization Examples

### Multiple entry points (multiple utilities)

If your project has multiple commands:

```nix
installPhase = ''
  mkdir -p $out/bin
  cp -r . $out/lib

  # Create multiple wrapper scripts
  for script in cmd1.rb cmd2.rb cmd3.rb; do
    name=$(basename $script .rb)
    cat > $out/bin/$name <<EOF
#!/bin/sh
export GEM_HOME="${gemEnv}/${ruby.gemPath}"
export GEM_PATH="${gemEnv}/${ruby.gemPath}"
exec ${ruby}/bin/ruby $out/lib/$script "\$@"
EOF
    chmod +x $out/bin/$name
  done
'';
```

### Adding native dependencies

If your gems need native libraries (like PostgreSQL, MySQL, etc.):

```nix
gemEnv = pkgs.bundlerEnv {
  name = "ruby-app-gems";
  inherit ruby;
  gemdir = ./.;

  # Add native dependencies
  buildInputs = with pkgs; [
    postgresql
    libxml2
    libxslt
  ];
};
```

### Running as a systemd service

Uncomment and customize the systemd service section in the NixOS module:

```nix
systemd.services.ruby-utility = {
  description = "My Ruby Utility Service";
  wantedBy = [ "multi-user.target" ];
  after = [ "network.target" ];
  serviceConfig = {
    Type = "simple";
    User = cfg.user;
    Group = cfg.group;
    ExecStart = "${cfg.package}/bin/my-ruby-utility";
    Restart = "on-failure";
    RestartSec = "10s";
  };
};
```

## Example Project Structure

```
my-aws-utility/
├── flake.nix              # This template, customized
├── .ruby-version          # "3.3.0"
├── Gemfile
├── Gemfile.lock
├── lib/
│   ├── ec2_manager.rb
│   └── s3_sync.rb
└── bin/
    ├── ec2-manager        # Your Ruby scripts
    └── s3-sync
```

## Deploying to EC2

1. Build your NixOS EC2 AMI with your utilities included
2. Reference utilities in your configuration.nix/flake.nix
3. Each utility runs with its own isolated Ruby + gems
4. No more Ubuntu gem conflicts!

## Troubleshooting

### Gems with native extensions fail to build

Add the required system libraries to `buildInputs` in the `gemEnv` definition.

### Wrong Ruby version

Check `.ruby-version` file - it must be a version available in nixpkgs-ruby.
See: https://github.com/bobvanderlinden/nixpkgs-ruby

### bundlerEnv can't find gems

Ensure `Gemfile.lock` exists and is up to date:
```bash
bundle install
bundle lock
```

## License

Customize this section for your project.
