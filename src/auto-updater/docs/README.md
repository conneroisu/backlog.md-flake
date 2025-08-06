# Auto-Updater System for backlog.md Flake

A comprehensive auto-updating system for the backlog.md@1.7.1 NPM package flake, implementing robust version tracking, automated updates, validation, and recovery mechanisms.

## 🌟 Features

### Core Functionality
- **NPM Registry Monitoring**: Real-time monitoring of backlog.md package versions
- **Automated Flake Updates**: Automatic updating of flake.nix and flake.lock files
- **Git Workflow Automation**: Automated branching, commits, and pull requests
- **Webhook & Polling System**: Support for both webhook and polling-based triggers
- **Comprehensive Validation**: Multi-stage validation pipeline with security scanning
- **Rollback & Recovery**: Robust backup and recovery mechanisms

### Advanced Features
- **Hierarchical Swarm Integration**: Built for Claude Code's swarm orchestration
- **Memory Persistence**: Cross-session state management with hive mind storage
- **Performance Optimization**: Efficient resource usage and caching
- **Security-First Design**: Built-in security scanning and validation
- **Event-Driven Architecture**: Modular, extensible component system

## 🏗️ Architecture

```
Auto-Updater System
├── Orchestrator (Main Controller)
├── NPM Version Monitor
├── Flake Updater
├── Git Automation
├── Webhook Server
├── Recovery System
└── Validation Pipeline
```

### Component Overview

| Component | Purpose | Key Features |
|-----------|---------|--------------|
| **Orchestrator** | Main coordination | Event-driven workflow, component management |
| **NPM Monitor** | Version tracking | Registry polling, change detection, webhooks |
| **Flake Updater** | File updates | Safe flake.nix/lock updates, backup creation |
| **Git Automation** | VCS operations | Branching, commits, PRs, tagging |
| **Webhook Server** | Event handling | HTTP endpoints, rate limiting, security |
| **Recovery System** | Backup/restore | Automated rollbacks, integrity validation |
| **Validation Pipeline** | Quality assurance | Multi-stage testing, security scanning |

## 🚀 Quick Start

### 1. Installation
```bash
# Navigate to the auto-updater directory
cd src/auto-updater

# Make scripts executable
chmod +x scripts/*.js
chmod +x lib/orchestrator.js
```

### 2. Configuration
Edit `config/auto-updater.json` to customize settings:

```json
{
  "packageName": "backlog.md",
  "currentVersion": "1.7.1",
  "monitoring": {
    "enabled": true,
    "checkInterval": 300000
  },
  "updates": {
    "autoUpdate": true,
    "strictValidation": true
  },
  "git": {
    "enabled": true,
    "enablePush": false,
    "enablePR": false
  }
}
```

### 3. Start the System
```bash
# Start the orchestrator
npm start

# Or run directly
node lib/orchestrator.js start
```

### 4. Check Status
```bash
# Check system status
npm run status

# Check individual components
npm run recovery
npm run validate
```

## 📋 Commands & Scripts

### Main Commands
```bash
npm start                    # Start the auto-updater
npm stop                     # Stop the running system
npm run status              # Show system status
npm run update              # Trigger manual update check
npm test                    # Run integration tests
```

### Component Scripts
```bash
npm run monitor             # Start NPM version monitoring
npm run webhook             # Start webhook server
npm run recovery            # Check recovery system status
npm run validate            # Run validation tests
npm run cleanup             # Clean up old backups
```

### Individual Script Usage
```bash
# NPM Version Monitor
node scripts/npm-version-monitor.js [start|check|stop]

# Flake Updater
node scripts/flake-updater.js <version-info-json>

# Git Automation
node scripts/git-automation.js [workflow|status] [version-info-json]

# Webhook Server
node scripts/webhook-server.js [start|stop|test]

# Recovery System
node scripts/recovery-system.js [status|list|rollback|validate|cleanup]

# Validation Pipeline
node scripts/validation-pipeline.js [run|test] [version-info-json]
```

## ⚙️ Configuration

### Environment Variables
```bash
# Webhook Configuration
WEBHOOK_PORT=3000
WEBHOOK_HOST=localhost
WEBHOOK_SECRET=your-secret-key
WEBHOOK_AUTH=true

# Git Configuration
ENABLE_GIT_PUSH=false
ENABLE_GIT_PR=false

# Feature Toggles
ENABLE_POLLING=true
POLLING_INTERVAL=300000
ENABLE_PERF_TESTS=false
ENABLE_SECURITY_SCANS=true

# Network Configuration
ALLOWED_IPS=127.0.0.1,::1
```

### Configuration File Structure
```json
{
  "packageName": "backlog.md",
  "currentVersion": "1.7.1",
  "registryUrl": "https://registry.npmjs.org",
  
  "monitoring": {
    "enabled": true,
    "checkInterval": 300000,
    "webhook": {
      "enabled": true,
      "port": 3000,
      "host": "localhost",
      "enableAuth": false,
      "allowedIPs": ["127.0.0.1", "::1"],
      "rateLimit": 10
    },
    "polling": {
      "enabled": true,
      "interval": 300000
    }
  },
  
  "updates": {
    "autoUpdate": true,
    "strictValidation": true,
    "enableRollback": true,
    "maxBackups": 10,
    "validation": {
      "enablePerformanceTests": false,
      "enableSecurityScans": true,
      "timeoutMs": 300000,
      "testSuites": [
        "flake-check",
        "build-test",
        "syntax-validation",
        "dependency-check",
        "security-scan",
        "integration-test"
      ]
    }
  },
  
  "git": {
    "enabled": true,
    "branch": "auto-update",
    "baseBranch": "main",
    "commitPrefix": "auto-update",
    "enablePush": false,
    "enablePR": false,
    "createTags": true
  },
  
  "notifications": {
    "enabled": true,
    "onSuccess": true,
    "onFailure": true,
    "onRollback": true
  },
  
  "paths": {
    "repoPath": ".",
    "flakeFile": "flake.nix",
    "flakeLockFile": "flake.lock",
    "backupDir": "src/auto-updater/backups",
    "logFile": "src/auto-updater/logs/auto-updater.log"
  },
  
  "memory": {
    "namespace": "hive/auto-update",
    "persistAcrossSessions": true,
    "compressionEnabled": false
  }
}
```

## 🔄 Workflow

### Automatic Update Process
1. **Detection**: Monitor detects new version via polling or webhook
2. **Validation**: Pre-update validation checks
3. **Backup**: Create backup of current state
4. **Update**: Update flake.nix and flake.lock files
5. **Validation**: Post-update validation pipeline
6. **Git Operations**: Create branch, commit, and optionally push/PR
7. **Notification**: Send success/failure notifications
8. **Cleanup**: Clean up old backups

### Recovery Process
1. **Failure Detection**: Validation or build failures trigger recovery
2. **Backup Selection**: Identify most recent valid backup
3. **Rollback**: Restore flake files from backup
4. **Validation**: Verify rollback success
5. **Git Reset**: Optional git operations
6. **Notification**: Alert about rollback

## 🧪 Testing

### Integration Tests
```bash
# Run full test suite
npm test

# Run specific test
node tests/integration-test.js run

# Setup test environment
node tests/integration-test.js setup

# Cleanup test environment
node tests/integration-test.js cleanup
```

### Manual Testing
```bash
# Test version detection
node scripts/npm-version-monitor.js check

# Test webhook endpoint
curl -X POST http://localhost:3000/webhook \
  -H "Content-Type: application/json" \
  -d '{"package":"backlog.md","event":"version-released"}'

# Test validation pipeline
node scripts/validation-pipeline.js test

# Test recovery system
node scripts/recovery-system.js list
```

## 🔐 Security

