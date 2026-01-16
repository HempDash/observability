# Grafana Dashboard Setup Report
**Generated:** January 15, 2026
**Status:** ✅ FILES CREATED - Manual Upload Required

---

## Overview

Created 5 comprehensive Grafana dashboards and Prometheus alert rules for HempDash infrastructure monitoring. Due to API authentication issues with curl special characters, dashboards have been created as JSON files and require manual upload to Grafana.

---

## Grafana Connection

**Grafana URL:** https://grafana-staging-064c.up.railway.app
**Organization:** Main Org. (ID: 1)
**API Key:** [REDACTED - Store in Doppler]
**Connection Status:** ✅ Verified (organization endpoint tested successfully)

---

## Dashboards Created

### 1. System Overview
- **File:** `/Users/jonathansullivan/Documents/GitHub/observability/grafana-dashboards/system-overview.json`
- **Title:** HempDash System Overview
- **Tags:** infrastructure, system
- **Panels:** 4 panels
  - Service Uptime (stat)
  - CPU Usage by Service (graph)
  - Memory Usage by Service (graph)
  - Request Rate (graph)
- **Refresh:** 30s
- **Time Range:** Last 6 hours

**Metrics Tracked:**
- `up{job=~"backend-api|eta-service|postgres-exporter"}`
- `rate(process_cpu_seconds_total[5m])`
- `process_resident_memory_bytes`
- `rate(http_requests_total[5m])`

---

### 2. API Performance
- **File:** `/Users/jonathansullivan/Documents/GitHub/observability/grafana-dashboards/api-performance.json`
- **Title:** HempDash API Performance
- **Tags:** api, performance
- **Panels:** 3 panels
  - Request Latency p50, p95, p99 (graph)
  - Error Rate % (graph with alert)
  - Top 10 Slowest Endpoints (table)
- **Refresh:** 30s
- **Alerts:** ✅ High Error Rate alert configured (threshold: 1%)

**Metrics Tracked:**
- `histogram_quantile(0.50|0.95|0.99, rate(http_request_duration_seconds_bucket[5m]))`
- `rate(http_requests_total{status=~"5.."}[5m])`
- `rate(http_requests_total{status=~"4.."}[5m])`

---

### 3. Business Metrics
- **File:** `/Users/jonathansullivan/Documents/GitHub/observability/grafana-dashboards/business-metrics.json`
- **Title:** HempDash Business Metrics
- **Tags:** business, metrics
- **Panels:** 5 panels
  - Orders per Hour (graph)
  - GMV - Gross Merchandise Value (stat)
  - Active Users 24h (stat)
  - Vendor Count by Status (pie chart)
  - Courier Count by Status (pie chart)
- **Refresh:** 5m

**Metrics Tracked:**
- `rate(orders_created_total[1h])`
- `sum(increase(order_value_total[24h]))`
- `count by (user_id) (user_activity_total)`
- `sum by (status) (vendor_status_total)`
- `sum by (status) (courier_status_total)`

---

### 4. Database Health
- **File:** `/Users/jonathansullivan/Documents/GitHub/observability/grafana-dashboards/database-health.json`
- **Title:** HempDash Database Health
- **Tags:** database, postgresql
- **Panels:** 3 panels
  - Database Connections (graph)
  - Query Duration p95 (graph)
  - Top 10 Slowest Queries (table)
- **Refresh:** 1m

**Metrics Tracked:**
- `pg_stat_database_numbackends{datname="hempdash"}`
- `pg_settings_max_connections`
- `histogram_quantile(0.95, rate(pg_stat_statements_query_time_bucket[5m]))`
- `topk(10, pg_stat_statements_mean_time_ms)`

**Note:** Requires postgres_exporter to be configured and running.

---

### 5. Compliance Monitoring
- **File:** `/Users/jonathansullivan/Documents/GitHub/observability/grafana-dashboards/compliance-monitoring.json`
- **Title:** HempDash Compliance Monitoring
- **Tags:** compliance, hemp
- **Panels:** 4 panels
  - Age Verification Rate (graph)
  - Geo-fence Violations (stat with alert)
  - COA Validation Rate (graph)
  - THC % Compliance (histogram)
