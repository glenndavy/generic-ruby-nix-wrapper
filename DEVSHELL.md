# Development Shell Features

The development shell provided by this flake is fully isolated and configured for Ruby development.

## Features

### 1. ✅ Ruby from .ruby-version

The shell uses the exact Ruby version specified in your `.ruby-version` file:

```bash
$ cat .ruby-version
3.3.0

$ nix develop
Ruby version: 3.3.0
```

If no `.ruby-version` exists, it defaults to Ruby 3.3.0.

### 2. ✅ Bundler from Gemfile.lock

The shell automatically extracts and uses the bundler version from your `Gemfile.lock`:

```ruby
# From your Gemfile.lock:
BUNDLED WITH
   2.4.22
```

The shell will use bundler 2.4.22 exactly. If no `Gemfile.lock` exists, it uses the default bundler that comes with Ruby.

### 3. ✅ Gem Binaries in PATH

All gem executables are automatically available in your PATH:

```bash
$ nix develop
$ rspec --version    # If rspec is in your Gemfile
$ rubocop --version  # If rubocop is in your Gemfile
$ thor               # Any gem binary works
```

This includes:
- Gems from your `Gemfile` (built by Nix)
- Gems you install during development with `gem install`

### 4. ✅ Complete Isolation

Your development environment is isolated from:
- System Ruby
- System gems
- Other Ruby projects on your machine
- Global gem installations

#### Isolation Details

```bash
$ nix develop

Isolation:
  GEM_HOME:   /path/to/your/project/.nix-gems
  GEM_PATH:   /nix/store/...-ruby-gems/lib/ruby/gems/3.3.0:/path/to/your/project/.nix-gems
  Built gems: /nix/store/...-ruby-gems/lib/ruby/gems/3.3.0
```

**GEM_HOME**: `.nix-gems/` directory in your project root
- All gems installed during development go here
- Isolated per project
- Automatically created
- Gitignored

**GEM_PATH**: Two locations
1. Pre-built gems from `Gemfile.lock` (read-only in `/nix/store`)
2. Development gems in `.nix-gems/` (writable)

## Usage Examples

### Starting Development

```bash
# Enter the development shell
nix develop

# You'll see:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Ruby Development Environment
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Ruby version: 3.3.0
Ruby binary:  /nix/store/...-ruby-3.3.0/bin/ruby
Bundler:      2.4.22 (from Gemfile.lock)

Isolation:
  GEM_HOME:   /Users/you/project/.nix-gems
  GEM_PATH:   /nix/store/...-ruby-gems/lib/ruby/gems/3.3.0:/Users/you/project/.nix-gems
  Built gems: /nix/store/...-ruby-gems/lib/ruby/gems/3.3.0

All gem binaries are in PATH
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ruby 3.3.0 (2023-12-25 revision 5124f9ac75) [x86_64-darwin23]
Bundler version 2.4.22
```

### Running Your Application

```bash
$ nix develop
$ ruby main.rb
$ ./bin/your-utility
```

All gems from your Gemfile are available.

### Installing Additional Development Gems

```bash
$ nix develop

# Install a gem for experimentation
$ gem install pry

# It goes to .nix-gems/ (isolated)
$ which pry
/Users/you/project/.nix-gems/bin/pry

# Use it immediately
$ pry
```

This gem is isolated to this project and won't affect other projects or your system.

### Updating Dependencies

```bash
$ nix develop

# Update Gemfile
$ vim Gemfile

# Update lock file
$ bundle update

# Exit and re-enter to rebuild gem environment
$ exit
$ nix develop  # Nix rebuilds gems based on new Gemfile.lock
```

### Running Tests

```bash
$ nix develop
$ rspec spec/          # If using rspec
$ rake test            # If using rake
$ ruby test/test_*.rb  # Plain Ruby tests
```

### Bundler Commands

```bash
$ nix develop
$ bundle install  # Installs to .nix-gems/
$ bundle exec ruby main.rb
$ bundle exec rspec
```

## Without Gemfile (New Projects)

If you start a fresh project without a Gemfile:

```bash
$ nix develop

Ruby Development Environment
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Ruby version: 3.3.0
Ruby binary:  /nix/store/...-ruby-3.3.0/bin/ruby
Bundler:      default (no Gemfile.lock)

Isolation:
  GEM_HOME:   /Users/you/project/.nix-gems
  GEM_PATH:   /Users/you/project/.nix-gems
  No Gemfile found - run 'bundle init' to create one

# Create a Gemfile
$ bundle init
$ vim Gemfile  # Add your gems
$ bundle install
$ exit
$ nix develop  # Nix now builds your gems
```

## Direnv Integration

For automatic shell activation when entering the directory:

```bash
# Create .envrc
echo "use flake" > .envrc

# Allow direnv
direnv allow

# Now the shell activates automatically when you cd into the directory!
```

## Comparison with Traditional Ruby Development

### Traditional (Ubuntu)

```bash
# Gems get installed system-wide or in vendor/bundle
$ bundle install
$ bundle exec ruby main.rb

# Problems:
# - Ruby 3.1.0 gems might conflict with 3.1.2
# - System gems can interfere
# - Different projects share gem installations
```

### With This Flake

```bash
# Everything is isolated per project
$ nix develop
$ ruby main.rb  # Gems already available

# Benefits:
# - Each project has its own Ruby version
# - Each project has its own gems
# - Reproducible across machines
# - No conflicts between projects
```

## Verification

You can verify isolation by checking environment variables:

```bash
$ nix develop
$ echo $GEM_HOME
/Users/you/project/.nix-gems

$ echo $GEM_PATH
/nix/store/hash-ruby-gems/lib/ruby/gems/3.3.0:/Users/you/project/.nix-gems

$ gem env
RubyGems Environment:
  - RUBYGEMS VERSION: 3.5.3
  - RUBY VERSION: 3.3.0
  - INSTALLATION DIRECTORY: /Users/you/project/.nix-gems
  - USER INSTALLATION DIRECTORY: /Users/you/project/.nix-gems
  - GEM PATHS:
     - /nix/store/hash-ruby-gems/lib/ruby/gems/3.3.0
     - /Users/you/project/.nix-gems
```

## Common Workflows

### Daily Development

```bash
# Morning: enter shell
nix develop

# Work on code, run tests, etc
ruby main.rb
rspec spec/

# Evening: exit
exit
```

### Adding a New Gem

```bash
nix develop

# Add to Gemfile
echo 'gem "awesome_gem"' >> Gemfile

# Update lock
bundle update awesome_gem

# Exit and re-enter to rebuild
exit
nix develop

# Now awesome_gem is available
ruby -r awesome_gem -e 'puts AwesomeGem::VERSION'
```

### Working on Multiple Ruby Projects

```bash
# Project A: Ruby 3.2.0
cd ~/projects/project-a
nix develop
ruby --version  # 3.2.0

# Exit and switch to project B
exit
cd ~/projects/project-b
nix develop
ruby --version  # 3.3.0

# Each has its own isolated environment!
```

## Troubleshooting

### Gem binaries not found

If a gem binary isn't in PATH:
1. Make sure the gem is in your `Gemfile`
2. Exit and re-enter the shell: `exit` then `nix develop`
3. Check that `Gemfile.lock` is up to date: `bundle install`

### Wrong Ruby version

Check your `.ruby-version` file:
```bash
cat .ruby-version
```

Make sure it's a version available in [nixpkgs-ruby](https://github.com/bobvanderlinden/nixpkgs-ruby).

### Bundler version mismatch

The flake reads the bundler version from the `BUNDLED WITH` section at the end of `Gemfile.lock`:

```ruby
BUNDLED WITH
   2.4.22
```

If you need a different version:
```bash
gem install bundler:2.5.0
bundle update --bundler
```

Then exit and re-enter the shell.

### Gems from system interfering

This shouldn't happen due to isolation, but verify:
```bash
$ nix develop
$ gem env

# Check that INSTALLATION DIRECTORY points to .nix-gems/
# Check that GEM PATHS doesn't include system paths like /usr or /home/user/.gem
```

## Advanced: Custom Development Dependencies

If you need additional system packages in your dev shell (like databases, editors, etc.), edit the `devShells.default` section:

```nix
devShells.default = pkgs.mkShell {
  buildInputs = [
    ruby
    bundler

    # Add your tools here
    pkgs.postgresql
    pkgs.redis
    pkgs.sqlite
  ] ++ pkgs.lib.optionals hasGemfile [ gemEnv ];

  # ... rest of shellHook
```

## Summary

The development shell provides:
- ✅ **Ruby from `.ruby-version`** - Exact version control
- ✅ **Bundler from `Gemfile.lock`** - Reproducible bundler version
- ✅ **Gem binaries in PATH** - Direct access to all gem commands
- ✅ **Complete isolation** - No interference with system or other projects

This solves the Ruby version conflicts you experienced on Ubuntu and provides a reproducible development environment for your AWS utilities!
