{ lib
, stdenv
, writeShellApplication
, curl
, jq
, nix
, git
, gnused
, coreutils
}:

writeShellApplication {
  name = "npm-update-helper";
  
  runtimeInputs = [
    curl
    jq
    nix
    git
    gnused
    coreutils
  ];
  
  text = ''
    #!/usr/bin/env bash
    set -euo pipefail
    
    PACKAGE_NAME="$1"
    REGISTRY_URL="https://registry.npmjs.org"
    FLAKE_FILE="flake.nix"
    PACKAGE_INFO_FILE="package.info"
    
    usage() {
      echo "Usage: $0 <npm-package-name>"
      echo "Example: $0 backlog.md"
      exit 1
    }
    
    if [ $# -ne 1 ]; then
      usage
    fi
    
    echo "🔍 Checking for updates to NPM package: $PACKAGE_NAME"
    
    # Get current version from package.info
    CURRENT_VERSION=""
    if [ -f "$PACKAGE_INFO_FILE" ]; then
      CURRENT_VERSION=$(jq -r '.version // "unknown"' "$PACKAGE_INFO_FILE")
    fi
    
    echo "📦 Current version: $CURRENT_VERSION"
    
    # Get latest version from NPM registry
    echo "🌐 Fetching latest version from NPM registry..."
    REGISTRY_DATA=$(curl -s "$REGISTRY_URL/$PACKAGE_NAME" || {
      echo "❌ Failed to fetch package data from NPM registry"
      exit 1
    })
    
    LATEST_VERSION=$(echo "$REGISTRY_DATA" | jq -r '.["dist-tags"].latest // empty')
    
    if [ -z "$LATEST_VERSION" ]; then
      echo "❌ Could not determine latest version for $PACKAGE_NAME"
      exit 1
    fi
    
    echo "🆕 Latest version: $LATEST_VERSION"
    
    if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
      echo "✅ Already at latest version!"
      exit 0
    fi
    
    echo "🔄 Update available: $CURRENT_VERSION → $LATEST_VERSION"
    
    # Get package tarball URL and metadata
    TARBALL_URL=$(echo "$REGISTRY_DATA" | jq -r ".versions[\"$LATEST_VERSION\"].dist.tarball")
    PACKAGE_HASH=$(echo "$REGISTRY_DATA" | jq -r ".versions[\"$LATEST_VERSION\"].dist.shasum")
    
    if [ -z "$TARBALL_URL" ] || [ "$TARBALL_URL" = "null" ]; then
      echo "❌ Could not find tarball URL for version $LATEST_VERSION"
      exit 1
    fi
    
    echo "📥 Tarball URL: $TARBALL_URL"
    echo "🔐 Package hash: $PACKAGE_HASH"
    
    # Calculate Nix hash for the tarball
    echo "🧮 Calculating Nix hash..."
    NIX_HASH=$(nix-prefetch-url "$TARBALL_URL" 2>/dev/null || {
      echo "❌ Failed to calculate Nix hash for tarball"
      exit 1
    })
    
    echo "🔑 Nix hash: $NIX_HASH"
    
    # Update package.info file
    echo "📝 Updating package.info..."
    cat > "$PACKAGE_INFO_FILE" << EOF
    {
      "name": "$PACKAGE_NAME",
      "version": "$LATEST_VERSION",
      "tarball_url": "$TARBALL_URL",
      "npm_hash": "$PACKAGE_HASH",
      "nix_hash": "$NIX_HASH",
      "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
      "updated_by": "npm-update-helper"
    }
    EOF
    
    # Update flake.nix with new version and hash
    echo "🔧 Updating flake.nix..."
    
    # Extract current tarball name from flake.nix
    OLD_TARBALL=$(grep -o "$PACKAGE_NAME-[0-9.]*.tgz" "$FLAKE_FILE" | head -1)
    NEW_TARBALL="$PACKAGE_NAME-$LATEST_VERSION.tgz"
    
    # Update the URL in flake.nix
    sed -i "s|$OLD_TARBALL|$NEW_TARBALL|g" "$FLAKE_FILE"
    
    # Update version in Nix files
    find nix/ -name "*.nix" -exec sed -i "s|version = \"[0-9.]*\"|version = \"$LATEST_VERSION\"|g" {} \; 2>/dev/null || true
    
    # Update flake.lock
    echo "🔒 Updating flake.lock..."
    nix flake update || echo "⚠️  Failed to update flake.lock automatically"
    
    # Git operations (if in a git repo)
    if git rev-parse --git-dir > /dev/null 2>&1; then
      echo "📊 Git repository detected, staging changes..."
      
      git add "$PACKAGE_INFO_FILE" "$FLAKE_FILE" nix/ flake.lock 2>/dev/null || true
      
      # Create commit message
      COMMIT_MSG="🔄 Auto-update $PACKAGE_NAME: $CURRENT_VERSION → $LATEST_VERSION
      
      - Updated NPM package to version $LATEST_VERSION
      - New tarball hash: $NIX_HASH
      - Updated package.info and flake configuration
      - Automated update by npm-update-helper"
      
      if git diff --cached --quiet; then
        echo "⚠️  No changes to commit"
      else
        echo "💾 Creating commit..."
        git commit -m "$COMMIT_MSG" || echo "⚠️  Failed to create commit"
        
        # Create tag
        echo "🏷️  Creating version tag..."
        git tag -a "v$LATEST_VERSION" -m "Auto-generated tag for $PACKAGE_NAME@$LATEST_VERSION" 2>/dev/null || echo "⚠️  Tag may already exist"
      fi
    fi
    
    echo "✅ Successfully updated $PACKAGE_NAME to version $LATEST_VERSION!"
    echo ""
    echo "📋 Summary:"
    echo "  • Package: $PACKAGE_NAME"
    echo "  • Version: $CURRENT_VERSION → $LATEST_VERSION"
    echo "  • Nix hash: $NIX_HASH"
    echo "  • Tarball: $TARBALL_URL"
    echo ""
    echo "🔄 Next steps:"
    echo "  • Run 'nix build' to test the new version"
    echo "  • Run 'nix flake check' to verify the flake"
    echo "  • Push changes to trigger CI/CD if ready"
  '';
}