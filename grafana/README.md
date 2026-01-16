# Grafana Dashboards for HempDash

This directory contains Grafana dashboard definitions and alert rules for monitoring the HempDash platform.

## Dashboards

### Checkr Invitation Metrics (`dashboards/checkr-invitation-dashboard.json`)

Comprehensive dashboard for monitoring the Checkr background check invitation lifecycle.

**Panels**:
- Overview: Invitations created today, completion rate, pending count, expired today
- Funnel: 7-day invitation funnel visualization (created → completed/expired)
- Trends: Creation rate time series, completion duration percentiles
- Errors: Error rate tracking, rate limit hits

**Metrics Used**:
- `invitation_created_total{status}`
- `invitation_completed_total`
- `invitation_expired_total`
- `invitation_resend_total{status}`
- `invitation_completion_duration_seconds_bucket`
- `invitation_pending_count`
- `invitation_completion_rate`

## Alert Rules

### Checkr Invitation Alerts (`alerts/checkr-invitation-alerts.yml`)

**6 Alert Rules**:

1. **HighExpirationRate** (Warning)
   - Trigger: >20% expiration rate in last hour
   - Duration: 1 hour
   - Action: Review driver communication and UX

2. **LowCompletionRate** (Warning)
   - Trigger: 7-day completion rate <60%
   - Duration: 2 hours
   - Action: Check email deliverability, driver engagement

3. **InvitationAPIErrors** (Critical)
   - Trigger: >5% error rate
   - Duration: 10 minutes
   - Action: Check Checkr API status, investigate backend logs

4. **StaleInvitations** (Info)
   - Trigger: >100 pending invitations for 24h
   - Duration: 24 hours
   - Action: Send reminder emails

5. **RateLimitSpike** (Warning)
   - Trigger: >20 rate limit hits in 1 hour
   - Duration: 15 minutes
   - Action: Investigate driver resend patterns

6. **SlowCompletionTimes** (Info)
   - Trigger: p95 >5 days (432000 seconds)
   - Duration: 6 hours
   - Action: Review UX friction points

## Setup Instructions

### 1. Configure Prometheus Data Source

```bash
# In Grafana UI:
# Configuration > Data Sources > Add data source > Prometheus
# URL: http://prometheus:9090 (or your Prometheus endpoint)
# Save & Test
```

### 2. Import Dashboard

**Option A: Via UI**
1. Navigate to Dashboards > Import
2. Upload `dashboards/checkr-invitation-dashboard.json`
3. Select Prometheus data source
4. Click Import

**Option B: Via API**
```bash
curl -X POST http://localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <GRAFANA_API_KEY>" \
  -d @dashboards/checkr-invitation-dashboard.json
```

**Option C: Provisioning (Recommended for Production)**
```yaml
# /etc/grafana/provisioning/dashboards/hempdash.yml
apiVersion: 1
providers:
  - name: 'HempDash Dashboards'
    folder: 'HempDash'
    type: file
    options:
      path: /etc/grafana/dashboards/hempdash
```

Copy dashboard JSON to `/etc/grafana/dashboards/hempdash/`

### 3. Configure Alert Rules

**Option A: Via Grafana UI**
1. Alerting > Alert rules > Import
2. Upload `alerts/checkr-invitation-alerts.yml`

**Option B: Via Provisioning**
```yaml
# /etc/grafana/provisioning/alerting/hempdash-alerts.yml
apiVersion: 1
groups:
  - orgId: 1
    name: Checkr Invitations
    folder: HempDash
    interval: 5m
    rules:
      # Paste rules from alerts/checkr-invitation-alerts.yml
```

**Option C: Via API**
```bash
# Convert YAML to JSON first
yq eval -o=json alerts/checkr-invitation-alerts.yml > /tmp/alerts.json

# Import via API
curl -X POST http://localhost:3000/api/v1/provisioning/alert-rules \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <GRAFANA_API_KEY>" \
  -d @/tmp/alerts.json
```

### 4. Configure Alert Notifications

Set up notification channels for alerts:

**Mattermost Integration**:
```bash
# In Grafana UI:
# Alerting > Contact points > Add contact point
# Type: Webhook
# URL: https://mattermost.gethempdash.com/hooks/<WEBHOOK_ID>
# HTTP Method: POST
```

**Email Notifications**:
```bash
# In Grafana UI:
# Alerting > Contact points > Add contact point
# Type: Email
# Addresses: ops@gethempdash.com, engineering@gethempdash.com
```

## Dashboard Access

- **URL**: https://grafana.gethempdash.com/d/checkr-invitations
- **Refresh**: 30 seconds (auto-refresh)
- **Time Range**: Last 7 days (default)

## Metrics Queries Reference

### Completion Rate
```promql
(invitation_completed_total / invitation_created_total{status="success"}) * 100
```

### Expiration Rate
```promql
(invitation_expired_total / invitation_created_total{status="success"}) * 100
```

### Average Completion Time
```promql
rate(invitation_completion_duration_seconds_sum[1h])
/
rate(invitation_completion_duration_seconds_count[1h])
```

### Invitations Per Minute
```promql
rate(invitation_created_total{status="success"}[5m]) * 60
```

### Error Rate
```promql
rate(invitation_created_total{status="error"}[5m])
```

## Troubleshooting

### Dashboard shows "No Data"
- Verify Prometheus is scraping backend `/metrics` endpoint
- Check Prometheus targets: http://prometheus:9090/targets
- Ensure backend metrics are being collected: `curl http://backend:8000/metrics | grep invitation`

### Alerts not firing
- Check alert rule syntax in Grafana UI
- Verify Prometheus query returns data
- Check alert evaluation interval (5 minutes default)
- Review Grafana logs: `docker logs grafana`

### Metrics seem incorrect
- Verify Prometheus scrape interval matches dashboard refresh
- Check for metric resets (counter resets after pod restarts)
- Use `increase()` for counters over time ranges
- Use `rate()` for per-second rates

## Production Deployment Checklist

- [ ] Prometheus configured to scrape backend `/metrics`
- [ ] Grafana data source added and tested
- [ ] Dashboard imported successfully
- [ ] Alert rules configured
- [ ] Notification channels tested
- [ ] Alert routing policies configured
- [ ] Dashboard URL added to runbooks
- [ ] Team trained on dashboard usage
- [ ] SLIs/SLOs documented
- [ ] Retention policy configured (30 days recommended)

## SLIs & SLOs

**Service Level Indicators**:
- Invitation completion rate (7-day rolling)
- Invitation expiration rate
- API error rate
- Average completion duration (p50, p95, p99)

**Service Level Objectives**:
- Completion rate: >80%
- Expiration rate: <10%
- API error rate: <1%
- p95 completion time: <3 days

## Related Documentation

- [Prometheus Metrics Guide](../prometheus/README.md)
- [Checkr Integration Runbook](../../docs/runbooks/checkr-integration.md)
- [Alert Response Procedures](../../docs/runbooks/alert-response.md)
- [Phase 4A Metrics Summary](../../../PHASE_4A_METRICS_SUMMARY.md)
