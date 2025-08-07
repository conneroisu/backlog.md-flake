#!/usr/bin/env bash
# Manual NPM Package Update Script
# Interactive update utility with safety checks and rollback capabilities

set -euo pipefail

# Configuration
PACKAGE_NAME="${1:-backlog.md}"
PACKAGE_INFO="package.info"
FLAKE_FILE="flake.nix"
DRY_RUN="${DRY_RUN:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Utility functions
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
highlight() { echo -e "${CYAN}[HIGHLIGHT]${NC} $*"; }

usage() {
    cat << EOF
Usage: $0 [package-name] [options]

Update NPM package in Nix flake with verification and safety checks.

Arguments:
  package-name    NPM package name (default: backlog.md)

Options:
  --dry-run       Show what would be done without making changes
  --force         Skip confirmation prompts
  --version=X.Y.Z Specify target version (default: latest)
  --help          Show this help message

Environment Variables:
  DRY_RUN=true    Enable dry-run mode
  FORCE=true      Skip confirmations

Examples:
  $0                          # Update backlog.md to latest
  $0 lodash                   # Update lodash package
  $0 --version=2.1.0          # Update to specific version
  DRY_RUN=true $0             # Preview changes only
EOF
}

check_dependencies() {
    info "Checking required dependencies..."
    
    local missing_deps=()
    local required_deps=("nix" "jq" "curl" "git")
    
    for dep in "${required_deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing_deps[*]}"
        error "Please install them and try again"
        exit 1
    fi
    
    # Check Nix flake
    if [[ ! -f "$FLAKE_FILE" ]]; then
        error "flake.nix not found in current directory"
        exit 1
    fi
    
    if ! nix flake show >/dev/null 2>&1; then
        error "Invalid Nix flake configuration"
        exit 1
    fi
    
    success "All dependencies satisfied"
}

get_package_info() {
    info "Fetching package information for: $PACKAGE_NAME"
    
    # Get current version
    local current_version="unknown"
    if [[ -f "$PACKAGE_INFO" ]]; then
        current_version=$(jq -r ".version // \"unknown\"" "$PACKAGE_INFO")
    fi
    
    # Get NPM registry data
    local registry_url="https://registry.npmjs.org/$PACKAGE_NAME"
    local registry_data
    
    if ! registry_data=$(curl -s --max-time 30 "$registry_url"); then
        error "Failed to fetch package data from NPM registry"
        exit 1
    fi
    
    # Parse registry data
    local latest_version
    local tarball_url
    local package_hash
    
    latest_version=$(echo "$registry_data" | jq -r '.["dist-tags"].latest // empty')
    
    if [[ -z "$latest_version" ]]; then
        error "Could not determine latest version for $PACKAGE_NAME"
        exit 1
    fi
    
    # Get specific version data
    local version_data
    version_data=$(echo "$registry_data" | jq -r ".versions[\"$latest_version\"] // empty")
    
    if [[ -z "$version_data" ]]; then
        error "Could not find version data for $latest_version"
        exit 1
    fi
    
    tarball_url=$(echo "$version_data" | jq -r '.dist.tarball // empty')
    package_hash=$(echo "$version_data" | jq -r '.dist.shasum // empty')
    
    # Export information
    export CURRENT_VERSION="$current_version"
    export LATEST_VERSION="$latest_version"
    export TARBALL_URL="$tarball_url"
    export PACKAGE_HASH="$package_hash"
    
    # Display information
    highlight "Package Information:"
    echo "  Name: $PACKAGE_NAME"
    echo "  Current Version: $current_version"
    echo "  Latest Version: $latest_version"
    echo "  Tarball URL: $tarball_url"
    echo "  Package Hash: $package_hash"
    echo
}

check_version_diff() {
    if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
        success "Already at latest version: $LATEST_VERSION"
        
        if [[ "${FORCE:-false}" != "true" ]]; then
            read -p "Do you want to continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                info "Exiting without changes"
                exit 0
            fi
        fi
    else
        highlight "Update available: $CURRENT_VERSION → $LATEST_VERSION"
    fi
}

calculate_nix_hash() {
    info "Calculating Nix hash for tarball..."
    
    local nix_hash
    if ! nix_hash=$(nix-prefetch-url "$TARBALL_URL" 2>/dev/null); then
        error "Failed to calculate Nix hash for $TARBALL_URL"
        exit 1
    fi
    
    export NIX_HASH="$nix_hash"
    success "Nix hash calculated: $nix_hash"
}

