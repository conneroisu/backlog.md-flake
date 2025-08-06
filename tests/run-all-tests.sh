#!/usr/bin/env bash
# Comprehensive Test Runner for Auto-Build System
# Executes all test suites with reporting and CI/CD integration

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly OUTPUT_DIR="$PROJECT_ROOT/tests/output"
readonly REPORTS_DIR="$OUTPUT_DIR/reports"

# Test configuration
declare -A TEST_SUITES=(
    [unit]="Unit Tests"
    [integration]="Integration Tests" 
    [e2e]="End-to-End Tests"
    [validation]="Validation Tests"
    [performance]="Performance Tests"
)

declare -A TEST_SCRIPTS=(
    [unit]="$SCRIPT_DIR/unit/version-validation.test.sh"
    [integration]="$SCRIPT_DIR/integration/auto-update-integration.test.sh"
    [e2e]="$SCRIPT_DIR/e2e/auto-build-workflow.test.sh"
    [validation]="$SCRIPT_DIR/validation/run-validation-tests.sh"
    [performance]="$SCRIPT_DIR/performance/run-benchmarks.sh"
)

# Load test utilities
source "$SCRIPT_DIR/utils/test-helpers.sh"

# Initialize test environment
setup_test_runner() {
    log_info "Setting up comprehensive test runner..."
    
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$REPORTS_DIR"
    
    # Initialize test counters
    export TOTAL_TEST_SUITES=0
    export PASSED_TEST_SUITES=0
    export FAILED_TEST_SUITES=0
    
    export TOTAL_TESTS=0
    export PASSED_TESTS=0 
    export FAILED_TESTS=0
    
    # Create test session
    export TEST_SESSION_ID="test_$(date +%Y%m%d_%H%M%S)"
    export TEST_SESSION_DIR="$OUTPUT_DIR/sessions/$TEST_SESSION_ID"
    
    mkdir -p "$TEST_SESSION_DIR"
    
    log_info "Test session: $TEST_SESSION_ID"
    log_info "Output directory: $TEST_SESSION_DIR"
}

# Run individual test suite
run_test_suite() {
    local suite_name="$1"
    local suite_description="${TEST_SUITES[$suite_name]}"
    local test_script="${TEST_SCRIPTS[$suite_name]}"
    
    ((TOTAL_TEST_SUITES++))
    
    log_header "Running $suite_description"
    
    local suite_start_time
    suite_start_time=$(date +%s.%3N)
    
    local suite_output="$TEST_SESSION_DIR/${suite_name}_output.log"
    local suite_report="$TEST_SESSION_DIR/${suite_name}_report.json"
    
    # Check if test script exists
    if [[ ! -f "$test_script" ]]; then
        log_error "Test script not found: $test_script"
        log_error "Skipping $suite_description"
        
        # Create dummy report for missing test
        create_missing_test_report "$suite_name" "$suite_report"
        return 1
    fi
    
    # Make test script executable
    chmod +x "$test_script"
    
    # Run test suite with timeout
    local suite_success=false
    local suite_timeout=1800  # 30 minutes
    
    if timeout "$suite_timeout" "$test_script" > "$suite_output" 2>&1; then
        suite_success=true
        ((PASSED_TEST_SUITES++))
        log_success "$suite_description passed"
    else
        local exit_code=$?
        suite_success=false
        ((FAILED_TEST_SUITES++))
        
        if [[ $exit_code -eq 124 ]]; then
            log_error "$suite_description timed out after ${suite_timeout}s"
        else
            log_error "$suite_description failed with exit code $exit_code"
        fi
    fi
    
    local suite_end_time
    suite_end_time=$(date +%s.%3N)
    local suite_duration
    suite_duration=$(echo "$suite_end_time - $suite_start_time" | bc)
    
    # Parse test results from output
    parse_test_results "$suite_output" "$suite_name"
    
    # Create suite report
    create_suite_report "$suite_name" "$suite_success" "$suite_duration" "$suite_report"
    
    # Show suite summary
    log_info "$suite_description completed in ${suite_duration}s"
    
    return $([ "$suite_success" == "true" ] && echo 0 || echo 1)
}

