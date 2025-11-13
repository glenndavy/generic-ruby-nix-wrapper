 Out of curiosity, how is the sha256 determined?

⏺ Great question! The sha256 is a hash of the entire source tree after it's been fetched and normalized by Nix.

  How Nix Calculates sha256

  Step-by-Step Process

  1. Fetch the source
     ↓
  2. Normalize it (remove .git, set timestamps, sort files)
     ↓
  3. Serialize to NAR (Nix Archive) format
     ↓
  4. Hash the NAR with SHA-256
     ↓
  5. Encode as base32 or base64

  What Gets Hashed

  NOT just the git commit SHA! The hash includes:

  - All file contents in the repository
  - File names and directory structure
  - File permissions (executable bit)
  - Normalized timestamps (all set to Unix epoch)

  Explicitly excluded:
  - .git directory (git metadata)
  - Other VCS directories (.svn, .hg, etc.)
  - Build outputs

  NAR Format

  NAR (Nix Archive) is Nix's own archive format that ensures:
  - Deterministic serialization
  - Platform-independent representation
  - Reproducible hashing

  Think of it like tar, but with guaranteed ordering and normalized metadata.

  Example Calculation

  # Using nix-prefetch-git
  nix-prefetch-git --url https://github.com/nixos/nixpkgs --rev nixos-23.11

  # What happens internally:
  # 1. git clone https://github.com/nixos/nixpkgs
  # 2. git checkout nixos-23.11
  # 3. Remove .git directory
  # 4. Normalize timestamps to 1970-01-01
  # 5. Serialize to NAR format
  # 6. sha256sum the NAR
  # 7. Encode to Nix hash format

  # Output:
  {
    "url": "https://github.com/nixos/nixpkgs",
    "rev": "nixos-23.11",
    "sha256": "sha256-abc123...",  # ← Hash of the NAR
    "path": "/nix/store/xyz-source"
  }

  Different Hash Formats

  Base32 (Legacy Nix)

  sha256 = "1a2b3c4d5e6f7g8h9i0j...";  # 32 characters, base32

  SRI (Subresource Integrity) - Modern

  sha256 = "sha256-ABCDEFGH1234567890+/==";  # base64 with "sha256-" prefix

  Nix automatically converts between formats.

  Why Not Just Use Git Commit SHA?

  Git commit SHA ≠ Content hash

  Git's SHA-1 hash includes:
  - Commit metadata (author, date, message)
  - Parent commit references
  - Tree objects
  - Blob objects

  Two different git repos with identical file contents can have different commit SHAs.

  Nix needs content-addressing, so it hashes the actual normalized file tree, not git metadata.

  Example

  # Two repos with identical files but different git history

  # Repo A
  git init
  echo "hello" > file.txt
  git add file.txt
  git commit -m "Add file"
  # Commit SHA: abc123...

  # Repo B
  git init
  echo "hello" > file.txt
  git add file.txt
  git commit -m "Initial commit"  # Different message
  # Commit SHA: def456...  ← Different!

  # But Nix sha256 would be THE SAME
  # Because file contents are identical

  Manual Calculation

  You can manually calculate what Nix would hash:

  # Clone repo
  git clone https://github.com/yourorg/repo.git
  cd repo
  git checkout v1.2.3

  # Remove .git
  rm -rf .git

  # Create NAR
  nix-store --dump . > repo.nar

  # Hash it
  nix-hash --type sha256 --base32 repo.nar
  # Output: abc123def456...

  # Or in SRI format
  nix-hash --type sha256 --sri repo.nar
  # Output: sha256-ABCDEFGH...==

  For Different Fetchers

  fetchurl (Simple File)

  src = fetchurl {
    url = "https://example.com/file.tar.gz";
    sha256 = "sha256-...";  # Hash of the downloaded file
  };

  Hash is literally sha256sum file.tar.gz.

  fetchgit (Git Repository)

  src = fetchgit {
    url = "https://github.com/org/repo.git";
    rev = "v1.2.3";
    sha256 = "sha256-...";  # Hash of NAR(normalized source tree)
  };

  Hash is NAR hash after removing .git and normalizing.

  fetchFromGitHub (Tarball Download)

  src = fetchFromGitHub {
    owner = "org";
    repo = "repo";
    rev = "v1.2.3";
    sha256 = "sha256-...";  # Hash of GitHub's generated tarball
  };

  GitHub generates a tarball on the fly. Hash is of that tarball (which is deterministic).

  Why Flakes Don't Need You to Provide It

  Flakes use fixed-output derivations with automatic hash calculation:

  1. First time: Fetch input
     ↓
  2. Calculate hash automatically
     ↓
  3. Store in flake.lock:
     {
       "narHash": "sha256-abc123...",
       "rev": "v1.2.3"
     }
     ↓
  4. Next time: Use cached version if hash matches

  The flake lock file tracks the hash, so you don't need to!

  Debugging Hash Mismatches

  Common scenario:

  src = fetchgit {
    url = "...";
    rev = "v1.2.3";
    sha256 = "sha256-OLDOLDOLD";  # Wrong hash
  };

  # Error:
  # hash mismatch in fixed-output derivation
  #   specified: sha256-OLDOLDOLD
  #        got: sha256-NEWNEWNEW

  What happened:
  1. Nix fetched the source
  2. Calculated actual hash: sha256-NEWNEWNEW
  3. Compared to your provided hash: sha256-OLDOLDOLD
  4. They don't match → error!

  Why it happens:
  - Upstream changed the tag (force-pushed)
  - You updated rev but not sha256
  - Fetcher behavior changed (e.g., GitHub tarball format)

  Fix: Use the hash from the error message:
  sha256 = "sha256-NEWNEWNEW";  # Copy from error

  Practical Tool: nix-prefetch

  # For git repos
  nix-prefetch-git https://github.com/org/repo.git --rev v1.2.3

  # For URLs
  nix-prefetch-url https://example.com/file.tar.gz

  # For GitHub specifically
  nix-prefetch-url --unpack https://github.com/org/repo/archive/v1.2.3.tar.gz

  These tools:
  1. Fetch the source
  2. Normalize it
  3. Calculate the NAR hash
  4. Output the hash in Nix format

  Summary

  How sha256 is determined:

  1. ✅ Fetch the source (git clone, download, etc.)
  2. ✅ Normalize (remove .git, set timestamps to epoch, sort)
  3. ✅ Serialize to NAR (Nix Archive) format
  4. ✅ Hash the NAR with SHA-256
  5. ✅ Encode as base32 or base64 with "sha256-" prefix

  Why it's needed:
  - Content-addressed storage
  - Reproducibility
  - Cache validity
  - Security (verify downloads)

  Why flakes are better:
  - Hash calculated automatically
  - Stored in flake.lock
  - You never see or manage it manually
  - Updates via nix flake lock --update-input

  The hash is NOT:
  - ❌ Git commit SHA
  - ❌ Just a checksum of a tarball
  - ❌ Anything git-specific

  It's a content hash of the normalized source tree in Nix's reproducible format!

