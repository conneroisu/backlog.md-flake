#!/bin/bash

# Pre-release hook script for auto-tagger
# This script runs before creating a tag and performing release operations

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
    log_error "Pre-release hook failed at line $line_number"
    exit 1
}

# Set up error handling
trap 'error_handler ${LINENO}' ERR

# Main pre-release checks
main() {
    log_info "Running pre-release checks for version: ${RELEASE_VERSION}"
    
    # Step 1: Validate environment
    validate_environment
    
    # Step 2: Check repository status
    check_repository_status
    
    # Step 3: Validate version format
    validate_version_format
    
    # Step 4: Run tests
    run_tests
    
    # Step 5: Build and validate
    build_project
    
    # Step 6: Generate documentation
    generate_documentation
    
    # Step 7: Validate changelog
    validate_changelog
    
    # Step 8: Security checks
    security_checks
    
    # Step 9: Dependencies check
    dependencies_check
    
    log_success "All pre-release checks passed!"
}

# Validate environment
validate_environment() {
    log_info "Validating environment..."
    
    # Check required tools
    local required_tools=("git" "go" "nix")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is required but not installed"
            return 1
        fi
    done
    
    # Check environment variables
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        log_warning "GITHUB_TOKEN not set - GitHub integration may fail"
    fi
    
    # Check Git configuration
    if ! git config user.name &> /dev/null; then
        log_error "Git user.name is not configured"
        return 1
    fi
    
    if ! git config user.email &> /dev/null; then
        log_error "Git user.email is not configured"
        return 1
    fi
    
    log_success "Environment validation passed"
}

# Check repository status
check_repository_status() {
    log_info "Checking repository status..."
    
    # Check if working directory is clean
    if ! git diff --quiet HEAD; then
        log_error "Working directory has uncommitted changes"
        git status --porcelain
        return 1
    fi
    
    # Check if we're on allowed branch
    local current_branch
    current_branch=$(git branch --show-current)
    local allowed_branches=("main" "master" "release")
    
    if [[ ! " ${allowed_branches[@]} " =~ " ${current_branch} " ]]; then
        log_warning "Current branch '$current_branch' is not in allowed branches: ${allowed_branches[*]}"
    fi
    
    # Check if remote is up to date
    git fetch origin
    local local_commit
    local remote_commit
    local_commit=$(git rev-parse HEAD)
    remote_commit=$(git rev-parse "origin/$current_branch" 2>/dev/null || echo "")
    
    if [[ -n "$remote_commit" && "$local_commit" != "$remote_commit" ]]; then
        log_error "Local branch is not up to date with remote"
        return 1
    fi
    
    log_success "Repository status check passed"
}

