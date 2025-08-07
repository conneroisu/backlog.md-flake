#!/bin/bash
# Auto-Updater Setup Script
# Sets up the complete auto-updater system for backlog.md flake

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTO_UPDATER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$AUTO_UPDATER_DIR/../.." && pwd)"

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

check_dependencies() {
    log_info "Checking dependencies..."
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        log_error "Node.js is required but not installed"
        exit 1
    fi
    
    local node_version=$(node --version | cut -d'v' -f2)
    local required_version="14.0.0"
    
    if ! printf '%s\n%s\n' "$required_version" "$node_version" | sort -V -C; then
        log_error "Node.js version $node_version is too old. Required: $required_version or higher"
        exit 1
    fi
    
    log_success "Node.js $node_version detected"
    
    # Check Nix
    if ! command -v nix &> /dev/null; then
        log_error "Nix is required but not installed"
        exit 1
    fi
    
    local nix_version=$(nix --version | cut -d' ' -f3)
    log_success "Nix $nix_version detected"
    
    # Check Git
    if ! command -v git &> /dev/null; then
        log_error "Git is required but not installed"
        exit 1
    fi
    
    local git_version=$(git --version | cut -d' ' -f3)
    log_success "Git $git_version detected"
    
    # Check if we're in a git repository
    if ! git -C "$REPO_ROOT" rev-parse --git-dir &> /dev/null; then
        log_error "Not in a git repository"
        exit 1
    fi
    
    log_success "Git repository detected"
}

