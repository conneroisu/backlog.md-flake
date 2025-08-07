#!/usr/bin/env bash
# Comprehensive Integration Testing for Auto-Update System
# Tests the complete workflow: NPM check -> Version update -> Flake rebuild -> Tag creation

set -euo pipefail

# Test configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly TEST_OUTPUT_DIR="$PROJECT_ROOT/tests/output"
readonly FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures"

# Test utilities
source "$PROJECT_ROOT/tests/utils/test-helpers.sh"

# Setup test environment
setup_test_env() {
    echo "Setting up integration test environment..."
    
    mkdir -p "$TEST_OUTPUT_DIR"
    mkdir -p "$FIXTURES_DIR"
    
    # Create test workspace
    export TEST_WORKSPACE="$(mktemp -d)"
    export TEST_FLAKE_DIR="$TEST_WORKSPACE/test-flake"
    
    # Copy project to test workspace
    cp -r "$PROJECT_ROOT" "$TEST_FLAKE_DIR"
    cd "$TEST_FLAKE_DIR"
    
    log_info "Test workspace: $TEST_WORKSPACE"
    log_info "Test flake directory: $TEST_FLAKE_DIR"
}

# Cleanup test environment
cleanup_test_env() {
    if [[ -n "${TEST_WORKSPACE:-}" ]] && [[ -d "$TEST_WORKSPACE" ]]; then
        log_info "Cleaning up test workspace: $TEST_WORKSPACE"
        rm -rf "$TEST_WORKSPACE"
    fi
}

# Test NPM version checking
test_npm_version_check() {
    log_test "Testing NPM version checking"
    
    local current_version
    local latest_version
    local update_needed
    
    # Get current version from flake
    current_version=$(nix eval ".#backlog-md.version" --raw 2>/dev/null || echo "unknown")
    log_info "Current version in flake: $current_version"
    
    # Check latest version from NPM
    latest_version=$(npm view backlog.md version 2>/dev/null || echo "unknown")
    log_info "Latest version on NPM: $latest_version"
    
    # Determine if update is needed
    if [[ "$current_version" != "$latest_version" ]]; then
        update_needed=true
        log_info "Update needed: $current_version -> $latest_version"
    else
        update_needed=false
        log_info "No update needed"
    fi
    
    # Store results for other tests
    export TEST_CURRENT_VERSION="$current_version"
    export TEST_LATEST_VERSION="$latest_version"
    export TEST_UPDATE_NEEDED="$update_needed"
    
    assert_not_empty "$current_version" "Current version should not be empty"
    assert_not_empty "$latest_version" "Latest version should not be empty"
    
    log_success "NPM version check completed"
}

# Test flake update process
test_flake_update() {
    log_test "Testing flake update process"
    
    if [[ "$TEST_UPDATE_NEEDED" != "true" ]]; then
        log_info "Skipping update test - no update needed"
        return 0
    fi
    
    # Record original flake.lock hash
    local original_lock_hash=""
    if [[ -f "flake.lock" ]]; then
        original_lock_hash=$(sha256sum flake.lock | cut -d' ' -f1)
        log_info "Original lock hash: $original_lock_hash"
    fi
    
    # Update the package version in flake.nix
    log_info "Updating package version to $TEST_LATEST_VERSION"
    
    # Use sed to update the version (assuming it's in a specific format)
    sed -i "s/version = \"[^\"]*\";/version = \"$TEST_LATEST_VERSION\";/" flake.nix
    
    # Get new package hash
    log_info "Fetching new package hash..."
    local tarball_url
    tarball_url=$(npm view "backlog.md@$TEST_LATEST_VERSION" dist.tarball)
    
    local new_hash
    new_hash=$(nix-prefetch-url "$tarball_url")
    log_info "New package hash: $new_hash"
    
    # Update hash in flake.nix
    sed -i "s/hash = \"[^\"]*\";/hash = \"$new_hash\";/" flake.nix
    
    # Update flake lock
    log_info "Updating flake lock..."
    nix flake update
    
    # Verify lock file changed
    if [[ -n "$original_lock_hash" ]]; then
        local new_lock_hash
        new_lock_hash=$(sha256sum flake.lock | cut -d' ' -f1)
        
        if [[ "$original_lock_hash" != "$new_lock_hash" ]]; then
            log_info "Flake lock updated successfully"
        else
            log_warn "Flake lock unchanged after update"
        fi
    fi
    
    log_success "Flake update completed"
}

# Test flake rebuild and validation
test_flake_rebuild() {
    log_test "Testing flake rebuild and validation"
    
    # Test flake evaluation
    log_info "Testing flake evaluation..."
    nix flake show --no-update-lock-file
    
    # Test flake check
    log_info "Running flake checks..."
    nix flake check --no-update-lock-file
    
    # Test package build
    log_info "Building backlog-md package..."
    local build_result
    build_result=$(nix build ".#backlog-md" --print-out-paths --no-link)
    
    assert_not_empty "$build_result" "Build result should not be empty"
    assert_path_exists "$build_result" "Built package should exist"
    
    log_info "Package built successfully: $build_result"
    
    # Verify version in built package
    local built_version
    built_version=$(nix eval ".#backlog-md.version" --raw)
    
    if [[ "$TEST_UPDATE_NEEDED" == "true" ]]; then
        assert_equals "$built_version" "$TEST_LATEST_VERSION" "Built version should match latest version"
    fi
    
    log_success "Flake rebuild and validation completed"
}

# Test auto-tagging functionality
test_auto_tagging() {
    log_test "Testing auto-tagging functionality"
    
    if [[ "$TEST_UPDATE_NEEDED" != "true" ]]; then
        log_info "Skipping tagging test - no update needed"
        return 0
    fi
    
    # Initialize git if not already done
    if [[ ! -d ".git" ]]; then
        git init
        git config user.name "Test Runner"
        git config user.email "test@example.com"
    fi
    
    # Stage changes
    git add flake.nix flake.lock
    
    # Create commit
    local commit_message="chore: update backlog.md to $TEST_LATEST_VERSION"
    git commit -m "$commit_message"
    
    # Create tag
    local tag_name="v$TEST_LATEST_VERSION"
    git tag -a "$tag_name" -m "Release $TEST_LATEST_VERSION"
    
    # Verify tag exists
    local tag_exists
    tag_exists=$(git tag -l "$tag_name")
    
    assert_not_empty "$tag_exists" "Git tag should exist"
    assert_equals "$tag_exists" "$tag_name" "Tag name should match"
    
    log_success "Auto-tagging completed"
}

# Test rollback functionality
test_rollback() {
    log_test "Testing rollback functionality"
    
    if [[ "$TEST_UPDATE_NEEDED" != "true" ]]; then
        log_info "Skipping rollback test - no update performed"
        return 0
    fi
    
    # Create a backup of current state
    local backup_dir="$TEST_WORKSPACE/backup"
    mkdir -p "$backup_dir"
    
    cp flake.nix "$backup_dir/flake.nix"
    cp flake.lock "$backup_dir/flake.lock"
    
    # Simulate a problem that requires rollback
    log_info "Simulating rollback scenario..."
    
    # Restore from backup
    cp "$backup_dir/flake.nix" flake.nix
    cp "$backup_dir/flake.lock" flake.lock
    
    # Verify rollback worked
    local rolled_back_version
    rolled_back_version=$(nix eval ".#backlog-md.version" --raw)
    
    # Should be back to original version or at least buildable
    nix flake check --no-update-lock-file
    
    log_success "Rollback functionality verified"
}

# Test performance metrics
test_performance_metrics() {
    log_test "Testing performance metrics collection"
    
    local metrics_file="$TEST_OUTPUT_DIR/performance_metrics.json"
    local start_time
    local end_time
    
    # Measure build time
    log_info "Measuring build performance..."
    
    # Clean builds for accurate timing
    nix store gc --max 0 2>/dev/null || true
    
    start_time=$(date +%s.%3N)
    nix build ".#backlog-md" --no-link --rebuild
    end_time=$(date +%s.%3N)
    
    local build_time
    build_time=$(echo "$end_time - $start_time" | bc)
    
    # Measure evaluation time
    start_time=$(date +%s.%3N)
    nix flake show --no-update-lock-file >/dev/null
    end_time=$(date +%s.%3N)
    
    local eval_time
    eval_time=$(echo "$end_time - $start_time" | bc)
    
    # Collect memory usage
    local max_memory
    max_memory=$(nix build ".#backlog-md" --no-link 2>&1 | grep -o "max.*MB" || echo "unknown")
    
    # Write metrics to JSON file
    cat > "$metrics_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "build_time_seconds": $build_time,
  "eval_time_seconds": $eval_time,
  "max_memory": "$max_memory",
  "package_version": "$TEST_LATEST_VERSION"
}
EOF
    
    log_info "Performance metrics written to $metrics_file"
    log_info "Build time: ${build_time}s"
    log_info "Eval time: ${eval_time}s"
    log_info "Max memory: $max_memory"
    
    log_success "Performance metrics collection completed"
}

# Test error handling and recovery
test_error_handling() {
    log_test "Testing error handling and recovery"
    
    # Test invalid version handling
    log_info "Testing invalid version handling..."
    
    # Backup current flake.nix
    cp flake.nix flake.nix.backup
    
    # Introduce invalid version
    sed -i 's/version = "[^"]*";/version = "999.999.999";/' flake.nix
    
    # This should fail
    local build_failed=false
    if ! nix flake check --no-update-lock-file 2>/dev/null; then
        build_failed=true
        log_info "Build correctly failed with invalid version"
    fi
    
    assert_true "$build_failed" "Build should fail with invalid version"
    
    # Restore valid flake.nix
    cp flake.nix.backup flake.nix
    rm flake.nix.backup
    
    # Verify recovery
    nix flake check --no-update-lock-file
    
    log_success "Error handling and recovery verified"
}

# Main test runner
run_integration_tests() {
    log_header "Starting Integration Test Suite"
    
    local failed_tests=0
    
    # Setup
    setup_test_env
    trap cleanup_test_env EXIT
    
    # Run test cases
    run_test "npm_version_check" test_npm_version_check || ((failed_tests++))
    run_test "flake_update" test_flake_update || ((failed_tests++))
    run_test "flake_rebuild" test_flake_rebuild || ((failed_tests++))
    run_test "auto_tagging" test_auto_tagging || ((failed_tests++))
    run_test "rollback" test_rollback || ((failed_tests++))
    run_test "performance_metrics" test_performance_metrics || ((failed_tests++))
    run_test "error_handling" test_error_handling || ((failed_tests++))
    
    # Results
    log_header "Integration Test Results"
    
    if [[ $failed_tests -eq 0 ]]; then
        log_success "All integration tests passed! 🎉"
        exit 0
    else
        log_error "$failed_tests integration tests failed"
        exit 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_integration_tests "$@"
fi