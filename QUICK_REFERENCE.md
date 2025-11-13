# Quick Reference

## Commands You Need

```bash
# 1. Update Gemfile.lock
bundle lock

# 2. Generate gemset.nix (required for git sources!)
bundix -l

# 3. Build the package
# With SSH git sources (private gems):
nix build --impure

# With only public gems:
nix build

# 4. Run the utility
nix run

# 5. Enter development shell
nix develop
```

## Do I Need bundix?

**YES** - If you have git sources in your Gemfile (including SSH private gems):
```bash
bundix -l  # Generates gemset.nix
```

**NO** - If you only have public gems from rubygems.org (but bundix still works fine)

## Do I Need `bundle install`?

**For Nix builds: NO**
- `bundlerEnv` reads `gemset.nix` (or `Gemfile.lock`)
- It fetches and builds gems automatically
- No `bundle install` needed

**In dev shell: OPTIONAL**
- Gems from `Gemfile.lock` are already available
- You CAN run `bundle install` for experimentation
- It installs to isolated `.nix-gems/` directory

## Do I Need --impure?

**YES** - If you have SSH git sources (private gems):
```bash
nix build --impure  # Allows SSH agent access
```

**NO** - If you only have public gems from rubygems.org

## Sandbox Network Issues?

**Short answer: Usually no!**

`bundlerEnv` fetches gems BEFORE the sandbox build:
```
Fetch gems (has network) → Build gems (in sandbox, no network needed)
```

**When you WILL have issues:**
1. Gems with native extensions → Add `buildInputs`
2. Git-sourced gems → Use published gems instead
3. Gems that download at install time → Find alternatives

## Adding System Dependencies for Native Gems

Edit `flake.nix`, find `gemEnv`, uncomment and add:

```nix
gemEnv = pkgs.bundlerEnv {
  name = "ruby-app-gems";
  inherit ruby;
  gemdir = ./.;

  buildInputs = with pkgs; [
    postgresql  # for 'pg' gem
    mysql80     # for 'mysql2' gem
    sqlite      # for 'sqlite3' gem
    libxml2     # for 'nokogiri' gem
    libxslt     # for 'nokogiri' gem
  ];
};
```

## Common Gems and Their Dependencies

| Gem | Add to buildInputs |
|-----|-------------------|
| `pg` | `postgresql` |
| `mysql2` | `mysql80` |
| `sqlite3` | `sqlite` |
| `nokogiri` | `libxml2` `libxslt` |
| `rmagick` | `imagemagick` |

## DevShell Features

When you run `nix develop`, you get:

✅ Ruby version from `.ruby-version`
✅ Bundler version from `Gemfile.lock`
✅ All gem binaries in PATH
✅ Complete isolation (`.nix-gems/` directory)

## Files You Need

```
your-project/
├── flake.nix           # Copy and customize
├── .ruby-version       # e.g., "3.3.0"
├── Gemfile             # Can include git sources!
├── Gemfile.lock        # Run: bundle lock
├── gemset.nix          # Run: bundix -l (required for git sources)
└── (your ruby code)
```

**IMPORTANT**: Commit `gemset.nix` to git along with `Gemfile.lock`!

## Customization Quick Guide

Three places to edit in `flake.nix`:

### 1. Package name (line ~75)
```nix
pname = "my-ruby-utility";  # ← Change this
version = "0.1.0";          # ← Change this
```

### 2. Entry point (line ~85)
```nix
exec ${ruby}/bin/ruby $out/lib/main.rb "\$@"  # ← Change 'main.rb'
chmod +x $out/bin/my-ruby-utility  # ← Change binary name
```

### 3. Service name (line ~169)
```nix
cfg = config.services.ruby-utility;  # ← Change 'ruby-utility'
options.services.ruby-utility = {    # ← Change 'ruby-utility'
```

## Typical Workflow

```bash
# 1. Copy flake to your project
cp /path/to/generic-ruby-flake/flake.nix .

# 2. Customize (see above)
vim flake.nix

# 3. Ensure you have Gemfile.lock
bundle lock

# 4. Generate gemset.nix (if you have git sources)
bundix -l

# 5. Test build
# With SSH git sources:
eval $(ssh-agent) && ssh-add
nix build --impure

# Or with only public gems:
nix build

# 6. Test run
nix run

# 7. Add to your NixOS configuration
# See README.md for examples
```

## Helper Script

Use the included helper for easier updates:

```bash
# Make it executable
chmod +x update-gems.sh

# Update all gems
./update-gems.sh all

# Update specific gem
./update-gems.sh gem-name

# Just regenerate gemset.nix
./update-gems.sh
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Gem not found" | Run `bundle lock` |
| Native extension fails | Add system lib to `buildInputs` |
| Wrong Ruby version | Check `.ruby-version` file |
| Bundler version mismatch | Check `BUNDLED WITH` in `Gemfile.lock` |
| Git gem fails | Use published gem instead |

## Need More Detail?

- **Full docs**: See `README.md`
- **Development shell**: See `DEVSHELL.md`
- **Bundler workflow**: See `BUNDLER_WORKFLOW.md`
- **Template guide**: See `TEMPLATE_USAGE.md`