setup_directories() {
    log_info "Setting up directories..."
    
    local dirs=(
        "$AUTO_UPDATER_DIR/logs"
        "$AUTO_UPDATER_DIR/backups" 
        "$REPO_ROOT/memory/auto-updater"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_success "Created directory: $dir"
        else
            log_info "Directory already exists: $dir"
        fi
    done
}

make_scripts_executable() {
    log_info "Making scripts executable..."
    
    local scripts=(
        "$AUTO_UPDATER_DIR/lib/orchestrator.js"
        "$AUTO_UPDATER_DIR/scripts/npm-version-monitor.js"
        "$AUTO_UPDATER_DIR/scripts/flake-updater.js"
        "$AUTO_UPDATER_DIR/scripts/git-automation.js"
        "$AUTO_UPDATER_DIR/scripts/webhook-server.js"
        "$AUTO_UPDATER_DIR/scripts/recovery-system.js"
        "$AUTO_UPDATER_DIR/scripts/validation-pipeline.js"
        "$AUTO_UPDATER_DIR/tests/integration-test.js"
    )
    
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            chmod +x "$script"
            log_success "Made executable: $(basename "$script")"
        else
            log_warning "Script not found: $script"
        fi
    done
}

setup_configuration() {
    log_info "Setting up configuration..."
    
    local config_file="$AUTO_UPDATER_DIR/config/auto-updater.json"
    local config_template="$AUTO_UPDATER_DIR/config/auto-updater.json"
    
    if [[ -f "$config_file" ]]; then
        log_info "Configuration file already exists"
        
        # Validate JSON
        if ! jq . "$config_file" > /dev/null 2>&1; then
            log_error "Configuration file is not valid JSON"
            exit 1
        fi
        
        log_success "Configuration file is valid"
    else
        log_error "Configuration file not found at $config_file"
        exit 1
    fi
    
    # Update paths in configuration to be absolute
    local temp_config=$(mktemp)
    jq --arg repo_root "$REPO_ROOT" \
       --arg auto_updater_dir "$AUTO_UPDATER_DIR" \
       '.paths.repoPath = $repo_root |
        .paths.flakeFile = ($repo_root + "/flake.nix") |
        .paths.flakeLockFile = ($repo_root + "/flake.lock") |
        .paths.backupDir = ($auto_updater_dir + "/backups") |
        .paths.logFile = ($auto_updater_dir + "/logs/auto-updater.log")' \
       "$config_file" > "$temp_config"
    
    mv "$temp_config" "$config_file"
    log_success "Updated configuration with absolute paths"
}

create_systemd_service() {
    if [[ "$EUID" -eq 0 ]]; then
        log_info "Creating systemd service..."
        
        local service_file="/etc/systemd/system/backlog-auto-updater.service"
        local user=$(logname 2>/dev/null || echo "$SUDO_USER")
        
        cat > "$service_file" << EOF
[Unit]
Description=Backlog.md Auto-Updater Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=$user
WorkingDirectory=$AUTO_UPDATER_DIR
ExecStart=/usr/bin/node $AUTO_UPDATER_DIR/lib/orchestrator.js start
ExecStop=/usr/bin/node $AUTO_UPDATER_DIR/lib/orchestrator.js stop
Restart=always
RestartSec=10
Environment=NODE_ENV=production

# Logging
StandardOutput=append:$AUTO_UPDATER_DIR/logs/service.log
StandardError=append:$AUTO_UPDATER_DIR/logs/service-error.log

# Security
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$AUTO_UPDATER_DIR $REPO_ROOT/memory

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        log_success "Systemd service created at $service_file"
        log_info "To enable the service: sudo systemctl enable backlog-auto-updater"
        log_info "To start the service: sudo systemctl start backlog-auto-updater"
    else
        log_info "Skipping systemd service creation (not running as root)"
    fi
}

setup_git_hooks() {
    log_info "Setting up Git hooks..."
    
    local hooks_dir="$REPO_ROOT/.git/hooks"
    local pre_commit_hook="$hooks_dir/pre-commit"
    
    if [[ ! -f "$pre_commit_hook" ]]; then
        cat > "$pre_commit_hook" << 'EOF'
#!/bin/bash
# Pre-commit hook for auto-updater
# Validates flake.nix and flake.lock before commits

set -e

# Check if flake files are being committed
if git diff --cached --name-only | grep -E "(flake\.nix|flake\.lock)" > /dev/null; then
    echo "🔍 Validating flake files..."
    
    # Run flake check
    if ! nix flake check; then
        echo "❌ Flake validation failed"
        exit 1
    fi
    
    echo "✅ Flake validation passed"
fi
EOF
        
        chmod +x "$pre_commit_hook"
        log_success "Created pre-commit hook"
    else
        log_info "Pre-commit hook already exists"
    fi
}

run_initial_tests() {
    log_info "Running initial tests..."
    
    cd "$AUTO_UPDATER_DIR"
    
    # Test configuration loading
    log_info "Testing configuration..."
    if node -e "
        const fs = require('fs');
        const config = JSON.parse(fs.readFileSync('config/auto-updater.json', 'utf8'));
        console.log('Configuration loaded successfully');
        console.log('Package:', config.packageName);
        console.log('Version:', config.currentVersion);
    "; then
        log_success "Configuration test passed"
    else
        log_error "Configuration test failed"
        exit 1
    fi
    
    # Test NPM registry connectivity
    log_info "Testing NPM registry connectivity..."
    if timeout 30 node scripts/npm-version-monitor.js check; then
        log_success "NPM registry connectivity test passed"
    else
        log_warning "NPM registry connectivity test failed (may indicate no updates available)"
    fi
    
    # Test flake validation
    log_info "Testing flake validation..."
    if timeout 60 nix flake check "$REPO_ROOT"; then
        log_success "Flake validation test passed"
    else
        log_warning "Flake validation test failed (flake may have issues)"
    fi
    
    # Test recovery system
    log_info "Testing recovery system..."
    if node scripts/recovery-system.js status > /dev/null; then
        log_success "Recovery system test passed"
    else
        log_error "Recovery system test failed"
        exit 1
    fi
}

store_setup_info() {
    log_info "Storing setup information..."
    
    local setup_info="{
        \"setupTime\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",
        \"version\": \"1.0.0\",
        \"nodeVersion\": \"$(node --version)\",
        \"nixVersion\": \"$(nix --version | cut -d' ' -f3)\",
        \"gitVersion\": \"$(git --version | cut -d' ' -f3)\",
        \"repoRoot\": \"$REPO_ROOT\",
        \"autoUpdaterDir\": \"$AUTO_UPDATER_DIR\",
        \"configPath\": \"$AUTO_UPDATER_DIR/config/auto-updater.json\",
        \"systemdService\": $(if [[ -f \"/etc/systemd/system/backlog-auto-updater.service\" ]]; then echo \"true\"; else echo \"false\"; fi)
    }"
    
    echo "$setup_info" > "$REPO_ROOT/memory/auto-updater/setup_info.json"
    log_success "Setup information stored"
}

