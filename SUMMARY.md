# Summary - Generic Ruby Flake with SSH Support

This flake provides a complete solution for packaging Ruby applications with **full SSH private gem support**.

## What You Get

✅ **Isolated Ruby environments** - No conflicts between projects
✅ **Ruby version from `.ruby-version`** - Automatic version management
✅ **SSH git sources** - Private gems work via `bundix`
✅ **Bundler compatibility** - Standard workflow for non-Nix users
✅ **Reproducible builds** - Same inputs = same outputs
✅ **NixOS module** - Declarative deployment to EC2
✅ **Development shell** - Fully configured with bundix, SSH tools

## The Key Innovation: bundix

**Problem**: bundlerEnv alone doesn't handle SSH git sources well

**Solution**: Use bundix to convert `Gemfile.lock` → `gemset.nix`

This enables:
- Fetching private gems via SSH during Nix's fetch phase
- Keeping gems in Gemfile (for other developers)
- Reproducible builds with hash verification

## Quick Start

```bash
# 1. Your Gemfile (can include SSH git sources)
cat > Gemfile <<'EOF'
source 'https://rubygems.org'
gem 'thor'
gem 'private-gem', git: 'git@github.com:org/private-gem.git', tag: 'v1.0'
EOF

# 2. Generate files
bundle lock    # Creates Gemfile.lock
bundix -l      # Creates gemset.nix

# 3. Build (with SSH)
eval $(ssh-agent) && ssh-add
nix build --impure

# 4. Deploy to EC2 (via NixOS configuration)
# See README.md for details
```

## File Structure

```
your-project/
├── flake.nix           # This template (customize pname, version, entry point)
├── .ruby-version       # e.g., "3.3.0"
├── Gemfile             # Public + private gems
├── Gemfile.lock        # bundle lock
├── gemset.nix          # bundix -l (commit this!)
├── update-gems.sh      # Helper script
└── (your code)
```

## Workflow

### Development

```bash
# Enter shell (bundix available)
nix develop

# Work normally
ruby main.rb
rspec spec/
```

### Updating Gems

```bash
# Easy way
./update-gems.sh gem-name

# Manual way
bundle update gem-name
bundix -l
nix build --impure
```

### Deploying to EC2

```nix
# In your NixOS configuration
{
  inputs.my-utility.url = "github:you/my-utility";

  imports = [ my-utility.nixosModules.default ];

  services.my-utility.enable = true;
}
```

## Why This Works

### The Fetch Timeline

```
Phase 1: Evaluation
  - Nix reads gemset.nix
  - Plans what to fetch

Phase 2: Fetch (network + SSH available)
  - fetchurl: Public gems from rubygems.org
  - fetchgit: Private gems via SSH
  - Uses your SSH agent (via --impure)
  - Verifies sha256 hashes
  - Stores in /nix/store

Phase 3: Build (sandbox, no network)
  - Uses pre-fetched sources
  - Compiles native extensions
  - Creates gem environment
```

**Key insight**: SSH access happens during fetch, not build!

## For Your AWS EC2 Use Case

This solves your original requirements:

1. ✅ **Move from Ubuntu to NixOS** - Reproducible Ruby environments
2. ✅ **Reference in configuration.nix** - NixOS module included
3. ✅ **No version conflicts** - Each utility isolated with its own Ruby/gems
4. ✅ **Private gems via SSH** - Fully supported with bundix
5. ✅ **Multiple utilities** - Each gets its own flake

**Example**: Three AWS utilities with different Rubies

```
ec2-manager/
├── .ruby-version (3.2.0)
├── Gemfile (with private gems)
└── flake.nix

s3-sync/
├── .ruby-version (3.3.0)
├── Gemfile (with private gems)
└── flake.nix

rds-backup/
├── .ruby-version (3.1.4)
├── Gemfile (with private gems)
└── flake.nix
```

Each is isolated, no conflicts, deploy declaratively to EC2!

## Documentation

| File | Purpose |
|------|---------|
| `README.md` | Main documentation |
| `BUNDIX_WORKFLOW.md` | Detailed bundix workflow |
| `SSH_PRIVATE_GEMS.md` | Complete SSH setup guide |
| `DEVSHELL.md` | Development shell features |
| `BUNDLER_WORKFLOW.md` | How bundlerEnv works |
| `QUICK_REFERENCE.md` | One-page cheat sheet |
| `TEMPLATE_USAGE.md` | How to customize |
| `update-gems.sh` | Helper script |

## Common Commands

```bash
# Update gems
./update-gems.sh

# Build with SSH private gems
nix build --impure

# Build with only public gems
nix build

# Enter dev shell
nix develop

# Deploy to EC2
nixos-rebuild switch --flake .#ec2-instance
```

## CI/CD Support

Includes GitHub Actions and GitLab CI examples with SSH setup.

See `SSH_PRIVATE_GEMS.md` for complete CI/CD configuration.

## Compatibility

- ✅ **Other Ruby developers**: Use `bundle install` normally
- ✅ **Nix users**: Use `bundix` + `nix build --impure`
- ✅ **CI/CD**: Works with GitHub Actions, GitLab CI, etc.
- ✅ **EC2 deployment**: NixOS module included

## The Workflow Summary

```
┌─────────────────────────────────────────────────────────────┐
│ For All Developers                                          │
├─────────────────────────────────────────────────────────────┤
│ Edit Gemfile (public + private gems)                        │
│ Commit to git                                               │
└─────────────────────────────────────────────────────────────┘
                           ↓
         ┌─────────────────┴─────────────────┐
         ↓                                   ↓
┌────────────────────┐            ┌──────────────────────┐
│ Non-Nix Developer  │            │ Nix User             │
├────────────────────┤            ├──────────────────────┤
│ bundle install     │            │ bundle lock          │
│ ruby main.rb       │            │ bundix -l            │
│ rspec spec/        │            │ nix build --impure   │
│                    │            │                      │
│ (Standard Ruby)    │            │ (Reproducible Nix)   │
└────────────────────┘            └──────────────────────┘
```

## Why --impure?

You need `--impure` **only** for SSH git sources:

```bash
# With private gems via SSH:
nix build --impure  # Allows SSH agent access

# With only public gems:
nix build           # Pure build, no --impure needed
```

The `--impure` flag:
- Allows access to `$SSH_AUTH_SOCK`
- Enables SSH authentication during fetch
- **Does NOT** make builds non-reproducible (hashes still verified!)

## Next Steps

1. Copy `flake.nix` to your project
2. Customize pname, version, entry point
3. Run `bundle lock && bundix -l`
4. Test: `nix build --impure`
5. Deploy to EC2 via NixOS configuration

## Support

- Check `QUICK_REFERENCE.md` for common commands
- See `SSH_PRIVATE_GEMS.md` for SSH troubleshooting
- Read `BUNDIX_WORKFLOW.md` for detailed workflow

## Success Criteria

You'll know it's working when:
- ✅ `nix build --impure` succeeds
- ✅ `./result/bin/your-utility` runs
- ✅ Private gems are accessible
- ✅ Ruby version matches `.ruby-version`
- ✅ Other developers can use `bundle install`
- ✅ Deployable to EC2 via NixOS

## Conclusion

This flake gives you:
- Reproducible Ruby environments
- SSH private gem support
- Bundler compatibility
- EC2 deployment capability
- Isolation from Ruby version conflicts

**Perfect for migrating AWS utilities from Ubuntu to NixOS!**
