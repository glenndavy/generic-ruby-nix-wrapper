# Private Gems and Git Sources

If your gems use SSH git sources or private GitHub repos, you need special handling because Nix builds in a sandbox without network access.

## The Problem

```ruby
# This won't work out-of-the-box with bundlerEnv:
gem 'private-gem', git: 'git@github.com:yourorg/private-gem.git'
```

**Why it fails:**
1. Nix sandbox has NO network access during builds
2. SSH keys aren't available in the sandbox
3. bundlerEnv is optimized for RubyGems.org, not git sources
4. Private repos need authentication

## Solutions

### Solution 1: GitHub Packages (Recommended for Production)

Publish your private gems to GitHub Packages, then use them like normal gems.

#### 1.1 Publish Your Gem to GitHub Packages

```bash
# In your private gem repo
# Create .github/workflows/publish.yml

name: Publish Gem

on:
  release:
    types: [created]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.3

      - name: Build gem
        run: gem build *.gemspec

      - name: Publish to GitHub Packages
        run: |
          mkdir -p ~/.gem
          cat > ~/.gem/credentials <<EOF
          ---
          :github: Bearer ${{ secrets.GITHUB_TOKEN }}
          EOF
          chmod 0600 ~/.gem/credentials
          gem push --key github --host https://rubygems.pkg.github.com/yourorg *.gem
```

#### 1.2 Use in Your Gemfile

```ruby
# Gemfile
source 'https://rubygems.org'

# Add GitHub Packages as a source
source 'https://rubygems.pkg.github.com/yourorg' do
  gem 'private-gem', '~> 1.0'
  gem 'another-private-gem', '~> 2.0'
end
```

#### 1.3 Authenticate for Bundle

```bash
# Create bundle config with GitHub token
bundle config https://rubygems.pkg.github.com/yourorg $GITHUB_TOKEN

# Then generate lock file
bundle lock
```

#### 1.4 Authenticate for Nix

For Nix to fetch from GitHub Packages during build:

```bash
# Option A: netrc file (simpler)
cat > ~/.netrc <<EOF
machine rubygems.pkg.github.com
  login $GITHUB_USERNAME
  password $GITHUB_TOKEN
EOF
chmod 600 ~/.netrc

# Option B: Nix config
export NIX_CONFIG="netrc-file = $HOME/.netrc"
```

**Pros:**
- ✅ Works with bundlerEnv
- ✅ Reproducible builds
- ✅ Proper versioning
- ✅ CI/CD friendly

**Cons:**
- ❌ Requires publishing gems
- ❌ Extra setup

---

### Solution 2: Convert Git Sources to HTTPS + Token

Replace SSH URLs with HTTPS and use token authentication.

#### 2.1 Update Gemfile

```ruby
# Instead of:
# gem 'private-gem', git: 'git@github.com:yourorg/private-gem.git'

# Use HTTPS:
gem 'private-gem', git: 'https://github.com/yourorg/private-gem.git', tag: 'v1.0.0'
```

#### 2.2 Configure Git Credentials

```bash
# For your user
git config --global url."https://${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"

# Generate Gemfile.lock
bundle lock
```

#### 2.3 Configure Nix

```bash
# Set up netrc for Nix fetchers
cat > ~/.netrc <<EOF
machine github.com
  login $GITHUB_USERNAME
  password $GITHUB_TOKEN
EOF
chmod 600 ~/.netrc

# Tell Nix about it
export NIX_CONFIG="netrc-file = $HOME/.netrc"

# Build
nix build
```

**Pros:**
- ✅ Simpler than packaging separately
- ✅ Works with existing git workflow

**Cons:**
- ⚠️ bundlerEnv may still struggle with git sources
- ⚠️ Less reproducible (git refs can change)

---

### Solution 3: Package Each Private Gem Separately (Most Flexible)

Create a Nix derivation for each private gem, then include in your gem environment.

#### 3.1 Create Derivation for Private Gem

