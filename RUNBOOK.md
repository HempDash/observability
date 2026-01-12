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
8. [Backups & Restore (Stage 7)](#backups--restore-stage-7)
9. [Failover Drill (Stage 7)](#failover-drill-stage-7)
10. [Security & Access Review (Stage 8)](#security--access-review-stage-8)
11. [Meta-Monitoring (Task 12.6)](#meta-monitoring-task-126)

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

## Backups & Restore (Stage 7)

### Backup Schedule

**Schedule**: Daily backups enabled in Railway with 7–14 day retention, scheduled during off-peak hours (typically 2-4 AM UTC).

**Retention Policy**: 14 days (adjust based on compliance and storage requirements).

### Manual Backup Procedure

To create a manual backup outside the automated schedule:

1. **Via Railway Dashboard**:
   ```
   Railway → Primary Postgres Service → Backups Tab → Create Backup
   ```

2. **Record Backup Metadata**:
   After backup completes, document in operations log:
   - Timestamp: `YYYY-MM-DD HH:MM:SS UTC`
   - Backup size: `XXX MB/GB`
   - Checksum/ID: (if available from Railway)
   - Reason: (scheduled, pre-migration, incident response, etc.)

3. **Via CLI** (if direct database access):
   ```bash
   # Create timestamped backup
   BACKUP_FILE="backup_$(date +%Y%m%d_%H%M%S).sql"
   pg_dump "$DATABASE_URL" > "$BACKUP_FILE"

   # Verify backup integrity
   psql "$DATABASE_URL" -c "SELECT 'Backup source verified' AS status"

   # Calculate checksum
   shasum -a 256 "$BACKUP_FILE"
   ```

### Restore Procedure

**Use Case**: Restore to scratch environment, staging, or disaster recovery.

#### Restore from Railway Backup

1. **Create Target Database**:
   ```
   Railway → New Service → Add PostgreSQL
   ```

2. **Restore from Backup**:
   ```
   Railway → New Postgres Service → Backups → Select Backup → Restore
   ```

3. **Verify Restoration**:
   ```bash
   # Connect to restored database
   railway connect postgres-restored

   # Verify schema
   \dt

   # Check migration version
   SELECT * FROM alembic_version;
   ```

#### Restore from SQL Dump

1. **Create Empty Database**:
   ```bash
   createdb hempdash_restore
   ```

2. **Restore from File**:
   ```bash
   # Restore backup
   psql "$RESTORE_DATABASE_URL" < backup_YYYYMMDD_HHMMSS.sql
   ```

3. **Validate Restoration**:
   ```sql
   -- Connect to restored database
   psql "$RESTORE_DATABASE_URL"

   -- List all tables
   \dt

   -- Verify migration state
   SELECT * FROM alembic_version;

   -- Run smoke query (example)
   SELECT COUNT(*) FROM users WHERE created_at > NOW() - INTERVAL '7 days';
   SELECT COUNT(*) FROM orders WHERE status = 'completed';
   ```

4. **Run QA Tests**:
   ```bash
   cd qa
   export TEST_DB_URL="$RESTORE_DATABASE_URL"
   make test-backup-restore
   ```

### Disaster Recovery Objectives

**RTO (Recovery Time Objective)**: ≤ 60 seconds for primary database restart.

**RPO (Recovery Point Objective)**: ≤ 15 minutes (based on backup frequency and WAL archiving).

**Data Retention**: 14 days for automated backups; critical backups archived separately for 90 days.

### Backup Verification

**Monthly Verification**:
1. Select random backup from previous month
2. Restore to test environment
3. Run QA validation suite
4. Document results in operations log

---

## Failover Drill (Stage 7)

### Objective

Measure and verify the Recovery Time Objective (RTO) when the primary database is restarted or fails over to replica.

### Prerequisites

1. **Health Checks Active**: Ensure synthetics monitoring or k6 health checks are running
2. **Monitoring Ready**: Grafana dashboards and Prometheus alerts active
3. **Communication**: Notify team that drill is in progress
4. **Replica Healthy**: Verify replica is streaming and lag < 1s

### Drill Procedure

#### Step 1: Pre-Drill Verification

```bash
# Verify primary is healthy
railway status --service primary-db

# Check replication status
psql "$PRIMARY_DATABASE_URL" -c "SELECT * FROM pg_stat_replication;"

# Verify replica lag
curl http://prometheus:9090/api/v1/query?query=pg_stat_replication_write_lag

# Baseline health check
curl https://your-app.railway.app/health/ready
```

#### Step 2: Execute Failover

**Manual Restart Drill**:
```bash
# Record start time
START_TIME=$(date +%s)
echo "Drill started at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"

# Restart primary database
railway restart --service primary-db

# Monitor health endpoint
while true; do
  if curl -s https://your-app.railway.app/health/ready | grep -q "ok"; then
    END_TIME=$(date +%s)
    RTO=$((END_TIME - START_TIME))
    echo "Service recovered at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo "RTO: ${RTO} seconds"
    break
  fi
  sleep 1
done
```

**Automated Failover** (with repmgr):
```bash
# Promote replica to primary
repmgr standby promote -f /etc/repmgr.conf --log-level INFO

# Update application connection strings
# (typically handled by connection pooler or DNS)
```

#### Step 3: Post-Drill Verification

```bash
# Verify primary is back online
railway status --service primary-db

# Check replication resumed
psql "$PRIMARY_DATABASE_URL" -c "SELECT * FROM pg_stat_replication;"

# Verify no data loss
psql "$PRIMARY_DATABASE_URL" -c "SELECT COUNT(*) FROM critical_table;"

# Check Prometheus alerts (should auto-resolve)
curl http://prometheus:9090/api/v1/alerts | grep -i replica
```

### Drill Results Template

Document results in operations log:

```markdown
## Failover Drill - [DATE]

**Drill Type**: Manual Restart / Automated Failover / Simulated Crash

**Participants**: [Team members]

**Timeline**:
- Start Time: YYYY-MM-DD HH:MM:SS UTC
- Failure Detected: YYYY-MM-DD HH:MM:SS UTC (+Xs)
- Failover Initiated: YYYY-MM-DD HH:MM:SS UTC (+Xs)
- Service Recovered: YYYY-MM-DD HH:MM:SS UTC (+Xs)
- Full Recovery: YYYY-MM-DD HH:MM:SS UTC (+Xs)

**Metrics**:
- RTO Measured: XX seconds
- RTO Target: ≤ 60 seconds
- Data Loss: None / XX transactions
- Alert Latency: XX seconds

**Observations**:
- [What went well]
- [What needs improvement]
- [Unexpected behaviors]

**Action Items**:
- [ ] Item 1
- [ ] Item 2
```

### Drill Frequency

- **Planned Drills**: Quarterly (every 3 months)
- **Unannounced Drills**: Bi-annually (every 6 months)
- **Post-Incident Drills**: After any production database incident

---

## Security & Access Review (Stage 8)

### Database Roles & Permissions

**Principle**: Least privilege access for all database users.

#### Application User
- **Role**: `app_user`
- **Privileges**:
  - `SELECT`, `INSERT`, `UPDATE`, `DELETE` on application tables
  - `EXECUTE` on application functions
  - **NO** superuser, replication, or DDL rights
- **Verification**:
  ```sql
  SELECT rolname, rolsuper, rolreplication, rolcreaterole, rolcreatedb
  FROM pg_roles
  WHERE rolname = 'app_user';
  ```

#### Replication User
- **Role**: `replication_user`
- **Privileges**:
  - `REPLICATION` privilege only
  - Minimal table access (pg_stat_replication only)
- **Verification**:
  ```sql
  SELECT rolname, rolreplication
  FROM pg_roles
  WHERE rolname = 'replication_user';
  ```

#### Admin User
- **Role**: `admin_user` (for migrations and schema changes only)
- **Usage**: CI/CD pipelines, schema migrations
- **Restrictions**: Not used by application runtime

### Secrets Management

**Policy**: All credentials stored in Railway Secrets or GitHub Secrets. **Never** commit secrets to Git.

**Rotation Schedule**: Every 90 days for all production credentials.

**Secrets Inventory**: See [`docs/security/secrets.md`](../docs/security/secrets.md) for full inventory and rotation tracking.

#### Key Secrets

| Secret | Location | Rotation Frequency |
|--------|----------|-------------------|
| `POSTGRES_PASSWORD` | Railway Secrets | 90 days |
| `PGPASSWORD` | Railway Secrets | 90 days |
| `REPMGR_USER_PWD` | Railway Secrets (Primary only) | 90 days |
| `SLACK_WEBHOOK_URL` | Railway Secrets (Alertmanager) | 180 days |
| `PAGERDUTY_SERVICE_KEY` | Railway Secrets (Alertmanager) | 180 days |
| `GRAFANA_ADMIN_PASSWORD` | Railway Secrets | 90 days |

#### Rotation Procedure

```bash
# 1. Generate new password
NEW_PASSWORD=$(openssl rand -base64 32)

# 2. Update in Railway
railway variables --set POSTGRES_PASSWORD="$NEW_PASSWORD"

# 3. Update application config (if needed)
# Update any downstream services that use this credential

# 4. Verify connectivity
psql "postgresql://app_user:$NEW_PASSWORD@primary-db:5432/hempdash" -c "SELECT 1;"

# 5. Document rotation
# Update docs/security/secrets.md with new rotation date

# 6. Revoke old credentials (if applicable)
# For database users:
psql -c "ALTER USER app_user WITH PASSWORD '$NEW_PASSWORD';"
```

### Network & TLS Security

**TLS Enforcement**: All database connections require SSL/TLS.

```bash
# Verify sslmode in connection strings
railway variables | grep DATABASE_URL
# Should contain: sslmode=require

# Test connection with SSL verification
psql "$DATABASE_URL?sslmode=require" -c "SELECT version();"
```

**Network Isolation**:
- Internal services use Railway private networking
- Public access minimized to only necessary endpoints
- Database ports not exposed publicly
- Grafana exposed via Railway public URL with authentication

**Firewall Rules** (if applicable):
- Only Railway internal network can access database
- Prometheus metrics endpoints restricted to monitoring network
- Alertmanager webhook endpoints validated

### CI/CD Security

**Branch Protection** (GitHub):
- `main` branch: Require PR reviews (minimum 1 approver)
- Status checks must pass before merge
- No direct commits to `main`

**Secret Scanning**:
- GitHub Advanced Security secret scanning enabled
- Pre-commit hooks to prevent credential commits
- Dependency scanning for vulnerabilities

**Container Security**:
- Base images pinned to specific versions (not `latest`)
- Regular image updates for security patches
- Minimal container images (distroless where possible)

**Verification**:
```bash
# Check GitHub branch protection
gh api repos/HempDash/observability/branches/main/protection

# Verify secret scanning enabled
gh api repos/HempDash/observability/secret-scanning/alerts

# Check Dockerfile base images
grep "^FROM" */Dockerfile
```

### Alerting & Monitoring Security

**Alert Routing Verified**:
- Critical alerts → PagerDuty + Slack `#alerts-critical`
- Warning alerts → Slack `#alerts-warnings`
- Platform alerts → Slack `#platform-alerts`

**Inhibition Rules Active**:
- Critical alerts suppress warning alerts for same instance
- Primary database down suppresses replica alerts

**Access Control**:
- Grafana dashboards: Viewer role for all team members
- Grafana admin: Platform team leads only
- Prometheus/Alertmanager: Internal network only

**Verification**:
```bash
# Test alert routing
amtool config routes test --config.file=alertmanager/alertmanager.yml \
  severity=critical team=platform

# Check Grafana users
curl -H "Authorization: Bearer $GRAFANA_API_KEY" \
  http://grafana:3000/api/org/users
```

### Security Audit Checklist

**Monthly**:
- [ ] Review Grafana user access and permissions
- [ ] Verify alert routes are delivering notifications
- [ ] Check for expired secrets (review `docs/security/secrets.md`)
- [ ] Review database user permissions

**Quarterly**:
- [ ] Rotate all production credentials
- [ ] Review and update firewall rules
- [ ] Audit CI/CD pipeline secrets
- [ ] Penetration testing of public endpoints

**Annually**:
- [ ] Full security audit by external firm
- [ ] Review and update security policies
- [ ] Compliance verification (SOC2, GDPR, etc.)

### Incident Response

**Security Incident Severity Levels**:

**P0 - Critical**:
- Unauthorized database access
- Credential leak in public repository
- Data exfiltration detected

**Response**: Immediate page, lock down affected systems, rotate all credentials

**P1 - High**:
- Suspicious login attempts
- Unusual query patterns
- Alert delivery failures

**Response**: Investigate within 1 hour, implement mitigations

**P2 - Medium**:
- Expired credentials still in use
- Missing MFA on admin accounts
- Outdated dependencies with known CVEs

**Response**: Schedule fix within 1 week

### Compliance & Audit Logging

**Enabled Logging**:
- PostgreSQL query logging (slow queries > 1s)
- Railway deployment logs (retained 30 days)
- Grafana audit logs (user actions)
- Alertmanager notification history

**Log Retention**:
- Application logs: 30 days
- Security logs: 90 days
- Compliance logs: 7 years

**Access**:
```bash
# View recent database logs
railway logs --service primary-db --since 1h

# Query slow query log
psql -c "SELECT * FROM pg_stat_statements ORDER BY total_time DESC LIMIT 10;"

# Grafana audit log
curl -H "Authorization: Bearer $GRAFANA_API_KEY" \
  http://grafana:3000/api/admin/stats
```

---

## Meta-Monitoring (Task 12.6)

### Overview

Meta-monitoring ensures the observability stack itself is healthy and functioning correctly. This includes monitoring Prometheus, Grafana, Loki, and Tempo to detect issues before they impact application monitoring.

### Architecture

```
Prometheus → Self-scrape metrics
          → Scrape Grafana metrics
          → Scrape Loki metrics
          → Scrape Tempo metrics
          → Evaluate meta-monitoring alerts
          → Send to Alertmanager
```

### Monitored Components

#### Prometheus Self-Monitoring

**Metrics Endpoint**: `http://prometheus:9090/metrics`

**Key Metrics**:
- `up{job="prometheus"}` - Prometheus availability
- `prometheus_tsdb_reloads_failures_total` - TSDB reload failures
- `prometheus_config_last_reload_successful` - Configuration reload status
- `prometheus_notifications_queue_length` - Alert notification queue size
- `prometheus_rule_evaluation_failures_total` - Rule evaluation errors
- `prometheus_target_interval_length_seconds` - Target scrape duration

#### Grafana Health Monitoring

**Metrics Endpoint**: `http://grafana:3000/metrics`

**Key Metrics**:
- `up{job="grafana"}` - Grafana availability
- `process_start_time_seconds{job="grafana"}` - Service uptime/restarts

**Health Check**: `curl http://grafana:3000/api/health`

#### Loki Capacity Monitoring

**Metrics Endpoint**: `http://loki:3100/metrics`

**Key Metrics**:
- `up{job="loki"}` - Loki availability
- `loki_request_duration_seconds_count` - Request rate by route
- `loki_request_duration_seconds_bucket` - Request latency distribution
- `loki_panic_total` - Panic events
- `process_start_time_seconds{job="loki"}` - Service uptime/restarts

**Health Check**: `curl http://loki:3100/ready`

#### Tempo Trace Monitoring

**Metrics Endpoint**: `http://tempo:3200/metrics`

**Key Metrics**:
- `up{job="tempo"}` - Tempo availability
- `tempo_distributor_spans_received_total` - Spans received at distributor
- `tempo_ingester_spans_received_total` - Spans received at ingester
- `tempo_ingester_blocks_flushed_total` - Block flush rate
- `tempodb_compactor_errors_total` - Compactor errors
- `tempo_request_duration_seconds_bucket` - Request latency distribution
- `process_start_time_seconds{job="tempo"}` - Service uptime/restarts

**Health Check**: `curl http://tempo:3200/ready`

### Meta-Monitoring Alerts

All meta-monitoring alerts are defined in `prometheus/rules/alerts.yml`.

#### Critical Alerts (P0)

**PrometheusDown**
- **Expression**: `up{job="prometheus"} == 0`
- **Duration**: 2 minutes
- **Impact**: Metrics collection stopped, no monitoring data
- **Response**: Immediate investigation required

**GrafanaDown**
- **Expression**: `absent(up{job="grafana"} == 1)`
- **Duration**: 2 minutes
- **Impact**: Dashboards unavailable, no visualization
- **Response**: Check Grafana service logs and restart if needed

**LokiDown**
- **Expression**: `absent(up{job="loki"} == 1)`
- **Duration**: 2 minutes
- **Impact**: Log ingestion stopped, no log querying
- **Response**: Check Loki service logs and restart if needed

**TempoDown**
- **Expression**: `absent(up{job="tempo"} == 1)`
- **Duration**: 2 minutes
- **Impact**: Trace ingestion stopped, no distributed tracing
- **Response**: Check Tempo service logs and restart if needed

**LokiRequestPanic**
- **Expression**: `sum(increase(loki_panic_total[10m])) by (namespace, job) > 0`
- **Duration**: 2 minutes
- **Impact**: Loki instability, potential data loss
- **Response**: Immediate investigation, check for OOM or configuration issues

#### Warning Alerts (P1)

**PrometheusTSDBReloadsFailing**
- **Expression**: `increase(prometheus_tsdb_reloads_failures_total[5m]) > 0`
- **Duration**: 2 minutes
- **Action**: Check Prometheus logs for TSDB errors

**PrometheusConfigurationReloadFailing**
- **Expression**: `prometheus_config_last_reload_successful == 0`
- **Duration**: 2 minutes
- **Action**: Validate configuration syntax with `promtool check config`

**PrometheusTooManyRestarts**
- **Expression**: `changes(process_start_time_seconds{job="prometheus"}[15m]) > 2`
- **Duration**: 2 minutes
- **Action**: Investigate crash logs and resource constraints

**PrometheusNotificationQueueRunningFull**
- **Expression**: `(prometheus_notifications_queue_length / prometheus_notifications_queue_capacity) > 0.8`
- **Duration**: 5 minutes
- **Action**: Check Alertmanager connectivity and alert volume

**PrometheusErrorSendingAlertsToAlertmanager**
- **Expression**: `rate(prometheus_notifications_errors_total[5m]) > 0`
- **Duration**: 2 minutes
- **Action**: Verify Alertmanager endpoint and credentials

**PrometheusTargetScrapingSlow**
- **Expression**: `prometheus_target_interval_length_seconds{quantile="0.9"} > 60`
- **Duration**: 5 minutes
- **Action**: Investigate slow targets, check network latency

**PrometheusLargeScrape**
- **Expression**: `increase(prometheus_target_scrapes_exceeded_sample_limit_total[5m]) > 0`
- **Duration**: 2 minutes
- **Action**: Increase sample limit or reduce cardinality

**PrometheusTargetScrapeDuplicate**
- **Expression**: `increase(prometheus_target_scrapes_sample_duplicate_timestamp_total[5m]) > 0`
- **Duration**: 2 minutes
- **Action**: Check for duplicate time series from targets

**PrometheusTSDBCheckpointCreationFailures**
- **Expression**: `increase(prometheus_tsdb_checkpoint_creations_failed_total[5m]) > 0`
- **Duration**: 2 minutes
- **Action**: Check disk space and TSDB health

**PrometheusTSDBCompactionsFailing**
- **Expression**: `increase(prometheus_tsdb_compactions_failed_total[5m]) > 0`
- **Duration**: 2 minutes
- **Action**: Check disk space and TSDB health

**PrometheusRuleEvaluationFailures**
- **Expression**: `increase(prometheus_rule_evaluation_failures_total[5m]) > 0`
- **Duration**: 2 minutes
- **Action**: Check rule syntax and query performance

**GrafanaTooManyRestarts**
- **Expression**: `changes(process_start_time_seconds{job="grafana"}[15m]) > 2`
- **Duration**: 2 minutes
- **Action**: Check Grafana logs for errors

**LokiRequestErrors**
- **Expression**: `100 * sum(rate(loki_request_duration_seconds_count{status_code=~"5.."}[5m])) by (namespace, job, route) / sum(rate(loki_request_duration_seconds_count[5m])) by (namespace, job, route) > 10`
- **Duration**: 5 minutes
- **Action**: Check Loki logs for error details

**LokiRequestLatency**
- **Expression**: `histogram_quantile(0.99, sum(rate(loki_request_duration_seconds_bucket{route!~"(?i).*tail.*"}[5m])) by (le, job)) > 1`
- **Duration**: 5 minutes
- **Action**: Investigate query performance and resource utilization

**LokiTooManyRestarts**
- **Expression**: `changes(process_start_time_seconds{job="loki"}[15m]) > 2`
- **Duration**: 2 minutes
- **Action**: Check Loki logs for crash reasons

**TempoDistributorSpansDropped**
- **Expression**: `rate(tempo_distributor_spans_received_total[5m]) - rate(tempo_ingester_spans_received_total[5m]) > 100`
- **Duration**: 5 minutes
- **Action**: Check ingester capacity and resource limits

**TempoIngesterBlocksFlushed**
- **Expression**: `rate(tempo_ingester_blocks_flushed_total[5m]) == 0`
- **Duration**: 15 minutes
- **Action**: Verify storage backend and ingester health

**TempoCompactorUnhealthy**
- **Expression**: `max_over_time(tempodb_compactor_errors_total[5m]) > 2`
- **Duration**: 5 minutes
- **Action**: Check compactor logs and storage backend

**TempoRequestErrors**
- **Expression**: `100 * sum(rate(tempo_request_duration_seconds_count{status_code=~"5.."}[5m])) by (job, route) / sum(rate(tempo_request_duration_seconds_count[5m])) by (job, route) > 10`
- **Duration**: 5 minutes
- **Action**: Check Tempo logs for error details

**TempoRequestLatency**
- **Expression**: `histogram_quantile(0.99, sum(rate(tempo_request_duration_seconds_bucket[5m])) by (le, job, route)) > 3`
- **Duration**: 5 minutes
- **Action**: Investigate query performance and resource utilization

**TempoTooManyRestarts**
- **Expression**: `changes(process_start_time_seconds{job="tempo"}[15m]) > 2`
- **Duration**: 2 minutes
- **Action**: Check Tempo logs for crash reasons

### Dashboards

**Meta-Monitoring Dashboard**: `grafana/dashboards/meta_monitoring.json`

The dashboard provides:
- **Stack Health Overview**: Status panels for all components (Prometheus, Grafana, Loki, Tempo)
- **Prometheus Monitoring**: Ingestion rate, scrape duration, error rates, notification queue usage
- **Loki Monitoring**: Request rate, latency, error rate, panic events
- **Tempo Monitoring**: Span ingestion rate, drop rate, latency, storage operations

**Access**: `http://grafana:3000/d/meta-monitoring/meta-monitoring-observability-stack-health`

### Troubleshooting Procedures

#### Prometheus Not Scraping Targets

**Symptoms**: `up{job="X"}` metric missing or = 0

**Diagnosis**:
```bash
# Check target status
curl http://prometheus:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health != "up")'

# Test endpoint manually
curl http://loki:3100/metrics
curl http://tempo:3200/metrics
curl http://grafana:3000/metrics
```

**Resolution**:
1. Verify service is running: `railway status --service X`
2. Check network connectivity: `nc -zv service-name port`
3. Verify metrics endpoint responds: `curl http://service:port/metrics`
4. Check Prometheus scrape config in `prometheus/prom.yml`
5. Restart Prometheus if needed: `railway restart --service prometheus`

#### High Alert Notification Queue

**Symptoms**: `PrometheusNotificationQueueRunningFull` alert firing

**Diagnosis**:
```bash
# Check queue size
curl http://prometheus:9090/api/v1/query?query=prometheus_notifications_queue_length

# Check Alertmanager status
curl http://alertmanager:9093/-/healthy

# Check alert delivery errors
curl http://prometheus:9090/api/v1/query?query=rate(prometheus_notifications_errors_total[5m])
```

**Resolution**:
1. Verify Alertmanager is healthy
2. Check webhook endpoints (PagerDuty, Slack) are responsive
3. Review alert volume - consider alert fatigue
4. Increase notification queue capacity if needed (requires Prometheus restart)

#### Loki High Error Rate

**Symptoms**: `LokiRequestErrors` alert firing

**Diagnosis**:
```bash
# Check Loki logs
railway logs --service loki --since 30m | grep -i error

# Query error metrics
curl http://prometheus:9090/api/v1/query?query='rate(loki_request_duration_seconds_count{status_code=~"5.."}[5m])'

# Check Loki health
curl http://loki:3100/ready
```

**Resolution**:
1. Check for storage issues (disk full, slow I/O)
2. Verify Loki configuration in `loki/loki.yml`
3. Check for resource constraints (CPU, memory)
4. Review recent log ingestion patterns for spikes
5. Restart Loki if configuration changed: `railway restart --service loki`

#### Tempo Dropping Spans

**Symptoms**: `TempoDistributorSpansDropped` alert firing

**Diagnosis**:
```bash
# Check span drop rate
curl http://prometheus:9090/api/v1/query?query='rate(tempo_distributor_spans_received_total[5m]) - rate(tempo_ingester_spans_received_total[5m])'

# Check Tempo logs
railway logs --service tempo --since 30m | grep -i drop

# Check ingester status
curl http://tempo:3200/status
```

**Resolution**:
1. Check ingester capacity and resource limits
2. Verify storage backend has sufficient space
3. Review trace volume - consider sampling rate
4. Increase ingester resources if needed
5. Check for network issues between distributor and ingester

### Verification Commands

```bash
# Verify all meta-monitoring targets are UP
curl http://prometheus:9090/api/v1/query?query='up{job=~"prometheus|grafana|loki|tempo"}' | jq '.data.result[] | {job: .metric.job, value: .value[1]}'

# Check for active meta-monitoring alerts
curl http://prometheus:9090/api/v1/alerts | jq '.data.alerts[] | select(.labels.severity == "critical" or .labels.severity == "warning") | {alert: .labels.alertname, state: .state, severity: .labels.severity}'

# Test meta-monitoring dashboard loads
curl -H "Authorization: Bearer $GRAFANA_API_KEY" http://grafana:3000/api/dashboards/uid/meta-monitoring

# Verify alert rules loaded
curl http://prometheus:9090/api/v1/rules | jq '.data.groups[] | select(.name | contains("prometheus.rules") or contains("grafana.rules") or contains("loki.rules") or contains("tempo.rules"))'
```

### Testing Meta-Monitoring

To verify meta-monitoring is working correctly:

1. **Simulate Service Down**:
   ```bash
   # Stop a service temporarily
   railway service stop loki

   # Wait 2-3 minutes for alert to fire
   curl http://prometheus:9090/api/v1/alerts | grep LokiDown

   # Restart service
   railway service start loki

   # Verify alert auto-resolves
   ```

2. **Test Dashboard**:
   - Navigate to Meta-Monitoring dashboard in Grafana
   - Verify all status panels show "UP"
   - Check that metrics are flowing for all services
   - Verify no data gaps in time series panels

3. **Alert Delivery Test**:
   ```bash
   # Manually fire test alert
   curl -X POST http://alertmanager:9093/api/v1/alerts -d '[
     {
       "labels": {
         "alertname": "TestMetaMonitoringAlert",
         "severity": "warning",
         "team": "platform"
       },
       "annotations": {
         "summary": "Test alert for meta-monitoring validation"
       }
     }
   ]'

   # Verify alert appears in Slack/PagerDuty
   ```

### Best Practices

1. **Regular Health Checks**: Review meta-monitoring dashboard daily during standup
2. **Alert Fatigue Prevention**: Tune alert thresholds based on historical data
3. **Documentation**: Keep this runbook updated with new findings
4. **Incident Response**: Include meta-monitoring checks in all incident procedures
5. **Capacity Planning**: Monitor metric cardinality and storage growth
6. **Backup Monitoring**: Ensure critical application alerts exist outside the stack

### Related Documentation

- Prometheus configuration: `prometheus/prom.yml`
- Alert rules: `prometheus/rules/alerts.yml`
- Meta-monitoring dashboard: `grafana/dashboards/meta_monitoring.json`

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
| 2025-10-08 | Added Stage 7 (Backups & Restore, Failover Drill) and Stage 8 (Security & Access Review) | Platform Team |
| 2026-01-12 | Added Task 12.6 (Meta-Monitoring) with comprehensive monitoring of observability stack | Platform Team |