# Parse test results from output
parse_test_results() {
    local output_file="$1"
    local suite_name="$2"
    
    if [[ ! -f "$output_file" ]]; then
        return 0
    fi
    
    # Extract test counts from output (assuming standard format)
    local suite_total suite_passed suite_failed
    
    # Try to parse from test helper output
    suite_total=$(grep -o "Total tests: [0-9]\+" "$output_file" | tail -1 | grep -o "[0-9]\+" || echo "0")
    suite_passed=$(grep -o "Passed: [0-9]\+" "$output_file" | tail -1 | grep -o "[0-9]\+" || echo "0")
    suite_failed=$(grep -o "Failed: [0-9]\+" "$output_file" | tail -1 | grep -o "[0-9]\+" || echo "0")
    
    # If no standard format found, try alternative parsing
    if [[ "$suite_total" -eq 0 ]]; then
        suite_passed=$(grep -c "✓\|PASS\|SUCCESS" "$output_file" || echo "0")
        suite_failed=$(grep -c "✗\|FAIL\|ERROR" "$output_file" || echo "0") 
        suite_total=$((suite_passed + suite_failed))
    fi
    
    # Update global counters
    TOTAL_TESTS=$((TOTAL_TESTS + suite_total))
    PASSED_TESTS=$((PASSED_TESTS + suite_passed))
    FAILED_TESTS=$((FAILED_TESTS + suite_failed))
    
    log_info "$suite_name results: $suite_total total, $suite_passed passed, $suite_failed failed"
}

# Create test suite report
create_suite_report() {
    local suite_name="$1"
    local success="$2"
    local duration="$3"
    local report_file="$4"
    
    local suite_total suite_passed suite_failed
    
    # Extract counts from global parsing (this is a simplified approach)
    # In a real implementation, we'd parse the specific suite results
    suite_total=$(grep -c "test" "$TEST_SESSION_DIR/${suite_name}_output.log" 2>/dev/null || echo "1")
    suite_passed=$([ "$success" == "true" ] && echo "$suite_total" || echo "0")
    suite_failed=$([ "$success" == "true" ] && echo "0" || echo "$suite_total")
    
    cat > "$report_file" << EOF
{
  "suite_name": "$suite_name",
  "suite_description": "${TEST_SUITES[$suite_name]}",
  "timestamp": "$(date -Iseconds)",
  "success": $success,
  "duration_seconds": $duration,
  "test_counts": {
    "total": $suite_total,
    "passed": $suite_passed,
    "failed": $suite_failed
  },
  "output_file": "$TEST_SESSION_DIR/${suite_name}_output.log",
  "test_script": "${TEST_SCRIPTS[$suite_name]}"
}
EOF
}

# Create report for missing test
create_missing_test_report() {
    local suite_name="$1"
    local report_file="$2"
    
    cat > "$report_file" << EOF
{
  "suite_name": "$suite_name",
  "suite_description": "${TEST_SUITES[$suite_name]}",
  "timestamp": "$(date -Iseconds)",
  "success": false,
  "error": "Test script not found",
  "duration_seconds": 0,
  "test_counts": {
    "total": 0,
    "passed": 0,
    "failed": 1
  },
  "test_script": "${TEST_SCRIPTS[$suite_name]}"
}
EOF
    
    ((FAILED_TEST_SUITES++))
}