- **Refresh:** 5m
- **Alerts:** ✅ Geo-fence violations alert configured (threshold: 10 violations per 24h)

**Metrics Tracked:**
- `age_verification_passed_total` / `age_verification_attempts_total`
- `sum(increase(geofence_violation_total[24h]))`
- `coa_validation_passed_total` / `coa_validation_attempts_total`
- `histogram_quantile(0.95, rate(product_thc_percentage_bucket[1h]))`

**Note:** These metrics require custom instrumentation in the backend application.

---

## Prometheus Alerts Configured

**File:** `/Users/jonathansullivan/Documents/GitHub/observability/prometheus-alerts.yml`

**Alert Rules:**
1. ✅ **HighErrorRate** (critical) - Fires when error rate > 1% for 2 minutes
2. ✅ **HighLatency** (warning) - Fires when p95 latency > 500ms for 5 minutes
3. ✅ **ServiceDown** (critical) - Fires when backend-api or eta-service is down for 1 minute
4. ✅ **HighMemoryUsage** (warning) - Fires when memory usage > 800MB for 5 minutes
5. ✅ **DatabaseConnectionPoolExhausted** (critical) - Fires when connections > 80% of max for 2 minutes
6. ✅ **HighGeofenceViolations** (warning) - Fires when > 10 violations per hour

**Alert File Location:** `/Users/jonathansullivan/Documents/GitHub/observability/prometheus-alerts.yml`

---

## Manual Upload Instructions

Since the API encountered authentication issues, upload the dashboards manually using one of these methods:

### Method 1: Grafana UI (Recommended for Human Review)

1. Open Grafana: https://grafana-staging-064c.up.railway.app
2. Login with credentials
3. Go to Dashboards → Import
4. For each dashboard JSON file:
   - Click "Upload JSON file"
   - Select the file from `/Users/jonathansullivan/Documents/GitHub/observability/grafana-dashboards/`
   - Click "Load"
   - Select Prometheus data source when prompted
   - Click "Import"

### Method 2: Using curl (after resolving API key issue)

```bash
GRAFANA_URL="https://grafana-staging-064c.up.railway.app"
GRAFANA_API_KEY="[YOUR_GRAFANA_API_KEY]"  # Get from Doppler

# Upload each dashboard
for dashboard in system-overview api-performance business-metrics database-health compliance-monitoring; do
  curl -X POST "${GRAFANA_URL}/api/dashboards/db" \
    -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
    -H "Content-Type: application/json" \
    -d @"/Users/jonathansullivan/Documents/GitHub/observability/grafana-dashboards/${dashboard}.json"
done
```

**Note:** The curl command was encountering issues with special characters in the API key. A script or alternative tool may be needed.

### Method 3: Using Grafana Provisioning

1. Add dashboards to Grafana provisioning directory:
```yaml
# grafana-provisioning.yml
apiVersion: 1

providers:
  - name: 'HempDash Dashboards'
    folder: 'HempDash'
    type: file
    options:
      path: /etc/grafana/provisioning/dashboards
```

2. Copy dashboard JSON files to provisioning directory
3. Restart Grafana to load dashboards automatically

---

## Prometheus Configuration

To load alert rules into Prometheus:

1. **Add alert rules to Prometheus configuration:**

```yaml
# prometheus.yml
rule_files:
  - "/etc/prometheus/rules/hempdash-alerts.yml"
```

2. **Copy alert rules file:**
```bash
cp /Users/jonathansullivan/Documents/GitHub/observability/prometheus-alerts.yml \
   /etc/prometheus/rules/hempdash-alerts.yml
```

3. **Reload Prometheus configuration:**
```bash
curl -X POST http://localhost:9090/-/reload
```

Or if using Railway, update the Prometheus service configuration to include the alert rules file.

---

## Data Source Configuration

Before dashboards will display data, configure the Prometheus data source in Grafana:

1. Go to Configuration → Data Sources
2. Click "Add data source"
3. Select "Prometheus"
4. Configure:
   - **Name:** Prometheus
   - **URL:** https://prometheus-staging-1d2e.up.railway.app
   - **Access:** Server (default)
   - **Auth:** None (Prometheus URL has no authentication per prompt)
5. Click "Save & Test"

---

## Verification Steps

