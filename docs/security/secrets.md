# Secrets Inventory & Rotation

This document tracks all secrets used in the HempDash observability stack, their storage locations, rotation schedules, and last rotation dates.

## Policy

- **Storage**: All secrets MUST be stored in Railway Secrets or GitHub Secrets. Never commit secrets to Git.
- **Rotation**: Rotate all production credentials every 90 days (database credentials) or 180 days (integration webhooks/API keys).
- **Scope**: Non-sensitive configuration toggles may use GitHub Actions Variables. Sensitive values use Secrets.
- **Access**: Limit secret access to Platform Team leads and authorized CI/CD pipelines only.

## Secrets Inventory

| Secret Name            | Location             | Owner        | Last Rotated | Next Due   | Notes                     |
|------------------------|----------------------|--------------|--------------|------------|---------------------------|
| `POSTGRES_PASSWORD`    | Railway (Secret)     | Platform     | 2025-10-08   | 2026-01-06 | App DB primary password   |
| `PGPASSWORD`          | Railway (Secret)     | Platform     | 2025-10-08   | 2026-01-06 | App DB PGPASSWORD         |
| `REPMGR_USER_PWD`     | Railway (Primary)    | Platform     | 2025-10-08   | 2026-01-06 | Primary only (NOT replica)|
| `REPLICATION_PASSWORD`| Railway (Secret)     | Platform     | 2025-10-08   | 2026-01-06 | Replication user password |
| `SLACK_WEBHOOK_URL`   | Alertmanager Secret  | Ops          | 2025-10-08   | 2026-04-07 | Slack #ops alerts         |
| `PAGERDUTY_SERVICE_KEY`| Alertmanager Secret | Ops          | 2025-10-08   | 2026-04-07 | PD critical route         |
| `GRAFANA_ADMIN_PASSWORD`| Railway (Secret)   | Platform     | 2025-10-08   | 2026-01-06 | Grafana admin user        |
| `GRAFANA_API_KEY`     | Railway (Secret)     | Platform     | 2025-10-08   | 2026-01-06 | Grafana API access        |
| `PROMETHEUS_ADMIN_PASSWORD`| Railway (Secret)| Platform     | 2025-10-08   | 2026-01-06 | Prometheus basic auth (if enabled)|
| `LOKI_PASSWORD`       | Railway (Secret)     | Platform     | 2025-10-08   | 2026-01-06 | Loki basic auth (if enabled)|

## Rotation Procedures

### Database Credentials

**Frequency**: Every 90 days

**Steps**:

1. **Generate New Password**:
   ```bash
   NEW_PASSWORD=$(openssl rand -base64 32)
   echo "Generated new password (save securely): $NEW_PASSWORD"
   ```

2. **Update in Railway**:
   ```bash
   # For primary database
   railway variables --set POSTGRES_PASSWORD="$NEW_PASSWORD" --service primary-db

   # For application services
   railway variables --set PGPASSWORD="$NEW_PASSWORD" --service app-service
   ```

3. **Update Database User**:
   ```bash
   # Connect to primary database
   railway run --service primary-db psql

   # Rotate password
   ALTER USER app_user WITH PASSWORD 'NEW_PASSWORD_HERE';
   ```

4. **Verify Connectivity**:
   ```bash
   # Test connection with new password
   psql "postgresql://app_user:$NEW_PASSWORD@primary-db.railway.internal:5432/hempdash?sslmode=require" -c "SELECT 1;"
   ```

5. **Update This Document**:
   - Update "Last Rotated" column with today's date (YYYY-MM-DD)
   - Calculate "Next Due" as Last Rotated + 90 days
   - Commit changes to Git

6. **Verify Application Health**:
   ```bash
   # Check application logs for connection errors
   railway logs --service app-service --since 5m

   # Verify metrics are flowing
   curl http://prometheus:9090/api/v1/query?query=up{job="app-service"}
   ```

### Replication User Password

**Frequency**: Every 90 days

**Critical**: Coordinate with replica to avoid replication breakage.

**Steps**:

1. **Generate New Password**:
   ```bash
   NEW_REPL_PASSWORD=$(openssl rand -base64 32)
   ```

2. **Update Primary Database**:
   ```bash
   railway run --service primary-db psql
   ALTER USER replication_user WITH PASSWORD 'NEW_REPL_PASSWORD_HERE';
   ```

3. **Update Replica Configuration**:
   ```bash
   # Update PRIMARY_PASSWORD on replica
   railway variables --set PRIMARY_PASSWORD="$NEW_REPL_PASSWORD" --service replica-db

   # Restart replica to pick up new password
   railway restart --service replica-db
   ```

4. **Verify Replication**:
   ```bash
   # Check replication status on primary
   railway run --service primary-db psql -c "SELECT * FROM pg_stat_replication;"

   # Should show streaming state with application_name matching replica
   ```

5. **Update This Document**: Update rotation dates

### Grafana Credentials

**Frequency**: Every 90 days

**Steps**:

1. **Generate New Password**:
   ```bash
   NEW_GRAFANA_PASSWORD=$(openssl rand -base64 32)
   ```

2. **Update in Railway**:
   ```bash
   railway variables --set GRAFANA_ADMIN_PASSWORD="$NEW_GRAFANA_PASSWORD" --service grafana
   ```

3. **Restart Grafana**:
   ```bash
   railway restart --service grafana
   ```

4. **Verify Access**:
   ```bash
   # Login via UI with new password
   # Or test API
   curl -u admin:$NEW_GRAFANA_PASSWORD http://grafana:3000/api/health
   ```

5. **Rotate API Keys** (if applicable):
   ```bash
   # Via Grafana UI: Configuration → API Keys → Regenerate
   # Or via API:
   curl -X POST -H "Authorization: Bearer $OLD_API_KEY" \
     http://grafana:3000/api/auth/keys \
     -d '{"name":"automation-key","role":"Admin"}'
   ```

6. **Update This Document**: Update rotation dates

### Integration Webhooks & API Keys

**Frequency**: Every 180 days (Slack, PagerDuty)

**Slack Webhook**:

1. **Generate New Webhook** (Slack Admin):
   - Go to Slack App Settings → Incoming Webhooks
   - Create new webhook or regenerate existing
   - Copy new webhook URL

2. **Update in Railway**:
   ```bash
   railway variables --set SLACK_WEBHOOK_URL="https://hooks.slack.com/services/NEW/WEBHOOK/URL" --service alertmanager
   ```

3. **Restart Alertmanager**:
   ```bash
   railway restart --service alertmanager
   ```

4. **Test Alert**:
   ```bash
   # Send test alert
   amtool alert add alertname=test-rotation severity=warning message="Testing webhook rotation"

   # Verify appears in Slack channel
   ```

5. **Revoke Old Webhook** (Slack Admin)

6. **Update This Document**: Update rotation dates

**PagerDuty Service Key**:

1. **Generate New Integration Key** (PagerDuty Admin):
   - Go to Services → Select Service → Integrations
   - Add new "Events API v2" integration or regenerate existing
   - Copy integration key

2. **Update in Railway**:
   ```bash
   railway variables --set PAGERDUTY_SERVICE_KEY="NEW_KEY_HERE" --service alertmanager
   ```

3. **Restart Alertmanager**:
   ```bash
   railway restart --service alertmanager
   ```

4. **Test Critical Alert**:
   ```bash
   # Send test critical alert
   amtool alert add alertname=test-pd-rotation severity=critical

   # Verify incident created in PagerDuty
   ```

5. **Remove Old Integration** (PagerDuty Admin)

6. **Update This Document**: Update rotation dates

## Rotation Checklist Template

Use this checklist when rotating secrets:

```markdown
## Secret Rotation - [DATE] - [SECRET_NAME]

- [ ] Generated new secret securely
- [ ] Updated in Railway/GitHub Secrets
- [ ] Updated in target service (database, application, etc.)
- [ ] Restarted affected services
- [ ] Verified connectivity/functionality
- [ ] Tested end-to-end (e.g., sent test alert, ran query)
- [ ] Updated docs/security/secrets.md with new dates
- [ ] Committed documentation update to Git
- [ ] Revoked/deleted old secret (where applicable)
- [ ] Notified team in #platform-ops Slack channel
```

## Emergency Secret Compromise Response

If a secret is compromised (leaked in logs, public repository, etc.):

**Immediate Actions** (within 15 minutes):

1. **Rotate Compromised Secret Immediately**:
   ```bash
   # Generate new secret
   NEW_SECRET=$(openssl rand -base64 32)

   # Update in all locations
   railway variables --set SECRET_NAME="$NEW_SECRET" --service affected-service
   railway restart --service affected-service
   ```

2. **Revoke Old Secret**:
   - Database users: `ALTER USER ... WITH PASSWORD ...`
   - API keys: Delete from provider (GitHub, Slack, PagerDuty)
   - Webhooks: Regenerate in source system

3. **Assess Impact**:
   - Review audit logs for unauthorized access
   - Check database query logs for suspicious activity
   - Review Grafana access logs
   - Examine Alertmanager notification history

4. **Document Incident**:
   - Create incident ticket with timeline
   - Note where secret was leaked
   - List all affected systems
   - Document rotation steps taken

5. **Communicate**:
   - Notify Platform Team leads immediately
   - Post in #security-incidents Slack channel
   - Create follow-up post-mortem

**Follow-Up Actions** (within 24 hours):

- [ ] Complete full security audit of affected systems
- [ ] Review and tighten secret access controls
- [ ] Implement additional monitoring for affected services
- [ ] Schedule post-mortem meeting
- [ ] Update incident response procedures if gaps found

## Audit & Compliance

**Monthly**:
- Review this document for secrets nearing rotation deadline
- Verify all secrets still in use (remove unused entries)
- Check Railway/GitHub Secrets for orphaned secrets

**Quarterly**:
- Full audit of all secrets against this inventory
- Verify rotation procedures work correctly
- Update procedures based on lessons learned

**Annually**:
- Review and update rotation policies
- External security audit of secrets management
- Compliance verification (SOC2, ISO 27001, etc.)

## Additional Resources

- [Railway Secrets Documentation](https://docs.railway.app/develop/variables#railway-provided-variables)
- [GitHub Encrypted Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [OWASP Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
- [NIST Password Guidelines](https://pages.nist.gov/800-63-3/sp800-63b.html)

---

**Last Updated**: 2025-10-08
**Document Owner**: Platform Team
**Review Frequency**: Quarterly