```nix
# private-gems.nix
{ pkgs, lib, ruby }:

rec {
  private-gem = pkgs.stdenv.mkDerivation {
    pname = "private-gem";
    version = "1.0.0";

    src = pkgs.fetchFromGitHub {
      owner = "yourorg";
      repo = "private-gem";
      rev = "v1.0.0";  # Use specific tag or commit
      sha256 = lib.fakeSha256;  # Run once to get real hash
      # For private repos, see authentication below
    };

    nativeBuildInputs = [ ruby pkgs.git ];

    buildPhase = ''
      gem build *.gemspec
    '';

    installPhase = ''
      export GEM_HOME=$out
      gem install --local --no-document *.gem
    '';

    meta = {
      description = "Private gem";
      platforms = ruby.meta.platforms;
    };
  };

  another-private-gem = pkgs.stdenv.mkDerivation {
    # Similar structure...
  };
}
```

#### 3.2 Authenticate GitHub Fetches

For private repos, you need to authenticate `fetchFromGitHub`:

**Option A: SSH Key**

```nix
src = pkgs.fetchgit {
  url = "git@github.com:yourorg/private-gem.git";
  rev = "v1.0.0";
  sha256 = "...";
  # This requires SSH agent with key loaded
};
```

Then run:
```bash
# Start SSH agent with your key
eval $(ssh-agent)
ssh-add ~/.ssh/id_ed25519

# Build with SSH available
nix build --impure  # Needed for SSH access
```

**Option B: GitHub Token**

```nix
src = pkgs.fetchFromGitHub {
  owner = "yourorg";
  repo = "private-gem";
  rev = "v1.0.0";
  sha256 = "...";
  # Nix will use ~/.netrc or NIX_GITHUB_PRIVATE_TOKEN
};
```

Set up:
```bash
# Option 1: netrc
cat > ~/.netrc <<EOF
machine github.com
  login $GITHUB_USERNAME
  password $GITHUB_TOKEN
EOF
chmod 600 ~/.netrc

# Option 2: Environment variable
export NIX_GITHUB_PRIVATE_TOKEN=$GITHUB_TOKEN
```

#### 3.3 Use in Your Flake

```nix
# In flake.nix
let
  privateGems = import ./private-gems.nix { inherit pkgs lib ruby; };

  # Remove private gems from Gemfile, only keep public ones
  gemEnv = pkgs.bundlerEnv {
    name = "ruby-app-gems";
    inherit ruby;
    gemdir = ./.;
  };

  # Combine public and private gems
  allGems = pkgs.buildEnv {
    name = "all-ruby-gems";
    paths = [
      gemEnv
      privateGems.private-gem
      privateGems.another-private-gem
    ];
  };
```

Then use `allGems` instead of `gemEnv` in your wrapper scripts.

**Pros:**
- ✅ Most flexible
- ✅ Works with any git source
- ✅ Can use SSH keys

**Cons:**
- ❌ More complex
- ❌ Must maintain separate derivations
- ❌ May need `--impure` for SSH

---

### Solution 4: Development Only - Impure Build

**WARNING: Only for development/testing! Not for production!**

```nix
gemEnv = pkgs.bundlerEnv {
  name = "ruby-app-gems";
  inherit ruby;
  gemdir = ./.;

  # DANGER: Disables sandbox for this derivation
  __impure = true;
};
```

This allows network access and SSH during the build, but:
- ❌ Not reproducible
- ❌ Breaks Nix's guarantees
- ❌ Won't work in CI/CD
- ❌ Security risk

**Only use for quick local testing!**

---

## Recommended Approach

Based on your use case:

### For Production EC2 Deployments
→ **Use GitHub Packages (Solution 1)**
- Most robust
- Proper versioning
- Works in CI/CD
- Fully reproducible

### For Internal Tools/Scripts
→ **Package Separately (Solution 3) with HTTPS + Token**
- More flexible
- Works with any git repo
- Can track specific commits

### For Development Only
→ **HTTPS + Token (Solution 2)** or **Impure (Solution 4)**
- Quick to set up
- Good enough for local dev

---

## DevShell with Private Gems

The development shell needs SSH access for git operations:

```nix
devShells.default = pkgs.mkShell {
  buildInputs = [
    ruby
    bundler
    pkgs.git
    pkgs.openssh  # For SSH git operations
  ] ++ pkgs.lib.optionals hasGemfile [ gemEnv ];

  shellHook = ''
    # Forward SSH agent (for git clone of private gems)
    if [ -n "$SSH_AUTH_SOCK" ]; then
      echo "SSH agent available for private gem access"
    else
      echo "WARNING: No SSH agent. Private gems may not be accessible."
      echo "Run: eval \$(ssh-agent) && ssh-add"
    fi

    # Rest of shellHook...
  '';
};
```

