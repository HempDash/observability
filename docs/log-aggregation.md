# Log Aggregation Setup

This document describes the log aggregation setup using Loki, Promtail, and Grafana in the observability stack.

## Overview

The log aggregation pipeline collects logs from all Docker containers, processes them with structured logging, and makes them queryable through Grafana dashboards. The setup includes:

- **Promtail**: Log collection agent that scrapes Docker container logs
- **Loki**: Log aggregation system for storage and querying
- **Grafana**: Visualization and exploration of logs
- **Alertmanager**: Alert routing and notification management
- **Structured Logging**: JSON-formatted logs with trace correlation

## Architecture

```
Docker Containers (with json-file driver)
    ↓
Promtail (scrapes container logs via Docker API)
    ↓
Loki (stores and indexes logs)
    ↓
Grafana (queries and visualizes logs)
    ↑
Loki Ruler (evaluates log-based alerts)
    ↓
Alertmanager (routes alerts to Slack/PagerDuty)
```

## Components

### Promtail Configuration

**Location**: `promtail/promtail.yml`

Promtail scrapes logs from:
1. **Docker containers**: All containers with `logging=promtail` label
2. **System logs**: `/var/log/*.log` files
3. **Application logs**: `/var/log/apps/**/*.log` files

**Key Features**:
- Automatic service discovery via Docker labels
- JSON log parsing for structured logs
- Log level extraction (ERROR, WARN, INFO, DEBUG)
- Trace ID correlation for distributed tracing
- Pipeline stages for log processing

**Labels Added**:
- `container_name`: Docker container name
- `container_id`: Docker container ID
- `image`: Container image
- `service`: Docker Compose service name
- `app`: Custom application label
- `environment`: Environment label (development, production, etc.)
- `level`: Log level (parsed from JSON)
- `trace_id`: Distributed trace ID (parsed from JSON)

### Docker Logging Configuration

All services are configured with:

```yaml
labels:
  logging: "promtail"
  app: "service-name"
  environment: "development"
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
    labels: "app,environment"
```

This ensures:
- Logs are in JSON format
- Log rotation (3 files × 10MB = 30MB max per service)
- Labels are included in log metadata
- Promtail can discover and scrape containers

### Loki Configuration

**Location**: `loki/loki.yml`

**Key Features**:
- 31-day log retention
- Local filesystem storage
- Built-in ruler for log-based alerting
- Integration with Alertmanager
- Rate limiting (10MB/s ingestion rate)

**Alerting Rules**: `loki/loki-rules.yml`

### Structured Logging

**Example Application**: `examples/api/logger.js`

The example API demonstrates best practices for structured logging:

```javascript
import { createLogger, transports, format } from 'winston';

const jsonFormat = format.combine(
  format.timestamp({ format: 'YYYY-MM-DDTHH:mm:ss.SSSZ' }),
  format.errors({ stack: true }),
  format.json()
);

logger.info('Request completed', {
  method: req.method,
  path: req.path,
  status: res.statusCode,
  duration_ms: duration,
  trace_id: traceId,
  span_id: spanId
});
```

**Structured Log Fields**:
- `timestamp`: ISO 8601 format
- `level`: Log level (info, warn, error)
- `message`: Human-readable message
- `service`: Service name
- `environment`: Environment
- `trace_id`: Distributed trace ID (for correlation with Tempo)
- `span_id`: Span ID within trace
- `duration_ms`: Request duration
- `method`, `path`, `status`: HTTP request metadata
- `error`, `stack`: Error details

## Log-Based Alerts

**Location**: `loki/loki-rules.yml`

### Alert Rules

1. **HighErrorRate** (Warning)
   - Triggers when error rate > 5% for 5 minutes
   - Severity: Warning
   - Team: Platform

2. **CriticalErrorRate** (Critical)
   - Triggers when error rate > 15% for 2 minutes
   - Severity: Critical
   - Team: Platform

3. **ApplicationErrorsDetected** (Warning)
   - Triggers when > 10 errors in 5 minutes
   - Severity: Warning
   - Team: Application

4. **NoLogsReceived** (Critical)
   - Triggers when no logs for 10 minutes
   - Severity: Critical
   - Team: Platform

5. **ServiceNotLogging** (Warning)
   - Triggers when specific service stops logging
   - Severity: Warning
   - Team: Platform

6. **HighLogVolume** (Warning)
   - Triggers when log rate > 100 lines/sec for 10 minutes
   - Severity: Warning
   - Team: Platform

7. **SlowRequestsDetected** (Warning)
   - Triggers when > 5 requests take > 3 seconds
   - Severity: Warning
   - Team: Application

8. **ExceptionInLogs** (Warning)
   - Triggers on exceptions/stack traces
   - Severity: Warning
   - Team: Application

9. **AuthenticationFailures** (Warning)
   - Triggers when > 10 auth failures in 5 minutes
   - Severity: Warning
   - Team: Security

10. **OutOfMemoryErrors** (Critical)
    - Triggers on OOM errors
    - Severity: Critical
    - Team: Platform

11. **DatabaseConnectionErrors** (Warning)
    - Triggers when > 5 DB connection errors in 5 minutes
    - Severity: Warning
    - Team: Platform

### Recording Rules

Pre-computed metrics for efficient querying:

- `log_messages:rate5m:by_app`: Log rate per service
- `log_errors:rate5m:by_app`: Error rate per service
- `log_warnings:rate5m:by_app`: Warning rate per service
- `log_error_ratio:rate5m:by_app`: Error ratio per service

## Grafana Dashboards

### 1. Logs Overview Dashboard

**Location**: `grafana/dashboards/logs_overview.json`

**Panels**:
- **All Logs Stream**: Real-time log viewer with JSON parsing
- **Log Volume by Service**: Time series chart showing logs per service
- **Log Volume by Level**: Time series chart showing logs by level (error, warn, info)
- **Error Logs**: Filtered view of error-level logs only
- **Error Count (5m)**: Stat panel showing recent errors
- **Warning Count (5m)**: Stat panel showing recent warnings
- **Total Log Count (5m)**: Stat panel showing total log volume
- **Logs by Service**: Pie chart distribution
- **Example API Logs**: Service-specific log viewer

**Queries**:
```logql
# All logs
{logging="promtail"} | json

# Error logs only
{logging="promtail"} | json | level =~ "error|ERROR"

# Log volume by service
sum by (app) (count_over_time({logging="promtail"} [$__auto]))

# Log volume by level
sum by (level) (count_over_time({logging="promtail"} | json | level != "" [$__auto]))
```

### 2. Trace to Logs Correlation Dashboard

**Location**: `grafana/dashboards/trace_to_logs.json`

**Panels**:
- **Logs by Trace ID**: Query logs by distributed trace ID
- **Recent Traces**: View traces from Tempo
- **Request Duration by Path**: Performance metrics from logs

**Key Feature**: Links traces from Tempo to logs in Loki using `trace_id` field.

**Query Example**:
```logql
{logging="promtail"} | json | trace_id =~ "$trace_id"
```

## Usage

### Starting the Stack

```bash
docker-compose up -d
```

This starts:
- Loki (port 3100)
- Promtail (port 9080)
- Grafana (port 3000)
- Alertmanager (port 9093)
- Example API (port 9091)
- Prometheus, Tempo

### Accessing Grafana

1. Open http://localhost:3000
2. Login: admin / yourpassword123
3. Navigate to Dashboards → Logs Overview

### Querying Logs

**LogQL Examples**:

```logql
# All logs from example_api
{app="example_api"}

# Error logs from any service
{logging="promtail"} | json | level = "error"

# Logs containing "timeout"
{logging="promtail"} |= "timeout"

# JSON parsed logs with specific trace_id
{app="example_api"} | json | trace_id = "abc123"

# Request duration > 1 second
{app="example_api"} | json | duration_ms > 1000

# Log rate by service
sum by (app) (rate({logging="promtail"}[5m]))

# Error ratio
sum(rate({logging="promtail"} | json | level="error" [5m]))
/
sum(rate({logging="promtail"}[5m]))
```

### Testing the Pipeline

1. **Generate logs**:
   ```bash
   # Normal request
   curl http://localhost:9091/hello?name=World

   # Slow request
   curl http://localhost:9091/slow?delay=2000

   # Error request
   curl http://localhost:9091/error
   ```

2. **View in Grafana**:
   - Navigate to Logs Overview dashboard
   - See logs appear in real-time
   - Check error count increases with `/error` endpoint

3. **Query by trace ID**:
   - Copy trace_id from logs
   - Use Trace to Logs dashboard
   - Enter trace_id to see all related logs

4. **Check Promtail status**:
   ```bash
   curl http://localhost:9080/ready
   ```

5. **Check Loki status**:
   ```bash
   curl http://localhost:3100/ready
   ```

### Adding Structured Logging to Your Application

**Node.js (Winston)**:

```javascript
import { createLogger, transports, format } from 'winston';
import LokiTransport from 'winston-loki';

const logger = createLogger({
  format: format.combine(
    format.timestamp(),
    format.errors({ stack: true }),
    format.json()
  ),
  defaultMeta: {
    service: 'my-service',
    environment: process.env.NODE_ENV
  },
  transports: [
    new LokiTransport({
      host: process.env.LOKI_URL,
      labels: { app: 'my-service' },
      json: true
    }),
    new transports.Console()
  ]
});

// Usage
logger.info('User logged in', {
  user_id: user.id,
  trace_id: traceId
});

logger.error('Database query failed', {
  error: error.message,
  stack: error.stack,
  query: sqlQuery
});
```

**Python (structlog)**:

```python
import structlog
import logging
from pythonjsonlogger import jsonlogger

# Configure JSON logging
logHandler = logging.StreamHandler()
formatter = jsonlogger.JsonFormatter()
logHandler.setFormatter(formatter)

logging.basicConfig(level=logging.INFO, handlers=[logHandler])
logger = structlog.get_logger()

# Usage
logger.info("user_logged_in", user_id=user.id, trace_id=trace_id)
logger.error("database_error", error=str(e), query=query)
```

