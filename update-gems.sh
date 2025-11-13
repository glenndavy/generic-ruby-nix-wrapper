#!/usr/bin/env bash
# update-gems.sh - Helper script for updating gems with bundix

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Gem Update Helper (with bundix)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check for SSH agent (needed for private gems)
if [ -z "$SSH_AUTH_SOCK" ]; then
  echo -e "${RED}Error: No SSH agent detected${NC}"
  echo ""
  echo "Private gems with git sources require SSH access."
  echo ""
  echo "To fix, run:"
  echo "  eval \$(ssh-agent)"
  echo "  ssh-add ~/.ssh/id_ed25519"
  echo ""
  echo "Then run this script again."
  exit 1
fi

echo -e "${GREEN}✓${NC} SSH agent available"

# Check if bundler is available
if ! command -v bundle &> /dev/null; then
  echo -e "${RED}Error: bundler not found${NC}"
  echo "Install with: gem install bundler"
  exit 1
fi

echo -e "${GREEN}✓${NC} bundler available"

# Check if bundix is available
if ! command -v bundix &> /dev/null; then
  echo -e "${YELLOW}Warning: bundix not found${NC}"
  echo ""
  echo "Install bundix with one of:"
  echo "  nix-env -iA nixpkgs.bundix"
  echo "  nix-shell -p bundix"
  echo "  Or enter: nix develop"
  echo ""
  exit 1
fi

echo -e "${GREEN}✓${NC} bundix available"
echo ""

# Parse command line arguments
UPDATE_ALL=false
SPECIFIC_GEM=""

if [ "$1" == "all" ]; then
  UPDATE_ALL=true
elif [ -n "$1" ]; then
  SPECIFIC_GEM="$1"
fi

# Update gems
if [ "$UPDATE_ALL" = true ]; then
  echo "Updating all gems..."
  bundle update
elif [ -n "$SPECIFIC_GEM" ]; then
  echo "Updating gem: $SPECIFIC_GEM"
  bundle update "$SPECIFIC_GEM"
else
  echo "Updating Gemfile.lock..."
  bundle lock
fi

echo ""
echo "Generating gemset.nix with bundix..."
bundix -l

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓${NC} gemset.nix generated successfully"
else
  echo -e "${RED}✗${NC} bundix failed"
  echo ""
  echo "If bundix couldn't calculate sha256 for a git source,"
  echo "you may need to manually update gemset.nix."
  echo ""
  echo "Use: nix-prefetch-git <git-url> <rev>"
  exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Update Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Review changes:"
echo "  git diff Gemfile.lock gemset.nix"
echo ""
echo "Test build:"
echo "  nix build --impure"
echo ""
echo "If build succeeds, commit:"
echo "  git add Gemfile.lock gemset.nix"
if [ -n "$SPECIFIC_GEM" ]; then
  echo "  git commit -m \"Update $SPECIFIC_GEM\""
elif [ "$UPDATE_ALL" = true ]; then
  echo "  git commit -m \"Update all gems\""
else
  echo "  git commit -m \"Update gems\""
fi
echo ""