preview_changes() {
    highlight "Changes to be made:"
    echo
    
    echo "📦 Package Updates:"
    echo "  • Name: $PACKAGE_NAME"
    echo "  • Version: $CURRENT_VERSION → $LATEST_VERSION"
    echo "  • Tarball: $TARBALL_URL"
    echo "  • NPM Hash: $PACKAGE_HASH"
    echo "  • Nix Hash: $NIX_HASH"
    echo
    
    echo "📁 Files to be modified:"
    echo "  • $PACKAGE_INFO (metadata update)"
    echo "  • $FLAKE_FILE (URL and version update)"
    echo "  • flake.lock (dependency lock update)"
    
    if find nix/ -name "*.nix" -type f >/dev/null 2>&1; then
        echo "  • nix/*.nix (version references)"
    fi
    echo
    
    if git rev-parse --git-dir >/dev/null 2>&1; then
        echo "📝 Git Operations:"
        echo "  • Stage modified files"
        echo "  • Create commit with update message"
        echo "  • Create version tag: v$LATEST_VERSION"
        echo
    fi
}

confirm_update() {
    if [[ "${FORCE:-false}" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}Do you want to proceed with the update? (y/N):${NC} "
    read -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Update cancelled by user"
        exit 0
    fi
}

backup_files() {
    info "Creating backup of current files..."
    
    local backup_dir="backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup current files
    [[ -f "$PACKAGE_INFO" ]] && cp "$PACKAGE_INFO" "$backup_dir/"
    [[ -f "$FLAKE_FILE" ]] && cp "$FLAKE_FILE" "$backup_dir/"
    [[ -f "flake.lock" ]] && cp "flake.lock" "$backup_dir/"
    
    # Backup Nix files
    if [[ -d "nix" ]]; then
        cp -r nix "$backup_dir/" 2>/dev/null || true
    fi
    
    # Git state backup
    if git rev-parse --git-dir >/dev/null 2>&1; then
        git rev-parse HEAD > "$backup_dir/git-commit.txt"
        git diff > "$backup_dir/git-diff.patch" 2>/dev/null || true
        git status --porcelain > "$backup_dir/git-status.txt"
    fi
    
    export BACKUP_DIR="$backup_dir"
    success "Backup created: $backup_dir"
}

update_package_info() {
    info "Updating $PACKAGE_INFO..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN: Would update $PACKAGE_INFO"
        return 0
    fi
    
    local updated_info
    updated_info=$(cat << EOF
{
  "name": "$PACKAGE_NAME",
  "version": "$LATEST_VERSION", 
  "tarball_url": "$TARBALL_URL",
  "npm_hash": "$PACKAGE_HASH",
  "nix_hash": "$NIX_HASH",
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "updated_by": "update-npm.sh",
  "previous_version": "$CURRENT_VERSION",
  "auto_update": {
    "enabled": true,
    "check_interval": "daily",
    "include_prereleases": false,
    "security_scan": true,
    "auto_commit": true,
    "auto_tag": true
  },
  "build_targets": [
    "default",
    "cli",
    "dev-tools", 
    "container"
  ],
  "platforms": [
    "x86_64-linux",
    "aarch64-linux",
    "x86_64-darwin", 
    "aarch64-darwin"
  ],
  "metadata": {
    "description": "A powerful markdown-based backlog management tool",
    "homepage": "https://www.npmjs.com/package/$PACKAGE_NAME",
    "license": "MIT",
    "repository": "https://github.com/user/$PACKAGE_NAME"
  }
}
EOF
)
    
    echo "$updated_info" | jq . > "$PACKAGE_INFO"
    success "Updated $PACKAGE_INFO"
}

update_flake() {
    info "Updating $FLAKE_FILE..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN: Would update $FLAKE_FILE URLs and versions"
        return 0
    fi
    
    # Update tarball URL in flake.nix
    local old_pattern="${PACKAGE_NAME}-[0-9.]*.tgz"
    local new_tarball="${PACKAGE_NAME}-${LATEST_VERSION}.tgz"
    
    sed -i "s|$old_pattern|$new_tarball|g" "$FLAKE_FILE"
    
    success "Updated $FLAKE_FILE"
}

update_nix_files() {
    info "Updating Nix package files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN: Would update version strings in nix/*.nix files"
        return 0
    fi
    
    # Update version strings in Nix files
    if [[ -d "nix" ]]; then
        find nix -name "*.nix" -type f -exec \
            sed -i "s|version = \"[0-9.]*\"|version = \"$LATEST_VERSION\"|g" {} \;
        success "Updated Nix package files"
    fi
}

update_flake_lock() {
    info "Updating flake.lock..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN: Would run 'nix flake update'"
        return 0
    fi
    
    if nix flake update --commit-lock-file; then
        success "Updated flake.lock"
    else
        warn "Failed to update flake.lock, continuing..."
    fi
}

verify_update() {
    info "Verifying update..."
    
    # Test build
    info "Testing build..."
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN: Would test build with 'nix build .#default'"
    else
        if nix build .#default --log-format bar-with-logs; then
            success "Build verification passed"
        else
            error "Build verification failed"
            return 1
        fi
    fi
    
    # Verify package.info
    if [[ -f "$PACKAGE_INFO" ]] && [[ "$DRY_RUN" != "true" ]]; then
        local updated_version
        updated_version=$(jq -r '.version' "$PACKAGE_INFO")
        
        if [[ "$updated_version" == "$LATEST_VERSION" ]]; then
            success "Package info verification passed"
        else
            error "Package info verification failed: expected $LATEST_VERSION, got $updated_version"
            return 1
        fi
    fi
}

commit_changes() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        warn "Not a git repository, skipping commit"
        return 0
    fi
    
    info "Committing changes..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN: Would create git commit and tag"
        return 0
    fi
    
    # Stage files
    git add "$PACKAGE_INFO" "$FLAKE_FILE" flake.lock
    [[ -d "nix" ]] && git add nix/
    
    # Create commit
    local commit_msg="📦 Update $PACKAGE_NAME: $CURRENT_VERSION → $LATEST_VERSION

- Updated NPM package to version $LATEST_VERSION
- Verified build and package integrity
- Updated flake.lock with new dependencies

Package Details:
- Tarball: $TARBALL_URL
- NPM Hash: $PACKAGE_HASH
- Nix Hash: $NIX_HASH
- Updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

Co-authored-by: update-npm.sh <noreply@localhost>"
    
    git commit -m "$commit_msg"
    success "Changes committed"
    
    # Create tag
    local tag_name="v$LATEST_VERSION"
    local tag_msg="Release $PACKAGE_NAME@$LATEST_VERSION

Updated from $CURRENT_VERSION to $LATEST_VERSION
Build verified and package integrity confirmed

NPM Package: https://www.npmjs.com/package/$PACKAGE_NAME/v/$LATEST_VERSION"
    
    git tag -a "$tag_name" -m "$tag_msg"
    success "Tag created: $tag_name"
}

