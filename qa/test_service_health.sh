#!/bin/bash

# Service Health Check Validation Script
# This script validates that all service health checks are working correctly
# and that the Service Health Dashboard has the required metrics

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0

# Function to print test result
print_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ PASS${NC}: $2"
        ((PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}: $2"
        ((FAILED++))
    fi
}

# Function to check if a service is reachable
check_service_health() {
    local service_name=$1
    local health_url=$2
    local expected_status=${3:-200}

    echo -e "\n${YELLOW}Checking $service_name health...${NC}"

    response=$(curl -s -o /dev/null -w "%{http_code}" "$health_url" 2>/dev/null || echo "000")

    if [ "$response" = "$expected_status" ]; then
        print_result 0 "$service_name is healthy (HTTP $response)"
        return 0
    else
        print_result 1 "$service_name is unhealthy (HTTP $response, expected $expected_status)"
        return 1
    fi
}

# Function to check Prometheus metrics
check_prometheus_metric() {
    local metric_name=$1
    local description=$2

    response=$(curl -s "http://localhost:9090/api/v1/query?query=$metric_name" 2>/dev/null || echo "")

    if echo "$response" | grep -q "\"status\":\"success\""; then
        result_count=$(echo "$response" | grep -o "\"result\":\[" | wc -l)
        if [ "$result_count" -gt 0 ]; then
            print_result 0 "Metric '$metric_name' exists ($description)"
            return 0
        fi
    fi

    print_result 1 "Metric '$metric_name' not found ($description)"
    return 1
}

# Function to check if Prometheus target is up
check_prometheus_target() {
    local job_name=$1

    response=$(curl -s "http://localhost:9090/api/v1/targets" 2>/dev/null || echo "")

    if echo "$response" | grep -q "\"job\":\"$job_name\""; then
        if echo "$response" | grep -A5 "\"job\":\"$job_name\"" | grep -q "\"health\":\"up\""; then
            print_result 0 "Prometheus target '$job_name' is up"
            return 0
        else
            print_result 1 "Prometheus target '$job_name' is down"
            return 1
        fi
    else
        print_result 1 "Prometheus target '$job_name' not found in config"
        return 1
    fi
}

echo "======================================"
echo "Service Health Check Validation"
echo "======================================"

# Check Prometheus is accessible
echo -e "\n${YELLOW}=== Checking Prometheus Accessibility ===${NC}"
check_service_health "Prometheus" "http://localhost:9090/-/healthy"

# Check if Prometheus scrape configs are loaded
echo -e "\n${YELLOW}=== Checking Prometheus Scrape Targets ===${NC}"
check_prometheus_target "prometheus"
check_prometheus_target "postgres-exporter"
check_prometheus_target "grafana"
check_prometheus_target "loki"
check_prometheus_target "tempo"
check_prometheus_target "alertmanager"

# Check service health recording rules
echo -e "\n${YELLOW}=== Checking Service Health Recording Rules ===${NC}"
check_prometheus_metric "service_up" "Individual service health status"
check_prometheus_metric "service_availability_5m" "5-minute availability percentage"
check_prometheus_metric "service_availability_1h" "1-hour availability percentage"
check_prometheus_metric "service_availability_24h" "24-hour availability percentage"
check_prometheus_metric "service_availability_7d" "7-day availability percentage"
check_prometheus_metric "service_availability_30d" "30-day availability percentage"
check_prometheus_metric "service_healthy_count" "Count of healthy services"
check_prometheus_metric "service_unhealthy_count" "Count of unhealthy services"
check_prometheus_metric "service_total_count" "Total service count"
check_prometheus_metric "service_health_percentage" "Overall service health percentage"
check_prometheus_metric "service_sla_compliance" "SLA compliance indicator"
check_prometheus_metric "service_type_health" "Service type health aggregation"

# Check if recording rules are loaded
echo -e "\n${YELLOW}=== Checking Prometheus Recording Rules ===${NC}"
rules_response=$(curl -s "http://localhost:9090/api/v1/rules" 2>/dev/null || echo "")

if echo "$rules_response" | grep -q "service_health.rules"; then
    print_result 0 "Service health recording rules are loaded"
else
    print_result 1 "Service health recording rules are NOT loaded"
fi

# Check if Grafana dashboard exists
echo -e "\n${YELLOW}=== Checking Grafana Dashboard ===${NC}"

# Check if dashboard file exists
if [ -f "../grafana/dashboards/service_health.json" ]; then
    print_result 0 "Service Health dashboard file exists"

    # Validate dashboard JSON
    if command -v jq &> /dev/null; then
        if jq empty "../grafana/dashboards/service_health.json" 2>/dev/null; then
            print_result 0 "Service Health dashboard JSON is valid"
        else
            print_result 1 "Service Health dashboard JSON is invalid"
        fi

        # Check for required panels
        panel_count=$(jq '.panels | length' "../grafana/dashboards/service_health.json" 2>/dev/null || echo "0")
        if [ "$panel_count" -gt 0 ]; then
            print_result 0 "Service Health dashboard has $panel_count panels"
        else
            print_result 1 "Service Health dashboard has no panels"
        fi
    else
        echo -e "${YELLOW}⚠ jq not installed, skipping JSON validation${NC}"
    fi
else
    print_result 1 "Service Health dashboard file does NOT exist"
fi

# Check service labels in Prometheus config
echo -e "\n${YELLOW}=== Checking Prometheus Service Labels ===${NC}"

if [ -f "../prometheus/prom.yml" ]; then
    print_result 0 "Prometheus config file exists"

    # Check if service labels are present
    if grep -q "service:" "../prometheus/prom.yml"; then
        print_result 0 "Service labels are configured in Prometheus"
    else
        print_result 1 "Service labels are NOT configured in Prometheus"
    fi

    if grep -q "service_type:" "../prometheus/prom.yml"; then
        print_result 0 "Service type labels are configured in Prometheus"
    else
        print_result 1 "Service type labels are NOT configured in Prometheus"
    fi
else
    print_result 1 "Prometheus config file does NOT exist"
fi

# Summary
echo ""
echo "======================================"
echo "Test Summary"
echo "======================================"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo "======================================"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Please review the output above.${NC}"
    exit 1
fi
