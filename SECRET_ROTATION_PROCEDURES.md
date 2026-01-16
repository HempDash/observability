# HempDash Secret Rotation Procedures

**Last Updated:** January 15, 2026
**Owner:** Infrastructure Team (Jonathan Sullivan)
**Review Frequency:** Quarterly

---

## 🔐 Secret Rotation Schedule

| Secret Type | Rotation Frequency | Last Rotated | Next Rotation | Priority |
|-------------|-------------------|--------------|---------------|----------|
| Database passwords | 90 days | TBD | TBD | Critical |
| API keys (3rd party) | 180 days | TBD | TBD | High |
| JWT signing keys | 365 days | TBD | TBD | Critical |
| Railway tokens | On compromise | TBD | N/A | Critical |
| Doppler tokens | On compromise | TBD | N/A | Critical |
| Stripe API keys | 180 days | TBD | TBD | High |
| Plaid credentials | 180 days | TBD | TBD | High |
| Auth0 secrets | 180 days | TBD | TBD | High |
| Grafana API keys | 180 days | TBD | TBD | Medium |
| Amplitude keys | 365 days | TBD | TBD | Low |

---

## 📋 Rotation Procedures

### 1. Database Password Rotation

**Service:** Railway PostgreSQL
**Impact:** High - requires backend restart
**Estimated Time:** 15 minutes

**Prerequisites:**
- Access to Railway dashboard
- Doppler write access
- Maintenance window scheduled (optional for staging, required for production)

**Staging Environment:**

```bash
# Step 1: Generate new secure password
NEW_PASSWORD=$(openssl rand -base64 32)
echo "New password generated (save securely): $NEW_PASSWORD"

# Step 2: Update password in Railway PostgreSQL service
# Via Railway dashboard:
# 1. Go to Railway project > PostgreSQL service
# 2. Settings > Environment Variables
# 3. Update POSTGRES_PASSWORD
# 4. Service will auto-restart

# Step 3: Update DATABASE_URL in Doppler
doppler secrets set DATABASE_URL "postgresql://hempdash:$NEW_PASSWORD@postgres-staging:5432/hempdash_staging" \
  --project backend \
  --config staging

# Step 4: Restart backend services to pick up new credentials
# Railway will auto-restart services connected to Doppler

# Step 5: Verify connections work
curl https://api-staging.gethempdash.com/health

# Step 6: Monitor logs for 15 minutes
# Check Railway logs for database connection errors
```

**Production Environment:**

```bash
# Same steps as staging but use production config
# CRITICAL: Schedule maintenance window
# CRITICAL: Notify team before starting
# CRITICAL: Test in staging first

doppler secrets set DATABASE_URL "postgresql://hempdash:$NEW_PASSWORD@postgres-prod:5432/hempdash_production" \
  --project backend \
  --config production

# Verify production health
curl https://api.gethempdash.com/health
```

**Rollback:**
1. Revert `DATABASE_URL` in Doppler to old password
2. Redeploy services
3. Verify connections restored

**Testing:**
- [ ] Backend API health check returns 200
- [ ] Database queries execute successfully
- [ ] No connection pool exhaustion errors
- [ ] All background jobs running

---

### 2. API Key Rotation (Stripe, Plaid, Amplitude, etc.)

**Impact:** Medium - requires deployment
**Estimated Time:** 10 minutes per service

**Prerequisites:**
- Access to third-party provider dashboard
- Doppler write access
- Testing environment to verify new key

**Steps:**

```bash
# Step 1: Generate new API key from provider dashboard
# Example: Stripe
# 1. Go to Stripe Dashboard > Developers > API Keys
# 2. Click "Create secret key"
# 3. Name it "HempDash Backend - 2026-01"
# 4. Copy the new key (shown only once)

# Step 2: Update key in Doppler (keep old key temporarily for rollback)
doppler secrets set STRIPE_API_KEY_NEW "sk_live_NEW_KEY_HERE" \
  --project backend \
  --config production

# Step 3: Update application code to use new key
# In backend config, temporarily support both keys:
# STRIPE_API_KEY = env.get('STRIPE_API_KEY_NEW') or env.get('STRIPE_API_KEY')

# Step 4: Deploy application with new key
# Test in staging first

# Step 5: Monitor for errors for 24 hours
# Check error tracking (Sentry) for API authentication failures

# Step 6: After 24 hours of successful operation, revoke old key
# Go to provider dashboard and revoke/delete old key

# Step 7: Remove fallback logic from code
# Update to only use STRIPE_API_KEY_NEW
# Rename STRIPE_API_KEY_NEW to STRIPE_API_KEY in Doppler

# Step 8: Clean up old secret
doppler secrets delete STRIPE_API_KEY_OLD \
  --project backend \
  --config production
```

**Rollback:**
1. Switch back to old key in Doppler
2. Redeploy application
3. Old key should still be valid if revocation was delayed

**Provider-Specific Notes:**