### Security Features
- **Input Validation**: All inputs are validated and sanitized
- **Rate Limiting**: Webhook endpoints have configurable rate limits
- **IP Allowlisting**: Restrict webhook access to specific IPs
- **Signature Verification**: Optional webhook signature verification
- **File Permission Checks**: Validate file permissions
- **Secret Scanning**: Detect potential secrets in flake files
- **Dependency Scanning**: Check for known vulnerabilities

### Security Best Practices
- Use WEBHOOK_SECRET for webhook authentication
- Restrict ALLOWED_IPS to known sources
- Enable signature verification in production
- Regularly review security scan results
- Keep backup files secure with proper permissions
- Monitor access logs for suspicious activity

## 📊 Monitoring & Observability

### Memory Storage
All operations are stored in the hive mind memory system:
```bash
# View stored memories
ls memory/auto-updater/

# Key memory entries
monitor_init.json          # Monitor initialization
version_change_detected.json   # Version changes
update_completed.json      # Successful updates
rollback_completed.json    # Recovery operations
```

### Logging
Comprehensive logging across all components:
- Operation start/completion
- Error conditions and recovery
- Performance metrics
- Security events
- Validation results

### Health Checks
```bash
# System health
curl http://localhost:3000/health

# Component status
npm run status

# Recovery system status
npm run recovery
```

## 🔧 Troubleshooting

### Common Issues

#### Update Detection Fails
```bash
# Check NPM registry connectivity
node scripts/npm-version-monitor.js check

# Verify package name and version
cat config/auto-updater.json | grep -E "(packageName|currentVersion)"
```

#### Flake Update Fails
```bash
# Check Nix installation
nix --version

# Validate current flake
nix flake check

# Check permissions
ls -la flake.nix flake.lock
```

#### Git Operations Fail
```bash
# Check git configuration
git config --list

# Verify repository status
git status

# Check branch permissions
git branch -a
```

#### Webhook Not Receiving Events
```bash
# Test webhook endpoint
curl http://localhost:3000/health

# Check firewall and network
netstat -tlnp | grep 3000

# Verify webhook configuration
cat config/auto-updater.json | jq .monitoring.webhook
```

### Recovery Commands
```bash
# Emergency rollback to latest backup
node scripts/recovery-system.js rollback <backup-name>

# List available backups
node scripts/recovery-system.js list

# Validate a specific backup
node scripts/recovery-system.js validate <backup-name>

# Force rollback (skip validation)
node scripts/recovery-system.js rollback <backup-name> --force
```

## 🚀 Advanced Usage

### Custom Validation
Add custom validation tests by extending the ValidationPipeline:

```javascript
const CustomValidation = require('./custom-validation');

class CustomValidationPipeline extends ValidationPipeline {
    async runCustomTest(versionInfo) {
        // Your custom validation logic
        return { success: true, details: {} };
    }
}
```

### Webhook Integration
Set up NPM registry webhooks (if available):

```bash
# Example webhook URL
https://your-domain.com/webhook

# Required headers
X-Hub-Signature-256: sha256=<signature>
Content-Type: application/json
```

### CI/CD Integration
Integrate with CI/CD pipelines:

```yaml
# GitHub Actions example
- name: Auto-updater check
  run: |
    cd src/auto-updater
    npm run status
    node scripts/npm-version-monitor.js check
```

## 🤝 Contributing

### Development Setup
```bash
# Install development dependencies
npm install --dev

# Run linting
npm run lint

# Run tests
npm test

# Check code coverage
npm run coverage
```

### Adding New Components
1. Create component in appropriate directory
2. Follow existing patterns and interfaces
3. Add comprehensive tests
4. Update documentation
5. Integrate with orchestrator

## 📄 License

MIT License - see LICENSE file for details

## 🆘 Support

For issues and questions:
1. Check this documentation
2. Review memory logs in `memory/auto-updater/`
3. Run diagnostic commands
4. Check system status with `npm run status`
5. Review integration test results

---

**Built with Claude Code for the HIVE MIND Auto-Updater Swarm** 🤖