# Generate comprehensive test report
generate_comprehensive_report() {
    local final_report="$REPORTS_DIR/comprehensive_report_$(date +%Y%m%d_%H%M%S).json"
    
    log_info "Generating comprehensive test report..."
    
    # Collect all suite reports
    local suite_reports=()
    for suite in "${!TEST_SUITES[@]}"; do
        local suite_report="$TEST_SESSION_DIR/${suite}_report.json"
        if [[ -f "$suite_report" ]]; then
            suite_reports+=("$suite_report")
        fi
    done
    
    # Calculate overall metrics
    local success_rate=0
    if [[ $TOTAL_TEST_SUITES -gt 0 ]]; then
        success_rate=$(echo "scale=1; $PASSED_TEST_SUITES * 100 / $TOTAL_TEST_SUITES" | bc)
    fi
    
    local overall_success=false
    if [[ $FAILED_TEST_SUITES -eq 0 ]]; then
        overall_success=true
    fi
    
    # Start building the report
    cat > "$final_report" << EOF
{
  "test_session": {
    "id": "$TEST_SESSION_ID",
    "timestamp": "$(date -Iseconds)",
    "duration_seconds": $(echo "$(date +%s.%3N) - ${TEST_START_TIME:-$(date +%s.%3N)}" | bc),
    "success": $overall_success
  },
  "summary": {
    "total_suites": $TOTAL_TEST_SUITES,
    "passed_suites": $PASSED_TEST_SUITES,
    "failed_suites": $FAILED_TEST_SUITES,
    "suite_success_rate": $success_rate,
    "total_tests": $TOTAL_TESTS,
    "passed_tests": $PASSED_TESTS,
    "failed_tests": $FAILED_TESTS,
    "test_success_rate": $(echo "scale=1; $PASSED_TESTS * 100 / ($TOTAL_TESTS + 0.01)" | bc)
  },
  "environment": {
    "nix_version": "$(nix --version | head -n1)",
    "os": "$(uname -s)",
    "architecture": "$(uname -m)",
    "hostname": "$(hostname)",
    "user": "$(whoami)",
    "pwd": "$(pwd)"
  },
  "suite_reports": [
EOF
    
    # Add suite reports
    local first=true
    for report_file in "${suite_reports[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$final_report"
        fi
        cat "$report_file" >> "$final_report"
    done
    
    cat >> "$final_report" << EOF
  ],
  "artifacts": {
    "session_directory": "$TEST_SESSION_DIR",
    "log_files": [
EOF
    
    # Add log files
    local log_files=()
    while IFS= read -r -d '' file; do
        log_files+=("$file")
    done < <(find "$TEST_SESSION_DIR" -name "*.log" -print0)
    
    first=true
    for log_file in "${log_files[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$final_report"
        fi
        echo "      \"$log_file\"" >> "$final_report"
    done
    
    cat >> "$final_report" << EOF
    ]
  }
}
EOF
    
    log_info "Comprehensive report generated: $final_report"
    
    # Create symlink to latest report
    local latest_report="$REPORTS_DIR/latest_comprehensive_report.json"
    ln -sf "$final_report" "$latest_report"
    
    echo "$final_report"
}

