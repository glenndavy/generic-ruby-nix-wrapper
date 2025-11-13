# SSH Fetcher for Private Gems

Since git submodules don't work and bundix doesn't solve the SSH issue, here's a robust approach for SSH-only private gems.

## The Architecture

```
Public Gems                    Private Gems
(bundlerEnv)                   (separate derivations)
     ↓                              ↓
  gemEnv                      privateGems
     └──────────┬──────────────────┘
                ↓
             allGems
                ↓
          Your wrapper script
```

## Implementation

### 1. Create private-gems.nix

```nix
# private-gems.nix
{ pkgs, lib, ruby, stdenv, fetchgit }:

let
  # Helper to build a gem from a git repo
  buildGemFromGit = { pname, gitUrl, rev, sha256, gemspec ? "${pname}.gemspec" }:
    stdenv.mkDerivation {
      name = "${pname}-${rev}";
      inherit pname;
      version = rev;

      # Fetch via SSH
      src = fetchgit {
        url = gitUrl;
        inherit rev sha256;
        # fetchgit uses SSH_AUTH_SOCK from environment
        leaveDotGit = false;
      };

      nativeBuildInputs = [ ruby ];

      buildPhase = ''
        # Build the gem from the gemspec
        gem build ${gemspec}
      '';

      installPhase = ''
        # Install gem to output
        mkdir -p $out/${ruby.gemPath}
        gem install \
          --local \
          --install-dir $out/${ruby.gemPath} \
          --bindir $out/bin \
          --no-document \
          *.gem
      '';

      meta = {
        platforms = ruby.meta.platforms;
      };
    };

in {
  # Define each private gem
  yourorg-utils = buildGemFromGit {
    pname = "yourorg-utils";
    gitUrl = "git@github.com:yourorg/yourorg-utils.git";
    rev = "v1.2.3";  # Use git tag or commit SHA
    sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";  # Placeholder
  };

  yourorg-aws = buildGemFromGit {
    pname = "yourorg-aws";
    gitUrl = "git@github.com:yourorg/yourorg-aws.git";
    rev = "abc123def456";  # Commit SHA
    sha256 = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";  # Placeholder
  };

  # If a gem has dependencies on other private gems, handle it here
  yourorg-complex = buildGemFromGit {
    pname = "yourorg-complex";
    gitUrl = "git@github.com:yourorg/yourorg-complex.git";
    rev = "v2.0.0";
    sha256 = "sha256-CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=";
  };
}
```

### 2. Update flake.nix

```nix
# Add after the gemEnv definition:

# Import private gems
privateGems = import ./private-gems.nix {
  inherit pkgs lib ruby;
  inherit (pkgs) stdenv fetchgit;
};

# Combine public and private gems
allGems = pkgs.buildEnv {
  name = "all-ruby-gems";
  paths = [
    gemEnv  # Public gems from bundlerEnv
  ] ++ (with privateGems; [
    yourorg-utils
    yourorg-aws
    yourorg-complex
  ]);
  pathsToLink = [ "/${ruby.gemPath}" "/bin" ];
};
```

### 3. Update wrapper to use allGems

```nix
wrappedApp = pkgs.stdenv.mkDerivation {
  # ... existing config ...

  buildInputs = [ allGems ruby ];  # Use allGems, not gemEnv

  installPhase = ''
    mkdir -p $out/bin
    cp -r . $out/lib

    cat > $out/bin/my-ruby-utility <<EOF
#!/bin/sh
export GEM_HOME="${allGems}/${ruby.gemPath}"
export GEM_PATH="${allGems}/${ruby.gemPath}"
exec ${ruby}/bin/ruby $out/lib/main.rb "\$@"
EOF

    chmod +x $out/bin/my-ruby-utility
  '';
};
```

### 4. Update devShell to use allGems

```nix
devShells.default = pkgs.mkShell {
  buildInputs = [
    ruby
    bundler
    pkgs.git
    pkgs.openssh
  ] ++ pkgs.lib.optionals hasGemfile [ allGems ];  # Use allGems

  shellHook = ''
    # Check for SSH agent
    if [ -z "$SSH_AUTH_SOCK" ]; then
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "⚠️  WARNING: No SSH agent detected!"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "Private gems require SSH access."
      echo ""
      echo "To fix, run:"
      echo "  eval \$(ssh-agent)"
      echo "  ssh-add ~/.ssh/id_ed25519"
      echo ""
      exit 1
    fi

    echo "✓ SSH agent available at $SSH_AUTH_SOCK"

    # Create isolated gem environment
    export GEM_HOME="$PWD/.nix-gems"
    mkdir -p "$GEM_HOME"

    export GEM_PATH="${allGems}/${ruby.gemPath}:$GEM_HOME"
    export PATH="$GEM_HOME/bin:${allGems}/bin:$PATH"
    export BUNDLE_PATH="$GEM_HOME"

    # Rest of shellHook...
  '';
};
```

## Workflow

### First-Time Setup for Each Private Gem

```bash
# 1. Get the commit SHA or tag you want
cd /path/to/yourorg-utils
git log -1 --format=%H
# Output: abc123def456...

# 2. Add to private-gems.nix with placeholder hash
# Use the commit SHA as 'rev'
# Use a placeholder sha256

# 3. Start SSH agent
eval $(ssh-agent)
ssh-add ~/.ssh/id_ed25519

# 4. Build to get the real hash
nix build --impure 2>&1 | grep "got:"
# Output: got:    sha256-RealHashHere...

# 5. Update private-gems.nix with the real hash

# 6. Build again
nix build --impure
```

### Updating a Private Gem

