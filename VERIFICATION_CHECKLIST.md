# Task 12.1 Verification Checklist

## Backend Service Instrumentation - Acceptance Criteria

Use this checklist to verify that Task 12.1 has been completed successfully.

### ✅ Configuration Changes

- [x] **Backend scrape target added to Prometheus config**
  - File: `prometheus/prom.yml` line 19-23
  - Job name: `backend-api`
  - Target: `backend:8000`
  - Metrics path: `/metrics`
  - Scrape interval: 15s

### 🔧 Backend Service Requirements

The following must be implemented in the backend service:

- [ ] **Prometheus middleware added to FastAPI**
  - Use `prometheus-fastapi-instrumentator` package
  - Middleware should instrument all HTTP requests

- [ ] **Metrics endpoint exposed**
  - Endpoint: `http://backend:8000/metrics`
  - Format: Prometheus text format
  - Returns metrics on GET request

### 📊 Required Metrics

Verify the following metrics are being exported:

#### HTTP Metrics
- [ ] **Request latency histogram**: `http_request_duration_seconds`
  - Type: Histogram
  - Labels: `endpoint`, `method`
  - Buckets: Appropriate latency buckets (e.g., 0.01, 0.05, 0.1, 0.5, 1.0, 2.5, 5.0, 10.0)

- [ ] **Request count**: `http_requests_total`
  - Type: Counter
  - Labels: `method`, `endpoint`, `status`
  - Increments on each request

- [ ] **Error rate by endpoint**: `http_requests_total{status=~"5.."}`
  - Derived from `http_requests_total` counter
  - Filter by 5xx status codes

#### Database Metrics
- [ ] **Database query metrics**: `db_query_duration_seconds` or similar
  - Type: Histogram
  - Labels: `query_type`, `table` (or similar)
  - Tracks database query latency

- [ ] **Database connection pool**: `db_connection_pool_size` or similar
  - Type: Gauge
  - Tracks active database connections

- [ ] **Database errors**: `db_query_errors_total` or similar
  - Type: Counter
  - Labels: `error_type`
  - Increments on database errors

#### System Metrics
- [ ] **Process metrics**: `process_*`
  - Standard metrics: CPU, memory, file descriptors
  - Automatically exported by prometheus_client

- [ ] **Python runtime metrics**: `python_*`
  - GC stats, thread count, etc.
  - Automatically exported by prometheus_client

### 🔍 Verification Steps

#### 1. Backend Metrics Endpoint
```bash
# Test the backend metrics endpoint
curl http://backend:8000/metrics

# Expected: Prometheus-format metrics output
# Should see metrics like:
# - http_requests_total
# - http_request_duration_seconds
# - db_query_duration_seconds
# - process_cpu_seconds_total
# - python_info
```

- [ ] Endpoint returns 200 OK
- [ ] Response is in Prometheus text format
- [ ] Contains HTTP metrics
- [ ] Contains database metrics
- [ ] Contains process/runtime metrics

#### 2. Prometheus Targets
```bash
# Access Prometheus UI
open http://localhost:9090/targets

# Check target status
```

- [ ] Target `backend-api` appears in list
- [ ] Status shows **UP** (not DOWN)
- [ ] Last scrape successful (no errors)
- [ ] Labels show correct job and instance

#### 3. Query Metrics in Prometheus UI
```bash
# Access Prometheus UI
open http://localhost:9090/graph
```

Test the following queries:

- [ ] **Request rate**:
  ```promql
  rate(http_requests_total[5m])
  ```
  Should return data points

- [ ] **P95 latency**:
  ```promql
  histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
  ```
  Should return latency values

- [ ] **Error rate**:
  ```promql
  rate(http_requests_total{status=~"5.."}[5m])
  ```
  Should return error rate (may be 0 if no errors)

- [ ] **Request count by endpoint**:
  ```promql
  sum(rate(http_requests_total[5m])) by (endpoint)
  ```
  Should show breakdown by endpoint

- [ ] **Database query latency**:
  ```promql
  histogram_quantile(0.99, rate(db_query_duration_seconds_bucket[5m]))
  ```
  Should return database query latency

#### 4. Generate Load and Verify
```bash
# Generate some traffic to the backend
for i in {1..100}; do
  curl http://backend:8000/api/health
done

# Wait 15 seconds for scrape
sleep 15

# Check metrics updated in Prometheus
```

- [ ] Metrics update after scrape interval
- [ ] Request counts increase
- [ ] Latency histograms show data
- [ ] Metrics are tagged with correct labels

### 📚 Documentation

- [x] **Backend instrumentation guide created**
  - File: `docs/BACKEND_INSTRUMENTATION.md`
  - Contains implementation examples
  - Includes verification steps
  - Lists required metrics

- [x] **README updated**
  - Added Prometheus metrics section
  - Links to instrumentation guide
  - Lists pre-configured scrape targets

### 🚀 Deployment

After verification, deploy changes:

```bash
# Commit changes
git add prometheus/prom.yml docs/BACKEND_INSTRUMENTATION.md README.md
git commit -m "feat: add backend-api scrape target to Prometheus

- Add backend-api job to scrape backend:8000/metrics
- Create comprehensive backend instrumentation guide
- Update README with Prometheus metrics section
- Document required metrics and verification steps

Resolves Task 12.1: Backend Service Instrumentation"

# Push to trigger deployment
git push
```

- [ ] Changes committed to git
- [ ] Pushed to repository
- [ ] Prometheus service restarted/reloaded
- [ ] Backend service deployed with metrics endpoint
- [ ] Verified in production environment

### ⚠️ Common Issues

#### Backend target shows DOWN
- Check backend service is running
- Verify backend exposes port 8000
- Test `curl http://backend:8000/metrics` from Prometheus container
- Check firewall/network policies

#### No metrics showing in Prometheus
- Verify `/metrics` endpoint returns data
- Check backend has prometheus-fastapi-instrumentator installed
- Wait for scrape interval (15 seconds)
- Check Prometheus logs for scrape errors

#### Metrics exist but queries return no data
- Verify metric names match exactly (case-sensitive)
- Check label names and values
- Ensure sufficient data collected (wait a few scrapes)
- Try simpler queries first (e.g., just `http_requests_total`)

### 📝 Notes

- The backend service code is not in this repository
- The backend must be separately deployed and configured
- This task only configures Prometheus to scrape the backend
- Backend instrumentation must be done in the backend repository
- See `docs/BACKEND_INSTRUMENTATION.md` for backend implementation details

### 🎯 Success Criteria Met

All acceptance criteria from Task 12.1:

- [x] Add backend scrape target to Prometheus config ✅
- [ ] Add Prometheus middleware to FastAPI (backend repo)
- [ ] Export request latency histogram (backend repo)
- [ ] Export request count by endpoint (backend repo)
- [ ] Export error rate by endpoint (backend repo)
- [ ] Export database query metrics (backend repo)
- [ ] Verify metrics in Prometheus UI (after backend deployment)

**Note**: Items marked "(backend repo)" must be implemented in the backend service repository, not in this observability repository.
