# Bundler Workflow with bundlerEnv

This document explains how bundler and bundlerEnv work together, and what commands you actually need.

## TL;DR - What You Need

```bash
# To create/update dependencies:
bundle lock              # ✅ Creates Gemfile.lock (all you need for Nix!)

# To build with Nix:
nix build                # ✅ bundlerEnv reads Gemfile.lock directly

# You do NOT need:
bundle install           # ❌ Not needed for Nix builds
```

## How bundlerEnv Works

### Traditional Bundler (Ubuntu)
```
Gemfile → bundle install → Downloads gems → Installs to vendor/bundle/
                           ↑
                           Needs network access
                           Not reproducible
```

### bundlerEnv (NixOS)
```
Gemfile.lock → bundlerEnv → Fetches gems (outside sandbox) → Builds in sandbox → /nix/store
               ↑
               Reads versions/hashes
               Fully reproducible
```

### Key Differences

| Aspect | Traditional Bundler | bundlerEnv |
|--------|-------------------|------------|
| Input | Gemfile + Gemfile.lock | Gemfile.lock only |
| Network | During `bundle install` | During Nix fetch (before build) |
| Output | `vendor/bundle/` | `/nix/store/...-ruby-gems` |
| Reproducible | No (even with lock file) | Yes (with fixed hashes) |
| Isolation | Per-project or system | Per derivation |

## Required Files

### Minimum Required

```
your-project/
├── flake.nix
├── Gemfile              # ✅ Required
└── Gemfile.lock         # ✅ Required - bundlerEnv needs this!
```

### How to Generate Gemfile.lock

```bash
# Option 1: Just create the lock file (no installation)
bundle lock

# Option 2: Install locally AND create lock file
bundle install

# Option 3: Update specific gem
bundle update aws-sdk-ec2
```

**For Nix, only the resulting `Gemfile.lock` matters!**

## Workflow Examples

### Starting a New Project

```bash
# 1. Initialize bundler
bundle init

# 2. Edit Gemfile
cat > Gemfile <<EOF
source 'https://rubygems.org'

gem 'aws-sdk-ec2'
gem 'thor'
EOF

# 3. Create lock file (doesn't install anything)
bundle lock

# 4. Build with Nix
nix build

# Done! No 'bundle install' needed for the Nix build
```

### Adding a New Gem

```bash
# 1. Edit Gemfile
echo "gem 'httparty'" >> Gemfile

# 2. Update lock file
bundle lock

# 3. Rebuild with Nix
nix build

# The new gem is now included!
```

### Updating a Gem

```bash
# Update specific gem
bundle update aws-sdk-ec2

# This updates Gemfile.lock
# Then rebuild:
nix build
```

### In Development Shell

```bash
# Enter shell
nix develop

# Now you CAN use bundle install if you want
# (but it installs to .nix-gems/, not used by Nix builds)
bundle install

# Or just work with the gems bundlerEnv already built
ruby main.rb
rspec spec/
```

## Network Access and Sandbox Issues

### How Gem Fetching Works

```
┌─────────────────────────────────────────────────────────────┐
│ Phase 1: Derivation Setup (OUTSIDE sandbox, HAS network)   │
├─────────────────────────────────────────────────────────────┤
│ bundlerEnv reads Gemfile.lock                               │
│ Creates fixed-output derivations for each gem               │
│ Nix fetches gems from rubygems.org                          │
│ Each gem is downloaded to /nix/store with verified hash     │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ Phase 2: Build (INSIDE sandbox, NO network)                │
├─────────────────────────────────────────────────────────────┤
│ Gems are already in /nix/store (from Phase 1)              │
│ bundlerEnv builds/compiles gems using fetched sources       │
│ No network needed - everything is pre-downloaded            │
└─────────────────────────────────────────────────────────────┘
```

**This works automatically for standard RubyGems.org gems!**

### Gems That Work Fine

✅ Pure Ruby gems (no compilation)
```ruby
gem 'thor'
gem 'httparty'
gem 'aws-sdk-ec2'
```

✅ Gems with native extensions (if system libs provided)
```ruby
gem 'json'    # Works out of box (minimal deps)
gem 'pg'      # Works if you add postgresql to buildInputs
gem 'mysql2'  # Works if you add mysql80 to buildInputs
```

### Gems That Need Extra Configuration

#### Gems with Native Extensions

**Problem**: They compile C code during installation and need system libraries.

**Example**: PostgreSQL gem

```ruby
# Gemfile
gem 'pg'
```

**Solution**: Add system dependencies to `buildInputs`:

```nix
gemEnv = pkgs.bundlerEnv {
  name = "ruby-app-gems";
  inherit ruby;
  gemdir = ./.;

  buildInputs = with pkgs; [
    postgresql  # ← Needed for pg gem
  ];
};
```

**Common dependencies**:

| Gem | System Package Needed |
|-----|----------------------|
| `pg` | `postgresql` |
| `mysql2` | `mysql80` |
| `sqlite3` | `sqlite` |
| `nokogiri` | `libxml2`, `libxslt` |
| `rmagick` | `imagemagick` |
| `curses` | `ncurses` |

#### Git-sourced Gems

**Problem**: bundlerEnv is optimized for RubyGems.org. Git sources can be tricky.

```ruby
# This might cause issues:
gem 'my-gem', git: 'https://github.com/user/my-gem.git'
```

