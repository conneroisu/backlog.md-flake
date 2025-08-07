# Comprehensive Flake Build Testing Framework
# Provides utilities for testing Nix flakes, builds, and package updates

{ pkgs ? import <nixpkgs> { }
, lib ? pkgs.lib
, writeShellScript ? pkgs.writeShellScript
, fetchurl ? pkgs.fetchurl
}:

let
  inherit (lib) concatStringsSep mapAttrsToList;

  # Test utilities for flake operations
  flakeTestUtils = rec {
    # Create a test flake environment
    mkTestFlake = { name, inputs ? {}, outputs ? {} }: pkgs.writeTextFile {
      name = "${name}-flake.nix";
      text = ''
        {
          description = "Test flake for ${name}";
          inputs = ${builtins.toJSON inputs};
          outputs = { self, nixpkgs, ... }: ${builtins.toJSON outputs};
        }
      '';
    };

    # Test flake lock file generation
    testFlakeLock = flakePath: writeShellScript "test-flake-lock" ''
      set -euo pipefail
      
      FLAKE_PATH="${flakePath}"
      TEMP_DIR=$(mktemp -d)
      
      echo "Testing flake lock generation for $FLAKE_PATH"
      
      # Copy flake to temp directory
      cp "$FLAKE_PATH/flake.nix" "$TEMP_DIR/"
      cd "$TEMP_DIR"
      
      # Test lock file generation
      ${pkgs.nix}/bin/nix flake lock --no-update-lock-file
      
      if [ ! -f "flake.lock" ]; then
        echo "ERROR: flake.lock not generated"
        exit 1
      fi
      
      echo "✓ Flake lock generated successfully"
      
      # Test lock file is valid JSON
      ${pkgs.jq}/bin/jq . flake.lock > /dev/null
      echo "✓ Flake lock is valid JSON"
      
      # Cleanup
      rm -rf "$TEMP_DIR"
    '';

    # Test flake evaluation
    testFlakeEval = flakePath: writeShellScript "test-flake-eval" ''
      set -euo pipefail
      
      FLAKE_PATH="${flakePath}"
      
      echo "Testing flake evaluation for $FLAKE_PATH"
      
      # Test flake show works
      ${pkgs.nix}/bin/nix flake show "$FLAKE_PATH" --no-update-lock-file
      echo "✓ Flake show successful"
      
      # Test flake check
      ${pkgs.nix}/bin/nix flake check "$FLAKE_PATH" --no-update-lock-file
      echo "✓ Flake check passed"
    '';

    # Test package building
    testPackageBuild = { flakePath, package ? "default" }: writeShellScript "test-package-build" ''
      set -euo pipefail
      
      FLAKE_PATH="${flakePath}"
      PACKAGE="${package}"
      
      echo "Testing package build: $PACKAGE"
      
      # Build the package
      RESULT=$(${pkgs.nix}/bin/nix build "$FLAKE_PATH#$PACKAGE" --print-out-paths --no-link)
      
      if [ -z "$RESULT" ]; then
        echo "ERROR: Package build failed"
        exit 1
      fi
      
      echo "✓ Package built successfully: $RESULT"
      
      # Verify the built package exists
      if [ ! -e "$RESULT" ]; then
        echo "ERROR: Built package does not exist at $RESULT"
        exit 1
      fi
      
      echo "✓ Built package verified at: $RESULT"
    '';

    # Test flake update
    testFlakeUpdate = flakePath: writeShellScript "test-flake-update" ''
      set -euo pipefail
      
      FLAKE_PATH="${flakePath}"
      TEMP_DIR=$(mktemp -d)
      
      echo "Testing flake update for $FLAKE_PATH"
      
      # Copy flake to temp directory
      cp -r "$FLAKE_PATH"/* "$TEMP_DIR/"
      cd "$TEMP_DIR"
      
      # Record original lock hash
      ORIGINAL_HASH=""
      if [ -f "flake.lock" ]; then
        ORIGINAL_HASH=$(sha256sum flake.lock | cut -d' ' -f1)
      fi
      
      # Update flake
      ${pkgs.nix}/bin/nix flake update
      
      # Verify lock file changed (if it existed before)
      if [ -n "$ORIGINAL_HASH" ]; then
        NEW_HASH=$(sha256sum flake.lock | cut -d' ' -f1)
        if [ "$ORIGINAL_HASH" = "$NEW_HASH" ]; then
          echo "WARNING: Flake lock file unchanged after update"
        else
          echo "✓ Flake lock file updated"
        fi
      fi
      
      # Test that updated flake still builds
      ${pkgs.nix}/bin/nix flake check --no-update-lock-file
      echo "✓ Updated flake passes checks"
      
      # Cleanup
      rm -rf "$TEMP_DIR"
    '';
  };

  # NPM package testing utilities
  npmTestUtils = rec {
    # Test NPM package info retrieval
    testNpmInfo = { package, version ? "latest" }: writeShellScript "test-npm-info" ''
      set -euo pipefail
      
      PACKAGE="${package}"
      VERSION="${version}"
      
      echo "Testing NPM info for $PACKAGE@$VERSION"
      
      # Get package info
      INFO=$(${pkgs.nodejs}/bin/npm view "$PACKAGE@$VERSION" --json)
      
      # Verify we got valid JSON
      echo "$INFO" | ${pkgs.jq}/bin/jq . > /dev/null
      echo "✓ NPM info retrieved and is valid JSON"
      
      # Extract key fields
      NAME=$(echo "$INFO" | ${pkgs.jq}/bin/jq -r '.name')
      VER=$(echo "$INFO" | ${pkgs.jq}/bin/jq -r '.version')
      
      echo "✓ Package: $NAME@$VER"
    '';

    # Test package hash generation
    testPackageHash = { package, version }: writeShellScript "test-package-hash" ''
      set -euo pipefail
      
      PACKAGE="${package}"
      VERSION="${version}"
      
      echo "Testing package hash generation for $PACKAGE@$VERSION"
      
      # Get package tarball URL
      TARBALL_URL=$(${pkgs.nodejs}/bin/npm view "$PACKAGE@$VERSION" dist.tarball --silent)
      
      if [ -z "$TARBALL_URL" ]; then
        echo "ERROR: Could not get tarball URL"
        exit 1
      fi
      
      echo "Tarball URL: $TARBALL_URL"
      
      # Generate hash using nix-prefetch-url
      HASH=$(${pkgs.nix}/bin/nix-prefetch-url "$TARBALL_URL")
      
      if [ -z "$HASH" ]; then
        echo "ERROR: Could not generate hash"
        exit 1
      fi
      
      echo "✓ Generated hash: $HASH"
    '';

    # Test version comparison
    testVersionCompare = writeShellScript "test-version-compare" ''
      set -euo pipefail
      
      echo "Testing version comparison utilities"
      
      # Test semver comparison using node
      ${pkgs.nodejs}/bin/node -e "
        const semver = require('semver');
        
        // Test basic comparison
        console.assert(semver.gt('2.0.0', '1.9.9'), 'Version comparison failed');
        console.assert(semver.lt('1.0.0', '1.0.1'), 'Version comparison failed');
        console.assert(semver.eq('1.2.3', '1.2.3'), 'Version equality failed');
        
        console.log('✓ Version comparison tests passed');
      "
    '';
  };

  # Integration testing utilities
  integrationTestUtils = rec {
    # Test complete build workflow
    testBuildWorkflow = { flakePath, package, expectedVersion }: writeShellScript "test-build-workflow" ''
      set -euo pipefail
      
      FLAKE_PATH="${flakePath}"
      PACKAGE="${package}"
      EXPECTED_VERSION="${expectedVersion}"
      
      echo "Testing complete build workflow"
      echo "Flake: $FLAKE_PATH"
      echo "Package: $PACKAGE"
      echo "Expected Version: $EXPECTED_VERSION"
      
      # Step 1: Test flake evaluation
      echo "Step 1: Testing flake evaluation..."
      ${flakeTestUtils.testFlakeEval flakePath}
      
      # Step 2: Test package build
      echo "Step 2: Testing package build..."
      ${flakeTestUtils.testPackageBuild { inherit flakePath package; }}
      
      # Step 3: Verify version
      echo "Step 3: Verifying version..."
      BUILT_VERSION=$(${pkgs.nix}/bin/nix eval "$FLAKE_PATH#$PACKAGE.version" --raw)
      
      if [ "$BUILT_VERSION" != "$EXPECTED_VERSION" ]; then
        echo "ERROR: Version mismatch. Expected: $EXPECTED_VERSION, Got: $BUILT_VERSION"
        exit 1
      fi
      
      echo "✓ Version verified: $BUILT_VERSION"
      echo "✓ Complete build workflow test passed"
    '';

    # Test update and rebuild cycle
    testUpdateCycle = { flakePath, package }: writeShellScript "test-update-cycle" ''
      set -euo pipefail
      
      FLAKE_PATH="${flakePath}"
      PACKAGE="${package}"
      TEMP_DIR=$(mktemp -d)
      
      echo "Testing update and rebuild cycle"
      
      # Copy flake to temp directory
      cp -r "$FLAKE_PATH"/* "$TEMP_DIR/"
      cd "$TEMP_DIR"
      
      # Get initial version
      INITIAL_VERSION=$(${pkgs.nix}/bin/nix eval ".#$PACKAGE.version" --raw)
      echo "Initial version: $INITIAL_VERSION"
      
      # Update flake
      echo "Updating flake..."
      ${pkgs.nix}/bin/nix flake update
      
      # Rebuild and check version
      echo "Rebuilding package..."
      ${pkgs.nix}/bin/nix build ".#$PACKAGE" --no-link
      
      NEW_VERSION=$(${pkgs.nix}/bin/nix eval ".#$PACKAGE.version" --raw)
      echo "New version: $NEW_VERSION"
      
      # Test still builds successfully
      ${pkgs.nix}/bin/nix flake check --no-update-lock-file
      echo "✓ Updated package builds and passes checks"
      
      # Cleanup
      rm -rf "$TEMP_DIR"
    '';
  };

  # Performance testing utilities
  perfTestUtils = rec {
    # Measure build time
    measureBuildTime = { flakePath, package }: writeShellScript "measure-build-time" ''
      set -euo pipefail
      
      FLAKE_PATH="${flakePath}"
      PACKAGE="${package}"
      
      echo "Measuring build time for $PACKAGE"
      
      # Clean any existing builds
      ${pkgs.nix}/bin/nix store gc --max 0 || true
      
      # Measure build time
      START_TIME=$(date +%s.%3N)
      ${pkgs.nix}/bin/nix build "$FLAKE_PATH#$PACKAGE" --no-link --rebuild
      END_TIME=$(date +%s.%3N)
      
      # Calculate duration
      DURATION=$(echo "$END_TIME - $START_TIME" | ${pkgs.bc}/bin/bc)
      
      echo "Build completed in: ''${DURATION}s"
      echo "build_time_seconds:$DURATION" >> build_metrics.log
    '';

    # Measure flake evaluation time
    measureEvalTime = flakePath: writeShellScript "measure-eval-time" ''
      set -euo pipefail
      
      FLAKE_PATH="${flakePath}"
      
      echo "Measuring flake evaluation time"
      
      START_TIME=$(date +%s.%3N)
      ${pkgs.nix}/bin/nix flake show "$FLAKE_PATH" > /dev/null
      END_TIME=$(date +%s.%3N)
      
      DURATION=$(echo "$END_TIME - $START_TIME" | ${pkgs.bc}/bin/bc)
      
      echo "Evaluation completed in: ''${DURATION}s"
      echo "eval_time_seconds:$DURATION" >> eval_metrics.log
    '';

    # Memory usage monitoring
    monitorMemoryUsage = { flakePath, package }: writeShellScript "monitor-memory" ''
      set -euo pipefail
      
      FLAKE_PATH="${flakePath}"
      PACKAGE="${package}"
      
      echo "Monitoring memory usage during build"
      
      # Start memory monitoring in background
      (
        while true; do
          MEMORY=$(${pkgs.procps}/bin/free -m | awk 'NR==2{printf "%.1f", $3*100/$2 }')
          echo "$(date '+%Y-%m-%d %H:%M:%S'),memory_usage_percent,$MEMORY" >> memory_metrics.log
          sleep 1
        done
      ) &
      MONITOR_PID=$!
      
      # Run the build
      ${pkgs.nix}/bin/nix build "$FLAKE_PATH#$PACKAGE" --no-link
      
      # Stop monitoring
      kill $MONITOR_PID 2>/dev/null || true
      
      echo "Memory monitoring complete. See memory_metrics.log"
    '';
  };

in {
  inherit flakeTestUtils npmTestUtils integrationTestUtils perfTestUtils;
  
  # Main test suite runner
  runTestSuite = { flakePath, package ? "default", testTypes ? [ "unit" "integration" "performance" ] }: writeShellScript "run-test-suite" ''
    set -euo pipefail
    
    FLAKE_PATH="${flakePath}"
    PACKAGE="${package}"
    TEST_TYPES=(${concatStringsSep " " testTypes})
    
    echo "Running comprehensive test suite"
    echo "Flake: $FLAKE_PATH"
    echo "Package: $PACKAGE"
    echo "Test Types: ''${TEST_TYPES[@]}"
    echo ""
    
    FAILED_TESTS=0
    
    for TEST_TYPE in "''${TEST_TYPES[@]}"; do
      echo "=== Running $TEST_TYPE tests ==="
      
      case "$TEST_TYPE" in
        "unit")
          echo "Unit tests..."
          ${flakeTestUtils.testFlakeLock flakePath} || ((FAILED_TESTS++))
          ${flakeTestUtils.testFlakeEval flakePath} || ((FAILED_TESTS++))
          ${npmTestUtils.testVersionCompare} || ((FAILED_TESTS++))
          ;;
        "integration") 
          echo "Integration tests..."
          ${integrationTestUtils.testBuildWorkflow { inherit flakePath package; expectedVersion = "1.7.1"; }} || ((FAILED_TESTS++))
          ${integrationTestUtils.testUpdateCycle { inherit flakePath package; }} || ((FAILED_TESTS++))
          ;;
        "performance")
          echo "Performance tests..."
          ${perfTestUtils.measureBuildTime { inherit flakePath package; }} || ((FAILED_TESTS++))
          ${perfTestUtils.measureEvalTime flakePath} || ((FAILED_TESTS++))
          ;;
      esac
      
      echo ""
    done
    
    echo "=== Test Suite Results ==="
    if [ $FAILED_TESTS -eq 0 ]; then
      echo "✓ All tests passed!"
      exit 0
    else
      echo "✗ $FAILED_TESTS tests failed"
      exit 1
    fi
  '';
}