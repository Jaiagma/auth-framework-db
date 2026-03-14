# Deployment Checklist

Use this checklist for every production deployment. Complete each section in order.
All items must be checked before proceeding to the next section.

---

## Pre-Deployment: Infrastructure

- [ ] Terraform plan reviewed — no unexpected destroys or replacements
- [ ] Terraform state is not locked from a previous failed run
- [ ] All resource quotas verified (vCores, IPs, Key Vault operations)
- [ ] VNet integration confirmed on App Service (production and staging slots)
- [ ] NSG rules reviewed — no overly permissive inbound rules
- [ ] Private endpoints active for Key Vault, ACR, and PostgreSQL

## Pre-Deployment: Secrets and Configuration

- [ ] All required Key Vault secrets exist and have current values
- [ ] Key Vault references in App Service app settings resolve successfully
- [ ] No plain-text secrets in app settings (all should be KV references or non-sensitive values)
- [ ] `ASPNETCORE_ENVIRONMENT` is set to `Production` on the production slot
- [ ] `WEBSITES_PORT` matches the port the container listens on (default: `8080`)
- [ ] Application Insights connection string is configured

## Pre-Deployment: Database

- [ ] A recent database backup exists (within the last 24 hours)
- [ ] Backup restore has been tested in staging within the last 30 days
- [ ] All EF Core migrations applied to staging and validated
- [ ] No pending schema migrations that could break the current production version
- [ ] `max_connections` parameter is sufficient for the expected instance count
- [ ] Row-level security policies verified in staging

## Pre-Deployment: Docker Image

- [ ] Docker image built from the correct git commit/tag
- [ ] Image pushed to ACR and tag confirmed present
- [ ] Image vulnerability scan passed (no CRITICAL or HIGH CVEs)
- [ ] Container runs as non-root user
- [ ] Image tested locally or in dev environment

## Pre-Deployment: Monitoring

- [ ] Application Insights is receiving data from staging
- [ ] Alert rules are active and action group email/webhook is reachable
- [ ] Log Analytics workspace has sufficient ingestion quota
- [ ] Dashboard is bookmarked and accessible for post-deployment monitoring

---

## Deployment Steps (In Order)

1. [ ] **Notify stakeholders** — send deployment notification (time, expected downtime if any, rollback plan)
2. [ ] **Deploy to staging slot** — update container image tag on the staging slot
   ```bash
   az webapp config container set -n "$APP_SERVICE_NAME" -g "$RESOURCE_GROUP" \
     --slot staging --docker-custom-image-name "$ACR_LOGIN_SERVER/auth-framework-api:$IMAGE_TAG"
   ```
3. [ ] **Run database migrations** (if any) against production database
4. [ ] **Restart staging slot** and wait for health check to pass
   ```bash
   az webapp restart -n "$APP_SERVICE_NAME" -g "$RESOURCE_GROUP" --slot staging
   ```
5. [ ] **Smoke test staging slot** — run the smoke test suite against the staging URL
6. [ ] **Swap staging to production**
   ```bash
   az webapp deployment slot swap -n "$APP_SERVICE_NAME" -g "$RESOURCE_GROUP" \
     --slot staging --target-slot production
   ```
7. [ ] **Verify production health check** passes within 2 minutes of swap

---

## Post-Deployment Verification

### Health Check

- [ ] `GET /health` returns `200 OK` on production
- [ ] `GET /health/ready` returns `200 OK` (database connectivity confirmed)
- [ ] No spike in 5xx errors in Application Insights (check for 10 minutes post-deploy)

### Smoke Test

- [ ] `POST /auth/login` returns a valid JWT for a test user
- [ ] `POST /auth/refresh` returns a new access token
- [ ] `POST /auth/logout` invalidates the refresh token
- [ ] `GET /health` is reachable and returns `200`

### Monitoring

- [ ] Application Insights showing requests from new version
- [ ] No new alert triggers in the 10 minutes following deployment
- [ ] P95 response latency is within baseline (< 500ms for `/auth/login`)
- [ ] CPU and memory on App Service instances are within normal range

### Performance

- [ ] Average response time comparable to pre-deployment baseline
- [ ] Auto-scale not triggering unexpectedly in the first 15 minutes

---

## Rollback Procedures

If any post-deployment check fails:

### Fast Rollback — Slot Swap Back

```bash
# Swap production back to the previous version (staging now holds old version)
az webapp deployment slot swap \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --slot production \
  --target-slot staging
```

This completes in under 60 seconds for most cases.

### Database Rollback

If a migration was applied and the rollback swap is not sufficient:

```bash
# 1. Restore to point-in-time before migration
RESTORE_TIME="<timestamp-before-migration>"
az postgres flexible-server restore \
  --name "psql-auth-framework-restore" \
  --resource-group "$RESOURCE_GROUP" \
  --source-server "$PG_SERVER_NAME" \
  --restore-time "$RESTORE_TIME"

# 2. Validate restored data
# 3. Update connection string in Key Vault to point to restored server
# 4. Restart App Service
az webapp restart -n "$APP_SERVICE_NAME" -g "$RESOURCE_GROUP"
```

### Rollback Checklist

- [ ] Swap-back or redeployment of previous image tag completed
- [ ] Health check passes after rollback
- [ ] Smoke tests pass after rollback
- [ ] Stakeholders notified of rollback and reason
- [ ] Incident ticket created to track root cause analysis

---

## Sign-Off

| Role | Name | Signed Off | Time |
|---|---|---|---|
| Deploying Engineer | | ☐ | |
| On-Call Engineer | | ☐ | |
| QA / Validation | | ☐ | |

**Deployment completed at:** _______________

**Image tag deployed:** _______________

**Notes:**

> (Record any issues encountered, workarounds applied, or follow-up actions required.)