**Solutions**:
1. Use a specific ref/tag: `gem 'my-gem', git: '...', ref: 'v1.2.3'`
2. Better: Package the gem separately as a Nix derivation
3. Best: Avoid git sources in production; use published gems

#### Gems That Download During Installation

**Problem**: Some gems download additional files during `gem install` (very rare).

**This will fail** because there's no network in the sandbox during gem installation.

**Solution**:
- Find an alternative gem
- Or patch the gem to not download at runtime
- Or pre-fetch the files as separate derivations

### Common Error Messages

#### Error: "Gem not found"

```
Error: Could not find gem 'some-gem' in any of the gem sources
```

**Cause**: Gem not in Gemfile.lock

**Fix**:
```bash
bundle lock  # Regenerate Gemfile.lock
nix build
```

#### Error: Native extension build failed

```
Error: Failed to build gem native extension
  ... cannot find -lpq
```

**Cause**: Missing system library for native gem

**Fix**: Add to `buildInputs`:
```nix
gemEnv = pkgs.bundlerEnv {
  buildInputs = with pkgs; [ postgresql ];  # ← Add this
  # ...
};
```

#### Error: Git source not available

```
Error: Git source not available for gem 'xyz'
```

**Cause**: bundlerEnv doesn't handle git sources well

**Fix**: Use a published gem version, or package the gem separately

## Best Practices

### 1. Keep Gemfile.lock in Git

```bash
# Always commit this!
git add Gemfile.lock
git commit -m "Lock gem dependencies"
```

This ensures reproducible builds across machines.

### 2. Use Published Gems

Prefer RubyGems.org gems over git sources:

```ruby
# Good:
gem 'aws-sdk-ec2', '~> 1.400'

# Avoid if possible:
gem 'my-gem', git: 'https://github.com/...'
```

### 3. Specify Versions

Be explicit about versions to ensure reproducibility:

```ruby
# Better:
gem 'thor', '~> 1.3.0'

# Avoid:
gem 'thor'  # Any version
```

### 4. Document Native Dependencies

In your README, note which gems need buildInputs:

```markdown
## Native Dependencies

This project uses the `pg` gem which requires PostgreSQL libraries.
Uncomment the `buildInputs` line in flake.nix:

    buildInputs = with pkgs; [ postgresql ];
```

### 5. Separate Dev and Production Gems

```ruby
# Gemfile
source 'https://rubygems.org'

gem 'aws-sdk-ec2'  # Production

group :development do
  gem 'pry'
  gem 'rubocop'
end

group :test do
  gem 'rspec'
end
```

Then in flake.nix:
```nix
gemEnv = pkgs.bundlerEnv {
  # ...
  groups = [ "default" "production" ];  # Exclude dev/test from builds
};
```

## Development vs Production

### In Development (nix develop)

```bash
nix develop

# You CAN use bundle commands:
bundle install    # Installs to .nix-gems/ (isolated)
bundle exec ruby main.rb

# But you can also just use gems directly:
ruby main.rb      # Gems from bundlerEnv already available
rspec spec/
```

The dev shell has:
- Pre-built gems from `bundlerEnv` (in PATH)
- Isolated `.nix-gems/` for ad-hoc gem installs
- Both are available simultaneously

### In Production (nix build)

```bash
nix build

# This:
# 1. Reads Gemfile.lock
# 2. Fetches all gems (with network)
# 3. Builds gems (in sandbox, no network)
# 4. Creates wrapper with GEM_HOME/GEM_PATH set
# 5. Outputs to ./result/bin/your-utility

# No 'bundle install' ever runs!
```

## Summary

| Command | When | Why |
|---------|------|-----|
| `bundle lock` | After editing Gemfile | Creates Gemfile.lock for bundlerEnv |
| `bundle update` | To update gems | Updates Gemfile.lock |
| `bundle install` | Optional in dev shell | Installs to .nix-gems/ for experimentation |
| `nix build` | To build package | bundlerEnv reads Gemfile.lock |
| `nix develop` | For development | Gives you ruby + gems + isolated env |

**The key insight**: `bundlerEnv` replaces `bundle install` for production builds. It reads `Gemfile.lock` and builds everything reproducibly in Nix.

## Troubleshooting Checklist

Build failing? Check:

- [ ] Do you have `Gemfile.lock`? (Run `bundle lock`)
- [ ] Is `Gemfile.lock` up to date? (Run `bundle lock` again)
- [ ] Do any gems have native extensions? (Add to `buildInputs`)
- [ ] Are you using git sources? (Try published gems instead)
- [ ] Is the gem actually on RubyGems.org? (Check https://rubygems.org/)

## Real-World Example

Let's say you're building an AWS EC2 utility:

```ruby
# Gemfile
source 'https://rubygems.org'

gem 'aws-sdk-ec2', '~> 1.400'
gem 'thor', '~> 1.3'
```

```bash
# Create lock file
bundle lock

# Build with Nix (no bundle install needed!)
nix build

# bundlerEnv will:
# 1. Read Gemfile.lock
# 2. Fetch aws-sdk-ec2 and all its dependencies (50+ gems!)
# 3. Fetch thor and its dependencies
# 4. Build everything in isolation
# 5. Create /nix/store/...-ruby-gems with all gems

# Your utility is ready:
./result/bin/ec2-manager
```

No network issues, no conflicts, fully reproducible! 🎉