---

## Authentication Setup Summary

### For GitHub Packages

```bash
# 1. Create GitHub Personal Access Token with 'read:packages' scope
# 2. Configure bundle
bundle config https://rubygems.pkg.github.com/yourorg $GITHUB_TOKEN

# 3. Configure Nix
cat > ~/.netrc <<EOF
machine rubygems.pkg.github.com
  login $GITHUB_USERNAME
  password $GITHUB_TOKEN
EOF
chmod 600 ~/.netrc
```

### For Git HTTPS Sources

```bash
# 1. Create GitHub Personal Access Token with 'repo' scope
# 2. Configure git
git config --global url."https://${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"

# 3. Configure Nix (same netrc as above)
cat > ~/.netrc <<EOF
machine github.com
  login $GITHUB_USERNAME
  password $GITHUB_TOKEN
EOF
chmod 600 ~/.netrc
```

### For Git SSH Sources

```bash
# 1. Add SSH key to GitHub
# 2. Start SSH agent
eval $(ssh-agent)
ssh-add ~/.ssh/id_ed25519

# 3. Test access
ssh -T git@github.com

# 4. Use with Nix (requires --impure)
nix build --impure
```

---

## Example: Complete Setup for Private Gems

Let's say you have:
- Public gems: `thor`, `httparty`
- Private gems: `yourorg-utils`, `yourorg-aws`

### Option A: GitHub Packages

```ruby
# Gemfile
source 'https://rubygems.org'

gem 'thor'
gem 'httparty'

source 'https://rubygems.pkg.github.com/yourorg' do
  gem 'yourorg-utils'
  gem 'yourorg-aws'
end
```

```bash
# Setup
bundle config https://rubygems.pkg.github.com/yourorg $GITHUB_TOKEN
bundle lock

# Create ~/.netrc (for Nix)
cat > ~/.netrc <<EOF
machine rubygems.pkg.github.com
  login $GITHUB_USERNAME
  password $GITHUB_TOKEN
EOF
chmod 600 ~/.netrc

# Build
nix build  # Works!
```

### Option B: Separate Derivations

```ruby
# Gemfile - ONLY public gems
source 'https://rubygems.org'

gem 'thor'
gem 'httparty'
# Don't include private gems here!
```

```nix
# private-gems.nix
{ pkgs, ruby }:
{
  yourorg-utils = pkgs.stdenv.mkDerivation {
    # ... build yourorg-utils gem
  };

  yourorg-aws = pkgs.stdenv.mkDerivation {
    # ... build yourorg-aws gem
  };
}
```

```nix
# flake.nix
let
  privateGems = import ./private-gems.nix { inherit pkgs ruby; };
  publicGems = pkgs.bundlerEnv { /* ... */ };

  allGems = pkgs.buildEnv {
    name = "all-gems";
    paths = [ publicGems privateGems.yourorg-utils privateGems.yourorg-aws ];
  };
```

---

## Troubleshooting

### "Authentication failed" for GitHub Packages

Check:
1. Token has `read:packages` scope
2. Bundle config is set: `bundle config list`
3. ~/.netrc exists and has correct format
4. Token hasn't expired

### "Permission denied (publickey)" for SSH

Check:
1. SSH agent is running: `echo $SSH_AUTH_SOCK`
2. Key is added: `ssh-add -l`
3. Key is on GitHub: `ssh -T git@github.com`
4. Using `--impure` flag with Nix

### bundlerEnv fails with git sources

bundlerEnv doesn't handle git sources well. Options:
1. Use GitHub Packages instead
2. Package gems separately (Solution 3)
3. Use impure build (dev only)

---

## Questions to Determine Best Approach

1. **How many private gems?** (1-2 → separate derivations; 10+ → GitHub Packages)
2. **Do you control them?** (Yes → GitHub Packages; No → HTTPS + token)
3. **Production or dev?** (Production → GitHub Packages; Dev → SSH + impure)
4. **CI/CD needed?** (Yes → GitHub Packages or HTTPS; No → SSH okay)

Let me know your answers and I can provide a more specific solution!