**Stripe:**
- Test mode and live mode keys rotate separately
- Can have multiple active keys simultaneously
- Revoke immediately if compromised

**Plaid:**
- Client ID and Secret rotate together
- Requires updating both in Doppler simultaneously
- Test with sandbox environment first

**Amplitude:**
- API key and Secret key rotate together
- Read-only keys can remain longer
- Check all analytics dashboards after rotation

---

### 3. JWT Signing Key Rotation

**Impact:** High - requires zero-downtime strategy
**Estimated Time:** 30 minutes
**Frequency:** Annually or on compromise

**Prerequisites:**
- Zero-downtime rotation strategy implemented
- Maintenance notification sent 24 hours in advance
- Rollback plan tested

**Steps:**

```bash
# Step 1: Generate new signing key
NEW_JWT_KEY=$(openssl rand -hex 64)
echo "New JWT signing key generated: $NEW_JWT_KEY"

# Step 2: Add new key to JWT_SIGNING_KEYS array (keep old key)
# This allows both keys to validate tokens during transition
doppler secrets set JWT_SIGNING_KEYS "[\"$OLD_KEY\",\"$NEW_JWT_KEY\"]" \
  --project backend \
  --config production

# Step 3: Deploy application with both keys active
# Application should:
# - Sign new tokens with NEW_JWT_KEY (first in array)
# - Validate tokens with either key
# This ensures existing user sessions remain valid

# Step 4: Wait 24 hours for all old tokens to expire
# JWT tokens typically have 24-hour expiry
# Monitor token validation success rate

# Step 5: After grace period, remove old key from array
doppler secrets set JWT_SIGNING_KEYS "[\"$NEW_JWT_KEY\"]" \
  --project backend \
  --config production

# Step 6: Deploy again with only new key

# Step 7: Monitor for authentication errors
# Check error logs for JWT validation failures
```

**Rollback:**
1. Re-add old key to JWT_SIGNING_KEYS array
2. Redeploy
3. Both keys active again

**Zero-Downtime Strategy:**
- Always maintain backward compatibility during transition
- Never immediately revoke old signing key
- Monitor token validation rates throughout process
- Grace period must exceed token TTL

---

### 4. Railway Token Rotation

**Impact:** Critical - affects deployment pipeline
**Estimated Time:** 20 minutes
**Trigger:** On compromise or annual review

**Steps:**

```bash
# Step 1: Generate new Railway token
# 1. Go to Railway dashboard > Settings > Tokens
# 2. Click "Create new token"
# 3. Name it "HempDash Deployment - 2026"
# 4. Copy token (shown only once)

# Step 2: Update token in CI/CD system
# Update GitHub Actions secrets
gh secret set RAILWAY_TOKEN --body "$NEW_RAILWAY_TOKEN" --repo HempDash/backend

# Step 3: Update token in Doppler (if used for deployments)
doppler secrets set RAILWAY_TOKEN "$NEW_RAILWAY_TOKEN" \
  --project infrastructure \
  --config production

# Step 4: Update local development environments
# Notify team members to update their .env files

# Step 5: Test deployment with new token
# Trigger a test deployment to staging

# Step 6: Revoke old token from Railway dashboard
# Only after confirming new token works

# Step 7: Update documentation
# Record rotation date in this file
```

**Rollback:**
1. Revert to old token in GitHub Actions
2. Old token should still be valid if not yet revoked

---

### 5. Doppler Token Rotation

**Impact:** Critical - affects all secret access
**Estimated Time:** 30 minutes
**Trigger:** On compromise only

**Steps:**

```bash
# Step 1: Generate new Doppler service token
# 1. Go to Doppler dashboard > Access > Service Tokens
# 2. Create new service token for "backend" project
# 3. Set appropriate permissions (read/write)
# 4. Copy token (shown only once)

# Step 2: Update token in Railway services
# For each Railway service using Doppler:
# 1. Go to service > Variables
# 2. Update DOPPLER_TOKEN environment variable
# 3. Redeploy service

# Step 3: Update token in CI/CD
gh secret set DOPPLER_TOKEN --body "$NEW_DOPPLER_TOKEN" --repo HempDash/backend

# Step 4: Update token in local development
# Notify team to update .env.local files

# Step 5: Test secret access
doppler secrets get DATABASE_URL --token "$NEW_DOPPLER_TOKEN"

# Step 6: Revoke old token from Doppler dashboard
# Confirm all services using new token first

# Step 7: Monitor for access errors
# Check Railway logs for Doppler sync failures
```

**Critical Notes:**
- Doppler token rotation affects ALL services
- Coordinate with entire team before rotating
- Have rollback plan ready
- Test thoroughly in staging first

---

## 🚨 Emergency Rotation (Compromised Secret)

**Immediate Actions (within 30 minutes):**

1. **Assess Scope**
   - Which secret was compromised?
   - What services use this secret?
   - What data could be accessed with this secret?
   - Document incident timeline

