#!/usr/bin/env bash
# Test Helper Functions and Utilities
# Provides common testing functionality across all test suites

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Test counters
export TEST_COUNT=0
export TEST_PASSED=0
export TEST_FAILED=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_test() {
    echo -e "${PURPLE}[TEST]${NC} $*" >&2
}

log_header() {
    echo -e "${CYAN}========================================${NC}" >&2
    echo -e "${CYAN} $*${NC}" >&2
    echo -e "${CYAN}========================================${NC}" >&2
}

# Assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2" 
    local message="${3:-Assertion failed}"
    
    if [[ "$expected" == "$actual" ]]; then
        log_success "✓ $message"
        return 0
    else
        log_error "✗ $message"
        log_error "  Expected: '$expected'"
        log_error "  Actual: '$actual'"
        return 1
    fi
}

assert_not_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should not be equal}"
    
    if [[ "$expected" != "$actual" ]]; then
        log_success "✓ $message"
        return 0
    else
        log_error "✗ $message"
        log_error "  Both values: '$expected'"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        log_success "✓ $message"
        return 0
    else
        log_error "✗ $message"
        log_error "  String: '$haystack'"
        log_error "  Should contain: '$needle'"
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should not contain substring}"
    
    if [[ "$haystack" != *"$needle"* ]]; then
        log_success "✓ $message"
        return 0
    else
        log_error "✗ $message"
        log_error "  String: '$haystack'"
        log_error "  Should not contain: '$needle'"
        return 1
    fi
}

assert_empty() {
    local value="$1"
    local message="${2:-Value should be empty}"
    
    if [[ -z "$value" ]]; then
        log_success "✓ $message"
        return 0
    else
        log_error "✗ $message"
        log_error "  Value: '$value'"
        return 1
    fi
}

assert_not_empty() {
    local value="$1"
    local message="${2:-Value should not be empty}"
    
    if [[ -n "$value" ]]; then
        log_success "✓ $message"
        return 0
    else
        log_error "✗ $message"
        log_error "  Value is empty"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist}"
    
    if [[ -f "$file" ]]; then
        log_success "✓ $message: $file"
        return 0
    else
        log_error "✗ $message: $file"
        return 1
    fi
}

assert_file_not_exists() {
    local file="$1"
    local message="${2:-File should not exist}"
    
    if [[ ! -f "$file" ]]; then
        log_success "✓ $message: $file"
        return 0
    else
        log_error "✗ $message: $file"
        return 1
    fi
}

assert_dir_exists() {
    local dir="$1"
    local message="${2:-Directory should exist}"
    
    if [[ -d "$dir" ]]; then
        log_success "✓ $message: $dir"
        return 0
    else
        log_error "✗ $message: $dir"
        return 1
    fi
}

assert_path_exists() {
    local path="$1"
    local message="${2:-Path should exist}"
    
    if [[ -e "$path" ]]; then
        log_success "✓ $message: $path"
        return 0
    else
        log_error "✗ $message: $path"
        return 1
    fi
}

assert_command_exists() {
    local command="$1"
    local message="${2:-Command should be available}"
    
    if command -v "$command" > /dev/null 2>&1; then
        log_success "✓ $message: $command"
        return 0
    else
        log_error "✗ $message: $command"
        return 1
    fi
}

assert_true() {
    local condition="$1"
    local message="${2:-Condition should be true}"
    
    if [[ "$condition" == "true" ]]; then
        log_success "✓ $message"
        return 0
    else
        log_error "✗ $message"
        log_error "  Condition: '$condition'"
        return 1
    fi
}

assert_false() {
    local condition="$1"
    local message="${2:-Condition should be false}"
    
    if [[ "$condition" == "false" ]]; then
        log_success "✓ $message"
        return 0
    else
        log_error "✗ $message"
        log_error "  Condition: '$condition'"
        return 1
    fi
}

assert_exit_code() {
    local expected_code="$1"
    local actual_code="$2"
    local message="${3:-Exit code assertion}"
    
    if [[ "$expected_code" -eq "$actual_code" ]]; then
        log_success "✓ $message (exit code: $actual_code)"
        return 0
    else
        log_error "✗ $message"
        log_error "  Expected exit code: $expected_code"
        log_error "  Actual exit code: $actual_code"
        return 1
    fi
}

# Test execution functions
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    ((TEST_COUNT++))
    
    log_test "Running test: $test_name"
    
    local start_time
    start_time=$(date +%s.%3N)
    
    if "$test_function"; then
        local end_time
        end_time=$(date +%s.%3N)
        local duration
        duration=$(echo "$end_time - $start_time" | bc)
        
        log_success "Test passed: $test_name (${duration}s)"
        ((TEST_PASSED++))
        return 0
    else
        local end_time
        end_time=$(date +%s.%3N)
        local duration
        duration=$(echo "$end_time - $start_time" | bc)
        
        log_error "Test failed: $test_name (${duration}s)"
        ((TEST_FAILED++))
        return 1
    fi
}

# Test environment utilities
setup_temp_dir() {
    local temp_dir
    temp_dir=$(mktemp -d)
    export TEST_TEMP_DIR="$temp_dir"
    log_info "Created temp directory: $temp_dir"
    echo "$temp_dir"
}

cleanup_temp_dir() {
    if [[ -n "${TEST_TEMP_DIR:-}" ]] && [[ -d "$TEST_TEMP_DIR" ]]; then
        log_info "Cleaning up temp directory: $TEST_TEMP_DIR"
        rm -rf "$TEST_TEMP_DIR"
        unset TEST_TEMP_DIR
    fi
}

# File comparison utilities
files_identical() {
    local file1="$1"
    local file2="$2"
    
    if [[ ! -f "$file1" ]] || [[ ! -f "$file2" ]]; then
        return 1
    fi
    
    cmp -s "$file1" "$file2"
}

file_contains() {
    local file="$1"
    local pattern="$2"
    
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    
    grep -q "$pattern" "$file"
}

# JSON utilities
json_extract() {
    local json="$1"
    local path="$2"
    
    echo "$json" | jq -r "$path"
}

assert_json_equals() {
    local json="$1"
    local path="$2"
    local expected="$3"
    local message="${4:-JSON path assertion}"
    
    local actual
    actual=$(json_extract "$json" "$path")
    
    assert_equals "$expected" "$actual" "$message"
}

# Version comparison utilities  
version_gt() {
    local version1="$1"
    local version2="$2"
    
    # Simple lexicographic comparison for semantic versions
    [[ "$(printf '%s\n' "$version1" "$version2" | sort -V | head -n1)" != "$version1" ]]
}

version_lt() {
    local version1="$1"
    local version2="$2"
    
    [[ "$(printf '%s\n' "$version1" "$version2" | sort -V | head -n1)" == "$version1" ]] && [[ "$version1" != "$version2" ]]
}

version_eq() {
    local version1="$1"
    local version2="$2"
    
    [[ "$version1" == "$version2" ]]
}

# Network utilities
wait_for_port() {
    local host="${1:-localhost}"
    local port="$2"
    local timeout="${3:-30}"
    
    local count=0
    
    while ! nc -z "$host" "$port" 2>/dev/null; do
        sleep 1
        ((count++))
        
        if [[ $count -ge $timeout ]]; then
            log_error "Timeout waiting for $host:$port"
            return 1
        fi
    done
    
    log_info "Port $host:$port is available"
    return 0
}

# Process utilities
wait_for_process() {
    local process_name="$1"
    local timeout="${2:-30}"
    
    local count=0
    
    while ! pgrep -f "$process_name" > /dev/null; do
        sleep 1
        ((count++))
        
        if [[ $count -ge $timeout ]]; then
            log_error "Timeout waiting for process: $process_name"
            return 1
        fi
    done
    
    log_info "Process found: $process_name"
    return 0
}

# Performance measurement
measure_time() {
    local start_time
    start_time=$(date +%s.%3N)
    
    "$@"
    
    local end_time
    end_time=$(date +%s.%3N)
    
    local duration
    duration=$(echo "$end_time - $start_time" | bc)
    
    echo "$duration"
}

# Mock utilities
create_mock_file() {
    local file_path="$1"
    local content="$2"
    
    mkdir -p "$(dirname "$file_path")"
    echo "$content" > "$file_path"
}

create_mock_executable() {
    local file_path="$1"
    local content="$2"
    
    create_mock_file "$file_path" "$content"
    chmod +x "$file_path"
}

# Report generation
generate_test_report() {
    local report_file="${1:-test_report.json}"
    
    cat > "$report_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "total_tests": $TEST_COUNT,
  "passed_tests": $TEST_PASSED,
  "failed_tests": $TEST_FAILED,
  "success_rate": $(echo "scale=2; $TEST_PASSED * 100 / $TEST_COUNT" | bc)
}
EOF
    
    log_info "Test report generated: $report_file"
}

print_test_summary() {
    log_header "Test Summary"
    echo -e "${BLUE}Total tests:${NC} $TEST_COUNT"
    echo -e "${GREEN}Passed:${NC} $TEST_PASSED"
    echo -e "${RED}Failed:${NC} $TEST_FAILED"
    
    if [[ $TEST_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed! 🎉${NC}"
    else
        local success_rate
        success_rate=$(echo "scale=1; $TEST_PASSED * 100 / $TEST_COUNT" | bc)
        echo -e "${YELLOW}Success rate: ${success_rate}%${NC}"
    fi
}

# Trap handlers for cleanup
setup_trap_handlers() {
    trap 'cleanup_temp_dir' EXIT
    trap 'log_error "Test interrupted"; cleanup_temp_dir; exit 130' INT TERM
}

# Initialize test environment
init_test_environment() {
    # Reset counters
    TEST_COUNT=0
    TEST_PASSED=0
    TEST_FAILED=0
    
    # Setup traps
    setup_trap_handlers
    
    # Verify required commands
    local required_commands=("nix" "jq" "bc" "curl")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done
    
    log_info "Test environment initialized"
}

# Export all functions for use in other scripts
set +u  # Allow undefined variables for the export check
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Script is being sourced, export functions
    export -f log_info log_success log_warn log_error log_test log_header
    export -f assert_equals assert_not_equals assert_contains assert_not_contains
    export -f assert_empty assert_not_empty assert_file_exists assert_file_not_exists
    export -f assert_dir_exists assert_path_exists assert_command_exists
    export -f assert_true assert_false assert_exit_code
    export -f run_test setup_temp_dir cleanup_temp_dir
    export -f files_identical file_contains json_extract assert_json_equals
    export -f version_gt version_lt version_eq wait_for_port wait_for_process
    export -f measure_time create_mock_file create_mock_executable
    export -f generate_test_report print_test_summary init_test_environment
fi
set -u