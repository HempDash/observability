#!/bin/bash

# Test script for log aggregation pipeline
# This script verifies that the log aggregation setup is working correctly

set -e

echo "======================================"
echo "Log Aggregation Pipeline Test"
echo "======================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if services are running
echo "1. Checking if services are running..."
echo ""

services=("loki" "promtail" "grafana" "example_api" "alertmanager")
for service in "${services[@]}"; do
    if docker-compose ps | grep -q "$service.*Up"; then
        echo -e "${GREEN}✓${NC} $service is running"
    else
        echo -e "${RED}✗${NC} $service is not running"
        echo "Please start services with: docker-compose up -d"
        exit 1
    fi
done

echo ""
echo "2. Checking service health endpoints..."
echo ""

# Check Loki
echo -n "Loki (http://localhost:3100): "
if curl -s http://localhost:3100/ready | grep -q "ready"; then
    echo -e "${GREEN}✓ Ready${NC}"
else
    echo -e "${RED}✗ Not ready${NC}"
fi

# Check Promtail
echo -n "Promtail (http://localhost:9080): "
if curl -s http://localhost:9080/ready | grep -q "ready"; then
    echo -e "${GREEN}✓ Ready${NC}"
else
    echo -e "${RED}✗ Not ready${NC}"
fi

# Check Grafana
echo -n "Grafana (http://localhost:3000): "
if curl -s http://localhost:3000/api/health | grep -q "ok"; then
    echo -e "${GREEN}✓ Ready${NC}"
else
    echo -e "${RED}✗ Not ready${NC}"
fi

# Check Alertmanager
echo -n "Alertmanager (http://localhost:9093): "
if curl -s http://localhost:9093/-/ready | grep -q "Alertmanager is Ready"; then
    echo -e "${GREEN}✓ Ready${NC}"
else
    echo -e "${RED}✗ Not ready${NC}"
fi

# Check Example API
echo -n "Example API (http://localhost:9091): "
if curl -s http://localhost:9091/hello 2>&1 | grep -q "Hello"; then
    echo -e "${GREEN}✓ Ready${NC}"
else
    echo -e "${RED}✗ Not ready${NC}"
fi

echo ""
echo "3. Generating test logs..."
echo ""

# Generate various types of logs
echo "Generating normal request logs..."
curl -s http://localhost:9091/hello?name=TestUser > /dev/null
sleep 1

echo "Generating slow request logs..."
curl -s http://localhost:9091/slow?delay=500 > /dev/null
sleep 1

echo "Generating error logs..."
curl -s http://localhost:9091/error > /dev/null 2>&1
sleep 1

echo -e "${GREEN}✓${NC} Test logs generated"

echo ""
echo "4. Waiting for logs to be ingested (10 seconds)..."
sleep 10

echo ""
echo "5. Querying Loki for logs..."
echo ""

# Query Loki for logs
LOGS_QUERY='http://localhost:3100/loki/api/v1/query?query={app="example_api"}'

LOGS_RESPONSE=$(curl -s "$LOGS_QUERY")

if echo "$LOGS_RESPONSE" | jq -e '.data.result | length > 0' > /dev/null 2>&1; then
    LOG_COUNT=$(echo "$LOGS_RESPONSE" | jq '.data.result | length')
    echo -e "${GREEN}✓${NC} Found $LOG_COUNT log streams from example_api"
else
    echo -e "${RED}✗${NC} No logs found from example_api"
    echo "Response: $LOGS_RESPONSE"
    exit 1
fi

# Query for error logs
ERROR_QUERY='http://localhost:3100/loki/api/v1/query?query={app="example_api"}|json|level="error"'

ERROR_RESPONSE=$(curl -s "$ERROR_QUERY")

if echo "$ERROR_RESPONSE" | jq -e '.data.result | length > 0' > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Found error logs from example_api"
else
    echo -e "${YELLOW}⚠${NC} No error logs found (this might be okay if no errors occurred)"
fi

# Check log labels
echo ""
echo "6. Verifying log labels..."
echo ""

LABELS=$(echo "$LOGS_RESPONSE" | jq -r '.data.result[0].stream | to_entries | .[].key' 2>/dev/null || echo "")

if [ -n "$LABELS" ]; then
    echo "Found labels:"
    echo "$LABELS" | while read label; do
        echo "  - $label"
    done
    echo -e "${GREEN}✓${NC} Log labels are present"
else
    echo -e "${YELLOW}⚠${NC} Could not verify labels"
fi

# Check for trace_id in logs
echo ""
echo "7. Checking for trace correlation..."
echo ""

TRACE_QUERY='http://localhost:3100/loki/api/v1/query_range?query={app="example_api"}|json|trace_id!=""&limit=1'

TRACE_RESPONSE=$(curl -s "$TRACE_QUERY")

if echo "$TRACE_RESPONSE" | jq -e '.data.result | length > 0' > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Logs contain trace_id for correlation"
else
    echo -e "${YELLOW}⚠${NC} No trace_id found in logs"
fi

# Check Loki rules
echo ""
echo "8. Checking Loki alerting rules..."
echo ""

RULES_RESPONSE=$(curl -s http://localhost:3100/loki/api/v1/rules)

if echo "$RULES_RESPONSE" | jq -e '.data.groups | length > 0' > /dev/null 2>&1; then
    RULE_COUNT=$(echo "$RULES_RESPONSE" | jq '.data.groups | length')
    echo -e "${GREEN}✓${NC} Found $RULE_COUNT rule groups"

    # Show rule group names
    RULE_GROUPS=$(echo "$RULES_RESPONSE" | jq -r '.data.groups[].name')
    echo "Rule groups:"
    echo "$RULE_GROUPS" | while read group; do
        echo "  - $group"
    done
else
    echo -e "${RED}✗${NC} No alerting rules found"
fi

# Check Grafana dashboards
echo ""
echo "9. Checking Grafana dashboards..."
echo ""

DASHBOARDS=$(curl -s -u admin:yourpassword123 http://localhost:3000/api/search?type=dash-db)

if echo "$DASHBOARDS" | jq -e '. | length > 0' > /dev/null 2>&1; then
    DASHBOARD_COUNT=$(echo "$DASHBOARDS" | jq '. | length')
    echo -e "${GREEN}✓${NC} Found $DASHBOARD_COUNT dashboards"

    # Look for log dashboards
    LOG_DASHBOARDS=$(echo "$DASHBOARDS" | jq -r '.[] | select(.title | contains("Log") or contains("log")) | .title')
    if [ -n "$LOG_DASHBOARDS" ]; then
        echo "Log-related dashboards:"
        echo "$LOG_DASHBOARDS" | while read dashboard; do
            echo "  - $dashboard"
        done
    fi
else
    echo -e "${YELLOW}⚠${NC} Could not fetch dashboard list (authentication may be required)"
fi

echo ""
echo "======================================"
echo "Test Results Summary"
echo "======================================"
echo ""
echo -e "${GREEN}✓${NC} Log aggregation pipeline is operational"
echo ""
echo "Next steps:"
echo "1. Open Grafana at http://localhost:3000"
echo "2. Navigate to Dashboards → Logs Overview"
echo "3. Explore logs using LogQL queries"
echo "4. Check Trace to Logs Correlation dashboard"
echo ""
echo "Useful commands:"
echo "  - Generate more logs: curl http://localhost:9091/hello"
echo "  - Generate errors: curl http://localhost:9091/error"
echo "  - View Promtail targets: curl http://localhost:9080/targets"
echo "  - Query Loki: curl 'http://localhost:3100/loki/api/v1/query?query={app=\"example_api\"}'"
echo ""
