#!/usr/bin/env bash
# Unit Tests for Version Validation and Comparison Logic
# Tests semantic versioning, NPM compatibility, and version parsing

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_ROOT/tests/utils/test-helpers.sh"

# Test semantic version validation
test_semver_validation() {
    log_test "Testing semantic version validation"
    
    # Valid versions
    local valid_versions=(
        "1.0.0"
        "1.2.3"
        "10.20.30"
        "1.0.0-alpha"
        "1.0.0-alpha.1" 
        "1.0.0-alpha.beta"
        "1.0.0-alpha.1+build.1"
        "1.0.0+build.1"
        "2.0.0-rc.1"
    )
    
    # Invalid versions
    local invalid_versions=(
        "1"
        "1.2"
        "1.2.a"
        "a.b.c"
        "1.2.3-"
        "1.2.3+"
        ""
        "v1.2.3"
        "1.2.3.4"
    )
    
    # Test valid versions
    for version in "${valid_versions[@]}"; do
        if validate_semver "$version"; then
            log_success "✓ Valid version accepted: $version"
        else
            log_error "✗ Valid version rejected: $version"
            return 1
        fi
    done
    
    # Test invalid versions
    for version in "${invalid_versions[@]}"; do
        if validate_semver "$version"; then
            log_error "✗ Invalid version accepted: $version"
            return 1
        else
            log_success "✓ Invalid version rejected: $version"
        fi
    done
    
    log_success "Semantic version validation tests passed!"
}

# Test version comparison functions
test_version_comparison() {
    log_test "Testing version comparison"
    
    # Test greater than
    local gt_tests=(
        "2.0.0:1.0.0"
        "1.1.0:1.0.0"
        "1.0.1:1.0.0"
        "1.0.0-beta.2:1.0.0-beta.1"
        "1.0.0:1.0.0-beta"
        "2.0.0-alpha:1.9.9"
    )
    
    for test_case in "${gt_tests[@]}"; do
        local v1="${test_case%:*}"
        local v2="${test_case#*:}"
        
        if version_gt "$v1" "$v2"; then
            log_success "✓ $v1 > $v2"
        else
            log_error "✗ $v1 should be > $v2"
            return 1
        fi
    done
    
    # Test less than
    local lt_tests=(
        "1.0.0:2.0.0"
        "1.0.0:1.1.0"
        "1.0.0:1.0.1"
        "1.0.0-alpha:1.0.0-beta"
        "1.0.0-beta:1.0.0"
    )
    
    for test_case in "${lt_tests[@]}"; do
        local v1="${test_case%:*}"
        local v2="${test_case#*:}"
        
        if version_lt "$v1" "$v2"; then
            log_success "✓ $v1 < $v2"
        else
            log_error "✗ $v1 should be < $v2"
            return 1
        fi
    done
    
    # Test equality
    local eq_tests=(
        "1.0.0:1.0.0"
        "2.1.3:2.1.3"
        "1.0.0-alpha:1.0.0-alpha"
    )
    
    for test_case in "${eq_tests[@]}"; do
        local v1="${test_case%:*}"
        local v2="${test_case#*:}"
        
        if version_eq "$v1" "$v2"; then
            log_success "✓ $v1 == $v2"
        else
            log_error "✗ $v1 should equal $v2"
            return 1
        fi
    done
    
    log_success "Version comparison tests passed!"
}

# Test NPM package version fetching
test_npm_version_fetch() {
    log_test "Testing NPM package version fetching"
    
    # Test fetching actual package versions
    local test_packages=(
        "backlog.md"
        "lodash"
        "express"
    )
    
    for package in "${test_packages[@]}"; do
        log_info "Testing package: $package"
        
        # Fetch latest version
        local latest_version
        latest_version=$(fetch_npm_version "$package" "latest") || {
            log_error "Failed to fetch version for $package"
            return 1
        }
        
        assert_not_empty "$latest_version" "Latest version should not be empty"
        assert_true "$(validate_semver "$latest_version" && echo true || echo false)" "Version should be valid semver"
        
        log_success "✓ $package@$latest_version"
        
        # Test specific version fetch
        if fetch_npm_version "$package" "$latest_version" >/dev/null; then
            log_success "✓ Specific version fetch works for $package@$latest_version"
        else
            log_error "✗ Failed to fetch specific version $package@$latest_version"
            return 1
        fi
    done
    
    # Test invalid package
    if fetch_npm_version "nonexistent-package-12345" "latest" 2>/dev/null; then
        log_error "✗ Should fail for nonexistent package"
        return 1
    else
        log_success "✓ Correctly fails for nonexistent package"
    fi
    
    log_success "NPM version fetch tests passed!"
}