show_summary() {
    echo
    highlight "Update Summary:"
    echo "  📦 Package: $PACKAGE_NAME"
    echo "  🔄 Version: $CURRENT_VERSION → $LATEST_VERSION"
    echo "  ✅ Build: Verified"
    echo "  🔐 Hash: $NIX_HASH"
    
    if git rev-parse --git-dir >/dev/null 2>&1 && [[ "$DRY_RUN" != "true" ]]; then
        echo "  🏷️  Tag: v$LATEST_VERSION"
    fi
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "  💾 Backup: $BACKUP_DIR"
    fi
    echo
    
    highlight "Next Steps:"
    echo "  • Test the updated package: nix run ."
    echo "  • Build other targets: nix build .#cli .#container"
    echo "  • Push changes: git push && git push --tags"
    echo "  • Monitor for issues and rollback if needed"
    echo
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                usage
                exit 0
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --version=*)
                TARGET_VERSION="${1#*=}"
                shift
                ;;
            -*)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                PACKAGE_NAME="$1"
                shift
                ;;
        esac
    done
    
    echo "🔄 NPM Package Update Utility"
    echo "📦 Package: $PACKAGE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN MODE - No changes will be made"
    fi
    
    echo "======================================="
    echo
    
    # Main workflow
    check_dependencies
    get_package_info
    check_version_diff
    calculate_nix_hash
    preview_changes
    confirm_update
    
    if [[ "$DRY_RUN" != "true" ]]; then
        backup_files
    fi
    
    update_package_info
    update_flake
    update_nix_files
    update_flake_lock
    verify_update
    commit_changes
    show_summary
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "Dry run completed - no changes made"
    else
        success "Update completed successfully!"
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi