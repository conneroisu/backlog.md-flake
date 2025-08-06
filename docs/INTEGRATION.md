# Integration Specifications

## Overview

This document specifies the integration points and interfaces for the backlog.md auto-updating flake system, including CI/CD pipelines, monitoring, and external service integration.

## Auto-Tagging System Integration

### Semantic Versioning Detection
The auto-tagging system automatically detects and applies semantic versioning based on NPM registry data:

```bash
# Version pattern detection
MAJOR_PATTERN="^[0-9]+\.0\.0$"     # Major version bump
MINOR_PATTERN="^[0-9]+\.[0-9]+\.0$" # Minor version bump  
PATCH_PATTERN="^[0-9]+\.[0-9]+\.[0-9]+$" # Patch version

# Tag generation with metadata
git tag -a "v${version}" -m "$(generate_tag_message)"
```

### Tag Message Generation
Automated tag messages include comprehensive metadata:

```markdown
Auto-generated release for backlog.md@{version}

🎯 Release Highlights:
- Updated from {previous} to {current}
- Comprehensive build verification
- Security analysis completed
- Multi-platform support verified

🔧 Technical Details:
- NPM Package: https://www.npmjs.com/package/backlog.md/v/{version}
- Container: backlog-md:{version}
- Build System: Nix Flakes with auto-update
- Release Pipeline: Fully automated

🛡️ Security & Quality:
- NPM audit: ✅ Passed
- Build verification: ✅ All targets
- Reproducible builds: ✅ Content-addressed
- Cross-platform: ✅ Linux, macOS
```

## CI/CD Pipeline Integration

### GitHub Actions Workflow
```yaml
name: Auto-Update and Release
on:
  schedule:
    - cron: '0 6 * * *'  # Daily at 6 AM UTC
  workflow_dispatch:
  push:
    paths:
      - 'package.info'
      - 'flake.nix'

jobs:
  auto-update:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      packages: write
      pull-requests: write
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          token: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Install Nix
        uses: cachix/install-nix-action@v27
        with:
          extra_nix_config: |
            experimental-features = nix-command flakes
            accept-flake-config = true
      
      - name: Setup Cachix
        uses: cachix/cachix-action@v15
        with:
          name: backlog-md-flake
          authToken: '${{ secrets.CACHIX_AUTH_TOKEN }}'
      
      - name: Run auto-update check
        id: update-check
        run: |
          if ./scripts/update-npm.sh --dry-run | grep -q "Update available"; then
            echo "update_needed=true" >> $GITHUB_OUTPUT
          else
            echo "update_needed=false" >> $GITHUB_OUTPUT
          fi
      
      - name: Execute auto-release pipeline
        if: steps.update-check.outputs.update_needed == 'true'
        run: ./scripts/auto-release.sh
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Build and cache all targets
        if: steps.update-check.outputs.update_needed == 'true'
        run: |
          nix build .#default .#cli .#dev-tools .#container
          nix flake check
      
      - name: Create release
        if: steps.update-check.outputs.update_needed == 'true'
        uses: softprops/action-gh-release@v1
        with:
          tag_name: ${{ env.LATEST_VERSION }}
          name: "Release ${{ env.LATEST_VERSION }}"
          body_path: release-summary-${{ env.LATEST_VERSION }}.md
          files: |
            result*
            security-report.txt
            release-summary-*.md
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### GitLab CI Pipeline
```yaml
stages:
  - check
  - update
  - build
  - test
  - deploy

variables:
  NIX_CONFIG: "experimental-features = nix-command flakes"

check-updates:
  stage: check
  image: nixos/nix:latest
  script:
    - ./scripts/update-npm.sh --dry-run
    - |
      if ./scripts/update-npm.sh --dry-run | grep -q "Update available"; then
        echo "UPDATE_NEEDED=true" >> variables.env
      else
        echo "UPDATE_NEEDED=false" >> variables.env
      fi
  artifacts:
    reports:
      dotenv: variables.env

auto-update:
  stage: update
  image: nixos/nix:latest
  script:
    - ./scripts/auto-release.sh
  only:
    variables:
      - $UPDATE_NEEDED == "true"
  artifacts:
    paths:
      - result*
      - "*.md"
      - "security-report.txt"
```

## Registry Monitoring Integration

### NPM Registry Webhook Support
```javascript
// Webhook endpoint for NPM registry notifications
app.post('/webhook/npm-update', (req, res) => {
  const { name, version, dist } = req.body;
  
  if (name === 'backlog.md') {
    // Trigger update workflow
    triggerUpdate({
      package: name,
      version: version,
      tarball: dist.tarball,
      shasum: dist.shasum
    });
  }
  
  res.status(200).json({ received: true });
});
```

### Polling-Based Monitoring
```bash
#!/usr/bin/env bash
# polling-monitor.sh - Periodic NPM registry monitoring

PACKAGE_NAME="backlog.md"
CHECK_INTERVAL=3600  # 1 hour
LOG_FILE="monitor.log"

while true; do
  log "Checking for updates to $PACKAGE_NAME..."
  
  if ./scripts/update-npm.sh --dry-run | grep -q "Update available"; then
    log "Update detected, triggering pipeline..."
    ./scripts/auto-release.sh
    
    # Notify monitoring systems
    curl -X POST "$WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "{\"event\": \"package_updated\", \"package\": \"$PACKAGE_NAME\"}"
  fi
  
  sleep $CHECK_INTERVAL
done
```

## Container Registry Integration

### Multi-Registry Deployment
```nix
# Container deployment configuration
containerDeployment = {
  registries = {
    docker-hub = {
      url = "docker.io/username/backlog-md";
      auth = "DOCKER_HUB_TOKEN";
    };
    github = {
      url = "ghcr.io/username/backlog-md";
      auth = "GITHUB_TOKEN";
    };
    gitlab = {
      url = "registry.gitlab.com/username/backlog-md";
      auth = "GITLAB_TOKEN";
    };
  };
  
  tags = [
    version
    "latest"
    "stable"
  ];
};
```

### Container Push Automation
```bash
# Multi-registry container deployment
deploy_containers() {
  local version="$1"
  local image_path="$2"
  
  # Load image
  podman load -i "$image_path"
  
  # Tag for different registries
  for registry in docker.io ghcr.io registry.gitlab.com; do
    podman tag "backlog-md:$version" "$registry/username/backlog-md:$version"
    podman tag "backlog-md:$version" "$registry/username/backlog-md:latest"
    
    # Push with retry logic
    for i in {1..3}; do
      if podman push "$registry/username/backlog-md:$version"; then
        break
      fi
      sleep $((i * 5))
    done
  done
}
```

## Binary Cache Integration

### Cachix Configuration
```yaml
# .github/workflows/cachix.yml
- name: Setup Cachix
  uses: cachix/cachix-action@v15
  with:
    name: backlog-md-flake
    authToken: '${{ secrets.CACHIX_AUTH_TOKEN }}'
    extraPullNames: nix-community,nixpkgs-unfree
    
- name: Build and cache
  run: |
    nix build .#default --print-build-logs
    nix build .#cli --print-build-logs
    nix build .#container --print-build-logs
```

### Self-Hosted Binary Cache
```nix
# Binary cache configuration
binaryCache = {
  url = "https://cache.example.com";
  publicKey = "cache.example.com:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  secretKey = "/etc/nix/signing-key.sec";
  
  # Cache warming strategy
  warmCache = writeShellScript "warm-cache" ''
    nix build .#default --json | jq -r '.[].outputs.out' | cachix push backlog-md-flake
    nix build .#cli --json | jq -r '.[].outputs.out' | cachix push backlog-md-flake
    nix build .#container --json | jq -r '.[].outputs.out' | cachix push backlog-md-flake
  '';
};
```

## Monitoring and Observability

### Metrics Collection
```bash
# metrics-collector.sh
collect_metrics() {
  local version="$1"
  local build_start="$2"
  local build_end="$3"
  
  # Calculate metrics
  local build_time=$((build_end - build_start))
  local package_size=$(du -sb result/bin/backlog-md | cut -f1)
  
  # Send to monitoring system
  curl -X POST "$METRICS_ENDPOINT" \
    -H "Content-Type: application/json" \
    -d "{
      \"timestamp\": $(date +%s),
      \"package\": \"backlog.md\",
      \"version\": \"$version\",
      \"build_time\": $build_time,
      \"package_size\": $package_size,
      \"success\": true
    }"
}
```

### Health Checks
```bash
# health-check.sh - Verify system health
check_system_health() {
  local health_status="healthy"
  
  # Check Nix daemon
  if ! nix-daemon --version >/dev/null 2>&1; then
    health_status="unhealthy"
    log_error "Nix daemon not responding"
  fi
  
  # Check NPM registry connectivity
  if ! curl -s --max-time 10 "https://registry.npmjs.org/backlog.md" >/dev/null; then
    health_status="degraded"
    log_warn "NPM registry connectivity issues"
  fi
  
  # Check binary cache
  if ! curl -s --max-time 5 "$BINARY_CACHE_URL" >/dev/null; then
    health_status="degraded" 
    log_warn "Binary cache connectivity issues"
  fi
  
  echo "$health_status"
}
```

## Security Integration

### Vulnerability Scanning Pipeline
```yaml
security-scan:
  runs-on: ubuntu-latest
  steps:
    - name: Security audit
      run: |
        nix run .#security-scan
        
    - name: Container security scan
      uses: aquasecurity/trivy-action@master
      with:
        image-ref: 'backlog-md:${{ env.VERSION }}'
        format: 'sarif'
        output: 'trivy-results.sarif'
        
    - name: Upload security results
      uses: github/codeql-action/upload-sarif@v2
      with:
        sarif_file: 'trivy-results.sarif'
