#!/usr/bin/env bash
set -e

# Load environment variables
if [ -f .env ]; then
  source .env
else
  echo "Warning: .env file not found, using defaults"
  PROMETHEUS_URL=${PROMETHEUS_URL:-http://localhost:9090}
  POSTGRES_EXPORTER_URL=${POSTGRES_EXPORTER_URL:-http://postgres-exporter:9187}
  TEST_TIMEOUT=${TEST_TIMEOUT:-30}
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "================================================"
echo "Testing Metrics Collection"
echo "================================================"
echo ""

# Function to test Prometheus health
test_prometheus_health() {
  echo -n "Testing Prometheus health... "
  response=$(curl -s -o /dev/null -w "%{http_code}" "${PROMETHEUS_URL}/-/healthy")
  if [ "$response" -eq 200 ]; then
    echo -e "${GREEN}PASS${NC}"
    return 0
  else
    echo -e "${RED}FAIL${NC} (HTTP $response)"
    return 1
  fi
}

# Function to test Prometheus targets
test_prometheus_targets() {
  echo -n "Testing Prometheus targets... "
  response=$(curl -s "${PROMETHEUS_URL}/api/v1/targets")
  active_targets=$(echo "$response" | grep -o '"health":"up"' | wc -l)

  if [ "$active_targets" -gt 0 ]; then
    echo -e "${GREEN}PASS${NC} ($active_targets active targets)"
    return 0
  else
    echo -e "${RED}FAIL${NC} (No active targets)"
    return 1
  fi
}

# Function to test postgres-exporter target
test_postgres_exporter_target() {
  echo -n "Testing postgres-exporter target... "
  response=$(curl -s "${PROMETHEUS_URL}/api/v1/targets")
  postgres_target=$(echo "$response" | grep -o '"job":"postgres-exporter".*"health":"up"')

  if [ -n "$postgres_target" ]; then
    echo -e "${GREEN}PASS${NC}"
    return 0
  else
    echo -e "${RED}FAIL${NC} (postgres-exporter not up)"
    return 1
  fi
}

# Function to test postgres metrics
test_postgres_metrics() {
  echo -n "Testing PostgreSQL metrics availability... "

  # Test for key postgres metrics
  metrics=(
    "pg_up"
    "pg_stat_database_numbackends"
    "pg_settings_max_connections"
  )

  failed=0
  for metric in "${metrics[@]}"; do
    response=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=${metric}")
    result=$(echo "$response" | grep -o '"status":"success"')

    if [ -z "$result" ]; then
      echo -e "${RED}FAIL${NC} (Metric $metric not available)"
      failed=1
    fi
  done

  if [ $failed -eq 0 ]; then
    echo -e "${GREEN}PASS${NC}"
    return 0
  else
    return 1
  fi
}

# Function to test replication metrics
test_replication_metrics() {
  echo -n "Testing replication metrics... "

  # Test for replication metrics
  response=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=pg_stat_replication_write_lag")
  result=$(echo "$response" | grep -o '"status":"success"')

  if [ -n "$result" ]; then
    echo -e "${GREEN}PASS${NC}"
    return 0
  else
    echo -e "${YELLOW}WARN${NC} (Replication metrics not available - may be expected if no replica configured)"
    return 0
  fi
}

# Function to test recording rules
test_recording_rules() {
  echo -n "Testing recording rules... "

  # Test for recording rule metrics
  rules=(
    "db_total_tps"
    "db_cache_hit_ratio"
    "db_active_connections"
  )

  failed=0
  for rule in "${rules[@]}"; do
    response=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=${rule}")
    result=$(echo "$response" | grep -o '"status":"success"')

    if [ -z "$result" ]; then
      echo -e "${RED}FAIL${NC} (Recording rule $rule not available)"
      failed=1
    fi
  done

  if [ $failed -eq 0 ]; then
    echo -e "${GREEN}PASS${NC}"
    return 0
  else
    return 1
  fi
}

# Run all tests
echo "Starting metrics tests..."
echo ""

test_results=0

test_prometheus_health || ((test_results++))
test_prometheus_targets || ((test_results++))
test_postgres_exporter_target || ((test_results++))
test_postgres_metrics || ((test_results++))
test_replication_metrics || ((test_results++))
test_recording_rules || ((test_results++))

echo ""
echo "================================================"
if [ $test_results -eq 0 ]; then
  echo -e "${GREEN}All metrics tests passed!${NC}"
  exit 0
else
  echo -e "${RED}$test_results test(s) failed${NC}"
  exit 1
fi
