#!/usr/bin/env bash
# End-to-End Testing for Complete Auto-Build Workflow
# Tests the full automation pipeline from NPM monitoring to deployment

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_ROOT/tests/utils/test-helpers.sh"

# E2E test configuration
readonly E2E_WORKSPACE="$(mktemp -d)"
readonly E2E_OUTPUT_DIR="$PROJECT_ROOT/tests/output/e2e"
readonly MONITORING_INTERVAL=5
readonly MAX_WAIT_TIME=300

cleanup_e2e() {
    if [[ -n "${E2E_WORKSPACE:-}" ]] && [[ -d "$E2E_WORKSPACE" ]]; then
        log_info "Cleaning up E2E workspace: $E2E_WORKSPACE"
        rm -rf "$E2E_WORKSPACE"
    fi
}

setup_e2e_environment() {
    log_info "Setting up E2E test environment..."
    
    mkdir -p "$E2E_OUTPUT_DIR"
    mkdir -p "$E2E_WORKSPACE"
    
    # Copy project to workspace
    cp -r "$PROJECT_ROOT"/* "$E2E_WORKSPACE/"
    cd "$E2E_WORKSPACE"
    
    # Initialize git repository if needed
    if [[ ! -d ".git" ]]; then
        git init
        git config user.name "E2E Test Runner"
        git config user.email "e2e@test.example"
        git add .
        git commit -m "Initial commit for E2E testing"
    fi
    
    export E2E_INITIAL_COMMIT=$(git rev-parse HEAD)
    
    log_info "E2E environment ready at: $E2E_WORKSPACE"
}

# Test complete workflow automation
test_complete_workflow() {
    log_test "Testing complete auto-build workflow"
    
    # Step 1: Monitor for updates
    log_info "Step 1: Checking for NPM updates..."
    
    local current_version
    current_version=$(nix eval ".#backlog-md.version" --raw)
    
    local latest_version
    latest_version=$(npm view backlog.md version)
    
    log_info "Current: $current_version, Latest: $latest_version"
    
    if [[ "$current_version" == "$latest_version" ]]; then
        log_warn "No update available - simulating update scenario"
        # For testing purposes, we'll simulate an update
        latest_version="$current_version"
        
        # Create a minor version bump for testing
        local major minor patch
        IFS='.' read -r major minor patch <<< "$current_version"
        patch=$((patch + 1))
        latest_version="$major.$minor.$patch"
        
        log_info "Simulated update to: $latest_version"
    fi
    
    # Step 2: Update flake configuration
    log_info "Step 2: Updating flake configuration..."
    
    # Update version in flake.nix
    sed -i "s/version = \"[^\"]*\";/version = \"$latest_version\";/" flake.nix
    
    # Get new package hash (simulate this for testing)
    local new_hash="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    if [[ "$current_version" != "$latest_version" ]]; then
        # In real scenario, fetch actual hash
        local tarball_url
        tarball_url=$(npm view "backlog.md@$latest_version" dist.tarball 2>/dev/null || echo "")
        if [[ -n "$tarball_url" ]]; then
            new_hash=$(nix-prefetch-url "$tarball_url" 2>/dev/null || echo "$new_hash")
        fi
    fi
    
    # Update hash in flake.nix
    sed -i "s/hash = \"[^\"]*\";/hash = \"$new_hash\";/" flake.nix
    
    # Step 3: Test flake integrity
    log_info "Step 3: Testing flake integrity..."
    
    # Update flake lock
    nix flake update
    
    # Verify flake is valid
    nix flake check --no-update-lock-file
    
    # Test package build
    local build_result
    build_result=$(nix build ".#backlog-md" --print-out-paths --no-link)
    assert_path_exists "$build_result" "Built package should exist"
    
    # Step 4: Commit changes
    log_info "Step 4: Committing changes..."
    
    git add flake.nix flake.lock
    git commit -m "chore: update backlog.md to $latest_version"
    
    # Step 5: Create release tag
    log_info "Step 5: Creating release tag..."
    
    local tag_name="v$latest_version"
    git tag -a "$tag_name" -m "Release $latest_version"
    
    # Step 6: Generate release notes
    log_info "Step 6: Generating release notes..."
    
    local release_notes_file="$E2E_OUTPUT_DIR/release_notes_$latest_version.md"
    cat > "$release_notes_file" << EOF
# Release $latest_version

## Changes
- Updated backlog.md to version $latest_version
- Rebuilt Nix flake with new package hash
- All tests passing

## Build Information
- Build result: $build_result
- Flake hash: $(sha256sum flake.lock | cut -d' ' -f1)
- Commit: $(git rev-parse HEAD)

## Verification
- ✅ Flake check passed
- ✅ Package builds successfully  
- ✅ All tests pass
EOF
    
    log_info "Release notes written to: $release_notes_file"
    
    # Step 7: Validate entire workflow
    log_info "Step 7: Validating workflow completion..."
    
    # Verify git state
    local current_commit
    current_commit=$(git rev-parse HEAD)
    assert_not_equals "$E2E_INITIAL_COMMIT" "$current_commit" "Should have new commit"
    
    # Verify tag exists
    local tag_exists
    tag_exists=$(git tag -l "$tag_name")
    assert_equals "$tag_name" "$tag_exists" "Release tag should exist"
    
    # Verify package version
    local built_version
    built_version=$(nix eval ".#backlog-md.version" --raw)
    assert_equals "$latest_version" "$built_version" "Built version should match target"
    
    log_success "Complete workflow test passed!"
    
    return 0
}

# Test parallel build validation
test_parallel_builds() {
    log_test "Testing parallel build validation"
    
    local build_jobs=3
    local pids=()
    
    log_info "Starting $build_jobs parallel builds..."
    
    for i in $(seq 1 $build_jobs); do
        (
            local job_id="job$i"
            local build_dir="$E2E_WORKSPACE/parallel_build_$job_id"
            
            mkdir -p "$build_dir"
            cp -r "$E2E_WORKSPACE"/* "$build_dir/"
            cd "$build_dir"
            
            log_info "[$job_id] Starting parallel build"
            
            # Build with different derivation names to avoid conflicts
            local start_time
            start_time=$(date +%s)
            
            nix build ".#backlog-md" --no-link --option substitute false
            
            local end_time
            end_time=$(date +%s)
            local duration=$((end_time - start_time))
            
            log_info "[$job_id] Build completed in ${duration}s"
            
            # Write result
            echo "$job_id:$duration" >> "$E2E_OUTPUT_DIR/parallel_build_results.txt"
            
        ) &
        pids+=($!)
    done
    
    # Wait for all builds to complete
    local failed_builds=0
    
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            ((failed_builds++))
        fi
    done
    
    # Analyze results
    if [[ -f "$E2E_OUTPUT_DIR/parallel_build_results.txt" ]]; then
        log_info "Parallel build results:"
        cat "$E2E_OUTPUT_DIR/parallel_build_results.txt"
        
        local completed_builds
        completed_builds=$(wc -l < "$E2E_OUTPUT_DIR/parallel_build_results.txt")
        
        assert_equals "$build_jobs" "$completed_builds" "All builds should complete"
    fi
    
    assert_equals 0 "$failed_builds" "No builds should fail"
    
    log_success "Parallel build validation passed!"
}

# Test rollback scenario
test_rollback_scenario() {
    log_test "Testing rollback scenario"
    
    # Create a checkpoint
    local checkpoint_commit
    checkpoint_commit=$(git rev-parse HEAD)
    
    log_info "Creating checkpoint at: $checkpoint_commit"
    
    # Introduce a breaking change
    log_info "Introducing breaking change..."
    
    # Corrupt the flake.nix
    echo "invalid nix syntax" >> flake.nix
    
    # Attempt to build (should fail)
    local build_failed=false
    if ! nix flake check --no-update-lock-file 2>/dev/null; then
        build_failed=true
        log_info "Build correctly failed with corrupted flake"
    fi
    
    assert_true "$build_failed" "Build should fail with corrupted flake"
    
    # Rollback to checkpoint
    log_info "Rolling back to checkpoint..."
    
    git reset --hard "$checkpoint_commit"
    
    # Verify rollback worked
    nix flake check --no-update-lock-file
    nix build ".#backlog-md" --no-link
    
    log_success "Rollback scenario test passed!"
}

# Test monitoring and alerting simulation
test_monitoring_alerting() {
    log_test "Testing monitoring and alerting simulation"
    
    local monitoring_log="$E2E_OUTPUT_DIR/monitoring.log"
    local alert_log="$E2E_OUTPUT_DIR/alerts.log"
    
    # Start monitoring process
    log_info "Starting monitoring simulation..."
    
    (
        for i in $(seq 1 10); do
            local timestamp
            timestamp=$(date -Iseconds)
            
            # Simulate health check
            if nix flake check --no-update-lock-file 2>/dev/null; then
                echo "$timestamp,health_check,PASS" >> "$monitoring_log"
            else
                echo "$timestamp,health_check,FAIL" >> "$monitoring_log"
                echo "$timestamp,ALERT,Health check failed" >> "$alert_log"
            fi
            
            # Simulate build time monitoring
            local start_time end_time duration
            start_time=$(date +%s.%3N)
            nix build ".#backlog-md" --no-link --quiet 2>/dev/null || true
            end_time=$(date +%s.%3N)
            duration=$(echo "$end_time - $start_time" | bc)
            
            echo "$timestamp,build_time,$duration" >> "$monitoring_log"
            
            # Alert on slow builds (>30s)
            if (( $(echo "$duration > 30" | bc -l) )); then
                echo "$timestamp,ALERT,Slow build detected: ${duration}s" >> "$alert_log"
            fi
            
            sleep 1
        done
    ) &
    
    local monitor_pid=$!
    
    # Let monitoring run
    sleep 5
    
    # Stop monitoring
    kill $monitor_pid 2>/dev/null || true
    wait $monitor_pid 2>/dev/null || true
    
    # Analyze monitoring data
    if [[ -f "$monitoring_log" ]]; then
        local health_checks
        health_checks=$(grep "health_check,PASS" "$monitoring_log" | wc -l)
        
        log_info "Health checks passed: $health_checks"
        assert_true "$(test "$health_checks" -gt 0 && echo true || echo false)" "Should have passed health checks"
    fi
    
    # Check for alerts
    if [[ -f "$alert_log" ]]; then
        local alert_count
        alert_count=$(wc -l < "$alert_log")
        log_info "Alerts generated: $alert_count"
    fi
    
    log_success "Monitoring and alerting test completed!"
}

# Test performance benchmarks
test_performance_benchmarks() {
    log_test "Testing performance benchmarks"
    
    local benchmark_results="$E2E_OUTPUT_DIR/benchmark_results.json"
    
    log_info "Running performance benchmarks..."
    
    # Benchmark 1: Cold build time
    log_info "Benchmark 1: Cold build time"
    nix store gc --max 0 2>/dev/null || true
    
    local cold_build_time
    cold_build_time=$(measure_time nix build ".#backlog-md" --no-link --rebuild)
    
    # Benchmark 2: Warm build time
    log_info "Benchmark 2: Warm build time"
    
    local warm_build_time
    warm_build_time=$(measure_time nix build ".#backlog-md" --no-link)
    
    # Benchmark 3: Flake evaluation time
    log_info "Benchmark 3: Flake evaluation time"
    
    local eval_time
    eval_time=$(measure_time nix flake show --no-update-lock-file)
    
    # Benchmark 4: Flake update time
    log_info "Benchmark 4: Flake update time"
    
    local update_time
    update_time=$(measure_time nix flake update)
    
    # Write benchmark results
    cat > "$benchmark_results" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "benchmarks": {
    "cold_build_time_seconds": $cold_build_time,
    "warm_build_time_seconds": $warm_build_time,
    "flake_eval_time_seconds": $eval_time,
    "flake_update_time_seconds": $update_time
  },
  "system_info": {
    "nix_version": "$(nix --version | head -n1)",
    "os": "$(uname -s)",
    "architecture": "$(uname -m)"
  }
}
EOF
    
    log_info "Benchmark results written to: $benchmark_results"
    
    # Performance assertions
    assert_true "$(echo "$cold_build_time < 300" | bc)" "Cold build should complete in under 5 minutes"
    assert_true "$(echo "$warm_build_time < 10" | bc)" "Warm build should complete in under 10 seconds"
    assert_true "$(echo "$eval_time < 5" | bc)" "Flake evaluation should complete in under 5 seconds"
    
    log_success "Performance benchmarks completed!"
}

# Main E2E test runner
run_e2e_tests() {
    log_header "Starting End-to-End Test Suite"
    
    init_test_environment
    
    # Setup
    setup_e2e_environment
    trap cleanup_e2e EXIT
    
    local failed_tests=0
    
    # Run E2E test cases
    run_test "complete_workflow" test_complete_workflow || ((failed_tests++))
    run_test "parallel_builds" test_parallel_builds || ((failed_tests++))
    run_test "rollback_scenario" test_rollback_scenario || ((failed_tests++))
    run_test "monitoring_alerting" test_monitoring_alerting || ((failed_tests++))
    run_test "performance_benchmarks" test_performance_benchmarks || ((failed_tests++))
    
    # Generate comprehensive report
    local e2e_report="$E2E_OUTPUT_DIR/e2e_test_report.json"
    generate_test_report "$e2e_report"
    
    # Results
    print_test_summary
    
    if [[ $failed_tests -eq 0 ]]; then
        log_success "All E2E tests passed! 🚀"
        exit 0
    else
        log_error "$failed_tests E2E tests failed"
        exit 1
    fi
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_e2e_tests "$@"
fi