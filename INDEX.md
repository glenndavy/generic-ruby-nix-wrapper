# Documentation Index

Welcome! This repository provides a complete Nix flake template for Ruby applications with **SSH private gem support**.

## 🚀 Start Here

- **[SUMMARY.md](SUMMARY.md)** - Overview of the solution
- **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** - One-page cheat sheet

## 📖 Main Documentation

### Getting Started
- **[README.md](README.md)** - Main documentation
  - Features overview
  - Quick start guide
  - NixOS configuration examples
  - Customization examples

- **[TEMPLATE_USAGE.md](TEMPLATE_USAGE.md)** - How to copy and customize this template
  - Step-by-step customization
  - Real-world examples
  - Multiple utilities in one repo

### SSH Private Gems (Your Use Case!)
- **[SSH_PRIVATE_GEMS.md](SSH_PRIVATE_GEMS.md)** - **Complete SSH setup guide** ⭐
  - Example Gemfile with git sources
  - Complete workflow
  - CI/CD setup (GitHub Actions, GitLab)
  - EC2 deployment
  - Troubleshooting

- **[BUNDIX_WORKFLOW.md](BUNDIX_WORKFLOW.md)** - Detailed bundix workflow
  - Why bundix is needed
  - Daily development workflow
  - Updating gems
  - Helper script usage
  - When bundix needs help

### Understanding the System
- **[BUNDLER_WORKFLOW.md](BUNDLER_WORKFLOW.md)** - How bundlerEnv works
  - bundix vs bundlerEnv explained
  - Prefetching concept
  - Network access and sandbox
  - Best practices

- **[DEVSHELL.md](DEVSHELL.md)** - Development shell features
  - Ruby from .ruby-version
  - Bundler from Gemfile.lock
  - Gem binaries in PATH
  - Complete isolation

### Alternative Approaches (Historical)
- **[PRIVATE_GEMS.md](PRIVATE_GEMS.md)** - Other approaches to private gems
  - GitHub Packages (HTTPS)
  - Separate derivations
  - Comparison table

- **[SSH_FETCHER.md](SSH_FETCHER.md)** - Separate derivation approach
  - When you can't use bundix
  - Manual gem packaging

- **[SSH_GEMS.md](SSH_GEMS.md)** - Git submodules approach
  - Simpler but limited

- **[BUNDIX_GIT.md](BUNDIX_GIT.md)** - Early bundix exploration
  - How bundix handles git sources

## 🛠️ Tools

- **[update-gems.sh](update-gems.sh)** - Helper script for updating gems
  ```bash
  ./update-gems.sh           # Update Gemfile.lock + gemset.nix
  ./update-gems.sh gem-name  # Update specific gem
  ./update-gems.sh all       # Update all gems
  ```

## 📁 Files

### Core Files
- **[flake.nix](flake.nix)** - The main flake template (customize this!)
- **[.ruby-version](.ruby-version)** - Ruby version specification
- **[.gitignore](.gitignore)** - Git ignore rules

### Example Project
- **[example/](example/)** - Example Gemfile and main.rb

## 🎯 Quick Navigation by Task

### "I want to add private gems to my project"
→ Read [SSH_PRIVATE_GEMS.md](SSH_PRIVATE_GEMS.md)

### "I want to understand the workflow"
→ Read [BUNDIX_WORKFLOW.md](BUNDIX_WORKFLOW.md)

### "I want a quick command reference"
→ Read [QUICK_REFERENCE.md](QUICK_REFERENCE.md)

### "I want to copy this to my project"
→ Read [TEMPLATE_USAGE.md](TEMPLATE_USAGE.md)

### "I want to understand how it works"
→ Read [BUNDLER_WORKFLOW.md](BUNDLER_WORKFLOW.md)

### "I want to see what the dev shell does"
→ Read [DEVSHELL.md](DEVSHELL.md)

### "I want to deploy to EC2"
→ Read [README.md](README.md) section "Usage in NixOS Configuration"

### "I'm having problems with SSH"
→ Read [SSH_PRIVATE_GEMS.md](SSH_PRIVATE_GEMS.md) "Troubleshooting" section

### "bundix is failing"
→ Read [BUNDIX_WORKFLOW.md](BUNDIX_WORKFLOW.md) "When bundix Needs Help"

## 🔑 Key Concepts

### The Core Innovation
This flake uses **bundix** to convert `Gemfile.lock` → `gemset.nix`, which enables:
- SSH git sources in Gemfile
- Private gems via `git@github.com:...`
- Standard bundler workflow for non-Nix users
- Reproducible builds with hash verification

### The Workflow
```
Edit Gemfile → bundle lock → bundix -l → nix build --impure
```

### Why --impure?
The `--impure` flag allows access to your SSH agent during the fetch phase:
- SSH authentication for private repos
- Happens BEFORE sandbox build
- Build itself is still reproducible (hashes verified)

### Required Files
```
your-project/
├── flake.nix           # This template
├── .ruby-version       # Ruby version
├── Gemfile             # Gems (public + private)
├── Gemfile.lock        # bundle lock
├── gemset.nix          # bundix -l
└── (your code)
```

## 📚 Documentation by Audience

### For Ruby Developers New to Nix
1. [README.md](README.md) - Start here
2. [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Commands you need
3. [BUNDIX_WORKFLOW.md](BUNDIX_WORKFLOW.md) - Daily workflow

### For Nix Users New to Ruby
1. [BUNDLER_WORKFLOW.md](BUNDLER_WORKFLOW.md) - How bundler works
2. [README.md](README.md) - Features and usage
3. [DEVSHELL.md](DEVSHELL.md) - Development environment

### For DevOps / CI/CD
1. [SSH_PRIVATE_GEMS.md](SSH_PRIVATE_GEMS.md) - CI/CD setup section
2. [BUNDIX_WORKFLOW.md](BUNDIX_WORKFLOW.md) - Workflow details
3. [README.md](README.md) - Deployment examples

### For EC2 Deployment
1. [README.md](README.md) - NixOS configuration examples
2. [SSH_PRIVATE_GEMS.md](SSH_PRIVATE_GEMS.md) - EC2 deployment section
3. [SUMMARY.md](SUMMARY.md) - Overview

## 🎓 Learning Path

### Beginner
1. Read [SUMMARY.md](SUMMARY.md)
2. Read [QUICK_REFERENCE.md](QUICK_REFERENCE.md)
3. Try: Copy flake.nix, run `bundle lock && bundix -l && nix build`

### Intermediate
1. Read [BUNDIX_WORKFLOW.md](BUNDIX_WORKFLOW.md)
2. Read [SSH_PRIVATE_GEMS.md](SSH_PRIVATE_GEMS.md)
3. Set up SSH private gems in your project

### Advanced
1. Read [BUNDLER_WORKFLOW.md](BUNDLER_WORKFLOW.md)
2. Read [DEVSHELL.md](DEVSHELL.md)
3. Customize for multiple utilities, CI/CD, EC2 deployment

## 🐛 Troubleshooting

Common issues and where to find solutions:

| Issue | See |
|-------|-----|
| SSH agent not detected | [SSH_PRIVATE_GEMS.md](SSH_PRIVATE_GEMS.md) → Troubleshooting |
| bundix can't calculate hash | [BUNDIX_WORKFLOW.md](BUNDIX_WORKFLOW.md) → When bundix Needs Help |
| Hash mismatch during build | [SSH_PRIVATE_GEMS.md](SSH_PRIVATE_GEMS.md) → Troubleshooting |
| Gem not available at runtime | [BUNDIX_WORKFLOW.md](BUNDIX_WORKFLOW.md) → Troubleshooting |
| Native extension build fails | [BUNDLER_WORKFLOW.md](BUNDLER_WORKFLOW.md) → Common Error Messages |
| Permission denied (publickey) | [SSH_PRIVATE_GEMS.md](SSH_PRIVATE_GEMS.md) → Troubleshooting |

## 💡 Pro Tips

1. **Always commit gemset.nix** along with Gemfile.lock
2. **Use the helper script**: `./update-gems.sh` saves time
3. **Pin git sources**: Use tags/commits instead of branches
4. **Test locally first**: Before pushing to CI
5. **Use deploy keys**: Not personal SSH keys in CI/CD

## 🤝 For Your Team

### Non-Nix Developers
Tell them:
- "Use `bundle install` as normal"
- "Ignore all the Nix files"
- "Gemfile is the source of truth"

They don't need to know about Nix!

### Nix Users
Tell them:
- "Run `bundix -l` after updating Gemfile.lock"
- "Use `nix build --impure` for SSH gems"
- "SSH agent must be running"

## 📝 Original Brief

See [breif.md](breif.md) for the original project goals:
- Generic flake for Ruby projects
- Wrapper for Ruby applications
- NixOS module for declarative configuration
- Isolated environments (no version conflicts)

**Status**: ✅ All goals achieved + SSH private gem support!

## 🎉 Success Criteria

You're ready to deploy when:
- ✅ `nix build --impure` succeeds
- ✅ `./result/bin/your-utility` runs
- ✅ Private gems accessible via SSH
- ✅ Ruby version matches `.ruby-version`
- ✅ Other developers can use `bundle install`
- ✅ Deployable to EC2 via NixOS configuration

## 📮 Getting Help

1. Check [QUICK_REFERENCE.md](QUICK_REFERENCE.md) for common commands
2. Search the appropriate doc file (use this index!)
3. Check troubleshooting sections
4. Review [SSH_PRIVATE_GEMS.md](SSH_PRIVATE_GEMS.md) for SSH issues

## 🚀 Next Steps

1. Read [SUMMARY.md](SUMMARY.md) for overview
2. Copy [flake.nix](flake.nix) to your project
3. Follow [SSH_PRIVATE_GEMS.md](SSH_PRIVATE_GEMS.md) for setup
4. Deploy to EC2 using [README.md](README.md) examples

Good luck! 🎉
