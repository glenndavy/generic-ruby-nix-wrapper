# How to Use This Template

This guide shows you how to copy this generic Ruby flake to your own Ruby utility project.

## Step-by-Step Guide

### 1. Prepare Your Ruby Project

Your project should have:
```
your-ruby-utility/
├── .ruby-version          # Optional, defaults to 3.3.0
├── Gemfile
├── Gemfile.lock           # Run 'bundle lock' to generate
└── (your ruby scripts)
```

### 2. Copy the Template

```bash
cd /path/to/your/ruby/utility
cp /path/to/generic-ruby-flake/flake.nix .
```

### 3. Customize flake.nix

You need to change these values in `flake.nix`:

#### A. Package name and version (appears twice in `wrappedApp`)
```nix
wrappedApp = pkgs.stdenv.mkDerivation {
  pname = "my-ruby-utility";  # ← CHANGE THIS to your utility name
  version = "0.1.0";          # ← CHANGE THIS to your version
```

#### B. Entry point script (in `installPhase`)
```nix
# CUSTOMIZE: Replace 'main.rb' with your entry point
cat > $out/bin/my-ruby-utility <<EOF
#!/bin/sh
export GEM_HOME="${gemEnv}/${ruby.gemPath}"
export GEM_PATH="${gemEnv}/${ruby.gemPath}"
exec ${ruby}/bin/ruby $out/lib/main.rb "\$@"  # ← CHANGE 'main.rb'
EOF

chmod +x $out/bin/my-ruby-utility  # ← CHANGE the binary name
```

#### C. Service name in NixOS module (appears 3 times)
```nix
cfg = config.services.ruby-utility;  # ← CHANGE 'ruby-utility'

options.services.ruby-utility = {    # ← CHANGE 'ruby-utility'
  enable = mkEnableOption "Ruby utility service";
```

### 4. Test It

```bash
# Build
nix build

# The binary will be in ./result/bin/
./result/bin/my-ruby-utility

# Or run directly
nix run
```

### 5. Use in Your NixOS Configuration

#### For EC2 deployments with flakes:

In your system flake:
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    my-utility.url = "path:/path/to/your/ruby/utility";
  };

  outputs = { nixpkgs, my-utility, ... }: {
    nixosConfigurations.my-ec2 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [{
        # Just install the utility
        environment.systemPackages = [
          my-utility.packages.x86_64-linux.default
        ];

        # OR enable as a service (if you configured the systemd part)
        # imports = [ my-utility.nixosModules.default ];
        # services.my-utility.enable = true;
      }];
    };
  };
}
```

## Real-World Example: AWS EC2 Manager

Let's say you have a Ruby utility called `ec2-snapshot` that manages EC2 snapshots.

### Your project structure:
```
ec2-snapshot/
├── flake.nix
├── .ruby-version         # contains: 3.2.2
├── Gemfile               # has: gem 'aws-sdk-ec2'
├── Gemfile.lock
└── bin/
    └── ec2-snapshot      # Your Ruby script
```

### Customizations in flake.nix:

```nix
wrappedApp = pkgs.stdenv.mkDerivation {
  pname = "ec2-snapshot";
  version = "1.0.0";
  # ...
  installPhase = ''
    mkdir -p $out/bin
    cp -r . $out/lib

    cat > $out/bin/ec2-snapshot <<EOF
#!/bin/sh
export GEM_HOME="${gemEnv}/${ruby.gemPath}"
export GEM_PATH="${gemEnv}/${ruby.gemPath}"
exec ${ruby}/bin/ruby $out/lib/bin/ec2-snapshot "\$@"
EOF

    chmod +x $out/bin/ec2-snapshot
  '';
};
```

And in the NixOS module section:
```nix
cfg = config.services.ec2-snapshot;

options.services.ec2-snapshot = {
  enable = mkEnableOption "EC2 Snapshot Manager";
  # ... rest of options
```

### In your EC2 NixOS configuration:

```nix
{
  inputs.ec2-snapshot.url = "github:yourname/ec2-snapshot";

  outputs = { nixpkgs, ec2-snapshot, ... }: {
    nixosConfigurations.prod-ec2 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [{
        environment.systemPackages = [
          ec2-snapshot.packages.x86_64-linux.default
        ];
      }];
    };
  };
}
```

Now when you deploy to your EC2 instance, `ec2-snapshot` will be available and fully isolated with its own Ruby 3.2.2 and gems!

## Multiple Utilities in One Repo

If you have several related utilities in one repository:

```nix
installPhase = ''
  mkdir -p $out/bin
  cp -r . $out/lib

  # Create wrapper for each utility
  ${lib.concatMapStringsSep "\n" (script: ''
    cat > $out/bin/${script} <<EOF
#!/bin/sh
export GEM_HOME="${gemEnv}/${ruby.gemPath}"
export GEM_PATH="${gemEnv}/${ruby.gemPath}"
exec ${ruby}/bin/ruby $out/lib/bin/${script} "\$@"
EOF
    chmod +x $out/bin/${script}
  '') [ "ec2-snapshot" "s3-sync" "rds-backup" ]}
'';
```

## Common Customizations

### Add system dependencies for gems

If gems need PostgreSQL, MySQL, etc.:

```nix
gemEnv = pkgs.bundlerEnv {
  name = "ruby-app-gems";
  inherit ruby;
  gemdir = ./.;

  buildInputs = with pkgs; [
    postgresql
    mysql80
    sqlite
  ];
};
```

### Use specific Ruby version (override .ruby-version)

```nix
ruby = nixpkgs-ruby.lib.packageFromRubyVersion {
  rubyVersion = "3.1.4";
  inherit system;
};
```

### Set default Ruby version if no .ruby-version

Already handled - change this line:
```nix
else "3.3.0";  # ← Change default here
```

## Tips

1. **Test locally first**: Use `nix build` and `nix run` before deploying to EC2
2. **Keep Gemfile.lock updated**: Run `bundle lock` after changing Gemfile
3. **Check available Ruby versions**: See [nixpkgs-ruby releases](https://github.com/bobvanderlinden/nixpkgs-ruby)
4. **Verify isolation**: Check `GEM_HOME` in your wrapper to ensure it's not using system gems
