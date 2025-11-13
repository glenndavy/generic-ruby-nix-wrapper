I would like to 'capture' the sha256 of a source, and store in in a database, so that I can find the cached build for a given git reference.  How would I capture the sha?

⏺ Great question! You want to capture the NAR hash that Nix will use for caching, so you can look up builds by git reference later.

  The Hash You Need

  You need the NAR hash (also called narHash in flakes), not the git commit SHA. This is what Nix uses for /nix/store paths.

  How to Capture It

  Option 1: From flake.lock (Easiest for Flakes)

  # After nix flake lock
  cat flake.lock | jq -r '.nodes["my-app"].locked.narHash'
  # Output: sha256-abc123...

  # Store in database:
  # git_ref=v2.0.0, nar_hash=sha256-abc123..., store_path=/nix/store/xyz-source

  The flake.lock contains exactly what you need:

  {
    "nodes": {
      "my-app": {
        "locked": {
          "narHash": "sha256-abc123...",  // ← This is what you want!
          "lastModified": 1699876543,
          "rev": "abc123def456",           // Git commit SHA
          "ref": "v2.0.0",                 // Git tag/branch
          "type": "git",
          "url": "git@github.com:org/app.git"
        }
      }
    }
  }

  Option 2: Using nix-prefetch-git

  # Prefetch and capture the hash
  result=$(nix-prefetch-git --url git@github.com:org/app.git --rev v2.0.0 --quiet)

  # Extract values
  nar_hash=$(echo "$result" | jq -r .sha256)
  git_rev=$(echo "$result" | jq -r .rev)
  store_path=$(echo "$result" | jq -r .path)

  # Store in database
  echo "INSERT INTO builds (git_ref, git_rev, nar_hash, store_path) VALUES ('v2.0.0', '$git_rev', '$nar_hash', '$store_path');"

  Output looks like:
  {
    "url": "git@github.com:org/app.git",
    "rev": "abc123def456789",
    "date": "2024-01-15T10:30:00Z",
    "path": "/nix/store/xyz123-source",
    "sha256": "sha256-ABCDEF123456...",
    "fetchSubmodules": false,
    "deepClone": false,
    "leaveDotGit": false
  }

  Option 3: From Nix Build Output

  # Build and capture info
  nix build .#my-app --json | jq -r '.[0].drvPath'

  # Or get the source derivation
  nix eval --raw .#my-app.src.narHash
  # Output: sha256-abc123...

  Option 4: Calculate Without Building

  # Just fetch the source and get its hash
  nix-instantiate --eval -E '
    let
      pkgs = import <nixpkgs> {};
      src = pkgs.fetchgit {
        url = "git@github.com:org/app.git";
        rev = "v2.0.0";
        sha256 = ""; # Will fail and show you the hash
      };
    in
      builtins.toString src
  '

  This will error with the correct hash, which you can parse.

  Complete Build Tracking System

  Here's a complete example of tracking builds by git reference:

  Database Schema

  CREATE TABLE build_cache (
      id SERIAL PRIMARY KEY,
      repo_url TEXT NOT NULL,
      git_ref TEXT NOT NULL,      -- Tag, branch, or "main"
      git_rev TEXT NOT NULL,       -- Actual commit SHA
      nar_hash TEXT NOT NULL,      -- Nix NAR hash (for cache lookup)
      store_path TEXT NOT NULL,    -- /nix/store/xyz-source
      built_at TIMESTAMP DEFAULT NOW(),
      UNIQUE(repo_url, git_ref, git_rev)
  );

  CREATE INDEX idx_nar_hash ON build_cache(nar_hash);
  CREATE INDEX idx_git_ref ON build_cache(repo_url, git_ref);

  Capture Script

  #!/usr/bin/env bash
  # capture-build.sh - Record git ref -> nar hash mapping

  REPO_URL=$1
  GIT_REF=$2
  DB_CONN="postgresql://user:pass@localhost/builds"

  echo "Fetching $REPO_URL @ $GIT_REF..."

  # Use nix-prefetch-git to get all the info
  result=$(nix-prefetch-git --url "$REPO_URL" --rev "$GIT_REF" --quiet)

  # Extract values
  nar_hash=$(echo "$result" | jq -r .sha256)
  git_rev=$(echo "$result" | jq -r .rev)
  store_path=$(echo "$result" | jq -r .path)

  echo "Captured:"
  echo "  Git commit: $git_rev"
  echo "  NAR hash:   $nar_hash"
  echo "  Store path: $store_path"

  # Store in database
  psql "$DB_CONN" <<EOF
  INSERT INTO build_cache (repo_url, git_ref, git_rev, nar_hash, store_path)
  VALUES ('$REPO_URL', '$GIT_REF', '$git_rev', '$nar_hash', '$store_path')
  ON CONFLICT (repo_url, git_ref, git_rev) DO UPDATE
    SET nar_hash = EXCLUDED.nar_hash,
        store_path = EXCLUDED.store_path,
        built_at = NOW();
  EOF

  echo "Stored in database!"

  Usage:
  ./capture-build.sh "git@github.com:org/rails-app.git" "v2.0.0"
  ./capture-build.sh "git@github.com:org/rails-app.git" "production"
  ./capture-build.sh "git@github.com:org/rails-app.git" "staging"

  Lookup Script

  #!/usr/bin/env bash
  # lookup-build.sh - Find cached build by git ref

  REPO_URL=$1
  GIT_REF=$2
  DB_CONN="postgresql://user:pass@localhost/builds"

  echo "Looking up build for $REPO_URL @ $GIT_REF..."

  result=$(psql "$DB_CONN" -t -c "
    SELECT git_rev, nar_hash, store_path, built_at
    FROM build_cache
    WHERE repo_url = '$REPO_URL' AND git_ref = '$GIT_REF'
    ORDER BY built_at DESC
    LIMIT 1;
  ")

  if [ -n "$result" ]; then
    echo "Found cached build:"
    echo "$result"

    # Extract store path
    store_path=$(echo "$result" | awk '{print $3}')

    # Check if it's still in the Nix store
    if [ -e "$store_path" ]; then
      echo "✓ Build still in Nix store: $store_path"
    else
      echo "✗ Build not in Nix store (garbage collected)"
    fi
  else
    echo "No cached build found"
  fi

  Integration with Deployment

  #!/usr/bin/env bash
  # deploy.sh - Deploy using cached build if available

  REPO_URL="git@github.com:org/rails-app.git"
  GIT_REF=$1
  INSTANCE=$2

  # Check if we have a cached build
  cached=$(psql "$DB_CONN" -t -c "
    SELECT nar_hash, store_path
    FROM build_cache
    WHERE repo_url = '$REPO_URL' AND git_ref = '$GIT_REF'
    ORDER BY built_at DESC
    LIMIT 1;
  ")

  if [ -n "$cached" ]; then
    nar_hash=$(echo "$cached" | awk '{print $1}')
    store_path=$(echo "$cached" | awk '{print $2}')

    echo "Found cached build with NAR hash: $nar_hash"

    if [ -e "$store_path" ]; then
      echo "Using cached build from: $store_path"
      # Deploy using the cached build
    else
      echo "Cached build was garbage collected, fetching fresh..."
      ./capture-build.sh "$REPO_URL" "$GIT_REF"
    fi
  else
    echo "No cached build, fetching..."
    ./capture-build.sh "$REPO_URL" "$GIT_REF"
  fi

  # Deploy
  ssh "$INSTANCE" "nixos-rebuild switch --flake github:org/infrastructure#$INSTANCE"

  Automated Tracking with Flakes

  Hook into flake.lock Updates

  #!/usr/bin/env bash
  # post-flake-lock.sh - Run after nix flake lock

  # Extract all input hashes from flake.lock
  jq -r '.nodes | to_entries[] |
    select(.value.locked.narHash) |
    [.key, .value.locked.ref // .value.locked.rev, .value.locked.rev, .value.locked.narHash, .value.locked.url] |
    @tsv' flake.lock | \
  while IFS=$'\t' read -r name ref rev nar_hash url; do
    echo "Recording: $name @ $ref -> $nar_hash"

    psql "$DB_CONN" <<EOF
      INSERT INTO build_cache (repo_url, git_ref, git_rev, nar_hash, store_path)
      VALUES ('$url', '$ref', '$rev', '$nar_hash', 'unknown')
      ON CONFLICT (repo_url, git_ref, git_rev) DO UPDATE
        SET nar_hash = EXCLUDED.nar_hash;
  EOF
  done

  Add to your workflow:
  # Update flake
  nix flake lock --update-input rails-app

  # Capture hashes
  ./post-flake-lock.sh

  # Commit
  git add flake.lock
  git commit -m "Update rails-app to v2.0.0"

  Using Nix Store as the Database

  Actually, Nix already has this info! You can query it:

  # Find all sources in the store
  nix-store --query --requisites /nix/store/*-myapp* | grep source

  # Get info about a store path
  nix-store --query --hash /nix/store/xyz-source
  # Output: sha256:abc123...

  # Find what depends on a source
  nix-store --query --referrers /nix/store/xyz-source

  Query Nix Store Directly

  #!/usr/bin/env bash
  # find-in-store.sh - Find builds in Nix store by NAR hash

  NAR_HASH=$1

  # Search Nix store SQLite database
  nix-store --query --all | while read path; do
    hash=$(nix-store --query --hash "$path" 2>/dev/null || echo "")
    if [ "$hash" = "sha256:${NAR_HASH#sha256-}" ]; then
      echo "Found: $path"
      nix-store --query --deriver "$path"
    fi
  done

  Production-Ready Solution

  Combining everything:

  #!/usr/bin/env python3
  # build-tracker.py - Track and lookup Nix builds

  import subprocess
  import json
  import sys
  from datetime import datetime
  import psycopg2

  class BuildTracker:
      def __init__(self, db_url):
          self.conn = psycopg2.connect(db_url)
          self._init_db()

      def _init_db(self):
          with self.conn.cursor() as cur:
              cur.execute("""
                  CREATE TABLE IF NOT EXISTS build_cache (
                      id SERIAL PRIMARY KEY,
                      repo_url TEXT NOT NULL,
                      git_ref TEXT NOT NULL,
                      git_rev TEXT NOT NULL,
                      nar_hash TEXT NOT NULL,
                      store_path TEXT,
                      captured_at TIMESTAMP DEFAULT NOW(),
                      UNIQUE(repo_url, git_ref, git_rev)
                  );
                  CREATE INDEX IF NOT EXISTS idx_nar_hash ON build_cache(nar_hash);
                  CREATE INDEX IF NOT EXISTS idx_git_ref ON build_cache(repo_url, git_ref);
              """)
              self.conn.commit()

      def capture(self, repo_url, git_ref):
          """Capture build info for a git reference"""
          print(f"Capturing {repo_url} @ {git_ref}...")

          # Use nix-prefetch-git
          result = subprocess.run(
              ['nix-prefetch-git', '--url', repo_url, '--rev', git_ref, '--quiet'],
              capture_output=True,
              text=True
          )

          data = json.loads(result.stdout)

          with self.conn.cursor() as cur:
              cur.execute("""
                  INSERT INTO build_cache (repo_url, git_ref, git_rev, nar_hash, store_path)
                  VALUES (%s, %s, %s, %s, %s)
                  ON CONFLICT (repo_url, git_ref, git_rev) DO UPDATE
                      SET nar_hash = EXCLUDED.nar_hash,
                          store_path = EXCLUDED.store_path,
                          captured_at = NOW()
                  RETURNING id
              """, (repo_url, git_ref, data['rev'], data['sha256'], data['path']))

              self.conn.commit()
              print(f"✓ Stored: {data['rev'][:8]} -> {data['sha256'][:16]}...")

          return data

      def lookup(self, repo_url, git_ref):
          """Lookup cached build by git reference"""
          with self.conn.cursor() as cur:
              cur.execute("""
                  SELECT git_rev, nar_hash, store_path, captured_at
                  FROM build_cache
                  WHERE repo_url = %s AND git_ref = %s
                  ORDER BY captured_at DESC
                  LIMIT 1
              """, (repo_url, git_ref))

              result = cur.fetchone()

              if result:
                  return {
                      'git_rev': result[0],
                      'nar_hash': result[1],
                      'store_path': result[2],
                      'captured_at': result[3]
                  }
              return None

      def lookup_by_hash(self, nar_hash):
          """Find all git refs that map to a NAR hash"""
          with self.conn.cursor() as cur:
              cur.execute("""
                  SELECT repo_url, git_ref, git_rev, store_path, captured_at
                  FROM build_cache
                  WHERE nar_hash = %s
                  ORDER BY captured_at DESC
              """, (nar_hash,))

              return cur.fetchall()

  if __name__ == '__main__':
      tracker = BuildTracker("postgresql://localhost/builds")

      if sys.argv[1] == 'capture':
          tracker.capture(sys.argv[2], sys.argv[3])
      elif sys.argv[1] == 'lookup':
          result = tracker.lookup(sys.argv[2], sys.argv[3])
          print(json.dumps(result, indent=2, default=str))
      elif sys.argv[1] == 'lookup-hash':
          results = tracker.lookup_by_hash(sys.argv[2])
          for r in results:
              print(f"{r[0]} @ {r[1]} -> {r[2][:8]}")

  Usage:
  # Capture a build
  ./build-tracker.py capture "git@github.com:org/app.git" "v2.0.0"

  # Look up by git ref
  ./build-tracker.py lookup "git@github.com:org/app.git" "v2.0.0"

  # Find what git refs map to a NAR hash
  ./build-tracker.py lookup-hash "sha256-abc123..."

  Summary

  To capture the NAR hash for a git reference:

  1. ✅ Use nix-prefetch-git (most reliable)
  nix-prefetch-git --url <url> --rev <ref> --quiet | jq -r .sha256
  2. ✅ Parse flake.lock (if using flakes)
  jq -r '.nodes["app"].locked.narHash' flake.lock
  3. ✅ Store in database
    - Table: (repo_url, git_ref, git_rev, nar_hash, store_path)
    - Index on nar_hash for lookups
    - Can map multiple git refs to same NAR hash
  4. ✅ Query Nix store (alternative)
    - Nix already tracks this internally
    - Can query with nix-store commands

  The NAR hash is what you want - it's what Nix uses for caching and /nix/store paths!


