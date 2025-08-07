# Build System Specification

## Overview

The backlog.md flake uses a sophisticated multi-stage build system with intelligent caching, security scanning, and automated deployment capabilities.

## Build Targets

### Core Packages

#### `nix build .#default`
Main backlog.md package with standard NPM integration.

**Features:**
- Direct NPM package consumption
- Integrity verification
- Cross-platform compatibility
- Hermetic build environment

#### `nix build .#cli`
Enhanced CLI variant with additional developer tools.

**Features:**
- Extended command-line interface
- Development utilities integration
- Enhanced error reporting
- Advanced configuration options

#### `nix build .#dev-tools`
Comprehensive development toolkit bundle.

**Contents:**
- npm-update-helper
- security-scanner
- Node.js runtime
- JSON processing utilities

#### `nix build .#container`
Production-ready container image.

**Specifications:**
- Minimal base image
- Non-root execution
- Security hardening
- Multi-architecture support

### Applications

#### `nix run .#default`
Execute backlog.md directly without installation.

#### `nix run .#update`
Run the NPM package update automation.

#### `nix run .#security-scan`
Execute comprehensive security analysis.

## Build Process

### Phase 1: Source Preparation
```nix
preBuild = ''
  # Environment setup
  export HOME=/tmp/home
  mkdir -p $HOME
  
  # NPM configuration for reproducibility
  npm config set cache /tmp/npm-cache
  npm config set fund false
  npm config set audit false
  npm config set update-notifier false
  
  # Package integrity verification
  jq -e '.name == "backlog.md"' package.json
  jq -e '.version == "${version}"' package.json
'';
```

### Phase 2: Dependency Installation
```nix
buildPhase = ''
  runHook preBuild
  
  # Offline dependency installation
  npm ci --offline --ignore-scripts
  
  # Custom build steps if needed
  if [ -f build.js ]; then
    node build.js
  fi
  
  runHook postBuild
'';
```

### Phase 3: Installation and Packaging
```nix
installPhase = ''
  runHook preInstall
  
  mkdir -p $out/{bin,lib,share}
  
  # Install main package
  cp -r . $out/lib/backlog-md/
  
  # Create executable wrapper
  BIN_NAME=$(jq -r '.bin // empty' package.json)
  if [ -n "$BIN_NAME" ]; then
    cat > $out/bin/backlog-md << 'EOF'
#!/usr/bin/env bash
exec ${nodejs}/bin/node $out/lib/backlog-md/$BIN_NAME "$@"
EOF
    chmod +x $out/bin/backlog-md
  fi
  
  # Install documentation
  cp -r *.md $out/share/ 2>/dev/null || true
  
  runHook postInstall
'';
```

## Caching Strategy

### Content-Addressed Storage
All build artifacts use content-addressed storage ensuring:
- Reproducible builds
- Efficient storage utilization
- Automatic deduplication
- Integrity verification

### NPM Dependency Caching
```nix
npmDepsHash = "sha256-..."; # Fixed hash for reproducibility
```

Dependencies are cached based on:
- package.json content
- package-lock.json state
- Build environment configuration

### Container Layer Caching
Container images use layered caching:
- Base system layer
- Node.js runtime layer
- Application dependencies layer
- Application code layer

## Security Integration

### Package Verification
```bash
# SHA integrity check
echo "$PACKAGE_HASH *package.tgz" | sha256sum -c

# GPG signature verification (if available)
gpg --verify package.sig package.tgz
```

### Vulnerability Scanning
```nix
security-scanner = writeShellApplication {
  name = "security-scan";
  runtimeInputs = [ nodejs jq curl ];
  text = ''
    echo "🔍 Running NPM security audit..."
    npm audit --audit-level high --json | jq .
    
    echo "📊 Generating security report..."
    npm audit --json > security-report.json
  '';
};
```

### SBOM Generation
```nix
# Software Bill of Materials generation
sbom-generator = writeShellApplication {
  name = "generate-sbom";
  text = ''
    npm list --json > npm-dependencies.json
    cyclonedx-npm --output-format json > sbom.json
  '';
};
```

## Auto-Update Mechanism