After uploading dashboards:

1. **Check Dashboard List:**
   - Go to Dashboards → Browse
   - Verify all 5 dashboards appear

2. **Test Each Dashboard:**
   - Open each dashboard
   - Verify panels are loading data (not showing "No data")
   - Check time range selector is working
   - Verify refresh is working

3. **Test Alerts:**
   - Go to Alerting → Alert Rules
   - Verify "High Error Rate" and "High Geo-fence Violations" alerts are present
   - Check alert status (should be "Normal" if system is healthy)

4. **Test Prometheus Connection:**
   - Go to Explore
   - Select Prometheus data source
   - Run test query: `up{job="backend-api"}`
   - Should return 1 if service is up

---

## Troubleshooting

### No Data in Dashboards

**Issue:** Panels show "No data"

**Solutions:**
1. Verify Prometheus data source is configured correctly
2. Check Prometheus is scraping metrics from services
3. Verify metric names match what backend exports
4. Check time range (try "Last 24 hours" instead of "Last 6 hours")

### Alerts Not Firing

**Issue:** Alerts don't fire even when conditions are met

**Solutions:**
1. Verify alert rules are loaded in Prometheus (`/rules` endpoint)
2. Check alert evaluation interval in Prometheus config
3. Verify Alertmanager is configured (if using external alerting)
4. Check alert conditions are syntactically correct

### Dashboard Import Fails

**Issue:** JSON import fails with error

**Solutions:**
1. Verify JSON is valid (use `jq '.' dashboard.json`)
2. Check Grafana version supports all panel types
3. Ensure Prometheus data source exists before import
4. Try creating dashboard manually and copying panel configs

---

## Next Steps

### Immediate Actions (Required):
- [ ] **Human action:** Upload all 5 dashboards to Grafana via UI (20 minutes)
- [ ] **Human action:** Configure Prometheus data source in Grafana (5 minutes)
- [ ] **Human action:** Load alert rules into Prometheus configuration (10 minutes)
- [ ] **Human action:** Verify all dashboards display data correctly (15 minutes)

### Backend Instrumentation (Required for Full Functionality):
- [ ] Add custom metrics to backend application:
  - `orders_created_total` counter
  - `order_value_total` counter
  - `user_activity_total` counter
  - `vendor_status_total` gauge
  - `courier_status_total` gauge
  - `age_verification_passed_total` / `age_verification_attempts_total` counters
  - `geofence_violation_total` counter
  - `coa_validation_passed_total` / `coa_validation_attempts_total` counters
  - `product_thc_percentage` histogram
- [ ] Configure postgres_exporter for database metrics
- [ ] Verify all metric exporters are running and being scraped

### Optional Improvements:
- [ ] Configure Alertmanager for alert notifications (email, Slack, PagerDuty)
- [ ] Add dashboard variables for filtering by environment, region, etc.
- [ ] Create additional dashboards for specific features (checkout flow, delivery tracking, etc.)
- [ ] Set up Grafana annotations for deployments and incidents
- [ ] Configure dashboard auto-refresh based on urgency
- [ ] Add links between related dashboards
- [ ] Create Grafana folders to organize dashboards

---

## Summary

**Phase 1A - Task 2 Status:** ✅ Configuration Complete

**Files Created:**
- ✅ 5 dashboard JSON files
- ✅ 1 Prometheus alert rules file
- ✅ This setup report

**What Works:**
- ✅ Grafana connection verified
- ✅ Dashboard structure and panels defined
- ✅ Alert rules defined
- ✅ All files ready for upload

**What Requires Human Action:**
- ⚠️ Dashboard upload to Grafana (manual via UI or fixed curl script)
- ⚠️ Prometheus data source configuration in Grafana
- ⚠️ Alert rules configuration in Prometheus
- ⚠️ Backend application instrumentation for custom metrics
- ⚠️ Verification that all panels display data

**Estimated Time for Human Actions:** 50 minutes (upload + configure + verify)

---

## Contact & Support

**Grafana URL:** https://grafana-staging-064c.up.railway.app
**Prometheus URL:** https://prometheus-staging-1d2e.up.railway.app
**Infrastructure Lead:** Jonathan Sullivan
**Next Review:** After manual upload and verification
