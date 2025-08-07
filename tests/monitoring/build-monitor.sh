#!/usr/bin/env bash
# Build Monitoring and Alerting System
# Monitors flake builds, detects failures, and sends alerts

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly MONITOR_DIR="$PROJECT_ROOT/tests/monitoring"

# Configuration
readonly CONFIG_FILE="${MONITOR_CONFIG_FILE:-$MONITOR_DIR/monitor.conf}"
readonly LOG_DIR="${MONITOR_LOG_DIR:-$PROJECT_ROOT/tests/output/monitoring}"
readonly ALERT_LOG="$LOG_DIR/alerts.log"
readonly BUILD_LOG="$LOG_DIR/builds.log"
readonly METRICS_LOG="$LOG_DIR/metrics.log"

# Default configuration
declare -A CONFIG=(
    [CHECK_INTERVAL]=30
    [BUILD_TIMEOUT]=300
    [FAILURE_THRESHOLD]=3
    [ALERT_COOLDOWN]=3600
    [ENABLE_SLACK]=false
    [ENABLE_EMAIL]=false
    [ENABLE_WEBHOOK]=false
    [PACKAGE_NAME]="backlog-md"
    [FLAKE_PATH]="."
)

# State tracking
declare -A STATE=(
    [CONSECUTIVE_FAILURES]=0
    [LAST_ALERT_TIME]=0
    [MONITORING_ACTIVE]=false
    [LAST_BUILD_TIME]=0
)

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Loading configuration from: $CONFIG_FILE"
        source "$CONFIG_FILE"
        
        # Override defaults with loaded config
        for key in "${!CONFIG[@]}"; do
            if [[ -n "${!key:-}" ]]; then
                CONFIG[$key]="${!key}"
            fi
        done
    else
        log_info "No config file found, using defaults"
        create_default_config
    fi
}

# Create default configuration file
create_default_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    
    cat > "$CONFIG_FILE" << 'EOF'
# Build Monitor Configuration

# Monitoring intervals (seconds)
CHECK_INTERVAL=30
BUILD_TIMEOUT=300

# Alert thresholds
FAILURE_THRESHOLD=3
ALERT_COOLDOWN=3600

# Package settings
PACKAGE_NAME="backlog-md"
FLAKE_PATH="."

# Alert channels (true/false)
ENABLE_SLACK=false
ENABLE_EMAIL=false  
ENABLE_WEBHOOK=false

# Slack settings (if enabled)
SLACK_WEBHOOK_URL=""
SLACK_CHANNEL="#alerts"

# Email settings (if enabled)
EMAIL_FROM="noreply@example.com"
EMAIL_TO="admin@example.com"
EMAIL_SMTP_SERVER="localhost"

# Webhook settings (if enabled)
WEBHOOK_URL=""
WEBHOOK_SECRET=""

# Performance thresholds
BUILD_TIME_WARNING=120
BUILD_TIME_CRITICAL=240
MEMORY_WARNING_MB=2048
MEMORY_CRITICAL_MB=4096
EOF

    log_info "Default configuration created at: $CONFIG_FILE"
}

# Logging functions
log_info() {
    echo "[$(date -Iseconds)] [INFO] $*" >&2
}

log_warn() {
    echo "[$(date -Iseconds)] [WARN] $*" >&2
}

log_error() {
    echo "[$(date -Iseconds)] [ERROR] $*" >&2
}

log_alert() {
    echo "[$(date -Iseconds)] [ALERT] $*" >&2
    echo "[$(date -Iseconds)] [ALERT] $*" >> "$ALERT_LOG"
}

# Build monitoring functions
check_build_health() {
    local flake_path="${CONFIG[FLAKE_PATH]}"
    local package="${CONFIG[PACKAGE_NAME]}"
    local build_timeout="${CONFIG[BUILD_TIMEOUT]}"
    
    local start_time
    start_time=$(date +%s)
    
    local build_result=""
    local build_success=false
    local build_duration=0
    local memory_usage=0
    
    log_info "Checking build health for $package"
    
    # Run build with timeout and capture metrics
    if timeout "$build_timeout" bash -c "
        cd '$flake_path'
        
        # Start memory monitoring in background
        (
            while kill -0 \$\$ 2>/dev/null; do
                if command -v free >/dev/null; then
                    free -m | awk 'NR==2{printf \"memory_mb:%d\\n\", \$3}' >> '$METRICS_LOG.tmp'
                fi
                sleep 1
            done
        ) &
        MEMORY_PID=\$!
        
        # Run the build
        nix build '.#$package' --no-link --rebuild
        
        # Stop memory monitoring
        kill \$MEMORY_PID 2>/dev/null || true
    "; then
        build_success=true
        build_result="SUCCESS"
        STATE[CONSECUTIVE_FAILURES]=0
    else
        local exit_code=$?
        build_success=false
        
        if [[ $exit_code -eq 124 ]]; then
            build_result="TIMEOUT"
        else
            build_result="FAILURE"
        fi
        
        ((STATE[CONSECUTIVE_FAILURES]++))
    fi
    
    local end_time
    end_time=$(date +%s)
    build_duration=$((end_time - start_time))
    
    # Get peak memory usage from monitoring
    if [[ -f "$METRICS_LOG.tmp" ]]; then
        memory_usage=$(grep "memory_mb:" "$METRICS_LOG.tmp" | cut -d: -f2 | sort -n | tail -1)
        rm -f "$METRICS_LOG.tmp"
    fi
    
    # Log build metrics
    log_build_metrics "$build_result" "$build_duration" "$memory_usage"
    
    # Check for performance issues
    check_performance_thresholds "$build_duration" "$memory_usage"
    
    # Handle build failures
    if [[ "$build_success" == "false" ]]; then
        handle_build_failure "$build_result"
    fi
    
    STATE[LAST_BUILD_TIME]=$start_time
    
    return $([ "$build_success" == "true" ] && echo 0 || echo 1)
}

# Log build metrics
log_build_metrics() {
    local result="$1"
    local duration="$2" 
    local memory="$3"
    
    local timestamp
    timestamp=$(date -Iseconds)
    
    # JSON log entry
    cat >> "$BUILD_LOG" << EOF
{"timestamp":"$timestamp","result":"$result","duration_seconds":$duration,"memory_mb":$memory,"package":"${CONFIG[PACKAGE_NAME]}"}
EOF
    echo "" >> "$BUILD_LOG"  # Newline for JSON streaming
    
    # Human-readable log
    log_info "Build result: $result (${duration}s, ${memory}MB)"
    
    # Update metrics
    cat >> "$METRICS_LOG" << EOF
$timestamp,build_duration,$duration
$timestamp,build_memory,$memory
$timestamp,build_result,$result
EOF
}

# Check performance thresholds
check_performance_thresholds() {
    local duration="$1"
    local memory="$2"
    
    # Build time warnings
    if [[ -n "${BUILD_TIME_CRITICAL:-}" ]] && (( duration > BUILD_TIME_CRITICAL )); then
        send_alert "CRITICAL" "Build time exceeded critical threshold: ${duration}s > ${BUILD_TIME_CRITICAL}s"
    elif [[ -n "${BUILD_TIME_WARNING:-}" ]] && (( duration > BUILD_TIME_WARNING )); then
        send_alert "WARNING" "Build time exceeded warning threshold: ${duration}s > ${BUILD_TIME_WARNING}s"
    fi
    
    # Memory usage warnings  
    if [[ -n "${MEMORY_CRITICAL_MB:-}" ]] && (( memory > MEMORY_CRITICAL_MB )); then
        send_alert "CRITICAL" "Memory usage exceeded critical threshold: ${memory}MB > ${MEMORY_CRITICAL_MB}MB"
    elif [[ -n "${MEMORY_WARNING_MB:-}" ]] && (( memory > MEMORY_WARNING_MB )); then
        send_alert "WARNING" "Memory usage exceeded warning threshold: ${memory}MB > ${MEMORY_WARNING_MB}MB"
    fi
}

# Handle build failures
handle_build_failure() {
    local failure_type="$1"
    local consecutive_failures="${STATE[CONSECUTIVE_FAILURES]}"
    local failure_threshold="${CONFIG[FAILURE_THRESHOLD]}"
    
    log_error "Build failed: $failure_type (consecutive failures: $consecutive_failures)"
    
    # Send alert if threshold reached
    if (( consecutive_failures >= failure_threshold )); then
        send_alert "CRITICAL" "Build failure threshold reached: $consecutive_failures consecutive failures ($failure_type)"
    elif (( consecutive_failures == 1 )); then
        send_alert "WARNING" "Build failure detected: $failure_type"
    fi
}

# Send alerts through configured channels
send_alert() {
    local level="$1"
    local message="$2"
    local current_time
    current_time=$(date +%s)
    local last_alert="${STATE[LAST_ALERT_TIME]}"
    local cooldown="${CONFIG[ALERT_COOLDOWN]}"
    
    # Check cooldown period
    if (( current_time - last_alert < cooldown )); then
        log_info "Alert cooldown active, skipping alert"
        return 0
    fi
    
    log_alert "[$level] $message"
    
    # Send to configured channels
    if [[ "${CONFIG[ENABLE_SLACK]}" == "true" ]]; then
        send_slack_alert "$level" "$message"
    fi
    
    if [[ "${CONFIG[ENABLE_EMAIL]}" == "true" ]]; then
        send_email_alert "$level" "$message"
    fi
    
    if [[ "${CONFIG[ENABLE_WEBHOOK]}" == "true" ]]; then
        send_webhook_alert "$level" "$message"
    fi
    
    STATE[LAST_ALERT_TIME]=$current_time
}

# Slack alert implementation
send_slack_alert() {
    local level="$1"
    local message="$2"
    
    if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
        log_warn "Slack webhook URL not configured"
        return 1
    fi
    
    local color
    case "$level" in
        "CRITICAL") color="#ff0000" ;;
        "WARNING") color="#ffaa00" ;;
        *) color="#00ff00" ;;
    esac
    
    local payload
    payload=$(cat << EOF
{
  "channel": "${SLACK_CHANNEL:-#alerts}",
  "username": "Build Monitor",
  "text": "Build Alert",
  "attachments": [{
    "color": "$color",
    "fields": [{
      "title": "$level Alert",
      "value": "$message",
      "short": false
    },{
      "title": "Package",
      "value": "${CONFIG[PACKAGE_NAME]}",
      "short": true
    },{
      "title": "Time",
      "value": "$(date -Iseconds)",
      "short": true
    }]
  }]
}
EOF
)
    
    if curl -s -X POST -H 'Content-type: application/json' \
        --data "$payload" "$SLACK_WEBHOOK_URL" > /dev/null; then
        log_info "Slack alert sent successfully"
    else
        log_error "Failed to send Slack alert"
    fi
}

# Email alert implementation  
send_email_alert() {
    local level="$1"
    local message="$2"
    
    if [[ -z "${EMAIL_TO:-}" ]]; then
        log_warn "Email recipient not configured"
        return 1
    fi
    
    local subject="[$level] Build Monitor Alert - ${CONFIG[PACKAGE_NAME]}"
    local body="
Build Monitor Alert

Level: $level
Package: ${CONFIG[PACKAGE_NAME]}
Time: $(date -Iseconds)
Message: $message

Consecutive Failures: ${STATE[CONSECUTIVE_FAILURES]}
Last Successful Build: $(date -Iseconds -d @"${STATE[LAST_BUILD_TIME]}")

-- 
Automated Build Monitor
"
    
    # Simple sendmail implementation
    if command -v sendmail >/dev/null; then
        (
            echo "To: ${EMAIL_TO}"
            echo "From: ${EMAIL_FROM:-build-monitor@localhost}"
            echo "Subject: $subject"
            echo ""
            echo "$body"
        ) | sendmail "${EMAIL_TO}"
        
        log_info "Email alert sent successfully"
    else
        log_warn "sendmail not available, cannot send email alert"
    fi
}

# Webhook alert implementation
send_webhook_alert() {
    local level="$1"
    local message="$2"
    
    if [[ -z "${WEBHOOK_URL:-}" ]]; then
        log_warn "Webhook URL not configured"
        return 1
    fi
    
    local payload
    payload=$(cat << EOF
{
  "timestamp": "$(date -Iseconds)",
  "level": "$level",
  "message": "$message",
  "package": "${CONFIG[PACKAGE_NAME]}",
  "consecutive_failures": ${STATE[CONSECUTIVE_FAILURES]},
  "build_metrics": {
    "last_build_time": ${STATE[LAST_BUILD_TIME]}
  }
}
EOF
)
    
    local headers=()
    if [[ -n "${WEBHOOK_SECRET:-}" ]]; then
        local signature
        signature=$(echo -n "$payload" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | cut -d' ' -f2)
        headers+=("-H" "X-Signature: sha256=$signature")
    fi
    
    if curl -s -X POST -H 'Content-Type: application/json' \
        "${headers[@]}" --data "$payload" "$WEBHOOK_URL" > /dev/null; then
        log_info "Webhook alert sent successfully"
    else
        log_error "Failed to send webhook alert"
    fi
}

# Generate monitoring reports
generate_report() {
    local report_type="${1:-daily}"
    local output_file="${2:-$LOG_DIR/report_$(date +%Y%m%d).json}"
    
    log_info "Generating $report_type monitoring report"
    
    # Calculate time range
    local since_time
    case "$report_type" in
        "hourly") since_time=$(date -d '1 hour ago' +%s) ;;
        "daily") since_time=$(date -d '1 day ago' +%s) ;;
        "weekly") since_time=$(date -d '1 week ago' +%s) ;;
        *) since_time=$(date -d '1 day ago' +%s) ;;
    esac
    
    # Analyze build logs
    local total_builds=0
    local successful_builds=0
    local failed_builds=0
    local avg_build_time=0
    local max_build_time=0
    local avg_memory=0
    local max_memory=0
    
    if [[ -f "$BUILD_LOG" ]]; then
        # Parse JSON build logs
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                local timestamp
                timestamp=$(echo "$line" | jq -r '.timestamp // empty' 2>/dev/null | xargs date -d)
                
                if [[ -n "$timestamp" ]] && (( $(date -d "$timestamp" +%s) >= since_time )); then
                    ((total_builds++))
                    
                    local result
                    result=$(echo "$line" | jq -r '.result // empty' 2>/dev/null)
                    
                    if [[ "$result" == "SUCCESS" ]]; then
                        ((successful_builds++))
                    else
                        ((failed_builds++))
                    fi
                    
                    # Aggregate metrics
                    local duration memory
                    duration=$(echo "$line" | jq -r '.duration_seconds // 0' 2>/dev/null)
                    memory=$(echo "$line" | jq -r '.memory_mb // 0' 2>/dev/null)
                    
                    avg_build_time=$((avg_build_time + duration))
                    avg_memory=$((avg_memory + memory))
                    
                    if (( duration > max_build_time )); then
                        max_build_time=$duration
                    fi
                    
                    if (( memory > max_memory )); then
                        max_memory=$memory
                    fi
                fi
            fi
        done < "$BUILD_LOG"
        
        # Calculate averages
        if (( total_builds > 0 )); then
            avg_build_time=$((avg_build_time / total_builds))
            avg_memory=$((avg_memory / total_builds))
        fi
    fi
    
    # Count alerts
    local total_alerts=0
    local critical_alerts=0
    local warning_alerts=0
    
    if [[ -f "$ALERT_LOG" ]]; then
        total_alerts=$(grep -c "\[ALERT\]" "$ALERT_LOG" || echo 0)
        critical_alerts=$(grep -c "\[CRITICAL\]" "$ALERT_LOG" || echo 0) 
        warning_alerts=$(grep -c "\[WARNING\]" "$ALERT_LOG" || echo 0)
    fi
    
    # Generate report
    cat > "$output_file" << EOF
{
  "report_type": "$report_type",
  "generated_at": "$(date -Iseconds)",
  "time_range": {
    "since": "$(date -Iseconds -d @$since_time)",
    "until": "$(date -Iseconds)"
  },
  "build_metrics": {
    "total_builds": $total_builds,
    "successful_builds": $successful_builds,
    "failed_builds": $failed_builds,
    "success_rate": $(echo "scale=2; $successful_builds * 100 / ($total_builds + 0.01)" | bc),
    "avg_build_time_seconds": $avg_build_time,
    "max_build_time_seconds": $max_build_time,
    "avg_memory_mb": $avg_memory,
    "max_memory_mb": $max_memory
  },
  "alert_metrics": {
    "total_alerts": $total_alerts,
    "critical_alerts": $critical_alerts,
    "warning_alerts": $warning_alerts
  },
  "system_status": {
    "monitoring_active": ${STATE[MONITORING_ACTIVE]},
    "consecutive_failures": ${STATE[CONSECUTIVE_FAILURES]},
    "last_build": "$(date -Iseconds -d @"${STATE[LAST_BUILD_TIME]}")"
  }
}
EOF
    
    log_info "Report generated: $output_file"
}

# Main monitoring loop
start_monitoring() {
    log_info "Starting build monitoring..."
    
    STATE[MONITORING_ACTIVE]=true
    
    # Create necessary directories
    mkdir -p "$LOG_DIR"
    
    # Signal handler for graceful shutdown
    trap 'stop_monitoring; exit 0' SIGINT SIGTERM
    
    log_info "Monitoring ${CONFIG[PACKAGE_NAME]} every ${CONFIG[CHECK_INTERVAL]} seconds"
    
    while [[ "${STATE[MONITORING_ACTIVE]}" == "true" ]]; do
        check_build_health || true  # Continue monitoring even on build failures
        
        # Generate periodic reports
        local current_minute
        current_minute=$(date +%M)
        
        # Generate hourly report at minute 0
        if [[ "$current_minute" == "00" ]]; then
            generate_report "hourly" "$LOG_DIR/hourly_$(date +%Y%m%d_%H).json"
        fi
        
        # Sleep for check interval
        sleep "${CONFIG[CHECK_INTERVAL]}"
    done
}

# Stop monitoring
stop_monitoring() {
    log_info "Stopping build monitoring..."
    STATE[MONITORING_ACTIVE]=false
    
    # Generate final report
    generate_report "session" "$LOG_DIR/final_report_$(date +%Y%m%d_%H%M%S).json"
}

# CLI interface
main() {
    local command="${1:-start}"
    
    case "$command" in
        "start")
            load_config
            start_monitoring
            ;;
        "check")
            load_config
            mkdir -p "$LOG_DIR"
            check_build_health
            ;;
        "report")
            local report_type="${2:-daily}"
            local output="${3:-}"
            generate_report "$report_type" "$output"
            ;;
        "config")
            create_default_config
            echo "Configuration created at: $CONFIG_FILE"
            ;;
        "status")
            if [[ -f "$BUILD_LOG" ]]; then
                echo "Recent builds:"
                tail -5 "$BUILD_LOG" | jq -r '"\(.timestamp) \(.result) (\(.duration_seconds)s)"'
            fi
            if [[ -f "$ALERT_LOG" ]]; then
                echo "Recent alerts:"
                tail -5 "$ALERT_LOG"
            fi
            ;;
        "help"|*)
            echo "Build Monitor - Usage:"
            echo "  $0 start       - Start continuous monitoring"
            echo "  $0 check       - Run single build check"
            echo "  $0 report [type] - Generate report (hourly/daily/weekly)"
            echo "  $0 config      - Create default configuration"
            echo "  $0 status      - Show recent activity"
            echo "  $0 help        - Show this help"
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi