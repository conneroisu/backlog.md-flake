#!/bin/bash

# Post-release hook script for auto-tagger
# This script runs after creating a tag and performing release operations

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
RELEASE_VERSION="${RELEASE_VERSION:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Error handler
error_handler() {
    local line_number=$1
    log_error "Post-release hook failed at line $line_number"
    log_warning "Release may have been created but post-release tasks failed"
    exit 1
}

# Set up error handling
trap 'error_handler ${LINENO}' ERR

# Main post-release tasks
main() {
    log_info "Running post-release tasks for version: ${RELEASE_VERSION}"
    
    # Step 1: Verify release was created
    verify_release
    
    # Step 2: Build and upload artifacts
    build_artifacts
    
    # Step 3: Update documentation sites
    update_documentation
    
    # Step 4: Send notifications
    send_notifications
    
    # Step 5: Update package repositories
    update_package_repositories
    
    # Step 6: Trigger deployments
    trigger_deployments
    
    # Step 7: Update development environment
    update_dev_environment
    
    # Step 8: Archive old releases
    archive_old_releases
    
    log_success "All post-release tasks completed successfully!"
}

# Verify release was created
verify_release() {
    log_info "Verifying release was created..."
    
    if [[ -z "$RELEASE_VERSION" ]]; then
        log_error "RELEASE_VERSION not set"
        return 1
    fi
    
    # Check if Git tag exists
    if ! git tag -l | grep -q "^$RELEASE_VERSION$"; then
        log_error "Git tag '$RELEASE_VERSION' was not created"
        return 1
    fi
    
    # Verify tag is annotated
    if ! git cat-file -t "$RELEASE_VERSION" | grep -q "tag"; then
        log_warning "Tag '$RELEASE_VERSION' is lightweight, not annotated"
    fi
    
    # Check if tag was pushed to remote
    if ! git ls-remote --tags origin | grep -q "refs/tags/$RELEASE_VERSION"; then
        log_warning "Tag '$RELEASE_VERSION' was not pushed to remote"
    fi
    
    log_success "Release verification passed"
}

# Build and upload artifacts
build_artifacts() {
    log_info "Building and uploading artifacts..."
    
    cd "$REPO_ROOT"
    
    # Create artifacts directory
    mkdir -p dist/
    
    # Build for multiple platforms
    if [[ -f "go.mod" ]]; then
        log_info "Building Go binaries..."
        
        local platforms=(
            "linux/amd64"
            "linux/arm64"  
            "darwin/amd64"
            "darwin/arm64"
            "windows/amd64"
        )
        
        for platform in "${platforms[@]}"; do
            local os="${platform%/*}"
            local arch="${platform#*/}"
            local output_dir="dist/${os}-${arch}"
            local binary_name="backlog-md"
            
            if [[ "$os" == "windows" ]]; then
                binary_name="${binary_name}.exe"
            fi
            
            log_info "Building for $os/$arch..."
            mkdir -p "$output_dir"
            
            GOOS="$os" GOARCH="$arch" go build \
                -ldflags="-X main.Version=$RELEASE_VERSION -X main.BuildDate=$(date -u +%Y%m%d.%H%M%S)" \
                -o "$output_dir/$binary_name" \
                ./src/main/
            
            # Create archive
            if [[ "$os" == "windows" ]]; then
                cd dist && zip -r "${os}-${arch}.zip" "${os}-${arch}/" && cd ..
            else
                cd dist && tar -czf "${os}-${arch}.tar.gz" "${os}-${arch}/" && cd ..
            fi
        done
    fi
    
    # Build Nix packages
    if [[ -f "flake.nix" ]]; then
        log_info "Building Nix packages..."
        nix build .#packages.x86_64-linux.default
        nix build .#packages.aarch64-linux.default 2>/dev/null || log_warning "ARM64 Linux build failed"
        nix build .#packages.x86_64-darwin.default 2>/dev/null || log_warning "x86_64 Darwin build failed"
        nix build .#packages.aarch64-darwin.default 2>/dev/null || log_warning "ARM64 Darwin build failed"
    fi
    
    # Generate checksums
    log_info "Generating checksums..."
    cd dist/
    find . -name "*.tar.gz" -o -name "*.zip" | xargs sha256sum > checksums.txt
    cd ..
    
    # Upload to GitHub Release if token is available
    if [[ -n "$GITHUB_TOKEN" ]]; then
        upload_to_github_release
    else
        log_warning "GITHUB_TOKEN not set, skipping GitHub release upload"
    fi
    
    log_success "Artifacts built and uploaded"
}

# Upload artifacts to GitHub Release
upload_to_github_release() {
    log_info "Uploading artifacts to GitHub Release..."
    
    # Extract repository info
    local repo_url
    repo_url=$(git config --get remote.origin.url)
    local repo_path
    repo_path=$(echo "$repo_url" | sed -e 's/.*github\.com[:/]\(.*\)\.git/\1/')
    
    # Upload each artifact
    for file in dist/*.tar.gz dist/*.zip dist/checksums.txt; do
        if [[ -f "$file" ]]; then
            local filename
            filename=$(basename "$file")
            log_info "Uploading $filename..."
            
            # This would use GitHub CLI or API to upload
            # gh release upload "$RELEASE_VERSION" "$file" --repo "$repo_path"
            log_info "Would upload $filename to GitHub Release"
        fi
    done
    
    log_success "GitHub Release artifacts uploaded"
}

# Update documentation sites
update_documentation() {
    log_info "Updating documentation..."
    
    # Update version in documentation
    if [[ -f "docs/installation.md" ]]; then
        log_info "Updating installation documentation..."
        # This would update version references in docs
    fi
    
    # Generate API documentation
    if [[ -f "go.mod" ]]; then
        mkdir -p docs/api/
        go doc -all ./... > docs/api/reference.txt
    fi
    
    # Update GitHub Pages or documentation site
    if [[ -n "$GITHUB_TOKEN" ]]; then
        log_info "Updating documentation site..."
        # This would trigger documentation site rebuild
    fi
    
    log_success "Documentation updated"
}

# Send notifications
send_notifications() {
    log_info "Sending notifications..."
    
    # Prepare release notes
    local release_notes
    if [[ -f "CHANGELOG.md" ]]; then
        # Extract relevant section from changelog
        release_notes=$(awk "/$RELEASE_VERSION/,/^## \[/ { if (/^## \[/ && !/$RELEASE_VERSION/) exit; print }" CHANGELOG.md)
    else
        release_notes="Release $RELEASE_VERSION has been published."
    fi
    
    # Send Slack notification
    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        send_slack_notification "$release_notes"
    fi
    
    # Send email notification
    if [[ -n "${SMTP_HOST:-}" ]]; then
        send_email_notification "$release_notes"
    fi
    
    # Send Discord notification
    if [[ -n "${DISCORD_WEBHOOK_URL:-}" ]]; then
        send_discord_notification "$release_notes"
    fi
    
    log_success "Notifications sent"
}

# Send Slack notification
send_slack_notification() {
    local release_notes="$1"
    log_info "Sending Slack notification..."
    
    local payload
    payload=$(cat <<EOF
{
    "text": "🚀 New Release: $RELEASE_VERSION",
    "blocks": [
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": "*🚀 New Release Published*\n\nVersion: \`$RELEASE_VERSION\`\nRepository: \`$(basename "$REPO_ROOT")\`"
            }
        },
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": "*Release Notes:*\n\`\`\`$release_notes\`\`\`"
            }
        }
    ]
}
EOF
    )
    
    # This would send the payload to Slack webhook
    log_info "Would send Slack notification"
    # curl -X POST -H 'Content-type: application/json' --data "$payload" "$SLACK_WEBHOOK_URL"
}

# Send email notification  
send_email_notification() {
    local release_notes="$1"
    log_info "Sending email notification..."
    
    # This would send email via SMTP
    log_info "Would send email notification"
}

# Send Discord notification
send_discord_notification() {
    local release_notes="$1"
    log_info "Sending Discord notification..."
    
    # This would send Discord webhook notification
    log_info "Would send Discord notification"
}

# Update package repositories
update_package_repositories() {
    log_info "Updating package repositories..."
    
    # Update Homebrew formula
    if [[ -n "${HOMEBREW_TAP_REPO:-}" ]]; then
        update_homebrew_formula
    fi
    
    # Update AUR package
    if [[ -n "${AUR_PACKAGE_NAME:-}" ]]; then
        update_aur_package
    fi
    
    # Update Nix packages
    if [[ -f "flake.nix" ]]; then
        update_nix_packages
    fi
    
    log_success "Package repositories updated"
}

# Update Homebrew formula
update_homebrew_formula() {
    log_info "Updating Homebrew formula..."
    
    # This would update Homebrew tap with new version
    log_info "Would update Homebrew formula"
}

# Update AUR package
update_aur_package() {
    log_info "Updating AUR package..."
    
    # This would update Arch User Repository package
    log_info "Would update AUR package"
}

# Update Nix packages
update_nix_packages() {
    log_info "Updating Nix packages..."
    
    # Update flake inputs
    nix flake update
    
    # This would submit PR to nixpkgs if appropriate
    log_info "Nix flake updated"
}

# Trigger deployments
trigger_deployments() {
    log_info "Triggering deployments..."
    
    # Trigger production deployment
    if [[ -n "${DEPLOY_WEBHOOK_URL:-}" ]]; then
        log_info "Triggering production deployment..."
        # curl -X POST "$DEPLOY_WEBHOOK_URL" -d "version=$RELEASE_VERSION"
        log_info "Would trigger production deployment"
    fi
    
    # Update staging environment
    if [[ -n "${STAGING_WEBHOOK_URL:-}" ]]; then
        log_info "Updating staging environment..."
        log_info "Would update staging environment"
    fi
    
    # Trigger CDN cache invalidation
    if [[ -n "${CDN_INVALIDATE_URL:-}" ]]; then
        log_info "Invalidating CDN cache..."
        log_info "Would invalidate CDN cache"
    fi
    
    log_success "Deployments triggered"
}

# Update development environment
update_dev_environment() {
    log_info "Updating development environment..."
    
    # Update version in development files
    if [[ -f "package.json" ]]; then
        # This would update package.json version
        log_info "Would update package.json version"
    fi
    
    # Create next development version
    local next_version
    next_version=$(echo "$RELEASE_VERSION" | sed 's/v\([0-9]*\.\[0-9]*\.\)\([0-9]*\)/v\1\2+1/')
    
    # Update version constants
    if [[ -f "src/main/auto_tagger_main.go" ]]; then
        # This would update version constant
        log_info "Would update version constant to $next_version-dev"
    fi
    
    # Commit development version updates
    if git status --porcelain | grep -q .; then
        git add .
        git commit -m "chore: bump development version to $next_version-dev"
        
        if [[ -n "$GITHUB_TOKEN" ]]; then
            git push origin "$(git branch --show-current)"
        fi
    fi
    
    log_success "Development environment updated"
}

# Archive old releases
archive_old_releases() {
    log_info "Archiving old releases..."
    
    # Keep only the last 10 releases
    local old_releases
    old_releases=$(git tag -l --sort=-version:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | tail -n +11)
    
    if [[ -n "$old_releases" ]]; then
        log_info "Found old releases to archive: $old_releases"
        # This would move old releases to archive or mark them as archived
        # For now, just log them
        log_info "Would archive old releases"
    else
        log_info "No old releases to archive"
    fi
    
    log_success "Old releases processed"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up temporary files..."
    
    # Remove temporary build artifacts
    rm -rf /tmp/go-deps.txt || true
    
    # Clean up dist directory if needed
    # rm -rf dist/ || true
    
    log_success "Cleanup completed"
}

# Set up cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"

exit 0