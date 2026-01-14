#!/bin/bash

# Startup Check Script
# Validates all third-party service connections before the observability stack is ready
# If any critical service fails, the script exits with non-zero status to stop the build

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration with defaults (can be overridden via environment variables)
PROMETHEUS_URL="${PROMETHEUS_URL:-http://prometheus:9090}"
GRAFANA_URL="${GRAFANA_URL:-http://grafana:3000}"
LOKI_URL="${LOKI_URL:-http://loki:3100}"
TEMPO_URL="${TEMPO_URL:-http://tempo:3200}"
ALERTMANAGER_URL="${ALERTMANAGER_URL:-http://alertmanager:9093}"
PROMTAIL_URL="${PROMTAIL_URL:-http://promtail:9080}"

# Optional external services (only checked if configured)
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
PAGERDUTY_SERVICE_KEY="${PAGERDUTY_SERVICE_KEY:-}"
POSTGRES_EXPORTER_URL="${POSTGRES_EXPORTER_URL:-}"

# Timing configuration
MAX_RETRIES="${MAX_RETRIES:-30}"
RETRY_INTERVAL="${RETRY_INTERVAL:-2}"
TIMEOUT="${TIMEOUT:-5}"

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Track critical failures
CRITICAL_FAILED=false

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓ PASS]${NC} $1"
    ((PASSED++))
}

log_error() {
    echo -e "${RED}[✗ FAIL]${NC} $1"
    ((FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[⚠ WARN]${NC} $1"
    ((WARNINGS++))
}

log_section() {
    echo ""
    echo -e "${YELLOW}=== $1 ===${NC}"
}

# Health check function with retry logic
check_service_health() {
    local service_name=$1
    local health_url=$2
    local expected_pattern=${3:-""}
    local is_critical=${4:-true}
    local max_retries=${5:-$MAX_RETRIES}

    log_info "Checking $service_name at $health_url..."

    for ((i=1; i<=max_retries; i++)); do
        response=$(curl -s --max-time $TIMEOUT "$health_url" 2>/dev/null || echo "")
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TIMEOUT "$health_url" 2>/dev/null || echo "000")

        # Check if response matches expected pattern or is HTTP 200
        if [ -n "$expected_pattern" ]; then
            if echo "$response" | grep -q "$expected_pattern"; then
                log_success "$service_name is healthy (matched: $expected_pattern)"
                return 0
            fi
        elif [ "$http_code" = "200" ]; then
            log_success "$service_name is healthy (HTTP 200)"
            return 0
        fi

        if [ $i -lt $max_retries ]; then
            log_info "Retry $i/$max_retries - $service_name not ready yet (HTTP $http_code), waiting ${RETRY_INTERVAL}s..."
            sleep $RETRY_INTERVAL
        fi
    done

    if [ "$is_critical" = true ]; then
        log_error "$service_name is not available after $max_retries attempts (HTTP $http_code)"
        CRITICAL_FAILED=true
    else
        log_warning "$service_name is not available (non-critical)"
    fi
    return 1
}

# Check if service port is open
check_port() {
    local service_name=$1
    local host=$2
    local port=$3
    local is_critical=${4:-true}

    log_info "Checking $service_name port connectivity ($host:$port)..."

    if nc -z -w $TIMEOUT "$host" "$port" 2>/dev/null; then
        log_success "$service_name port $port is accessible"
        return 0
    else
        if [ "$is_critical" = true ]; then
            log_error "$service_name port $port is not accessible"
            CRITICAL_FAILED=true
        else
            log_warning "$service_name port $port is not accessible (non-critical)"
        fi
        return 1
    fi
}

# Validate Slack webhook (non-blocking test)
check_slack_webhook() {
    local webhook_url=$1

    if [ -z "$webhook_url" ] || [ "$webhook_url" = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL" ]; then
        log_warning "Slack webhook not configured (using placeholder or empty)"
        return 0
    fi

    log_info "Validating Slack webhook configuration..."

    # We don't send actual messages, just validate the URL format
    if echo "$webhook_url" | grep -qE "^https://hooks\.slack\.com/services/"; then
        log_success "Slack webhook URL format is valid"
        return 0
    else
        log_warning "Slack webhook URL format appears invalid"
        return 1
    fi
}

# Validate PagerDuty service key
check_pagerduty() {
    local service_key=$1

    if [ -z "$service_key" ] || [ "$service_key" = "your-pagerduty-key" ]; then
        log_warning "PagerDuty service key not configured (using placeholder or empty)"
        return 0
    fi

    log_info "Validating PagerDuty configuration..."

    # Validate key format (32 character alphanumeric)
    if echo "$service_key" | grep -qE "^[a-zA-Z0-9]{32}$"; then
        log_success "PagerDuty service key format is valid"
        return 0
    else
        log_warning "PagerDuty service key format may be invalid (expected 32 alphanumeric characters)"
        return 1
    fi
}

# Check Prometheus targets
check_prometheus_targets() {
    log_info "Checking Prometheus scrape targets..."

    local targets_response
    targets_response=$(curl -s --max-time $TIMEOUT "${PROMETHEUS_URL}/api/v1/targets" 2>/dev/null || echo "")

    if [ -z "$targets_response" ]; then
        log_warning "Could not fetch Prometheus targets"
        return 1
    fi

    if echo "$targets_response" | grep -q "\"status\":\"success\""; then
        local active_targets
        active_targets=$(echo "$targets_response" | grep -o '"health":"up"' | wc -l | tr -d ' ')
        local total_targets
        total_targets=$(echo "$targets_response" | grep -o '"health":' | wc -l | tr -d ' ')

        if [ "$active_targets" -gt 0 ]; then
            log_success "Prometheus has $active_targets/$total_targets targets up"
            return 0
        else
            log_warning "Prometheus has no active targets yet"
            return 1
        fi
    else
        log_warning "Prometheus targets query failed"
        return 1
    fi
}

# Check Grafana datasources
check_grafana_datasources() {
    log_info "Checking Grafana datasources..."

    local datasources_response
    datasources_response=$(curl -s --max-time $TIMEOUT -u admin:yourpassword123 "${GRAFANA_URL}/api/datasources" 2>/dev/null || echo "")

    if [ -z "$datasources_response" ]; then
        log_warning "Could not fetch Grafana datasources"
        return 1
    fi

    if echo "$datasources_response" | grep -q "\"name\""; then
        local ds_count
        ds_count=$(echo "$datasources_response" | grep -o '"name"' | wc -l | tr -d ' ')
        log_success "Grafana has $ds_count datasources configured"
        return 0
    else
        log_warning "No Grafana datasources found"
        return 1
    fi
}

# Main startup check sequence
main() {
    echo ""
    echo "======================================"
    echo "  Observability Stack Startup Check"
    echo "======================================"
    echo ""
    echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo ""

    # ==========================================
    # Core Observability Services (Critical)
    # ==========================================
    log_section "Core Observability Services (Critical)"

    # Prometheus - Metrics collection
    check_service_health "Prometheus" "${PROMETHEUS_URL}/-/healthy" "" true

    # Loki - Log aggregation
    check_service_health "Loki" "${LOKI_URL}/ready" "ready" true

    # Tempo - Distributed tracing
    check_service_health "Tempo" "${TEMPO_URL}/ready" "ready" true

    # Grafana - Visualization
    check_service_health "Grafana" "${GRAFANA_URL}/api/health" "ok" true

    # Alertmanager - Alert routing
    check_service_health "Alertmanager" "${ALERTMANAGER_URL}/-/healthy" "" true

    # Promtail - Log shipper
    check_service_health "Promtail" "${PROMTAIL_URL}/ready" "ready" true

    # ==========================================
    # Service Integration Checks
    # ==========================================
    log_section "Service Integration Checks"

    # Check Prometheus targets are being scraped
    check_prometheus_targets || true

    # Check Grafana datasources are configured
    check_grafana_datasources || true

    # ==========================================
    # Optional External Services
    # ==========================================
    log_section "External Notification Services (Optional)"

    # Slack webhook validation
    check_slack_webhook "$SLACK_WEBHOOK_URL"

    # PagerDuty validation
    check_pagerduty "$PAGERDUTY_SERVICE_KEY"

    # ==========================================
    # Optional Infrastructure Services
    # ==========================================
    if [ -n "$POSTGRES_EXPORTER_URL" ]; then
        log_section "Infrastructure Services (Optional)"
        check_service_health "PostgreSQL Exporter" "${POSTGRES_EXPORTER_URL}/metrics" "pg_up" false 5
    fi

    # ==========================================
    # Summary
    # ==========================================
    echo ""
    echo "======================================"
    echo "  Startup Check Summary"
    echo "======================================"
    echo -e "${GREEN}Passed:   $PASSED${NC}"
    echo -e "${RED}Failed:   $FAILED${NC}"
    echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
    echo "======================================"
    echo ""

    if [ "$CRITICAL_FAILED" = true ]; then
        echo -e "${RED}STARTUP CHECK FAILED${NC}"
        echo "One or more critical services are not available."
        echo "Please check the logs above for details."
        exit 1
    fi

    if [ $FAILED -gt 0 ]; then
        echo -e "${YELLOW}STARTUP CHECK COMPLETED WITH FAILURES${NC}"
        echo "Some non-critical checks failed. Review warnings above."
        exit 1
    fi

    echo -e "${GREEN}STARTUP CHECK PASSED${NC}"
    echo "All critical services are healthy and connected."
    exit 0
}

# Run main function
main "$@"
