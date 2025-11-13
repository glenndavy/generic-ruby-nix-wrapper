# SSH Private Gems - Complete Guide

This flake **fully supports** private gems accessed via SSH git sources.

## The Solution: bundix + bundlerEnv

Your gems stay in `Gemfile` (compatible with other developers), and bundix enables Nix to fetch them via SSH.

## Example Gemfile

```ruby
# Gemfile
source 'https://rubygems.org'

# Public gems from RubyGems.org
gem 'thor', '~> 1.3'
gem 'aws-sdk-ec2', '~> 1.400'

# Private gems via SSH
gem 'yourorg-utils',
    git: 'git@github.com:yourorg/yourorg-utils.git',
    tag: 'v1.2.3'

gem 'yourorg-aws',
    git: 'git@github.com:yourorg/yourorg-aws.git',
    branch: 'main'
```

## Complete Workflow

### Initial Setup

```bash
# 1. Your Gemfile already has git sources (see above)

# 2. Ensure SSH agent is running
eval $(ssh-agent)
ssh-add ~/.ssh/id_ed25519

# 3. Test SSH access
ssh -T git@github.com
# Should see: "Hi username! You've successfully authenticated..."

# 4. Generate Gemfile.lock
bundle lock

# 5. Generate gemset.nix with bundix
bundix -l

# 6. Build
nix build --impure
```

### Daily Development

```bash
# Start SSH agent (once per terminal session)
eval $(ssh-agent)
ssh-add

# Enter dev shell (bundix and SSH tools available)
nix develop

# Work normally
ruby main.rb
rspec spec/
```

### Updating Gems

```bash
# Option 1: Use helper script
chmod +x update-gems.sh
./update-gems.sh gem-name

# Option 2: Manual steps
bundle update gem-name
bundix -l
nix build --impure
```

## What Happens During Build

```
Step 1: nix build --impure
  ↓
Step 2: Nix reads gemset.nix
  ↓
  For each gem:
    - Type "gem": fetchurl from rubygems.org
    - Type "git": fetchgit via SSH
  ↓
Step 3: FETCH PHASE (network available, SSH available)
  - fetchgit uses your SSH agent
  - Authenticates with your SSH key
  - Clones the git repo
  - Verifies sha256 hash
  - Stores in /nix/store
  ↓
Step 4: BUILD PHASE (sandbox, no network)
  - Gems already in /nix/store
  - Compile native extensions
  - Create gem environment
  - No network needed!
  ↓
Step 5: Success! ./result/bin/your-utility
```

## Why --impure is Needed

```bash
nix build --impure
```

The `--impure` flag allows:
- Access to `$SSH_AUTH_SOCK` environment variable
- SSH agent can provide authentication
- Git can clone private repos

**Important**: The build itself is still reproducible!
- The sha256 hash is verified
- Same inputs = same outputs
- `--impure` only affects the SSH access during fetch

## For Other Developers (Non-Nix)

Your teammates who don't use Nix can work normally:

```bash
# Regular Ruby workflow (no Nix needed)
bundle install
ruby main.rb
rspec spec/

# They can ignore:
# - flake.nix
# - gemset.nix
# - All Nix stuff
```

**The Gemfile is the source of truth for everyone.**

## CI/CD Setup

### GitHub Actions

```yaml
name: Build

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Install Nix
        uses: cachix/install-nix-action@v22
        with:
          extra_nix_config: |
            experimental-features = nix-command flakes

      - name: Setup SSH for private gems
        env:
          SSH_PRIVATE_KEY: ${{ secrets.PRIVATE_GEM_SSH_KEY }}
        run: |
          mkdir -p ~/.ssh
          echo "$SSH_PRIVATE_KEY" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519

          # Add GitHub to known_hosts
          ssh-keyscan github.com >> ~/.ssh/known_hosts

          # Start SSH agent
          eval $(ssh-agent -s)
          ssh-add ~/.ssh/id_ed25519

          # Export for subsequent steps
          echo "SSH_AUTH_SOCK=$SSH_AUTH_SOCK" >> $GITHUB_ENV
          echo "SSH_AGENT_PID=$SSH_AGENT_PID" >> $GITHUB_ENV

      - name: Build package
        run: nix build --impure

      - name: Run tests
        run: nix develop --impure -c rspec spec/
```

**Setting up the SSH key secret:**
1. Generate a deploy key or use a service account SSH key
2. Add the public key to your private gem repositories (Settings → Deploy keys)
3. Add the private key to GitHub secrets as `PRIVATE_GEM_SSH_KEY`

### GitLab CI

```yaml
# .gitlab-ci.yml
build:
  image: nixos/nix:latest

  before_script:
    # Setup SSH
    - mkdir -p ~/.ssh
    - echo "$PRIVATE_GEM_SSH_KEY" > ~/.ssh/id_ed25519
    - chmod 600 ~/.ssh/id_ed25519
    - ssh-keyscan github.com >> ~/.ssh/known_hosts

    # Start SSH agent
    - eval $(ssh-agent -s)
    - ssh-add ~/.ssh/id_ed25519

    # Enable flakes
    - echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

  script:
    - nix build --impure

  variables:
    PRIVATE_GEM_SSH_KEY: ${PRIVATE_GEM_SSH_KEY}
```

