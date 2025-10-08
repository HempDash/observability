# Observability Stack Operations Runbook

This runbook provides operational guidance for managing and troubleshooting the Grafana observability stack deployed on Railway, including Prometheus, Grafana, Loki, Tempo, and Alertmanager.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Service Health Checks](#service-health-checks)
3. [DB Replication Triage](#db-replication-triage)
4. [Common Issues](#common-issues)
5. [Alert Response Procedures](#alert-response-procedures)
6. [Maintenance Procedures](#maintenance-procedures)
7. [Recovery Procedures](#recovery-procedures)

---

## Architecture Overview

### Services

- **Grafana**: Visualization and dashboarding (Port: 3000)
- **Prometheus**: Metrics collection and alerting (Port: 9090)
- **Loki**: Log aggregation (Port: 3100)
- **Tempo**: Distributed tracing (Port: 3200, 4317 GRPC, 4318 HTTP)
- **Alertmanager**: Alert routing and notifications (Port: 9093)
- **PostgreSQL Exporter**: Database metrics exporter (Port: 9187)

### Data Flow

```
Application → Prometheus (scrape) → Grafana (visualize)
            → Loki (push logs)    → Grafana (query)
            → Tempo (push traces) → Grafana (query)

Prometheus → Alertmanager → PagerDuty/Slack
```

---

## Service Health Checks

### Prometheus

```bash
# Check Prometheus health
curl http://prometheus:9090/-/healthy

# Check targets status
curl http://prometheus:9090/api/v1/targets

# Check loaded rules
curl http://prometheus:9090/api/v1/rules
```

### Grafana

```bash
# Check Grafana health
curl http://grafana:3000/api/health

# Check datasources
curl -H "Authorization: Bearer $GRAFANA_API_KEY" \
  http://grafana:3000/api/datasources
```

### Alertmanager

```bash
# Check Alertmanager health
curl http://alertmanager:9093/-/healthy

# Check current alerts
curl http://alertmanager:9093/api/v1/alerts
```

### PostgreSQL Exporter

```bash
# Check exporter metrics endpoint
curl http://postgres-exporter:9187/metrics

# Verify postgres connection
curl http://postgres-exporter:9187/metrics | grep pg_up
```

---

## DB Replication Triage

### Symptoms

- Alert: **ReplicaNotStreaming**
- Alert: **ReplicaLagHigh**
- Alert: **ExporterDown**

### Quick Checks

1. **Verify Prometheus Target Status**
   ```bash
   # Check if postgres-exporter target is UP
   curl http://prometheus:9090/api/v1/targets | grep postgres-exporter
   ```

2. **Check Primary Database Replication Status**
   ```sql
   SELECT
     application_name,
     state,
     sync_state,
     write_lag,
     flush_lag,
     replay_lag
   FROM pg_stat_replication;
   ```

   **Expected Result**: At least one row with `state='streaming'`

3. **Check Replica Logs**
   ```bash
   # View repmgrd logs on replica for errors
   railway logs --service replica-db | grep -i error

   # Look for common issues:
   # - Authentication failures
   # - Network connectivity problems
   # - WAL segment not found
   ```

4. **Verify Network Reachability**
   ```bash
   # From replica, test connection to primary
   nc -zv primary-db 5432

   # Check DNS resolution
   nslookup primary-db
   ```

### Diagnostic Queries

#### On Primary Database

```sql
-- Check replication slots
SELECT slot_name, active, restart_lsn
FROM pg_replication_slots;

-- Check WAL sender processes
SELECT pid, state, sent_lsn, write_lsn, flush_lsn, replay_lsn
FROM pg_stat_replication;

-- Check current WAL position
SELECT pg_current_wal_lsn();
```

#### On Replica Database

```sql
-- Check if in recovery mode (should return 't')
SELECT pg_is_in_recovery();

-- Check replication lag
SELECT
  now() - pg_last_xact_replay_timestamp() AS replication_lag;

-- Check last received WAL position
SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn();
```

### Fix Patterns

#### ReplicaNotStreaming

**Cause**: Replica has stopped streaming from primary

**Resolution**:
1. Check replica connection parameters
   ```bash
   # Verify PRIMARY_* environment variables on replica
   railway variables --service replica-db | grep PRIMARY
   ```

2. Verify replication user credentials
   ```sql
   -- On primary: ensure replication user exists
   SELECT rolname, rolreplication FROM pg_roles WHERE rolreplication = true;
   ```

3. Check `pg_hba.conf` on primary
   ```
   # Ensure replication connection is allowed
   host replication replication_user replica-ip/32 md5
   ```

4. Restart replica if configuration was corrected
   ```bash
   railway restart --service replica-db
   ```

#### ReplicaLagHigh

**Cause**: Replica is streaming but falling behind

**Resolution**:
1. **Check for long-running transactions**
   ```sql
   -- On primary
   SELECT pid, usename, state, query_start, query
   FROM pg_stat_activity
   WHERE state != 'idle'
     AND query_start < now() - interval '5 minutes'
   ORDER BY query_start;
   ```

2. **Check autovacuum activity**
   ```sql
   -- On primary
   SELECT * FROM pg_stat_progress_vacuum;
   ```

3. **Verify WAL retention settings**
   ```sql
   -- On primary
   SHOW wal_keep_size;
   SHOW max_wal_senders;
   ```

4. **Check replica performance**
   ```sql
   -- On replica
   SELECT * FROM pg_stat_database WHERE datname = 'your_database';
   ```

5. **Network latency issues**
   ```bash
   # Test network latency between primary and replica
   ping -c 10 primary-db
   ```

   If latency is high (>50ms), consider:
   - Moving services to same region
   - Upgrading network tier on Railway

#### ExporterDown

**Cause**: postgres-exporter service is not responding

**Resolution**:
1. Check exporter service logs
   ```bash
   railway logs --service postgres-exporter | tail -50
   ```

2. Verify database connection from exporter
   ```bash
   # Check DATA_SOURCE_NAME environment variable
   railway variables --service postgres-exporter | grep DATA_SOURCE_NAME
   ```

3. Restart exporter service
   ```bash
   railway restart --service postgres-exporter
   ```

4. Verify Prometheus can reach exporter
   ```bash
   # From Prometheus service
   curl http://postgres-exporter:9187/metrics
   ```

### Escalation

If issues persist after following the above steps:

1. **Immediate Actions**:
   - Document current state (output of all diagnostic queries)
   - Take timestamp when issue began
   - Check recent deployments or configuration changes

2. **Contact**:
   - Platform team lead
   - Database administrator on-call
   - Railway support (if infrastructure issue)

3. **Communication**:
   - Post in `#platform-alerts` Slack channel
   - Create incident ticket with:
     - Timeline of events
     - Steps already taken
     - Current system state
     - Business impact

### Closure

1. Verify alerts have auto-resolved (check Prometheus/Alertmanager)
2. Confirm metrics are flowing normally for 15+ minutes
3. Document resolution in Ops notes
4. Conduct post-mortem if downtime exceeded SLA

---

## Common Issues

### Issue: Prometheus High Memory Usage

**Symptoms**: Prometheus service OOM, slow queries

**Resolution**:
```yaml
# Reduce retention period in prom.yml
storage:
  tsdb:
    retention.time: 7d  # Reduce from 15d
```

### Issue: Grafana Dashboard Not Loading

**Symptoms**: Dashboard shows "No data" or errors

**Resolution**:
1. Check datasource connectivity
2. Verify query syntax in dashboard JSON
3. Check Prometheus has data for time range selected

### Issue: Alertmanager Not Sending Notifications

**Symptoms**: Alerts firing in Prometheus but no PagerDuty/Slack messages

**Resolution**:
1. Verify Alertmanager configuration
2. Check webhook URLs and API keys
3. Test notification manually:
   ```bash
   amtool alert add alertname=test severity=critical
   ```

---

## Alert Response Procedures

### Critical Alerts (PagerDuty)

1. **Acknowledge** alert within 5 minutes
2. **Assess** severity and business impact
3. **Triage** using runbook procedures
4. **Communicate** status in Slack
5. **Resolve** or escalate within 30 minutes
6. **Document** resolution

### Warning Alerts (Slack only)

1. **Review** during business hours
2. **Investigate** if pattern emerges
3. **Create ticket** for tracking
4. **Address** in next sprint if non-urgent

---

## Maintenance Procedures

### Updating Prometheus Rules

```bash
# 1. Edit rules file
vim prometheus/rules/alerts.yml

# 2. Validate syntax
promtool check rules prometheus/rules/alerts.yml

# 3. Commit and push
git add prometheus/rules/alerts.yml
git commit -m "Update alert rules"
git push

# 4. Railway auto-deploys, verify rules loaded
curl http://prometheus:9090/api/v1/rules
```

### Adding New Scrape Targets

```yaml
# In prometheus/prom.yml
scrape_configs:
  - job_name: 'new-service'
    scrape_interval: 30s
    static_configs:
      - targets: ['new-service:9090']
```

### Updating Grafana Dashboards

1. Export dashboard JSON from Grafana UI
2. Save to `grafana/dashboards/`
3. Commit and push to Git
4. Dashboard auto-loads via provisioning

---

## Recovery Procedures

### Prometheus Data Loss

```bash
# If Prometheus volume is lost, data is unrecoverable
# Prometheus will start fresh and begin collecting new data
# Historical data is lost - ensure regular backups if needed
```

### Grafana Configuration Loss

```bash
# Dashboards in Git are automatically re-provisioned
# User-created dashboards not in Git will be lost
# Recommendation: Export important dashboards to Git regularly
```

### Complete Stack Restart

```bash
# Restart all services in order
railway restart --service prometheus
railway restart --service alertmanager
railway restart --service loki
railway restart --service tempo
railway restart --service grafana
```

---

## Additional Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Alertmanager Documentation](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [PostgreSQL Replication Documentation](https://www.postgresql.org/docs/current/warm-standby.html)
- [Railway Documentation](https://docs.railway.app/)

---

## Changelog

| Date | Change | Author |
|------|--------|--------|
| 2025-10-08 | Initial runbook creation with DB-HA triage section | Platform Team |