```

### SBOM Generation
```nix
# Software Bill of Materials generation
sbomGenerator = writeShellApplication {
  name = "generate-sbom";
  runtimeInputs = [ nodejs jq syft ];
  text = ''
    # NPM dependencies SBOM
    npm list --json > npm-dependencies.json
    
    # System dependencies SBOM  
    syft packages dir:. -o spdx-json > system-sbom.json
    
    # Combine SBOMs
    jq -s '.[0] * .[1]' npm-dependencies.json system-sbom.json > complete-sbom.json
    
    echo "SBOM generated: complete-sbom.json"
  '';
};
```

## External Service Integration

### Notification Systems
```bash
# notification-handler.sh
send_notifications() {
  local event="$1"
  local version="$2"
  local status="$3"
  
  # Slack notification
  if [[ -n "$SLACK_WEBHOOK" ]]; then
    curl -X POST "$SLACK_WEBHOOK" \
      -H "Content-Type: application/json" \
      -d "{
        \"text\": \"📦 backlog.md $event: $version - $status\",
        \"channel\": \"#releases\"
      }"
  fi
  
  # Discord notification
  if [[ -n "$DISCORD_WEBHOOK" ]]; then
    curl -X POST "$DISCORD_WEBHOOK" \
      -H "Content-Type: application/json" \
      -d "{
        \"content\": \"🎉 backlog.md updated to $version!\",
        \"embeds\": [{
          \"title\": \"Release $version\",
          \"color\": 3066993,
          \"fields\": [{
            \"name\": \"Status\",
            \"value\": \"$status\",
            \"inline\": true
          }]
        }]
      }"
  fi
  
  # Email notification
  if [[ -n "$EMAIL_SMTP" ]]; then
    echo "Package $event: backlog.md $version - $status" | \
      mail -s "backlog.md Release Notification" "$EMAIL_RECIPIENTS"
  fi
}
```

### Database Integration
```sql
-- Release tracking database schema
CREATE TABLE releases (
  id SERIAL PRIMARY KEY,
  package_name VARCHAR(255) NOT NULL,
  version VARCHAR(50) NOT NULL,
  previous_version VARCHAR(50),
  npm_hash VARCHAR(64),
  nix_hash VARCHAR(64),
  tarball_url TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  build_status VARCHAR(20) DEFAULT 'pending',
  security_status VARCHAR(20) DEFAULT 'pending',
  deployment_status VARCHAR(20) DEFAULT 'pending'
);

CREATE INDEX idx_releases_package_version ON releases(package_name, version);
CREATE INDEX idx_releases_created_at ON releases(created_at);
```

## API Integration

### REST API Endpoints
```javascript
// Release management API
app.get('/api/packages/:name/releases', (req, res) => {
  const releases = getReleaseHistory(req.params.name);
  res.json(releases);
});

app.post('/api/packages/:name/update', async (req, res) => {
  const result = await triggerUpdate(req.params.name);
  res.json({ success: true, updateId: result.id });
});

app.get('/api/packages/:name/status', (req, res) => {
  const status = getPackageStatus(req.params.name);
  res.json(status);
});
```

### GraphQL Integration
```graphql
type Package {
  name: String!
  currentVersion: String!
  latestVersion: String
  lastUpdate: DateTime
  buildStatus: BuildStatus!
  releases: [Release!]!
}

type Release {
  version: String!
  timestamp: DateTime!
  buildTime: Int!
  packageSize: Int!
  securityStatus: SecurityStatus!
}

type Query {
  package(name: String!): Package
  packages: [Package!]!
  pendingUpdates: [Package!]!
}

type Mutation {
  triggerUpdate(packageName: String!): UpdateResult!
  scheduleUpdate(packageName: String!, scheduledAt: DateTime!): ScheduleResult!
}
```

This integration specification provides comprehensive guidance for connecting the backlog.md flake system with external services, monitoring platforms, and automation pipelines while maintaining security, reliability, and observability.