# Test version range checking
test_version_ranges() {
    log_test "Testing version range checking"
    
    local test_cases=(
        "1.2.3:^1.0.0:true"
        "2.0.0:^1.0.0:false"
        "1.2.3:~1.2.0:true"
        "1.3.0:~1.2.0:false"
        "1.2.3:>=1.0.0:true"
        "0.9.0:>=1.0.0:false"
        "1.2.3:<2.0.0:true"
        "2.0.0:<2.0.0:false"
        "1.2.3:1.2.3:true"
        "1.2.4:1.2.3:false"
    )
    
    for test_case in "${test_cases[@]}"; do
        local version="${test_case%%:*}"
        local range="${test_case#*:}"
        range="${range%:*}"
        local expected="${test_case##*:}"
        
        local result
        if version_satisfies_range "$version" "$range"; then
            result="true"
        else
            result="false"
        fi
        
        if [[ "$result" == "$expected" ]]; then
            log_success "✓ $version satisfies $range: $result"
        else
            log_error "✗ $version vs $range: expected $expected, got $result"
            return 1
        fi
    done
    
    log_success "Version range tests passed!"
}

# Test hash validation and generation
test_hash_validation() {
    log_test "Testing hash validation and generation"
    
    # Test valid Nix hashes
    local valid_hashes=(
        "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        "sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="
        "sha1-2jmj7l5rSw0yVb/vlWAYkK/YBwk="
    )
    
    # Test invalid hashes
    local invalid_hashes=(
        "invalid-hash"
        "sha256-toolong-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        "sha256-tooshort"
        "md5-notsupported"
        ""
    )
    
    for hash in "${valid_hashes[@]}"; do
        if validate_nix_hash "$hash"; then
            log_success "✓ Valid hash accepted: ${hash:0:20}..."
        else
            log_error "✗ Valid hash rejected: $hash"
            return 1
        fi
    done
    
    for hash in "${invalid_hashes[@]}"; do
        if validate_nix_hash "$hash"; then
            log_error "✗ Invalid hash accepted: $hash"
            return 1
        else
            log_success "✓ Invalid hash rejected: $hash"
        fi
    done
    
    log_success "Hash validation tests passed!"
}

# Test package integrity verification
test_package_integrity() {
    log_test "Testing package integrity verification"
    
    # Test with a known package
    local package="lodash"
    local version="4.17.21"
    
    log_info "Testing package integrity for $package@$version"
    
    # Get package tarball URL
    local tarball_url
    tarball_url=$(npm view "$package@$version" dist.tarball) || {
        log_error "Failed to get tarball URL"
        return 1
    }
    
    assert_contains "$tarball_url" "registry.npmjs.org" "Should be from NPM registry"
    assert_contains "$tarball_url" "$package" "URL should contain package name"
    
    # Generate and validate hash
    local generated_hash
    generated_hash=$(generate_package_hash "$tarball_url") || {
        log_error "Failed to generate package hash"
        return 1
    }
    
    assert_not_empty "$generated_hash" "Generated hash should not be empty"
    assert_true "$(validate_nix_hash "$generated_hash" && echo true || echo false)" "Generated hash should be valid"
    
    log_info "Generated hash: $generated_hash"
    
    # Verify reproducibility - should get same hash
    local second_hash
    second_hash=$(generate_package_hash "$tarball_url")
    
    assert_equals "$generated_hash" "$second_hash" "Hash generation should be reproducible"
    
    log_success "Package integrity tests passed!"
}

# Helper functions for tests
validate_semver() {
    local version="$1"
    
    # Basic semver regex pattern
    local semver_pattern='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
    
    [[ "$version" =~ $semver_pattern ]]
}

fetch_npm_version() {
    local package="$1"
    local version_spec="${2:-latest}"
    
    npm view "$package@$version_spec" version --silent 2>/dev/null
}

version_satisfies_range() {
    local version="$1"
    local range="$2"
    
    # Simplified range checking using Node.js semver
    node -e "
        const semver = require('semver');
        const satisfies = semver.satisfies('$version', '$range');
        process.exit(satisfies ? 0 : 1);
    " 2>/dev/null
}

validate_nix_hash() {
    local hash="$1"
    
    # Basic Nix hash validation
    if [[ -z "$hash" ]]; then
        return 1
    fi
    
    # Check format: algorithm-base64
    if [[ "$hash" =~ ^(sha256|sha1|md5)-[A-Za-z0-9+/]+=*$ ]]; then
        return 0
    fi
    
    return 1
}

generate_package_hash() {
    local url="$1"
    
    # Use nix-prefetch-url to generate hash
    nix-prefetch-url "$url" 2>/dev/null
}

# Main unit test runner
run_unit_tests() {
    log_header "Starting Unit Test Suite - Version Validation"
    
    init_test_environment
    
    local failed_tests=0
    
    # Run unit test cases
    run_test "semver_validation" test_semver_validation || ((failed_tests++))
    run_test "version_comparison" test_version_comparison || ((failed_tests++))
    run_test "npm_version_fetch" test_npm_version_fetch || ((failed_tests++))
    run_test "version_ranges" test_version_ranges || ((failed_tests++))
    run_test "hash_validation" test_hash_validation || ((failed_tests++))
    run_test "package_integrity" test_package_integrity || ((failed_tests++))
    
    # Results
    print_test_summary
    
    if [[ $failed_tests -eq 0 ]]; then
        log_success "All unit tests passed! ✅"
        exit 0
    else
        log_error "$failed_tests unit tests failed"
        exit 1
    fi
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_unit_tests "$@"
fi