print_usage_instructions() {
    log_success "🎉 Auto-Updater setup completed successfully!"
    echo
    log_info "Usage Instructions:"
    echo
    echo "  📁 Change to auto-updater directory:"
    echo "     cd $AUTO_UPDATER_DIR"
    echo
    echo "  ▶️  Start the auto-updater:"
    echo "     npm start"
    echo "     # or"
    echo "     node lib/orchestrator.js start"
    echo
    echo "  📊 Check status:"
    echo "     npm run status"
    echo
    echo "  🔄 Trigger manual update:"
    echo "     npm run update"
    echo
    echo "  🧪 Run tests:"
    echo "     npm test"
    echo
    echo "  📝 View logs:"
    echo "     tail -f logs/auto-updater.log"
    echo
    echo "  🛑 Stop the system:"
    echo "     npm stop"
    echo
    
    if [[ -f "/etc/systemd/system/backlog-auto-updater.service" ]]; then
        echo "  🔧 Systemd service commands:"
        echo "     sudo systemctl enable backlog-auto-updater"
        echo "     sudo systemctl start backlog-auto-updater"
        echo "     sudo systemctl status backlog-auto-updater"
        echo "     sudo systemctl logs -f backlog-auto-updater"
        echo
    fi
    
    echo "  📚 Documentation:"
    echo "     cat docs/README.md"
    echo
    echo "  🆘 Recovery commands:"
    echo "     node scripts/recovery-system.js list"
    echo "     node scripts/recovery-system.js rollback <backup-name>"
    echo
}

main() {
    log_info "🚀 Starting Auto-Updater Setup"
    echo
    
    check_dependencies
    setup_directories
    make_scripts_executable
    setup_configuration
    create_systemd_service
    setup_git_hooks
    run_initial_tests
    store_setup_info
    
    echo
    print_usage_instructions
}

# Handle command line arguments
case "${1:-setup}" in
    "setup")
        main
        ;;
    "test")
        log_info "Running setup tests only..."
        check_dependencies
        run_initial_tests
        log_success "Setup tests completed"
        ;;
    "service")
        if [[ "$EUID" -ne 0 ]]; then
            log_error "Service setup requires root privileges"
            log_info "Run: sudo $0 service"
            exit 1
        fi
        create_systemd_service
        ;;
    "clean")
        log_info "Cleaning up auto-updater setup..."
        rm -rf "$AUTO_UPDATER_DIR/logs"
        rm -rf "$AUTO_UPDATER_DIR/backups"
        rm -rf "$REPO_ROOT/memory/auto-updater"
        if [[ -f "/etc/systemd/system/backlog-auto-updater.service" ]]; then
            rm -f "/etc/systemd/system/backlog-auto-updater.service"
            systemctl daemon-reload
        fi
        log_success "Cleanup completed"
        ;;
    "help"|"-h"|"--help")
        echo "Auto-Updater Setup Script"
        echo
        echo "Usage: $0 [command]"
        echo
        echo "Commands:"
        echo "  setup    - Full setup (default)"
        echo "  test     - Run tests only"
        echo "  service  - Create systemd service only (requires root)"
        echo "  clean    - Clean up setup"
        echo "  help     - Show this help"
        ;;
    *)
        log_error "Unknown command: $1"
        echo "Run '$0 help' for usage information"
        exit 1
        ;;
esac