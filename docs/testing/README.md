# Testing Framework Documentation

This document describes the comprehensive testing framework for the auto-updating, auto-tagging flake building system for backlog.md@1.7.1.

## Overview

The testing framework provides multi-layered validation of the entire auto-build pipeline:

- **Unit Tests**: Core validation logic and utilities
- **Integration Tests**: NPM update workflow automation  
- **End-to-End Tests**: Complete build and deployment pipeline
- **Validation Tests**: Auto-tagging accuracy and consistency
- **Performance Tests**: Build time and resource monitoring
- **Monitoring**: Real-time build health and alerting

## Quick Start

### Run All Tests
```bash
# Run complete test suite
./tests/run-all-tests.sh

# Run specific test suites
./tests/run-all-tests.sh unit integration e2e
```

### Run Individual Test Suites
```bash
# Unit tests
./tests/unit/version-validation.test.sh

# Integration tests  
./tests/integration/auto-update-integration.test.sh

# End-to-end tests
./tests/e2e/auto-build-workflow.test.sh
```

### Monitor Build Health
```bash
# Start continuous monitoring
./tests/monitoring/build-monitor.sh start

# Single health check
./tests/monitoring/build-monitor.sh check

# Generate monitoring report
./tests/monitoring/build-monitor.sh report daily
```

## Test Architecture

### Framework Components

```
tests/
├── flake-test-framework.nix      # Nix testing utilities
├── utils/
│   └── test-helpers.sh          # Common testing functions
├── unit/                        # Unit test suites
├── integration/                 # Integration test suites  
├── e2e/                        # End-to-end test suites
├── validation/                 # Validation pipelines
├── monitoring/                 # Build monitoring
├── fixtures/                   # Test data and mocks
├── output/                     # Test results and reports
└── run-all-tests.sh            # Main test runner
```

### Test Types

#### 1. Unit Tests (`tests/unit/`)

**Purpose**: Test individual components and validation logic

**Coverage**:
- Semantic version validation and comparison
- NPM package version fetching
- Hash generation and validation
- Version range checking
- Package integrity verification

**Example**:
```bash
# Test semantic version validation
./tests/unit/version-validation.test.sh

# Expected output:
# ✓ Valid version accepted: 1.2.3
# ✓ Invalid version rejected: 1.2.a  
# ✓ Version comparison: 2.0.0 > 1.9.9
```

#### 2. Integration Tests (`tests/integration/`)

**Purpose**: Test complete update workflow automation

**Coverage**:
- NPM version monitoring and detection
- Flake update process (version + hash)
- Build validation after updates
- Git tagging automation
- Rollback scenarios
- Performance metrics collection

**Example**:
```bash
# Test auto-update integration
./tests/integration/auto-update-integration.test.sh

# Workflow tested:
# 1. Check NPM for newer version
# 2. Update flake.nix with new version/hash
# 3. Rebuild and validate package
# 4. Create git commit and tag
# 5. Verify rollback capability
```

#### 3. End-to-End Tests (`tests/e2e/`)

**Purpose**: Test complete automation pipeline from monitoring to deployment

**Coverage**:
- Full workflow automation
- Parallel build validation
- Error handling and recovery
- Monitoring and alerting simulation
- Performance benchmarking

**Example**:
```bash
# Test complete workflow
./tests/e2e/auto-build-workflow.test.sh

# Pipeline tested:
# NPM Monitor → Update Detection → Flake Update → 
# Build Validation → Git Tagging → Release Notes
```

#### 4. Validation Tests (`tests/validation/`)

**Purpose**: Validate auto-tagging accuracy and release consistency

**Coverage**:
- Git tag format validation (semantic versioning)
- Tag metadata verification
- Chronological tag ordering
- Release consistency (tag ↔ flake version)
- Batch tag validation

**Example**:
```bash
# Validate specific tag
nix run .#validateAutoTagging -- . v1.7.1 backlog-md 1.7.1

# Batch validate all tags
nix run .#validateTagBatch -- . ./validation_output
```

#### 5. Performance Tests

**Purpose**: Monitor build performance and resource usage

**Metrics Collected**:
- Build time (cold vs warm builds)
- Memory usage during builds
- Flake evaluation time
- Parallel build performance
- Resource utilization trends

#### 6. Monitoring (`tests/monitoring/`)

**Purpose**: Continuous build health monitoring with alerting

**Features**:
- Configurable monitoring intervals
- Build failure threshold alerting
- Performance degradation detection
- Multiple alert channels (Slack, email, webhook)
- Comprehensive reporting

## Configuration

### Test Configuration

Tests can be configured via environment variables:

```bash
# Test timeouts
export TEST_TIMEOUT=300
export BUILD_TIMEOUT=600

# Package settings  
export PACKAGE_NAME="backlog-md"
export FLAKE_PATH="/path/to/flake"

# Output directories
export TEST_OUTPUT_DIR="./test_output" 
export TEST_REPORTS_DIR="./reports"
```

### Monitoring Configuration

Create `tests/monitoring/monitor.conf`:

```bash
# Monitoring intervals (seconds)
CHECK_INTERVAL=30
BUILD_TIMEOUT=300

# Alert thresholds
FAILURE_THRESHOLD=3
ALERT_COOLDOWN=3600

# Performance thresholds
BUILD_TIME_WARNING=120
BUILD_TIME_CRITICAL=240
MEMORY_WARNING_MB=2048

# Alert channels
ENABLE_SLACK=true
SLACK_WEBHOOK_URL="https://hooks.slack.com/..."
SLACK_CHANNEL="#build-alerts"
```

## Nix Testing Framework

The Nix testing framework (`tests/flake-test-framework.nix`) provides utilities for:

### Flake Testing
```nix
# Test flake evaluation
testFlakeEval = flakePath: # ... validates flake.nix syntax

# Test package building  
testPackageBuild = { flakePath, package }: # ... builds and validates

# Test flake updates
testFlakeUpdate = flakePath: # ... tests update process
```

### NPM Integration
```nix  
# Test NPM package info retrieval
testNpmInfo = { package, version }: # ... validates NPM API calls

# Test package hash generation
testPackageHash = { package, version }: # ... generates Nix hashes
```

### Performance Monitoring
```nix
# Measure build time
measureBuildTime = { flakePath, package }: # ... times builds

# Monitor memory usage
monitorMemoryUsage = { flakePath, package }: # ... tracks resources
```

## Validation Pipeline

The validation pipeline ensures auto-tagging accuracy:

### Tag Format Validation
- Semantic versioning compliance (`v1.2.3`)
- Proper version progression
- Consistent naming conventions

### Metadata Validation  
- Annotated vs lightweight tags
- Tag messages and content
- Commit references and reachability

### Chronology Validation
- Version ordering (newer > older)
- Commit timeline consistency
- No version conflicts

### Release Consistency
- Tag version ↔ flake.nix version matching
- Package buildability at tagged commits
- Hash consistency verification

## Reporting

### Test Reports

The framework generates multiple report formats:

#### JSON Report
```json
{
  "test_session": {
    "id": "test_20250806_142030",
    "success": true,
    "duration_seconds": 245.7
  },
  "summary": {
    "total_suites": 5,
    "passed_suites": 5,
    "failed_suites": 0,
    "suite_success_rate": 100.0
  },
  "suite_reports": [...]
}
```

#### HTML Report
Interactive HTML report with:
- Visual test results dashboard
- Suite-by-suite breakdown
- Performance metrics
- Error details and logs

#### JUnit XML
For CI/CD integration:
```xml
<testsuites name="AutoBuildSystem" tests="24" failures="0">
  <testsuite name="Unit Tests" tests="6" failures="0">
    <testcase name="semver_validation" time="1.2"/>
  </testsuite>
</testsuites>
```

### Monitoring Reports

Build monitoring generates:
- Real-time health status
- Performance trend analysis
- Alert summaries
- Resource utilization metrics

## CI/CD Integration

### GitHub Actions

```yaml
name: Auto-Build Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - uses: cachix/install-nix-action@v22
    
    - name: Run test suite
      run: ./tests/run-all-tests.sh
      
    - name: Upload test results
      uses: actions/upload-artifact@v3
      if: always()
      with:
        name: test-results
        path: tests/output/
```

### Test Artifacts

CI artifacts include:
- `test_results.json` - Machine-readable results
- `test_results.xml` - JUnit format
- `status.json` - Simple pass/fail status
- Complete logs and reports

## Performance Benchmarks

Expected performance baselines:

| Metric | Target | Warning | Critical |
|--------|--------|---------|----------|  
| Cold Build | < 120s | > 180s | > 300s |
| Warm Build | < 10s | > 20s | > 30s |
| Flake Eval | < 5s | > 10s | > 15s |
| Memory Usage | < 1GB | > 2GB | > 4GB |

## Troubleshooting

### Common Issues

#### Test Failures
```bash
# Check test logs
cat tests/output/sessions/test_*/unit_output.log

# Run with verbose output
TEST_VERBOSE=1 ./tests/unit/version-validation.test.sh
```

#### Build Monitoring Issues
```bash
# Check monitor configuration
./tests/monitoring/build-monitor.sh config

# Test alert channels
./tests/monitoring/build-monitor.sh check
```

#### Performance Issues
```bash
# Run performance benchmarks
./tests/run-all-tests.sh performance

# Check system resources
nix run .#measureBuildTime
```

### Debug Mode

Enable debug mode for detailed output:
```bash
export TEST_DEBUG=1
export TEST_VERBOSE=1
./tests/run-all-tests.sh
```

## Contributing

### Adding New Tests

1. **Create test file** in appropriate directory
2. **Follow naming convention**: `*.test.sh`
3. **Use test helpers**: Source `tests/utils/test-helpers.sh`
4. **Add to test runner**: Update `run-all-tests.sh`

### Test Structure Template

```bash
#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_ROOT/tests/utils/test-helpers.sh"

test_my_feature() {
    log_test "Testing my feature"
    
    # Test implementation
    assert_equals "expected" "actual" "Feature should work"
    
    log_success "My feature test passed"
}

run_my_tests() {
    init_test_environment
    
    local failed_tests=0
    run_test "my_feature" test_my_feature || ((failed_tests++))
    
    print_test_summary
    exit $failed_tests
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_my_tests "$@"
fi
```

## Resources

- [Nix Testing Best Practices](https://nixos.org/manual/nix/stable/testing.html)
- [Semantic Versioning](https://semver.org/)
- [NPM Registry API](https://docs.npmjs.com/api/registry)
- [Git Tagging](https://git-scm.com/book/en/v2/Git-Basics-Tagging)

---

*This testing framework ensures the reliability and quality of the auto-build system through comprehensive validation at every level.*