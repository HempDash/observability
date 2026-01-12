# Log Aggregation - Quick Reference

## Service URLs

| Service | URL | Purpose |
|---------|-----|---------|
| Grafana | http://localhost:3000 | Log dashboards (admin/yourpassword123) |
| Loki | http://localhost:3100 | Log storage and querying |
| Promtail | http://localhost:9080 | Log collection agent |
| Alertmanager | http://localhost:9093 | Alert routing |
| Example API | http://localhost:9091 | Test application |

## Quick Start

```bash
# Start the stack
docker-compose up -d

# Wait for services
sleep 30

# Run tests
./qa/test-log-aggregation.sh

# Generate test logs
curl http://localhost:9091/hello
curl http://localhost:9091/error
curl http://localhost:9091/slow?delay=2000
```

## Common LogQL Queries

```logql
# All logs from a service
{app="example_api"}

# Error logs only
{logging="promtail"} | json | level = "error"

# Search for text
{logging="promtail"} |= "timeout"

# Logs by trace ID
{app="example_api"} | json | trace_id = "your-trace-id"

# Slow requests (duration > 1s)
{app="example_api"} | json | duration_ms > 1000

# Log rate by service
sum by (app) (rate({logging="promtail"}[5m]))

# Error ratio
sum(rate({logging="promtail"} | json | level="error" [5m]))
/
sum(rate({logging="promtail"}[5m]))
```

## Key Files

| File | Purpose |
|------|---------|
| `promtail/promtail.yml` | Log collection configuration |
| `loki/loki.yml` | Log storage configuration |
| `loki/loki-rules.yml` | Log-based alert rules |
| `grafana/dashboards/logs_overview.json` | Main log dashboard |
| `grafana/dashboards/trace_to_logs.json` | Trace correlation |
| `examples/api/logger.js` | Structured logging example |

## Dashboards

1. **Logs Overview** (`http://localhost:3000`)
   - All Logs Stream
   - Log Volume by Service
   - Log Volume by Level
   - Error Logs
   - Stats (Error/Warning/Total counts)

2. **Trace to Logs Correlation**
   - Logs by Trace ID
   - Recent Traces
   - Request Duration

## Alert Rules

| Alert | Threshold | Severity |
|-------|-----------|----------|
| HighErrorRate | >5% errors for 5m | Warning |
| CriticalErrorRate | >15% errors for 2m | Critical |
| ApplicationErrorsDetected | >10 errors in 5m | Warning |
| NoLogsReceived | No logs for 10m | Critical |
| ServiceNotLogging | Service silent 10m | Warning |
| SlowRequestsDetected | >5 slow (>3s) in 5m | Warning |
| OutOfMemoryErrors | Any OOM error | Critical |
| DatabaseConnectionErrors | >5 DB errors in 5m | Warning |

## Troubleshooting

```bash
# Check service health
curl http://localhost:3100/ready  # Loki
curl http://localhost:9080/ready  # Promtail

# View logs
docker-compose logs loki
docker-compose logs promtail

# Query Loki directly
curl -G -s "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query={logging="promtail"}' | jq

# Check Promtail targets
curl http://localhost:9080/targets

# Check alert rules
curl http://localhost:3100/loki/api/v1/rules

# Check active alerts
curl http://localhost:9093/api/v1/alerts
```

## Structured Logging Format

```json
{
  "timestamp": "2026-01-12T00:30:00.123Z",
  "level": "info|warn|error",
  "message": "Description",
  "service": "service-name",
  "environment": "development",
  "trace_id": "abc123...",
  "span_id": "xyz789...",
  "duration_ms": 45,
  "method": "GET",
  "path": "/endpoint",
  "status": 200
}
```

## Adding Logging to Your Service

### 1. Add Docker labels

```yaml
labels:
  logging: "promtail"
  app: "your-service"
  environment: "development"
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
    labels: "app,environment"
```

### 2. Use structured logging (Node.js example)

```javascript
import { createLogger, format, transports } from 'winston';

const logger = createLogger({
  format: format.combine(
    format.timestamp(),
    format.json()
  ),
  transports: [new transports.Console()]
});

logger.info('Request processed', {
  user_id: 123,
  duration_ms: 45,
  trace_id: traceId
});
```

## Environment Variables

```bash
# Alertmanager
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK
PAGERDUTY_SERVICE_KEY=your-key

# Example API
LOKI_URL=http://loki:3100
```

## Performance Tips

- Use recording rules for common queries
- Sample high-volume logs
- Set appropriate retention (default: 31 days)
- Use label filters before line filters
- Limit query time ranges

## Documentation

- Full Guide: `docs/log-aggregation.md`
- Summary: `docs/TASK-12.3-LOG-AGGREGATION-SUMMARY.md`
- Test Script: `qa/test-log-aggregation.sh`