### Registry Monitoring
```bash
#!/usr/bin/env bash
LATEST_VERSION=$(curl -s "https://registry.npmjs.org/backlog.md/latest" | jq -r .version)
CURRENT_VERSION=$(jq -r .version package.info)

if [ "$LATEST_VERSION" != "$CURRENT_VERSION" ]; then
  echo "Update available: $CURRENT_VERSION → $LATEST_VERSION"
  # Trigger update process
fi
```

### Hash Calculation
```bash
# Calculate new Nix hash for updated package
NEW_HASH=$(nix-prefetch-url "https://registry.npmjs.org/backlog.md/-/backlog.md-$LATEST_VERSION.tgz")

# Update package metadata
jq --arg version "$LATEST_VERSION" \
   --arg hash "$NEW_HASH" \
   '.version = $version | .nix_hash = $hash' \
   package.info > package.info.new
```

### Automated Commit Generation
```bash
# Create structured commit message
COMMIT_MSG="🔄 Auto-update backlog.md: $CURRENT_VERSION → $LATEST_VERSION

- Updated NPM package to version $LATEST_VERSION
- New tarball hash: $NEW_HASH
- Updated package.info and flake configuration
- Automated update by npm-update-helper

Co-authored-by: npm-update-helper <noreply@localhost>"

git commit -m "$COMMIT_MSG"
git tag -a "v$LATEST_VERSION" -m "Auto-generated tag for backlog.md@$LATEST_VERSION"
```

## Performance Optimizations

### Parallel Builds
```bash
# Build multiple targets concurrently
nix build .#default .#cli .#container --max-jobs auto
```

### Build Metrics
```nix
# Build timing and resource usage
metrics-collector = writeShellApplication {
  name = "collect-metrics";
  text = ''
    start_time=$(date +%s)
    nix build .#default --json > build-result.json
    end_time=$(date +%s)
    
    echo "Build completed in $((end_time - start_time)) seconds"
    jq '.[] | {drv, outputs}' build-result.json
  '';
};
```

### Resource Management
```nix
# Memory and CPU constraints
buildInputs = [ nodejs ];
requiredSystemFeatures = [ ];
allowedReferences = [ nodejs ];
allowedRequisites = null;
```

## Cross-Platform Support

### Architecture Matrix
- x86_64-linux (Intel/AMD Linux)
- aarch64-linux (ARM64 Linux)
- x86_64-darwin (Intel macOS)
- aarch64-darwin (Apple Silicon macOS)

### Platform-Specific Optimizations
```nix
platformConfig = lib.optionalAttrs stdenv.isDarwin {
  # macOS-specific build flags
  buildFlags = [ "--target=darwin" ];
} // lib.optionalAttrs stdenv.isLinux {
  # Linux-specific optimizations
  buildFlags = [ "--target=linux" ];
};
```

## Quality Assurance

### Build Verification
```bash
# Comprehensive build testing
nix flake check                    # Verify flake syntax
nix build .#default               # Test main build
nix run .#default -- --help       # Test execution
nix build .#container             # Test container build
```

### Integration Testing
```nix
checks = {
  package-builds = packages.default;
  security-audit = runCommand "security-audit" { } ''
    ${security-scanner}/bin/security-scan > $out
  '';
  format-check = runCommand "format-check" { } ''
    treefmt --fail-on-change
    touch $out
  '';
};
```

## Deployment Pipeline

### CI/CD Integration
```yaml
name: Build and Deploy
on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v27
      - name: Build all targets
        run: |
          nix build .#default .#cli .#container
          nix flake check
      - name: Security scan
        run: nix run .#security-scan
```

### Release Automation
```bash
#!/usr/bin/env bash
# Automated release pipeline

# 1. Update package
nix run .#update -- backlog.md

# 2. Build and test
nix build .#default
nix flake check

# 3. Security verification
nix run .#security-scan

# 4. Create release artifacts
nix build .#container
podman save backlog-md:$(jq -r .version package.info) > backlog-md-container.tar

# 5. Deploy to registry
# ... deployment logic ...
```

This build system provides a robust, secure, and efficient foundation for automated NPM package deployment with comprehensive quality assurance and monitoring capabilities.