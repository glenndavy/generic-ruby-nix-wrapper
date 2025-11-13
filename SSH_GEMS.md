# SSH-Only Private Gems

For environments where HTTPS is not an option and SSH is required for GitHub access.

## The Core Issue

- `bundlerEnv` doesn't handle git sources well, especially SSH
- Nix sandbox blocks network access during builds
- SSH authentication needs to happen during fetch, not build

## Solution: Package Each Private Gem as a Nix Derivation

### Step 1: Create private-gems.nix

```nix
# private-gems.nix
{ pkgs, lib, ruby }:

let
  # Helper function to build a gem from git
  buildGemFromGit = { pname, owner, repo, rev, sha256 }:
    pkgs.stdenv.mkDerivation {
      inherit pname;
      version = rev;

      src = pkgs.fetchgit {
        url = "git@github.com:${owner}/${repo}.git";
        inherit rev sha256;
        # fetchgit will use your SSH agent
      };

      nativeBuildInputs = [ ruby ];

      buildPhase = ''
        # Build the gem
        gem build *.gemspec
      '';

      installPhase = ''
        # Install to output directory
        export GEM_HOME=$out/lib/ruby/gems/${ruby.version}
        mkdir -p $GEM_HOME
        gem install --local --no-document --install-dir $GEM_HOME *.gem
      '';
    };

in {
  # Define each private gem
  yourorg-utils = buildGemFromGit {
    pname = "yourorg-utils";
    owner = "yourorg";
    repo = "yourorg-utils";
    rev = "v1.2.3";  # Use tag or commit SHA
    sha256 = lib.fakeSha256;  # Replace with real hash after first build
  };

  yourorg-aws = buildGemFromGit {
    pname = "yourorg-aws";
    owner = "yourorg";
    repo = "yourorg-aws";
    rev = "abc123def";  # Commit SHA
    sha256 = lib.fakeSha256;
  };
}
```

### Step 2: Update flake.nix

```nix
# In your flake.nix, after the gemEnv definition:

# Import private gems
privateGems = import ./private-gems.nix { inherit pkgs lib ruby; };

# Combine public gems (from Gemfile) with private gems
allGems = pkgs.buildEnv {
  name = "all-ruby-gems";
  paths = [
    gemEnv  # Public gems from bundlerEnv
    privateGems.yourorg-utils
    privateGems.yourorg-aws
  ];
  pathsToLink = [ "/lib" "/bin" ];
};
```

### Step 3: Use allGems instead of gemEnv

```nix
# In your wrapper script (wrappedApp):
installPhase = ''
  mkdir -p $out/bin
  cp -r . $out/lib

  cat > $out/bin/my-ruby-utility <<EOF
#!/bin/sh
export GEM_HOME="${allGems}/lib/ruby/gems/${ruby.version}"
export GEM_PATH="${allGems}/lib/ruby/gems/${ruby.version}"
exec ${ruby}/bin/ruby $out/lib/main.rb "\$@"
EOF

  chmod +x $out/bin/my-ruby-utility
'';
```

### Step 4: Your Gemfile - Public Gems Only

```ruby
# Gemfile - ONLY include public gems from rubygems.org
source 'https://rubygems.org'

gem 'thor'
gem 'httparty'
gem 'aws-sdk-ec2'

# DO NOT include private gems here!
# They're handled by private-gems.nix
```

### Step 5: Build Process

```bash
# 1. Ensure SSH agent is running with your key
eval $(ssh-agent)
ssh-add ~/.ssh/id_ed25519

# 2. Test SSH access
ssh -T git@github.com

# 3. First build (to get sha256)
nix build --impure
# It will fail and show you the correct sha256

# 4. Update private-gems.nix with the real sha256
# Replace lib.fakeSha256 with the hash Nix showed you

# 5. Build again
nix build --impure

# The --impure flag is needed for SSH access during fetch
```

## Why --impure is Needed

Nix needs `--impure` to access your SSH agent during the git fetch. This:
- Allows SSH authentication
- Uses your existing SSH keys
- Respects your SSH config

The build itself is still reproducible (hashes are verified), but the fetch needs SSH access.

## For Development Shell

```nix
devShells.default = pkgs.mkShell {
  buildInputs = [
    ruby
    bundler
    pkgs.git
    pkgs.openssh
  ] ++ pkgs.lib.optionals hasGemfile [ allGems ];  # Use allGems, not gemEnv

  shellHook = ''
    # Check SSH agent
    if [ -z "$SSH_AUTH_SOCK" ]; then
      echo "WARNING: No SSH agent detected!"
      echo "Run: eval \$(ssh-agent) && ssh-add"
      echo "Private gems will not be accessible without SSH."
    else
      echo "✓ SSH agent available"
    fi

    # Set up gem environment with ALL gems (public + private)
    export GEM_HOME="$PWD/.nix-gems"
    mkdir -p "$GEM_HOME"
    export GEM_PATH="${allGems}/lib/ruby/gems/${ruby.version}:$GEM_HOME"
    export PATH="$GEM_HOME/bin:${allGems}/bin:$PATH"

    # Rest of shellHook...
  '';
};
```

## Workflow

### When Updating a Private Gem

```bash
# 1. Note the new commit SHA or tag
cd /path/to/yourorg-utils
git log -1 --format=%H  # Get commit SHA

# 2. Update private-gems.nix
vim private-gems.nix
# Change rev to new SHA
# Set sha256 = lib.fakeSha256

# 3. Rebuild to get new hash
nix build --impure  # Will fail, shows correct hash

# 4. Update sha256 in private-gems.nix

# 5. Final build
nix build --impure
```

### For CI/CD

CI/CD needs SSH key access:

```yaml
# GitHub Actions example
- name: Setup SSH
  run: |
    mkdir -p ~/.ssh
    echo "${{ secrets.PRIVATE_GEM_SSH_KEY }}" > ~/.ssh/id_ed25519
    chmod 600 ~/.ssh/id_ed25519
    ssh-keyscan github.com >> ~/.ssh/known_hosts
    eval $(ssh-agent)
    ssh-add ~/.ssh/id_ed25519

- name: Build
  run: nix build --impure
```

## Alternative: Git Submodules (Simpler but Less Flexible)

If you want something simpler:

### Step 1: Add private gems as submodules

```bash
git submodule add git@github.com:yourorg/yourorg-utils.git vendor/yourorg-utils
git submodule add git@github.com:yourorg/yourorg-aws.git vendor/yourorg-aws
```

### Step 2: Reference local paths in Gemfile

```ruby
# Gemfile
source 'https://rubygems.org'

gem 'thor'
gem 'httparty'

# Private gems from submodules
gem 'yourorg-utils', path: 'vendor/yourorg-utils'
gem 'yourorg-aws', path: 'vendor/yourorg-aws'
```

### Step 3: Bundle and build

```bash
bundle lock
nix build  # No --impure needed!
```

**Pros:**
- ✅ No --impure flag needed
- ✅ bundlerEnv can handle local path gems
- ✅ Simpler workflow

**Cons:**
- ❌ Need to commit submodules
- ❌ Need to update submodules manually
- ❌ Increases repo size

## Comparison

| Approach | Pros | Cons | Best For |
|----------|------|------|----------|
| **Separate derivations** | Clean, versioned, flexible | Needs --impure, more complex | Production with versioned releases |
| **Git submodules** | Simple, works with bundlerEnv | Submodule management, repo bloat | Development, small teams |

## Recommendation

For AWS EC2 utilities:
1. **Start with git submodules** (simpler, gets you working quickly)
2. **Later migrate to separate derivations** if you need better version control

Both are SSH-only and don't require HTTPS.
