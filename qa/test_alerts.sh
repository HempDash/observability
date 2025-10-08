#!/usr/bin/env bash
set -e

# Load environment variables
if [ -f .env ]; then
  source .env
else
  echo "Warning: .env file not found, using defaults"
  PROMETHEUS_URL=${PROMETHEUS_URL:-http://localhost:9090}
  ALERTMANAGER_URL=${ALERTMANAGER_URL:-http://localhost:9093}
  TEST_TIMEOUT=${TEST_TIMEOUT:-30}
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "================================================"
echo "Testing Alert Configuration"
echo "================================================"
echo ""

# Function to test Prometheus rules loading
test_prometheus_rules() {
  echo -n "Testing Prometheus rules loaded... "
  response=$(curl -s "${PROMETHEUS_URL}/api/v1/rules")
  status=$(echo "$response" | grep -o '"status":"success"')

  if [ -n "$status" ]; then
    rule_groups=$(echo "$response" | grep -o '"name":' | wc -l)
    echo -e "${GREEN}PASS${NC} ($rule_groups rule groups loaded)"
    return 0
  else
    echo -e "${RED}FAIL${NC} (Could not load rules)"
    return 1
  fi
}

# Function to test DB-HA alert rules
test_db_ha_alert_rules() {
  echo -n "Testing DB-HA alert rules... "
  response=$(curl -s "${PROMETHEUS_URL}/api/v1/rules")

  # Check for specific DB-HA alerts
  replica_not_streaming=$(echo "$response" | grep -o 'ReplicaNotStreaming')
  replica_lag_high=$(echo "$response" | grep -o 'ReplicaLagHigh')
  exporter_down=$(echo "$response" | grep -o 'ExporterDown')

  if [ -n "$replica_not_streaming" ] && [ -n "$replica_lag_high" ] && [ -n "$exporter_down" ]; then
    echo -e "${GREEN}PASS${NC}"
    return 0
  else
    echo -e "${RED}FAIL${NC} (DB-HA alert rules not found)"
    echo "  ReplicaNotStreaming: $([ -n "$replica_not_streaming" ] && echo "✓" || echo "✗")"
    echo "  ReplicaLagHigh: $([ -n "$replica_lag_high" ] && echo "✓" || echo "✗")"
    echo "  ExporterDown: $([ -n "$exporter_down" ] && echo "✓" || echo "✗")"
    return 1
  fi
}

# Function to test PostgreSQL alert rules
test_postgres_alert_rules() {
  echo -n "Testing PostgreSQL alert rules... "
  response=$(curl -s "${PROMETHEUS_URL}/api/v1/rules")

  # Check for PostgreSQL alerts
  postgres_down=$(echo "$response" | grep -o 'PostgreSQLDown')
  too_many_connections=$(echo "$response" | grep -o 'PostgreSQLTooManyConnections')

  if [ -n "$postgres_down" ] && [ -n "$too_many_connections" ]; then
    echo -e "${GREEN}PASS${NC}"
    return 0
  else
    echo -e "${RED}FAIL${NC} (PostgreSQL alert rules not found)"
    return 1
  fi
}

# Function to check alert states
test_alert_states() {
  echo -n "Testing alert states... "
  response=$(curl -s "${PROMETHEUS_URL}/api/v1/alerts")
  status=$(echo "$response" | grep -o '"status":"success"')

  if [ -n "$status" ]; then
    firing_alerts=$(echo "$response" | grep -o '"state":"firing"' | wc -l)
    pending_alerts=$(echo "$response" | grep -o '"state":"pending"' | wc -l)
    inactive_alerts=$(echo "$response" | grep -o '"state":"inactive"' | wc -l)

    echo -e "${GREEN}PASS${NC}"
    echo "  Firing: $firing_alerts"
    echo "  Pending: $pending_alerts"
    echo "  Inactive: $inactive_alerts"

    if [ "$firing_alerts" -gt 0 ]; then
      echo -e "${YELLOW}Warning: $firing_alerts alert(s) currently firing${NC}"
    fi
    return 0
  else
    echo -e "${RED}FAIL${NC} (Could not retrieve alert states)"
    return 1
  fi
}

# Function to test Alertmanager health
test_alertmanager_health() {
  echo -n "Testing Alertmanager health... "
  response=$(curl -s -o /dev/null -w "%{http_code}" "${ALERTMANAGER_URL}/-/healthy")

  if [ "$response" -eq 200 ]; then
    echo -e "${GREEN}PASS${NC}"
    return 0
  else
    echo -e "${YELLOW}WARN${NC} (Alertmanager not available - HTTP $response)"
    return 0
  fi
}

# Function to test Alertmanager configuration
test_alertmanager_config() {
  echo -n "Testing Alertmanager configuration... "
  response=$(curl -s "${ALERTMANAGER_URL}/api/v1/status")
  status=$(echo "$response" | grep -o '"status":"success"')

  if [ -n "$status" ]; then
    echo -e "${GREEN}PASS${NC}"
    return 0
  else
    echo -e "${YELLOW}WARN${NC} (Alertmanager configuration not available)"
    return 0
  fi
}

# Function to validate alert rule syntax
test_rule_syntax() {
  echo -n "Testing alert rule syntax... "

  # Check if promtool is available
  if command -v promtool &> /dev/null; then
    # Validate alert rules
    if promtool check rules ../prometheus/rules/alerts.yml > /dev/null 2>&1; then
      echo -e "${GREEN}PASS${NC}"
      return 0
    else
      echo -e "${RED}FAIL${NC} (Alert rule syntax errors)"
      promtool check rules ../prometheus/rules/alerts.yml
      return 1
    fi
  else
    echo -e "${YELLOW}SKIP${NC} (promtool not available)"
    return 0
  fi
}

# Run all tests
echo "Starting alert tests..."
echo ""

test_results=0

test_prometheus_rules || ((test_results++))
test_db_ha_alert_rules || ((test_results++))
test_postgres_alert_rules || ((test_results++))
test_alert_states || ((test_results++))
test_alertmanager_health || ((test_results++))
test_alertmanager_config || ((test_results++))
test_rule_syntax || ((test_results++))

echo ""
echo "================================================"
if [ $test_results -eq 0 ]; then
  echo -e "${GREEN}All alert tests passed!${NC}"
  exit 0
else
  echo -e "${RED}$test_results test(s) failed${NC}"
  exit 1
fi