# Validate version format
validate_version_format() {
    log_info "Validating version format..."
    
    if [[ -z "$RELEASE_VERSION" ]]; then
        log_warning "RELEASE_VERSION not set, skipping version validation"
        return 0
    fi
    
    # Check semantic versioning format
    if ! [[ "$RELEASE_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?(\+[a-zA-Z0-9.-]+)?$ ]]; then
        log_error "Version '$RELEASE_VERSION' does not follow semantic versioning format"
        return 1
    fi
    
    # Check if version already exists
    if git tag -l | grep -q "^$RELEASE_VERSION$"; then
        log_error "Version '$RELEASE_VERSION' already exists"
        return 1
    fi
    
    log_success "Version format validation passed"
}

# Run tests
run_tests() {
    log_info "Running tests..."
    
    cd "$REPO_ROOT"
    
    # Run Go tests
    if [[ -f "go.mod" ]]; then
        log_info "Running Go tests..."
        go test ./... -v
        
        # Run race condition tests
        go test ./... -race
        
        # Check test coverage
        go test ./... -coverprofile=coverage.out
        local coverage
        coverage=$(go tool cover -func=coverage.out | grep total | awk '{print $3}' | sed 's/%//')
        
        if (( $(echo "$coverage < 80" | bc -l) )); then
            log_warning "Test coverage is below 80%: ${coverage}%"
        else
            log_success "Test coverage: ${coverage}%"
        fi
        
        # Clean up coverage file
        rm -f coverage.out
    fi
    
    # Run Nix flake checks
    if [[ -f "flake.nix" ]]; then
        log_info "Running Nix flake checks..."
        nix flake check
    fi
    
    log_success "All tests passed"
}

# Build project
build_project() {
    log_info "Building project..."
    
    cd "$REPO_ROOT"
    
    # Build with Nix
    if [[ -f "flake.nix" ]]; then
        log_info "Building with Nix..."
        nix build
        
        # Check if binary exists and is executable
        if [[ -x "./result/bin/"* ]]; then
            log_success "Nix build successful"
        else
            log_error "Nix build produced no executable binary"
            return 1
        fi
    fi
    
    # Build with Go
    if [[ -f "go.mod" ]]; then
        log_info "Building with Go..."
        go build -v ./...
        
        # Build for multiple platforms
        local platforms=("linux/amd64" "darwin/amd64" "windows/amd64")
        for platform in "${platforms[@]}"; do
            local os="${platform%/*}"
            local arch="${platform#*/}"
            log_info "Building for $os/$arch..."
            GOOS="$os" GOARCH="$arch" go build -o "dist/$os-$arch/" ./...
        done
    fi
    
    log_success "Build completed successfully"
}

# Generate documentation
generate_documentation() {
    log_info "Generating documentation..."
    
    # Generate Go documentation
    if [[ -f "go.mod" ]]; then
        go doc ./... > docs/api.txt || true
    fi
    
    # Update README with version
    if [[ -f "README.md" && -n "$RELEASE_VERSION" ]]; then
        # This would update version badges and links
        log_info "README.md exists, version information may need manual update"
    fi
    
    log_success "Documentation generated"
}

# Validate changelog
validate_changelog() {
    log_info "Validating changelog..."
    
    if [[ ! -f "CHANGELOG.md" ]]; then
        log_warning "CHANGELOG.md not found"
        return 0
    fi
    
    # Check if changelog has entry for current version
    if [[ -n "$RELEASE_VERSION" ]]; then
        if ! grep -q "$RELEASE_VERSION" CHANGELOG.md; then
            log_warning "CHANGELOG.md does not contain entry for $RELEASE_VERSION"
        else
            log_success "Changelog entry found for $RELEASE_VERSION"
        fi
    fi
    
    # Validate changelog format
    if grep -q "## \[Unreleased\]" CHANGELOG.md; then
        log_info "Unreleased section found in changelog"
    fi
    
    log_success "Changelog validation passed"
}

# Security checks
security_checks() {
    log_info "Running security checks..."
    
    # Check for sensitive files that shouldn't be committed
    local sensitive_patterns=(
        "*.key"
        "*.pem"
        "*.p12"
        "*.env"
        "config/secrets*"
        ".env*"
    )
    
    for pattern in "${sensitive_patterns[@]}"; do
        if find . -name "$pattern" -type f | grep -v .git | head -1 | grep -q .; then
            log_warning "Found potentially sensitive files matching pattern: $pattern"
        fi
    done
    
    # Check for hardcoded secrets in code
    local secret_patterns=(
        "password\s*=\s*['\"][^'\"]+['\"]"
        "secret\s*=\s*['\"][^'\"]+['\"]"
        "token\s*=\s*['\"][^'\"]+['\"]"
        "api_key\s*=\s*['\"][^'\"]+['\"]"
    )
    
    for pattern in "${secret_patterns[@]}"; do
        if grep -r -E "$pattern" --include="*.go" --include="*.js" --include="*.py" . | head -5 | grep -q .; then
            log_warning "Found potential hardcoded secrets (pattern: $pattern)"
        fi
    done
    
    log_success "Security checks passed"
}

# Dependencies check
dependencies_check() {
    log_info "Checking dependencies..."
    
    # Check Go dependencies
    if [[ -f "go.mod" ]]; then
        log_info "Checking Go dependencies..."
        
        # Check for vulnerabilities
        if command -v govulncheck &> /dev/null; then
            govulncheck ./... || log_warning "Vulnerability check found issues"
        fi
        
        # Check for outdated dependencies
        go list -u -m all > /tmp/go-deps.txt || true
        if grep -q "available" /tmp/go-deps.txt; then
            log_warning "Some Go dependencies have updates available"
            grep "available" /tmp/go-deps.txt | head -5
        fi
        
        # Tidy up dependencies
        go mod tidy
        
        # Verify dependencies
        go mod verify
    fi
    
    # Check Nix dependencies
    if [[ -f "flake.lock" ]]; then
        log_info "Checking Nix dependencies..."
        
        # Check if flake.lock is up to date
        local lock_age
        lock_age=$(find flake.lock -mtime +30 2>/dev/null || echo "new")
        if [[ "$lock_age" != "new" ]]; then
            log_warning "flake.lock is older than 30 days, consider updating"
        fi
    fi
    
    log_success "Dependencies check passed"
}

# Run main function
main "$@"

exit 0