**Go (zap)**:

```go
import "go.uber.org/zap"

logger, _ := zap.NewProduction()
defer logger.Sync()

// Usage
logger.Info("user logged in",
    zap.String("user_id", user.ID),
    zap.String("trace_id", traceID),
)

logger.Error("database query failed",
    zap.Error(err),
    zap.String("query", sqlQuery),
)
```

## Alertmanager Configuration

**Location**: `alertmanager/alertmanager.yml`

Configure notification channels:

```bash
# Set environment variables
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
export PAGERDUTY_SERVICE_KEY="your-pagerduty-key"

# Restart alertmanager
docker-compose restart alertmanager
```

**Notification Channels**:
- Critical alerts → PagerDuty + Slack (#alerts-critical)
- Warning alerts → Slack (#alerts-warnings)
- Platform alerts → Slack (#platform-alerts)

## Troubleshooting

### Promtail not collecting logs

1. Check Promtail is running:
   ```bash
   docker-compose ps promtail
   ```

2. Check Promtail logs:
   ```bash
   docker-compose logs promtail
   ```

3. Verify Docker socket access:
   ```bash
   docker-compose exec promtail ls -la /var/run/docker.sock
   ```

4. Check container labels:
   ```bash
   docker inspect <container> | grep logging
   ```

### Loki not receiving logs

1. Check Loki is running:
   ```bash
   curl http://localhost:3100/ready
   ```

2. Check Loki logs:
   ```bash
   docker-compose logs loki
   ```

3. Query Loki directly:
   ```bash
   curl -G -s "http://localhost:3100/loki/api/v1/query" \
     --data-urlencode 'query={logging="promtail"}' | jq
   ```

### Alerts not firing

1. Check Loki ruler status:
   ```bash
   curl http://localhost:3100/loki/api/v1/rules
   ```

2. Check Alertmanager status:
   ```bash
   curl http://localhost:9093/-/ready
   ```

3. View active alerts:
   ```bash
   curl http://localhost:9093/api/v1/alerts
   ```

### Grafana not showing logs

1. Check Loki datasource:
   - Grafana → Configuration → Data Sources → Loki
   - Test connection

2. Verify query syntax:
   - Use Explore view
   - Test simple query: `{logging="promtail"}`

3. Check time range:
   - Ensure time range includes when logs were generated

## Performance Tuning

### Promtail

- Adjust batch size in `promtail.yml`:
  ```yaml
  clients:
    - url: http://loki:3100/loki/api/v1/push
      batchwait: 1s
      batchsize: 1048576
  ```

### Loki

- Increase ingestion limits in `loki.yml`:
  ```yaml
  limits_config:
    ingestion_rate_mb: 20
    ingestion_burst_size_mb: 40
  ```

- Adjust retention:
  ```yaml
  limits_config:
    retention_period: 744h  # 31 days
  ```

### Docker Logging

- Adjust log rotation:
  ```yaml
  logging:
    options:
      max-size: "50m"
      max-file: "5"
  ```

## Security Considerations

1. **Log Sanitization**: Remove sensitive data before logging
   - Passwords, API keys, tokens
   - PII (email, phone, SSN)
   - Credit card numbers

2. **Access Control**:
   - Enable auth in Loki: `auth_enabled: true`
   - Use Grafana RBAC for dashboard access
   - Restrict Alertmanager access

3. **Network Security**:
   - Use internal Docker networks
   - Don't expose Loki/Promtail ports publicly
   - Use TLS for production deployments

4. **Log Retention**:
   - Set appropriate retention periods
   - Archive old logs to object storage
   - Implement log deletion policies

## Best Practices

1. **Structured Logging**:
   - Always use JSON format
   - Include timestamps in ISO 8601 format
   - Add trace IDs for distributed tracing
   - Include context (user_id, request_id, etc.)

2. **Log Levels**:
   - ERROR: Application errors requiring attention
   - WARN: Potential issues, degraded performance
   - INFO: Normal application behavior
   - DEBUG: Detailed diagnostic information

3. **Performance**:
   - Don't log in hot paths
   - Use sampling for high-volume logs
   - Avoid logging large objects
   - Use async logging

4. **Correlation**:
   - Always include trace_id for requests
   - Link logs to metrics and traces
   - Use consistent field names across services

5. **Alerting**:
   - Alert on symptoms, not causes
   - Set appropriate thresholds
   - Use severity levels correctly
   - Include actionable information in alerts

## References

- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Promtail Documentation](https://grafana.com/docs/loki/latest/clients/promtail/)
- [LogQL Documentation](https://grafana.com/docs/loki/latest/logql/)
- [Alertmanager Documentation](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [Winston Logger](https://github.com/winstonjs/winston)
- [Structlog](https://www.structlog.org/)
- [Zap Logger](https://github.com/uber-go/zap)