> why then does bundix create different sha's for gems with c extensions on different pulls?

⏺ Excellent catch! This reveals a fundamental issue with bundix and gems with native extensions.

  The Problem

  Gems with C extensions (native code) can have platform-specific build artifacts that get included in the gem, making the hash different across builds/platforms.

  But there's more to it...

  Why bundix Generates Different Hashes

  1. Timestamp Differences in Gem Archives

  When you run bundle install, bundler downloads .gem files from RubyGems.org. These are actually tar archives containing:
  - Ruby source files
  - C extension source
  - Gemspec metadata
  - Timestamps (file modification times)

  Even though Nix should normalize timestamps, bundix might be hashing the gem before Nix normalization happens.

  # First bundix run
  bundix -l
  # gem 'pg' -> sha256-AAAA...

  # Delete gemset.nix, run again
  rm gemset.nix
  bundix -l
  # gem 'pg' -> sha256-BBBB...  ← Different!

  2. Bundix Fetching vs Nix Fetching

  bundix has its own fetching logic that might not be using Nix's normalized fetchers:

  # bundix (simplified)
  # 1. Downloads gem from rubygems.org
  # 2. Calculates hash of downloaded .gem file
  # 3. Writes to gemset.nix

  # The .gem file might have varying metadata

  vs

  # What bundlerEnv does later
  fetchurl {
    url = "https://rubygems.org/downloads/pg-1.5.0.gem";
    sha256 = "...";  # From gemset.nix
  }

  If bundix calculates the hash differently than Nix's fetchurl, you get mismatches.

  3. RubyGems API Responses Can Vary

  RubyGems.org serves gems through a CDN that might:
  - Add/change HTTP headers
  - Compress differently
  - Include different metadata in the response

  4. Network Timing / CDN Issues

  If bundix fetches from different CDN nodes or during an upload/replication window, you might get slightly different files.

  Real-World Example

  # Clean slate
  rm -rf ~/.bundle Gemfile.lock gemset.nix

  # First attempt
  bundle lock
  bundix -l

  # gemset.nix shows:
  pg = {
    version = "1.5.0";
    source = {
      sha256 = "1abc...";
    };
  };

  # Delete and try again
  rm gemset.nix
  bundix -l

  # gemset.nix shows:
  pg = {
    version = "1.5.0";
    source = {
      sha256 = "2def...";  # ← Different!
    };
  };

  Why This Is a Problem

  When you have gems with C extensions in gemset.nix with hash A, then someone else runs bundix -l and gets hash B:

  1. They commit gemset.nix with hash B
  2. Your build fails because Nix has the gem cached with hash A
  3. Hash mismatch error!

  error: hash mismatch in fixed-output derivation '/nix/store/...-pg-1.5.0.gem':
    specified: sha256-2def...
         got: sha256-1abc...

  Solutions

  Solution 1: Don't Re-run bundix Unnecessarily

  # Only run bundix when Gemfile.lock actually changes
  git diff Gemfile.lock

  # If Gemfile.lock hasn't changed, don't run bundix

  Once gemset.nix is generated and committed, don't regenerate it unless dependencies changed.

  Solution 2: Use nix-prefetch-url for Gems

  Manually fix the hash using Nix's own fetcher:

  # Get the correct hash using Nix
  nix-prefetch-url https://rubygems.org/downloads/pg-1.5.0.gem

  # Update gemset.nix with this hash

  This ensures the hash matches what bundlerEnv will calculate.

  Solution 3: Lock gemset.nix in Git

  Treat gemset.nix as generated code that should be committed:

  # One person generates it
  bundix -l
  git add gemset.nix
  git commit -m "Update gemset.nix"

  # Everyone else uses the committed version
  # Don't regenerate unless Gemfile.lock changes

  Solution 4: Use --lockfile Flag (if available)

  Some versions of bundix have options to use Gemfile.lock's checksums, but this isn't always reliable.

  Solution 5: Pin bundix Version

  Different versions of bundix might calculate hashes differently:

  # In your flake.nix devShell
  pkgs.bundix  # Uses whatever nixpkgs provides

  # Or pin specific version
  (pkgs.bundix.overrideAttrs (old: {
    version = "2.5.0";  # Specific version
  }))

  Why C Extension Gems Are Particularly Problematic

  Pure Ruby Gem (Stable)

  thor-1.3.0.gem
  ├── lib/thor.rb
  ├── lib/thor/command.rb
  └── thor.gemspec

  Same files, same timestamps (after normalization), same hash.

  C Extension Gem (Unstable)

  pg-1.5.0.gem
  ├── lib/pg.rb
  ├── ext/pg.c              ← C source
  ├── ext/pg.h
  ├── ext/extconf.rb        ← Build config (can vary)
  └── pg.gemspec

  The .gem archive might include:
  - Different build metadata
  - Platform-specific detection code
  - Varying timestamps in ext/ directory

  The Root Cause

  bundix is using different hash calculation than Nix's fetchurl:

  # bundix calculates hash like this (pseudocode)
  def calculate_hash(gem_file)
    Digest::SHA256.hexdigest(File.read(gem_file))
  end

  vs

  # Nix's fetchurl does this
  1. Download file
  2. Store in /nix/store
  3. Create NAR from store path
  4. Hash the NAR

  These can produce different hashes even for the same gem file!

  Verification

  You can verify this yourself:

  # Download a gem directly
  curl -L https://rubygems.org/downloads/pg-1.5.0.gem > pg.gem

  # Hash it directly (what bundix might do)
  sha256sum pg.gem
  # Output: abc123...

  # Hash it the Nix way
  nix-prefetch-url file://$(pwd)/pg.gem
  # Output: def456...  ← Different!

  The difference is because Nix:
  1. Copies to /nix/store
  2. Normalizes permissions
  3. Creates NAR
  4. Hashes NAR

  Whereas sha256sum just hashes the file directly.

  Best Practice

  For Your Team

  1. One person runs bundix
  bundle lock
  bundix -l
  git add Gemfile.lock gemset.nix
  git commit
  2. Everyone else just pulls
  git pull
  nix build --impure  # Uses committed gemset.nix
  3. Only regenerate when dependencies change
  # Only if you edited Gemfile or updated gems
  bundle update some-gem
  bundix -l
  git add Gemfile.lock gemset.nix
  git commit
  4. If you get hash mismatch:
  # Clear Nix cache for that gem
  nix-store --delete /nix/store/*-pg-1.5.0.gem

  # Rebuild
  nix build --impure

  Alternative: Use bundlerEnv Without gemset.nix

  For only public gems (no git sources), you can skip bundix entirely:

  gemEnv = pkgs.bundlerEnv {
    name = "ruby-app-gems";
    inherit ruby;
    gemdir = ./.;
    # No gemset.nix!
    # bundlerEnv will read Gemfile.lock directly
  };

  But this doesn't work for git sources, which is why you need bundix in the first place.

  Summary

  Why bundix creates different hashes:

  1. ✅ Timing/CDN differences - RubyGems.org serves slightly different files
  2. ✅ Different hash calculation - bundix hashes differently than Nix's fetchurl
  3. ✅ Metadata variance - Gem archives can have varying timestamps/metadata
  4. ✅ C extension gems - More complex builds = more variation points

  What to do:

  - ✅ Commit gemset.nix to git
  - ✅ Don't regenerate unnecessarily
  - ✅ Only one person runs bundix per update
  - ✅ If hash mismatch, use the hash from Nix's error message
  - ✅ Consider using nix-prefetch-url for manual hash verification

  The real issue: bundix is a separate tool with its own fetching/hashing logic that doesn't perfectly align with Nix's. This is a known rough edge in the Ruby/Nix ecosystem!

> any reason we can't replace bundix with a tool that fetchs nix-prefetch*  to generate a correct gemset.nix ?

⏺ Absolutely not - that's a GREAT idea! And you're right that it would solve the hash consistency problem.

  In fact, this should probably be what bundix does internally. Let me explore this:

  Why This Would Work Better

  Current bundix (Problematic)

  # bundix calculates hash itself
  def gem_hash(gem_path)
    Digest::SHA256.hexdigest(File.read(gem_path))
  end

  Better Approach (Use Nix's Fetchers)

  # For each gem in Gemfile.lock:

  # Public gem
  nix-prefetch-url https://rubygems.org/downloads/thor-1.3.0.gem

  # Git source
  nix-prefetch-git git@github.com:org/private-gem.git --rev abc123

  This guarantees the hash matches what Nix will calculate!

  A Better bundix Alternative

  Let me sketch out what this would look like:

  #!/usr/bin/env bash
  # bundix-ng (Next Generation)
  # Generates gemset.nix using Nix's own prefetch tools

  set -e

  if [ ! -f Gemfile.lock ]; then
    echo "Error: Gemfile.lock not found"
    exit 1
  fi

  echo "Generating gemset.nix using nix-prefetch tools..."
  echo "{" > gemset.nix

  # Parse Gemfile.lock (simplified - would need proper parser)
  while IFS= read -r line; do
    # Detect gem entries
    if [[ $line =~ ^[[:space:]]+([a-z0-9_-]+)[[:space:]]\(([0-9.]+)\) ]]; then
      gem_name="${BASH_REMATCH[1]}"
      gem_version="${BASH_REMATCH[2]}"

      echo "Processing $gem_name $gem_version..."

      # Use nix-prefetch-url for RubyGems.org gems
      hash=$(nix-prefetch-url "https://rubygems.org/downloads/${gem_name}-${gem_version}.gem" 2>/dev/null)

      # Write to gemset.nix
      cat >> gemset.nix <<EOF
    "$gem_name" = {
      version = "$gem_version";
      source = {
        remotes = ["https://rubygems.org"];
        sha256 = "$hash";
        type = "gem";
      };
    };
  EOF
    fi

    # Detect git sources
    if [[ $line =~ remote:[[:space:]]+(.*) ]]; then
      git_url="${BASH_REMATCH[1]}"
      # Next line should have revision
      read -r next_line
      if [[ $next_line =~ revision:[[:space:]]+(.*) ]]; then
        git_rev="${BASH_REMATCH[1]}"

        echo "Processing git source $git_url @ $git_rev..."

        # Use nix-prefetch-git
        hash=$(nix-prefetch-git --url "$git_url" --rev "$git_rev" --quiet | jq -r .sha256)

        # Write git source to gemset.nix
        cat >> gemset.nix <<EOF
    "$gem_name" = {
      source = {
        type = "git";
        url = "$git_url";
        rev = "$git_rev";
        sha256 = "$hash";
      };
    };
  EOF
      fi
    fi
  done < Gemfile.lock

  echo "}" >> gemset.nix
  echo "Done! gemset.nix generated with Nix-consistent hashes."

  Proper Implementation

  A real implementation would need:

  1. Proper Gemfile.lock Parser

  # Use Nix to parse Gemfile.lock
  { pkgs }:

  let
    # Parse Gemfile.lock
    lockfile = builtins.fromTOML (builtins.readFile ./Gemfile.lock);
    # Actually Gemfile.lock isn't TOML, would need proper parser

    # Or use Ruby to parse it
    parsedLock = pkgs.runCommand "parse-lock" {
      buildInputs = [ pkgs.ruby ];
    } ''
      ruby -e '
        require "bundler"
        lockfile = Bundler::LockfileParser.new(File.read("${./Gemfile.lock}"))

        lockfile.specs.each do |spec|
          puts "#{spec.name}|#{spec.version}|#{spec.source}"
        end
      ' > $out
    '';
  in
    parsedLock

  2. Call nix-prefetch-url for Each Gem

  generateGemsetNix = pkgs.writeShellScript "generate-gemset" ''
    ${pkgs.bundler}/bin/bundle lock --print | \
    ${pkgs.ruby}/bin/ruby ${./parse-gemfile.rb} | \
    while IFS='|' read -r name version source_type source_url; do
      if [ "$source_type" = "rubygems" ]; then
        hash=$(${pkgs.nix}/bin/nix-prefetch-url \
          "https://rubygems.org/downloads/$name-$version.gem")

        echo "  \"$name\" = {"
        echo "    version = \"$version\";"
        echo "    source = {"
        echo "      remotes = [\"https://rubygems.org\"];"
        echo "      sha256 = \"$hash\";"
        echo "      type = \"gem\";"
        echo "    };"
        echo "  };"
      elif [ "$source_type" = "git" ]; then
        result=$(${pkgs.nix}/bin/nix-prefetch-git --url "$source_url" --quiet)
        hash=$(echo "$result" | ${pkgs.jq}/bin/jq -r .sha256)
        rev=$(echo "$result" | ${pkgs.jq}/bin/jq -r .rev)

        echo "  \"$name\" = {"
        echo "    source = {"
        echo "      type = \"git\";"
        echo "      url = \"$source_url\";"
        echo "      rev = \"$rev\";"
        echo "      sha256 = \"$hash\";"
        echo "    };"
        echo "  };"
      fi
    done
  '';

  3. Integration with Your Flake

  # flake.nix
  {
    outputs = { self, nixpkgs, ... }:
      let
        pkgs = nixpkgs.legacyPackages.x86_64-linux;

        # Better bundix using nix-prefetch
        bundix-ng = pkgs.writeShellScriptBin "bundix-ng" ''
          ${./generate-gemset.sh}
        '';
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            bundix-ng  # Use this instead of bundix
          ];
        };
      };
  }

  Why This Isn't Already Done

  Good question! Some reasons:

  1. bundix Predates Modern Nix

  bundix was written before nix-prefetch-* tools were as mature. It made sense at the time to calculate hashes directly.

  2. Performance

  Calling nix-prefetch-url for every gem is slower:
  # bundix (fast)
  - Downloads all gems once
  - Calculates hashes directly
  - ~10 seconds for 50 gems

  # nix-prefetch approach (slower)
  - Spawns nix-prefetch-url 50 times
  - Each prefetch downloads the gem
  - ~60 seconds for 50 gems

  3. Dependency on Nix

  bundix is a Ruby gem that can run anywhere. Using nix-prefetch-* requires Nix to be installed.

  4. Nobody Fixed It

  Classic open source problem - everyone knows about the issue, but it's "good enough" so nobody prioritized fixing it.

  What You Could Do

  Option 1: Write bundix-ng

  Create a proper replacement:

  # bundix-ng
  #!/usr/bin/env bash
  # Better bundix that uses nix-prefetch-* for correct hashes

  # ... implementation ...

  Publish it, document why it's better, get adoption.

  Option 2: Contribute to bundix

  Submit a PR to bundix to use nix-prefetch-* internally:
  - https://github.com/nix-community/bundix

  Option 3: Use Nix to Generate gemset.nix

  Instead of a separate tool, do it in your flake:

  {
    outputs = { self, nixpkgs, ... }:
      let
        pkgs = nixpkgs.legacyPackages.x86_64-linux;

        # Auto-generate gemset.nix from Gemfile.lock
        gemset = pkgs.runCommand "gemset.nix" {
          buildInputs = [ pkgs.bundler pkgs.nix pkgs.jq ];
        } ''
          # Parse Gemfile.lock and generate gemset.nix
          # using nix-prefetch-url for each gem
          ${./generate-gemset.sh} > $out
        '';

        gemEnv = pkgs.bundlerEnv {
          name = "ruby-app-gems";
          inherit ruby;
          gemdir = ./.;
          gemset = gemset;  # Use generated file
        };
      in
      {
        packages.default = gemEnv;
      };
  }

  Option 4: Hash Verification Script

  Add to your workflow:

  #!/usr/bin/env bash
  # verify-gemset.sh - Verify gemset.nix hashes match Nix's calculation

  for gem in $(jq -r 'keys[]' gemset.nix); do
    version=$(jq -r ".[\"$gem\"].version" gemset.nix)
    expected_hash=$(jq -r ".[\"$gem\"].source.sha256" gemset.nix)

    actual_hash=$(nix-prefetch-url "https://rubygems.org/downloads/$gem-$version.gem")

    if [ "$expected_hash" != "$actual_hash" ]; then
      echo "MISMATCH: $gem-$version"
      echo "  Expected: $expected_hash"
      echo "  Actual:   $actual_hash"
    fi
  done

  Practical Solution for Now

  Until someone builds bundix-ng, here's a workaround:

  #!/usr/bin/env bash
  # fix-gemset-hashes.sh
  # Re-calculate hashes using nix-prefetch-url

  while IFS= read -r line; do
    if [[ $line =~ \"([a-z0-9_-]+)\"[[:space:]]*=[[:space:]]*\{ ]]; then
      gem_name="${BASH_REMATCH[1]}"
    elif [[ $line =~ version[[:space:]]*=[[:space:]]*\"([0-9.]+)\" ]]; then
      gem_version="${BASH_REMATCH[1]}"
    elif [[ $line =~ sha256[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
      old_hash="${BASH_REMATCH[1]}"

      # Calculate correct hash
      echo "Verifying $gem_name $gem_version..."
      correct_hash=$(nix-prefetch-url "https://rubygems.org/downloads/${gem_name}-${gem_version}.gem" 2>/dev/null)

      if [ "$old_hash" != "$correct_hash" ]; then
        echo "  Fixing hash: $old_hash -> $correct_hash"
        sed -i "s|sha256 = \"$old_hash\"|sha256 = \"$correct_hash\"|" gemset.nix
      fi
    fi
  done < gemset.nix

  Summary

  Yes, you're absolutely right!

  ✅ Using nix-prefetch- would solve the hash inconsistency*
  ✅ It's technically feasible
  ✅ It would be more correct

  Why it hasn't been done:
  - ⚠️ Performance (slower)
  - ⚠️ Requires Nix to be installed
  - ⚠️ Nobody has prioritized it

  What you can do:
  1. Write bundix-ng using nix-prefetch tools
  2. Contribute to bundix to use nix-prefetch internally
  3. Use a hash-fixing script as a workaround
  4. Generate gemset.nix directly in your flake

  This would be a great contribution to the Nix/Ruby ecosystem! The current bundix hash inconsistency is a real pain point that many people have encountered.