## EC2 Deployment

For deploying to EC2 with NixOS:

### Option 1: Build on EC2

```nix
# In your EC2 NixOS configuration
{ config, pkgs, ... }:

{
  # Install your utility
  inputs.my-utility.url = "github:yourorg/my-utility";

  imports = [ my-utility.nixosModules.default ];

  services.my-utility.enable = true;

  # Ensure SSH key is available for builds
  programs.ssh.extraConfig = ''
    Host github.com
      IdentityFile /root/.ssh/deploy_key
      StrictHostKeyChecking no
  '';
}
```

Add the deploy SSH key to `/root/.ssh/deploy_key` on your EC2 instance.

### Option 2: Pre-build and Deploy

Build on your local machine (or CI), then deploy the binary:

```bash
# Build locally
eval $(ssh-agent) && ssh-add
nix build --impure

# Copy to EC2
nix copy --to ssh://ec2-user@your-ec2-ip ./result
```

## Troubleshooting

### "No SSH agent detected"

```bash
# Start SSH agent
eval $(ssh-agent)

# Add your key
ssh-add ~/.ssh/id_ed25519

# Verify it's loaded
ssh-add -l
```

### "Permission denied (publickey)"

```bash
# Test GitHub SSH access
ssh -T git@github.com

# If fails, check:
# 1. Is your public key on GitHub?
#    https://github.com/settings/keys
# 2. Is the right key loaded?
ssh-add -l

# 3. Add the correct key
ssh-add ~/.ssh/id_ed25519
```

### "bundix: Cannot determine sha256"

bundix sometimes can't fetch git sources to calculate hashes.

**Solution**: Manually calculate:

```bash
# Get the sha256
nix-prefetch-git git@github.com:yourorg/gem.git v1.2.3

# Edit gemset.nix and update the sha256 field
vim gemset.nix
```

### "hash mismatch" during build

The git source changed but gemset.nix has the old hash.

**Solution**:
```bash
# Regenerate gemset.nix
bundix -l

# This recalculates all hashes
```

### Build works but gem not available at runtime

**Solution**: Regenerate and rebuild:

```bash
bundle lock
bundix -l
rm -rf result
nix build --impure
```

## Best Practices

### 1. Pin Git Sources with Tags or Commits

```ruby
# Good: Specific tag
gem 'foo', git: '...', tag: 'v1.2.3'

# Good: Specific commit
gem 'foo', git: '...', ref: 'abc123def'

# Avoid: Branch (can change)
gem 'foo', git: '...', branch: 'main'
```

### 2. Commit gemset.nix

```bash
git add Gemfile.lock gemset.nix
git commit -m "Update gems"
```

Both files should be in version control for reproducibility.

### 3. Use Deploy Keys for CI/CD

Instead of personal SSH keys, create deploy keys:
- Read-only access
- Scoped to specific repositories
- Easily rotated
- No tied to individual accounts

### 4. Test Locally Before CI

```bash
# Ensure it builds locally first
eval $(ssh-agent) && ssh-add
nix build --impure

# Then commit
git add .
git commit -m "Update"
git push
```

## Security Considerations

### SSH Key Security

- ✅ Use read-only deploy keys when possible
- ✅ Scope keys to specific repositories
- ✅ Rotate keys periodically
- ✅ Don't commit private keys to git
- ❌ Don't use personal SSH keys in CI/CD

### --impure Flag

The `--impure` flag:
- ✅ Only affects the fetch phase (accessing SSH agent)
- ✅ Build itself is still deterministic (hashes verified)
- ✅ Safe for private gems
- ⚠️ Means builds depend on external state (your SSH agent)

### Alternative: GitHub Packages

If you control the private gems and want fully pure builds:
1. Publish gems to GitHub Packages
2. Use token authentication (no SSH needed)
3. No `--impure` flag needed

See `PRIVATE_GEMS.md` for details.

## Summary

**For SSH private gems:**

1. ✅ Keep gems in Gemfile (git sources)
2. ✅ Run `bundix -l` to generate gemset.nix
3. ✅ Use `nix build --impure` (for SSH access)
4. ✅ SSH agent must be running with key loaded
5. ✅ Commit gemset.nix to git

**The workflow:**
```
Edit Gemfile → bundle lock → bundix -l → nix build --impure
```

**For CI/CD:**
- Add deploy SSH key as secret
- Start SSH agent in CI script
- Export SSH_AUTH_SOCK
- Run `nix build --impure`

**For other developers:**
- They use `bundle install` normally
- No Nix knowledge required
- Gemfile is source of truth

This solution gives you:
- ✅ SSH private gem support
- ✅ Reproducible builds (hashes verified)
- ✅ Compatible with standard bundler workflow
- ✅ Works in CI/CD
- ✅ Easy deployment to EC2