```bash
# 1. Find new commit/tag
cd /path/to/yourorg-utils
git pull
git log -1 --format=%H

# 2. Update private-gems.nix
#    - Change 'rev' to new commit SHA
#    - Set sha256 to placeholder

# 3. Get new hash
eval $(ssh-agent) && ssh-add
nix build --impure 2>&1 | grep "got:"

# 4. Update sha256 in private-gems.nix

# 5. Final build
nix build --impure
```

## Your Gemfile - Public Gems Only

```ruby
# Gemfile
source 'https://rubygems.org'

# Only public gems from RubyGems.org
gem 'thor', '~> 1.3'
gem 'httparty', '~> 0.21'
gem 'aws-sdk-ec2', '~> 1.400'

# DO NOT include private gems here!
# Private gems are handled by private-gems.nix
```

Then:
```bash
bundle lock  # Creates Gemfile.lock with only public gems
```

## Build Commands

### Development
```bash
# Ensure SSH agent is running
eval $(ssh-agent)
ssh-add ~/.ssh/id_ed25519

# Enter dev shell
nix develop
```

### Production Build
```bash
# With SSH agent
eval $(ssh-agent)
ssh-add ~/.ssh/id_ed25519

# Build
nix build --impure
```

### Why --impure?

The `--impure` flag is needed because:
1. `fetchgit` needs access to `$SSH_AUTH_SOCK` environment variable
2. SSH authentication happens during the **prefetch phase**
3. The build phase itself is still pure (uses fetched sources from `/nix/store`)

## Handling Dependencies Between Private Gems

If one private gem depends on another:

```nix
# In private-gems.nix
yourorg-base = buildGemFromGit {
  pname = "yourorg-base";
  gitUrl = "git@github.com:yourorg/yourorg-base.git";
  rev = "v1.0.0";
  sha256 = "...";
};

yourorg-advanced = stdenv.mkDerivation {
  pname = "yourorg-advanced";
  version = "v2.0.0";

  src = fetchgit {
    url = "git@github.com:yourorg/yourorg-advanced.git";
    rev = "v2.0.0";
    sha256 = "...";
  };

  nativeBuildInputs = [ ruby ];

  # Make base gem available during build
  buildInputs = [ yourorg-base ];

  buildPhase = ''
    export GEM_PATH="${yourorg-base}/${ruby.gemPath}"
    gem build *.gemspec
  '';

  installPhase = ''
    mkdir -p $out/${ruby.gemPath}

    # Install with access to base gem
    GEM_PATH="${yourorg-base}/${ruby.gemPath}" \
      gem install \
        --local \
        --install-dir $out/${ruby.gemPath} \
        --bindir $out/bin \
        --no-document \
        *.gem
  '';
};
```

## CI/CD Setup

For GitHub Actions:

```yaml
name: Build

on: [push]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Install Nix
        uses: cachix/install-nix-action@v22

      - name: Setup SSH for private gems
        env:
          SSH_PRIVATE_KEY: ${{ secrets.PRIVATE_GEM_SSH_KEY }}
        run: |
          mkdir -p ~/.ssh
          echo "$SSH_PRIVATE_KEY" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          ssh-keyscan github.com >> ~/.ssh/known_hosts

          # Start SSH agent
          eval $(ssh-agent -s)
          ssh-add ~/.ssh/id_ed25519

          # Export for Nix
          echo "SSH_AUTH_SOCK=$SSH_AUTH_SOCK" >> $GITHUB_ENV

      - name: Build
        run: nix build --impure
```

## Pros and Cons

**Pros:**
- ✅ SSH-only (no HTTPS required)
- ✅ Works with private repos
- ✅ Reproducible (hashes verified)
- ✅ Clean separation of public/private gems
- ✅ Can version private gems with git tags

**Cons:**
- ⚠️ Requires `--impure` flag
- ⚠️ Need to manually update hashes when updating gems
- ⚠️ More complex than using only bundlerEnv
- ⚠️ SSH agent must be running

## Alternative: One-Time Prefetch Script

To make hash updates easier, create a helper script:

```bash
#!/usr/bin/env bash
# prefetch-gem.sh - Helper to get sha256 for private gems

set -e

if [ $# -ne 2 ]; then
  echo "Usage: $0 <git-url> <rev>"
  echo "Example: $0 git@github.com:yourorg/gem.git v1.2.3"
  exit 1
fi

GIT_URL=$1
REV=$2

# Ensure SSH agent is running
if [ -z "$SSH_AUTH_SOCK" ]; then
  echo "Error: No SSH agent detected"
  echo "Run: eval \$(ssh-agent) && ssh-add"
  exit 1
fi

echo "Fetching $GIT_URL @ $REV..."

# Use nix-prefetch-git to get the hash
nix-prefetch-git --url "$GIT_URL" --rev "$REV" --quiet | grep sha256 | cut -d'"' -f4
```

Usage:
```bash
chmod +x prefetch-gem.sh
eval $(ssh-agent) && ssh-add

./prefetch-gem.sh git@github.com:yourorg/yourorg-utils.git v1.2.3
# Output: sha256-abc123...
```

## Summary

Since git submodules don't work for you and you need SSH-only:

1. **Public gems**: Keep in `Gemfile`, use `bundlerEnv` (works normally)
2. **Private gems**: Package separately in `private-gems.nix`, use `fetchgit` with SSH
3. **Combine**: Use `buildEnv` to merge public + private gems
4. **Build**: Run `nix build --impure` (needed for SSH during prefetch)

This is the cleanest SSH-only solution that maintains reproducibility while working around bundlerEnv's limitations with git sources.