2. **Revoke Immediately**
   - Disable compromised secret at source (provider dashboard)
   - Do NOT wait for rotation completion
   - Priority: stop unauthorized access

3. **Rotate in Doppler**
   - Generate new secret
   - Update in Doppler immediately
   - Push to production ASAP

4. **Emergency Deploy**
   - Deploy to production immediately
   - Skip normal approval gates if needed
   - Monitor deployment closely

5. **Monitor Access**
   - Watch for unauthorized access attempts
   - Check logs for suspicious activity during compromise window
   - Set up alerts for unusual patterns

6. **Audit Logs**
   - Review all access logs for compromise period
   - Identify what data was accessed
   - Document findings

7. **Post-Mortem**
   - Document how compromise occurred
   - Implement preventive measures
   - Update rotation procedures if needed
   - Notify affected parties if required (GDPR, etc.)

**Emergency Contact:**
- Infrastructure Lead: Jonathan Sullivan
- On-Call Engineer: [PagerDuty/Opsgenie schedule]
- Security Lead: [Name/Contact]

---

## 🔍 Audit & Compliance

### Doppler Audit Logs

**View recent secret access:**

```bash
# Get audit logs for backend project
curl -s "https://api.doppler.com/v3/logs?project=backend&page=1&per_page=20" \
  -u "$DOPPLER_TOKEN:" | jq '.logs[] | {timestamp: .created_at, user: .user.email, action: .action, secret: .secret}'

# Filter by secret name
curl -s "https://api.doppler.com/v3/logs?project=backend&page=1&per_page=20" \
  -u "$DOPPLER_TOKEN:" | jq '.logs[] | select(.secret == "DATABASE_URL")'
```

### Railway Deployment History

**View deployment history (verify secrets were rotated):**
1. Go to Railway dashboard: https://railway.app/project/[PROJECT_ID]/deployments
2. Check "Environment Variables" tab for each deployment
3. Verify timestamps align with rotation schedule

### Quarterly Compliance Check

**Checklist (run every 90 days):**

- [ ] Review SECRET_ROTATION_PROCEDURES.md for accuracy
- [ ] Verify all rotation dates are up to date
- [ ] Check for any overdue rotations
- [ ] Test rollback procedures in staging
- [ ] Update team on upcoming rotations
- [ ] Review Doppler audit logs for unauthorized access
- [ ] Verify all services using latest secrets
- [ ] Document any incidents or near-misses
- [ ] Update emergency contact information

---

## 📞 Contacts

**Infrastructure Lead:** Jonathan Sullivan
**Email:** jonathan@gethempdash.com
**On-Call Rotation:** [Link to PagerDuty/Opsgenie schedule]

**Vendor Support:**
- **Doppler Support:** support@doppler.com
- **Railway Support:** team@railway.app
- **Stripe Support:** https://support.stripe.com

---

## ✅ Rotation Checklist Template

**Use this checklist for each rotation:**

### Pre-Rotation
- [ ] Maintenance window scheduled (if required)
- [ ] Team notified (email/Slack)
- [ ] Backup of current secrets documented
- [ ] Rollback plan reviewed
- [ ] Testing environment verified working

### Rotation
- [ ] New secret generated using secure method
- [ ] Secret updated in Doppler staging
- [ ] Staging deployment tested and verified
- [ ] Secret updated in Doppler production
- [ ] Production deployment successful
- [ ] Health checks passing
- [ ] No errors in logs (15-minute monitoring)

### Post-Rotation
- [ ] Old secret revoked after grace period
- [ ] Rotation documented in this file
- [ ] Team notified of completion
- [ ] Next rotation date calculated and scheduled
- [ ] Post-rotation testing completed
- [ ] Audit logs reviewed

---

## 📝 Rotation History Log

Record all secret rotations here:

| Date | Secret Type | Rotated By | Environment | Notes |
|------|-------------|-----------|-------------|-------|
| TBD  | Database Password | TBD | Staging | Initial rotation |
| TBD  | Database Password | TBD | Production | Initial rotation |
| TBD  | Stripe API Key | TBD | Production | Scheduled rotation |
| TBD  | JWT Signing Key | TBD | Production | Annual rotation |

---

## 🔄 Automation Opportunities

**Future Improvements:**

1. **Automated Rotation Reminders**
   - Set up calendar reminders for upcoming rotations
   - Send Slack/email notifications 7 days before rotation due

2. **Secret Rotation Automation**
   - Implement automated rotation for database passwords
   - Use Doppler webhooks to trigger deployments on secret change
   - Automated rollback on health check failures

3. **Compliance Reporting**
   - Automated quarterly compliance reports
   - Dashboard showing rotation status for all secrets
   - Alerts for overdue rotations

4. **Zero-Downtime Improvements**
   - Implement blue/green deployments for all services
   - Automated canary deployments with rollback
   - Secret version management in Doppler

---

**END OF DOCUMENT**

**Next Review:** April 15, 2026