# Generate HTML report
generate_html_report() {
    local json_report="$1"
    local html_report="${json_report%.json}.html"
    
    if [[ ! -f "$json_report" ]]; then
        log_error "JSON report not found: $json_report"
        return 1
    fi
    
    log_info "Generating HTML report..."
    
    # Extract data from JSON report
    local session_id success total_suites passed_suites failed_suites
    session_id=$(jq -r '.test_session.id' "$json_report")
    success=$(jq -r '.test_session.success' "$json_report")
    total_suites=$(jq -r '.summary.total_suites' "$json_report") 
    passed_suites=$(jq -r '.summary.passed_suites' "$json_report")
    failed_suites=$(jq -r '.summary.failed_suites' "$json_report")
    
    # Generate HTML
    cat > "$html_report" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Test Report - $session_id</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { text-align: center; margin-bottom: 30px; padding-bottom: 20px; border-bottom: 2px solid #eee; }
        .status { display: inline-block; padding: 8px 16px; border-radius: 4px; font-weight: bold; margin-left: 10px; }
        .status.success { background: #d4edda; color: #155724; }
        .status.failure { background: #f8d7da; color: #721c24; }
        .metrics { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 30px 0; }
        .metric { text-align: center; padding: 20px; background: #f8f9fa; border-radius: 6px; }
        .metric-value { font-size: 2em; font-weight: bold; margin-bottom: 5px; }
        .metric-label { color: #666; font-size: 0.9em; }
        .suites { margin-top: 30px; }
        .suite { margin: 15px 0; padding: 15px; border: 1px solid #ddd; border-radius: 4px; }
        .suite.success { border-left: 4px solid #28a745; }
        .suite.failure { border-left: 4px solid #dc3545; }
        .suite-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; }
        .suite-name { font-weight: bold; }
        .suite-duration { color: #666; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Auto-Build System Test Report</h1>
            <h2>Session: $session_id</h2>
            <span class="status $([ "$success" == "true" ] && echo "success" || echo "failure")">
                $([ "$success" == "true" ] && echo "✅ ALL PASSED" || echo "❌ SOME FAILED")
            </span>
        </div>
        
        <div class="metrics">
            <div class="metric">
                <div class="metric-value">$total_suites</div>
                <div class="metric-label">Test Suites</div>
            </div>
            <div class="metric">
                <div class="metric-value" style="color: #28a745">$passed_suites</div>
                <div class="metric-label">Passed</div>
            </div>
            <div class="metric">
                <div class="metric-value" style="color: #dc3545">$failed_suites</div>
                <div class="metric-label">Failed</div>
            </div>
            <div class="metric">
                <div class="metric-value">$(jq -r '.summary.suite_success_rate' "$json_report")%</div>
                <div class="metric-label">Success Rate</div>
            </div>
        </div>
        
        <div class="suites">
            <h3>Test Suite Results</h3>
EOF
    
    # Add suite details
    jq -r '.suite_reports[] | @base64' "$json_report" | while IFS= read -r suite_data; do
        local suite_json
        suite_json=$(echo "$suite_data" | base64 -d)
        
        local suite_name suite_desc suite_success suite_duration
        suite_name=$(echo "$suite_json" | jq -r '.suite_name')
        suite_desc=$(echo "$suite_json" | jq -r '.suite_description')
        suite_success=$(echo "$suite_json" | jq -r '.success')
        suite_duration=$(echo "$suite_json" | jq -r '.duration_seconds')
        
        local status_class status_icon
        if [[ "$suite_success" == "true" ]]; then
            status_class="success"
            status_icon="✅"
        else
            status_class="failure" 
            status_icon="❌"
        fi
        
        cat >> "$html_report" << EOF
            <div class="suite $status_class">
                <div class="suite-header">
                    <span class="suite-name">$status_icon $suite_desc</span>
                    <span class="suite-duration">${suite_duration}s</span>
                </div>
                <div class="suite-details">
                    Tests: $(echo "$suite_json" | jq -r '.test_counts.total // 0') | 
                    Passed: $(echo "$suite_json" | jq -r '.test_counts.passed // 0') | 
                    Failed: $(echo "$suite_json" | jq -r '.test_counts.failed // 0')
                </div>
            </div>
EOF
    done
    
    cat >> "$html_report" << EOF
        </div>
        
        <div style="margin-top: 40px; text-align: center; color: #666; font-size: 0.9em;">
            Generated at $(date) by Auto-Build Test System
        </div>
    </div>
</body>
</html>
EOF
    
    log_info "HTML report generated: $html_report"
}

# CI/CD integration functions
prepare_ci_artifacts() {
    log_info "Preparing CI/CD artifacts..."
    
    local ci_dir="$OUTPUT_DIR/ci"
    mkdir -p "$ci_dir"
    
    # Copy important files for CI
    if [[ -f "$REPORTS_DIR/latest_comprehensive_report.json" ]]; then
        cp "$REPORTS_DIR/latest_comprehensive_report.json" "$ci_dir/test_results.json"
    fi
    
    # Create JUnit XML format for CI systems
    create_junit_report "$ci_dir/test_results.xml"
    
    # Create simple status file
    local overall_success=true
    if [[ $FAILED_TEST_SUITES -gt 0 ]]; then
        overall_success=false
    fi
    
    echo "{\"success\": $overall_success, \"failed_suites\": $FAILED_TEST_SUITES}" > "$ci_dir/status.json"
    
    log_info "CI artifacts prepared in: $ci_dir"
}

# Create JUnit XML report for CI integration
create_junit_report() {
    local junit_file="$1"
    
    cat > "$junit_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="AutoBuildSystem" tests="$TOTAL_TESTS" failures="$FAILED_TESTS" time="$(echo "$(date +%s) - ${TEST_START_TIME:-$(date +%s)}" | bc)">
EOF
    
    for suite in "${!TEST_SUITES[@]}"; do
        local suite_report="$TEST_SESSION_DIR/${suite}_report.json"
        if [[ -f "$suite_report" ]]; then
            local suite_success suite_duration suite_total suite_failed
            suite_success=$(jq -r '.success' "$suite_report")
            suite_duration=$(jq -r '.duration_seconds' "$suite_report") 
            suite_total=$(jq -r '.test_counts.total' "$suite_report")
            suite_failed=$(jq -r '.test_counts.failed' "$suite_report")
            
            cat >> "$junit_file" << EOF
  <testsuite name="${TEST_SUITES[$suite]}" tests="$suite_total" failures="$suite_failed" time="$suite_duration">
EOF
            
            if [[ "$suite_success" == "true" ]]; then
                cat >> "$junit_file" << EOF
    <testcase name="$suite" time="$suite_duration"/>
EOF
            else
                cat >> "$junit_file" << EOF
    <testcase name="$suite" time="$suite_duration">
      <failure message="Test suite failed">Suite execution failed</failure>
    </testcase>
EOF
            fi
            
            echo "  </testsuite>" >> "$junit_file"
        fi
    done
    
    echo "</testsuites>" >> "$junit_file"
}

# Main test execution
run_all_tests() {
    local suites_to_run=("$@")
    
    # If no suites specified, run all
    if [[ ${#suites_to_run[@]} -eq 0 ]]; then
        suites_to_run=("${!TEST_SUITES[@]}")
    fi
    
    log_header "Starting Comprehensive Test Suite"
    log_info "Running test suites: ${suites_to_run[*]}"
    
    export TEST_START_TIME=$(date +%s.%3N)
    
    # Setup test environment
    setup_test_runner
    
    # Run test suites
    for suite in "${suites_to_run[@]}"; do
        if [[ -n "${TEST_SUITES[$suite]:-}" ]]; then
            run_test_suite "$suite" || true  # Continue with other suites
        else
            log_error "Unknown test suite: $suite"
        fi
    done
    
    # Generate reports
    local json_report
    json_report=$(generate_comprehensive_report)
    
    local html_report="${json_report%.json}.html"
    generate_html_report "$json_report"
    
    # Prepare CI artifacts
    prepare_ci_artifacts
    
    # Final summary
    log_header "Test Execution Complete"
    log_info "Session ID: $TEST_SESSION_ID"
    log_info "JSON Report: $json_report"
    log_info "HTML Report: $html_report"
    log_info ""
    log_info "Summary:"
    log_info "  Total Suites: $TOTAL_TEST_SUITES"
    log_info "  Passed Suites: $PASSED_TEST_SUITES"
    log_info "  Failed Suites: $FAILED_TEST_SUITES"
    log_info "  Total Tests: $TOTAL_TESTS"
    log_info "  Passed Tests: $PASSED_TESTS"
    log_info "  Failed Tests: $FAILED_TESTS"
    
    if [[ $FAILED_TEST_SUITES -eq 0 ]]; then
        log_success "🎉 All test suites passed!"
        exit 0
    else
        log_error "❌ $FAILED_TEST_SUITES test suite(s) failed"
        exit 1
    fi
}

# CLI interface
main() {
    local command="${1:-run}"
    
    case "$command" in
        "run")
            shift
            run_all_tests "$@"
            ;;
        "list")
            echo "Available test suites:"
            for suite in "${!TEST_SUITES[@]}"; do
                echo "  $suite - ${TEST_SUITES[$suite]}"
            done
            ;;
        "help"|*)
            echo "Comprehensive Test Runner - Usage:"
            echo "  $0 run [suite1] [suite2] ...  - Run test suites (all if none specified)"
            echo "  $0 list                       - List available test suites"
            echo "  $0 help                       - Show this help"
            echo ""
            echo "Available suites: ${!TEST_SUITES[*]}"
            ;;
    esac
}

# Initialize test helpers
init_test_environment

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi