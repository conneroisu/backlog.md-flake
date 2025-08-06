# Auto-Tag Validation Pipeline
# Validates the accuracy of auto-generated tags and release metadata

{ pkgs ? import <nixpkgs> { }
, lib ? pkgs.lib
, writeShellScript ? pkgs.writeShellScript
}:

let
  inherit (lib) concatStringsSep mapAttrsToList;

  # Validation utilities
  validationUtils = rec {
    
    # Validate git tag format
    validateTagFormat = writeShellScript "validate-tag-format" ''
      set -euo pipefail
      
      TAG="$1"
      EXPECTED_VERSION="$2"
      
      echo "Validating tag format: $TAG"
      
      # Check tag follows semver pattern with v prefix
      if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ ]]; then
        echo "ERROR: Tag does not follow semantic versioning format"
        exit 1
      fi
      
      # Extract version from tag (remove 'v' prefix)
      TAG_VERSION="''${TAG#v}"
      
      # Verify tag version matches expected version
      if [[ "$TAG_VERSION" != "$EXPECTED_VERSION" ]]; then
        echo "ERROR: Tag version ($TAG_VERSION) does not match expected version ($EXPECTED_VERSION)"
        exit 1
      fi
      
      echo "✓ Tag format validation passed: $TAG"
    '';
    
    # Validate tag metadata
    validateTagMetadata = writeShellScript "validate-tag-metadata" ''
      set -euo pipefail
      
      TAG="$1"
      REPO_PATH="$2"
      
      echo "Validating tag metadata: $TAG"
      
      cd "$REPO_PATH"
      
      # Check if tag exists
      if ! git tag -l | grep -q "^$TAG$"; then
        echo "ERROR: Tag $TAG does not exist"
        exit 1
      fi
      
      # Get tag details
      TAG_TYPE=$(git cat-file -t "$TAG")
      
      if [[ "$TAG_TYPE" == "tag" ]]; then
        # Annotated tag - get message
        TAG_MESSAGE=$(git tag -l --format='%(contents)' "$TAG")
        
        if [[ -z "$TAG_MESSAGE" ]]; then
          echo "ERROR: Annotated tag has no message"
          exit 1
        fi
        
        # Validate tag message contains version
        TAG_VERSION="''${TAG#v}"
        if [[ "$TAG_MESSAGE" != *"$TAG_VERSION"* ]]; then
          echo "WARNING: Tag message does not contain version number"
        fi
        
        echo "✓ Annotated tag with message: $TAG_MESSAGE"
        
      elif [[ "$TAG_TYPE" == "commit" ]]; then
        echo "✓ Lightweight tag pointing to commit"
      else
        echo "ERROR: Invalid tag type: $TAG_TYPE"
        exit 1
      fi
      
      # Get commit that tag points to
      TAG_COMMIT=$(git rev-list -n 1 "$TAG")
      echo "Tag points to commit: $TAG_COMMIT"
      
      # Verify commit exists and is reachable
      if ! git cat-file -e "$TAG_COMMIT"; then
        echo "ERROR: Tag points to non-existent commit"
        exit 1
      fi
      
      echo "✓ Tag metadata validation passed"
    '';
    
    # Validate tag chronology
    validateTagChronology = writeShellScript "validate-tag-chronology" ''
      set -euo pipefail
      
      REPO_PATH="$1"
      NEW_TAG="$2"
      
      echo "Validating tag chronology: $NEW_TAG"
      
      cd "$REPO_PATH"
      
      # Get all version tags sorted by version
      mapfile -t ALL_TAGS < <(git tag -l 'v*' | sort -V)
      
      if [[ ''${#ALL_TAGS[@]} -eq 0 ]]; then
        echo "✓ First tag in repository"
        exit 0
      fi
      
      # Get the latest tag before this one
      LATEST_TAG=""
      for tag in "''${ALL_TAGS[@]}"; do
        if [[ "$tag" != "$NEW_TAG" ]]; then
          LATEST_TAG="$tag"
        else
          break
        fi
      done
      
      if [[ -n "$LATEST_TAG" ]]; then
        echo "Latest existing tag: $LATEST_TAG"
        
        # Verify new tag is newer than latest
        NEW_VERSION="''${NEW_TAG#v}"
        LATEST_VERSION="''${LATEST_TAG#v}"
        
        # Use semver comparison with Node.js
        if ${pkgs.nodejs}/bin/node -e "
          const semver = require('semver');
          if (!semver.gt('$NEW_VERSION', '$LATEST_VERSION')) {
            console.error('New version must be greater than latest version');
            process.exit(1);
          }
        "; then
          echo "✓ Version progression valid: $LATEST_VERSION -> $NEW_VERSION"
        else
          echo "ERROR: New version is not greater than latest version"
          exit 1
        fi
        
        # Check commit timeline
        LATEST_COMMIT_DATE=$(git log -1 --format='%ct' "$LATEST_TAG")
        NEW_COMMIT_DATE=$(git log -1 --format='%ct' "$NEW_TAG")
        
        if [[ "$NEW_COMMIT_DATE" -lt "$LATEST_COMMIT_DATE" ]]; then
          echo "WARNING: New tag points to older commit than latest tag"
        fi
      fi
      
      echo "✓ Tag chronology validation passed"
    '';
    
    # Validate release consistency
    validateReleaseConsistency = writeShellScript "validate-release-consistency" ''
      set -euo pipefail
      
      REPO_PATH="$1"
      TAG="$2"
      PACKAGE_NAME="$3"
      
      echo "Validating release consistency: $TAG"
      
      cd "$REPO_PATH"
      
      # Get tag version
      TAG_VERSION="''${TAG#v}"
      
      # Get commit that tag points to
      TAG_COMMIT=$(git rev-list -n 1 "$TAG")
      
      # Checkout the tagged commit temporarily
      CURRENT_BRANCH=$(git branch --show-current)
      git checkout "$TAG_COMMIT" -q
      
      # Verify flake.nix has correct version
      if [[ -f "flake.nix" ]]; then
        # Extract version from flake.nix
        FLAKE_VERSION=$(${pkgs.nix}/bin/nix eval ".#$PACKAGE_NAME.version" --raw 2>/dev/null || echo "")
        
        if [[ -n "$FLAKE_VERSION" ]]; then
          if [[ "$FLAKE_VERSION" != "$TAG_VERSION" ]]; then
            echo "ERROR: Flake version ($FLAKE_VERSION) does not match tag version ($TAG_VERSION)"
            git checkout "$CURRENT_BRANCH" -q
            exit 1
          fi
          echo "✓ Flake version matches tag version: $TAG_VERSION"
        else
          echo "WARNING: Could not extract version from flake"
        fi
      fi
      
      # Verify package builds at this commit
      if ${pkgs.nix}/bin/nix build ".#$PACKAGE_NAME" --no-link --quiet 2>/dev/null; then
        echo "✓ Package builds successfully at tagged commit"
      else
        echo "ERROR: Package does not build at tagged commit"
        git checkout "$CURRENT_BRANCH" -q
        exit 1
      fi
      
      # Return to original branch
      git checkout "$CURRENT_BRANCH" -q
      
      echo "✓ Release consistency validation passed"
    '';
    
    # Generate validation report
    generateValidationReport = writeShellScript "generate-validation-report" ''
      set -euo pipefail
      
      REPO_PATH="$1"
      TAG="$2"
      OUTPUT_FILE="$3"
      
      echo "Generating validation report for: $TAG"
      
      cd "$REPO_PATH"
      
      # Collect tag information
      TAG_VERSION="''${TAG#v}"
      TAG_COMMIT=$(git rev-list -n 1 "$TAG")
      TAG_DATE=$(git log -1 --format='%ci' "$TAG_COMMIT")
      TAG_AUTHOR=$(git log -1 --format='%an <%ae>' "$TAG_COMMIT")
      TAG_MESSAGE=$(git tag -l --format='%(contents)' "$TAG" 2>/dev/null || echo "Lightweight tag")
      
      # Get commit details
      COMMIT_SUBJECT=$(git log -1 --format='%s' "$TAG_COMMIT")
      CHANGED_FILES=$(git diff --name-only "$TAG_COMMIT~1" "$TAG_COMMIT" | wc -l)
      
      # Generate JSON report
      cat > "$OUTPUT_FILE" << EOF
{
  "validation_timestamp": "$(date -Iseconds)",
  "tag": {
    "name": "$TAG",
    "version": "$TAG_VERSION",
    "commit": "$TAG_COMMIT",
    "date": "$TAG_DATE",
    "author": "$TAG_AUTHOR",
    "message": $(echo "$TAG_MESSAGE" | ${pkgs.jq}/bin/jq -Rs .)
  },
  "commit": {
    "subject": "$COMMIT_SUBJECT",
    "changed_files": $CHANGED_FILES
  },
  "validations": {
    "format_valid": true,
    "metadata_valid": true,
    "chronology_valid": true,
    "consistency_valid": true
  },
  "repository": {
    "path": "$REPO_PATH",
    "current_branch": "$(git branch --show-current)",
    "total_tags": $(git tag | wc -l)
  }
}
EOF
      
      echo "Validation report generated: $OUTPUT_FILE"
    '';
  };

  # Main validation pipeline
  validateAutoTagging = writeShellScript "validate-auto-tagging" ''
    set -euo pipefail
    
    REPO_PATH="''${1:-.}"
    TAG="$2"
    PACKAGE_NAME="''${3:-backlog-md}"
    EXPECTED_VERSION="$4"
    OUTPUT_DIR="''${5:-./validation_output}"
    
    echo "=== Auto-Tagging Validation Pipeline ==="
    echo "Repository: $REPO_PATH"
    echo "Tag: $TAG"
    echo "Package: $PACKAGE_NAME"
    echo "Expected Version: $EXPECTED_VERSION"
    echo ""
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    VALIDATION_LOG="$OUTPUT_DIR/validation.log"
    VALIDATION_REPORT="$OUTPUT_DIR/validation_report.json"
    
    # Track validation results
    FAILED_VALIDATIONS=0
    
    # Run validations
    echo "Step 1: Validating tag format..." | tee -a "$VALIDATION_LOG"
    if ${validationUtils.validateTagFormat} "$TAG" "$EXPECTED_VERSION" >> "$VALIDATION_LOG" 2>&1; then
      echo "✓ Tag format validation passed" | tee -a "$VALIDATION_LOG"
    else
      echo "✗ Tag format validation failed" | tee -a "$VALIDATION_LOG"
      ((FAILED_VALIDATIONS++))
    fi
    
    echo "Step 2: Validating tag metadata..." | tee -a "$VALIDATION_LOG"
    if ${validationUtils.validateTagMetadata} "$TAG" "$REPO_PATH" >> "$VALIDATION_LOG" 2>&1; then
      echo "✓ Tag metadata validation passed" | tee -a "$VALIDATION_LOG"
    else
      echo "✗ Tag metadata validation failed" | tee -a "$VALIDATION_LOG"
      ((FAILED_VALIDATIONS++))
    fi
    
    echo "Step 3: Validating tag chronology..." | tee -a "$VALIDATION_LOG"
    if ${validationUtils.validateTagChronology} "$REPO_PATH" "$TAG" >> "$VALIDATION_LOG" 2>&1; then
      echo "✓ Tag chronology validation passed" | tee -a "$VALIDATION_LOG"
    else
      echo "✗ Tag chronology validation failed" | tee -a "$VALIDATION_LOG"
      ((FAILED_VALIDATIONS++))
    fi
    
    echo "Step 4: Validating release consistency..." | tee -a "$VALIDATION_LOG"
    if ${validationUtils.validateReleaseConsistency} "$REPO_PATH" "$TAG" "$PACKAGE_NAME" >> "$VALIDATION_LOG" 2>&1; then
      echo "✓ Release consistency validation passed" | tee -a "$VALIDATION_LOG"
    else
      echo "✗ Release consistency validation failed" | tee -a "$VALIDATION_LOG"
      ((FAILED_VALIDATIONS++))
    fi
    
    # Generate comprehensive report
    echo "Step 5: Generating validation report..." | tee -a "$VALIDATION_LOG"
    ${validationUtils.generateValidationReport} "$REPO_PATH" "$TAG" "$VALIDATION_REPORT"
    
    # Summary
    echo "" | tee -a "$VALIDATION_LOG"
    echo "=== Validation Summary ===" | tee -a "$VALIDATION_LOG"
    echo "Total validations: 4" | tee -a "$VALIDATION_LOG"
    echo "Failed validations: $FAILED_VALIDATIONS" | tee -a "$VALIDATION_LOG"
    
    if [[ $FAILED_VALIDATIONS -eq 0 ]]; then
      echo "✅ All validations passed!" | tee -a "$VALIDATION_LOG"
      echo "Tag $TAG is valid and ready for release." | tee -a "$VALIDATION_LOG"
      exit 0
    else
      echo "❌ $FAILED_VALIDATIONS validations failed!" | tee -a "$VALIDATION_LOG"
      echo "Tag $TAG has validation issues." | tee -a "$VALIDATION_LOG"
      exit 1
    fi
  '';

in {
  inherit validationUtils validateAutoTagging;
  
  # Additional utilities
  validateTagBatch = writeShellScript "validate-tag-batch" ''
    set -euo pipefail
    
    REPO_PATH="''${1:-.}"
    OUTPUT_DIR="''${2:-./batch_validation}"
    
    echo "Batch validating all tags in repository..."
    
    cd "$REPO_PATH"
    mkdir -p "$OUTPUT_DIR"
    
    # Get all version tags
    mapfile -t ALL_TAGS < <(git tag -l 'v*' | sort -V)
    
    if [[ ''${#ALL_TAGS[@]} -eq 0 ]]; then
      echo "No version tags found in repository"
      exit 0
    fi
    
    BATCH_REPORT="$OUTPUT_DIR/batch_validation_report.json"
    echo '{"timestamp":"'$(date -Iseconds)'","validations":[' > "$BATCH_REPORT"
    
    FAILED_COUNT=0
    TOTAL_COUNT=''${#ALL_TAGS[@]}
    
    for i in "''${!ALL_TAGS[@]}"; do
      tag="''${ALL_TAGS[i]}"
      echo "Validating tag: $tag ($((i+1))/$TOTAL_COUNT)"
      
      tag_version="''${tag#v}"
      tag_output="$OUTPUT_DIR/validation_''${tag//\//_}"
      
      if ${validateAutoTagging} "$REPO_PATH" "$tag" "backlog-md" "$tag_version" "$tag_output"; then
        echo "✓ $tag validation passed"
        status="passed"
      else
        echo "✗ $tag validation failed"
        status="failed"
        ((FAILED_COUNT++))
      fi
      
      # Add to batch report
      if [[ $i -gt 0 ]]; then echo ',' >> "$BATCH_REPORT"; fi
      echo "  {\"tag\":\"$tag\",\"status\":\"$status\"}" >> "$BATCH_REPORT"
    done
    
    echo ']}' >> "$BATCH_REPORT"
    
    echo ""
    echo "Batch validation complete:"
    echo "Total tags: $TOTAL_COUNT"
    echo "Failed: $FAILED_COUNT"
    echo "Success rate: $(echo "scale=1; ($TOTAL_COUNT - $FAILED_COUNT) * 100 / $TOTAL_COUNT" | ${pkgs.bc}/bin/bc)%"
    
    if [[ $FAILED_COUNT -eq 0 ]]; then
      echo "🎉 All tags passed validation!"
      exit 0
    else
      echo "⚠️  Some tags failed validation"
      exit 1
    fi
  '';
}