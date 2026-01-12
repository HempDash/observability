# Backend Service Instrumentation Guide

This guide covers how to instrument your backend service to work with the Prometheus metrics collection system.

## Overview

The Prometheus instance is configured to scrape metrics from the backend service at:
- **Target**: `backend:8000`
- **Metrics Path**: `/metrics`
- **Scrape Interval**: 15 seconds

## Backend Requirements

### 1. Expose Metrics Endpoint

Your backend service MUST expose a `/metrics` endpoint that returns metrics in Prometheus format.

For FastAPI applications, use the `prometheus-fastapi-instrumentator` library:

```python
from fastapi import FastAPI
from prometheus_fastapi_instrumentator import Instrumentator

app = FastAPI()

# Initialize and expose metrics
Instrumentator().instrument(app).expose(app)
```

### 2. Required Metrics

The backend should export the following metrics categories:

#### HTTP Request Metrics
- `http_requests_total` - Counter of total HTTP requests
  - Labels: `method`, `endpoint`, `status`
- `http_request_duration_seconds` - Histogram of request latency
  - Labels: `endpoint`, `method`

#### Database Metrics
- `db_query_duration_seconds` - Histogram of database query latency
  - Labels: `query_type`, `table`
- `db_connection_pool_size` - Gauge of active database connections
- `db_query_errors_total` - Counter of database query errors
  - Labels: `error_type`

#### Application Metrics
- `process_*` - Standard process metrics (CPU, memory, etc.)
- `python_*` - Python runtime metrics (GC, threads, etc.)

### 3. Custom Metrics Implementation

Add custom metrics to your backend:

```python
from prometheus_client import Counter, Histogram, Gauge

# Request metrics
http_requests_total = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

http_request_duration_seconds = Histogram(
    'http_request_duration_seconds',
    'HTTP request latency in seconds',
    ['endpoint', 'method']
)

# Database metrics
db_query_duration_seconds = Histogram(
    'db_query_duration_seconds',
    'Database query latency in seconds',
    ['query_type', 'table']
)

db_connection_pool_size = Gauge(
    'db_connection_pool_size',
    'Active database connections'
)

db_query_errors_total = Counter(
    'db_query_errors_total',
    'Total database query errors',
    ['error_type']
)
```

### 4. Middleware Integration

Add Prometheus middleware to your FastAPI application:

```python
from fastapi import FastAPI, Request
from prometheus_client import Counter, Histogram
import time

app = FastAPI()

# Initialize metrics
REQUEST_COUNT = Counter(
    'http_requests_total',
    'Total requests',
    ['method', 'endpoint', 'status']
)

REQUEST_LATENCY = Histogram(
    'http_request_duration_seconds',
    'Request latency',
    ['endpoint']
)

@app.middleware("http")
async def prometheus_middleware(request: Request, call_next):
    start_time = time.time()

    response = await call_next(request)

    duration = time.time() - start_time
    REQUEST_LATENCY.labels(endpoint=request.url.path).observe(duration)
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.url.path,
        status=response.status_code
    ).inc()

    return response
```

## Prometheus Configuration

The backend scrape job is configured in `prometheus/prom.yml`:

```yaml
scrape_configs:
  - job_name: 'backend-api'
    scrape_interval: 15s
    metrics_path: '/metrics'
    static_configs:
      - targets: ['backend:8000']
    metric_relabel_configs:
      # Keep all HTTP request metrics
      - source_labels: [__name__]
        regex: 'http_.*'
        action: keep
      # Keep all database metrics
      - source_labels: [__name__]
        regex: 'db_.*'
        action: keep
      # Keep all custom application metrics
      - source_labels: [__name__]
        regex: '(process_|python_).*'
        action: keep
```

## Verification

### 1. Check Metrics Endpoint

Verify your backend exposes metrics correctly:

```bash
curl http://backend:8000/metrics
```

Expected output:
```
# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="GET",endpoint="/api/health",status="200"} 42.0

# HELP http_request_duration_seconds HTTP request latency
# TYPE http_request_duration_seconds histogram
http_request_duration_seconds_bucket{endpoint="/api/health",le="0.005"} 10.0
...
```

### 2. Check Prometheus Targets

Access Prometheus UI at `http://localhost:9090/targets` and verify:
- Target `backend-api` shows as **UP**
- Last scrape successful
- No scrape errors

### 3. Query Metrics

In Prometheus UI, query for backend metrics:

```promql
# Request rate
rate(http_requests_total[5m])

# Request latency (95th percentile)
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Error rate
rate(http_requests_total{status=~"5.."}[5m])

# Database query latency
histogram_quantile(0.99, rate(db_query_duration_seconds_bucket[5m]))
```

## Troubleshooting

### Target Shows as DOWN

1. Check backend service is running: `docker ps | grep backend`
2. Verify backend exposes port 8000
3. Test metrics endpoint: `curl http://backend:8000/metrics`
4. Check Prometheus logs: `docker logs observability-prometheus-1`

### No Metrics Showing

1. Verify `/metrics` endpoint returns data
2. Check metric_relabel_configs aren't filtering out your metrics
3. Wait 15 seconds for next scrape interval
4. Check for scrape errors in Prometheus UI

### High Cardinality Warnings

If you see cardinality warnings:
1. Avoid using unbounded label values (user IDs, timestamps, etc.)
2. Limit label cardinality to < 100 unique values per label
3. Use histogram buckets instead of individual timing metrics

## Docker Compose Integration

To add the backend service to the observability stack, add to `docker-compose.yml`:

```yaml
services:
  backend:
    build:
      context: ../backend  # Path to your backend repository
      dockerfile: Dockerfile
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://user:pass@db:5432/dbname
      - PROMETHEUS_METRICS_ENABLED=true
    networks:
      - default

networks:
  default:
    name: observability_default
```

## Best Practices

1. **Use Standard Metric Names**: Follow Prometheus naming conventions
   - Use `_total` suffix for counters
   - Use `_seconds` suffix for durations
   - Use snake_case for metric names

2. **Keep Label Cardinality Low**: Avoid high-cardinality labels
   - DON'T: Use user IDs, request IDs, timestamps as labels
   - DO: Use status codes, endpoint patterns, error types

3. **Use Appropriate Metric Types**:
   - **Counter**: Monotonically increasing values (requests, errors)
   - **Gauge**: Values that can go up or down (connections, queue size)
   - **Histogram**: Distributions (latency, response size)

4. **Instrument Critical Paths**:
   - All HTTP endpoints
   - Database queries
   - External API calls
   - Background jobs
   - Cache operations

5. **Set Meaningful Histogram Buckets**:
   ```python
   REQUEST_LATENCY = Histogram(
       'http_request_duration_seconds',
       'Request latency',
       buckets=[0.01, 0.05, 0.1, 0.5, 1.0, 2.5, 5.0, 10.0]
   )
   ```

## Example Queries for Dashboards

### Request Rate by Endpoint
```promql
sum(rate(http_requests_total[5m])) by (endpoint)
```

### Error Rate Percentage
```promql
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) * 100
```

### P95 Latency
```promql
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, endpoint))
```

### Database Connection Pool Usage
```promql
db_connection_pool_size / db_connection_pool_max_size * 100
```

## References

- [Prometheus Python Client](https://github.com/prometheus/client_python)
- [Prometheus FastAPI Instrumentator](https://github.com/trallnag/prometheus-fastapi-instrumentator)
- [Prometheus Best Practices](https://prometheus.io/docs/practices/naming/)
- [Prometheus Metric Types](https://prometheus.io/docs/concepts/metric_types/)
