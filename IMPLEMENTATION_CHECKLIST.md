# Docker Auto-Migration Implementation Checklist

## Quick Reference - Print & Check Off

---

## PREPARATION (0-5 min)
- [ ] Read DOCKER_AUTO_MIGRATION_PLAN.md
- [ ] Create backups:
  - [ ] `cp docker-compose.yml docker-compose.yml.backup`
  - [ ] `cp init-db.sql init-db.sql.backup`
- [ ] Verify all service directories exist
- [ ] Verify entrypoint.sh doesn't already exist

---

## DATABASE PHASE (5-10 min)

### init-db.sql
- [ ] Add 3 lines after Facebook database:
  ```sql
  -- Scraping Service Database
  CREATE DATABASE scraping_db;
  ```

### .env
- [ ] Add after SCRAPING_PORT=3008:
  ```
  SCRAPING_DATABASE_URL=postgresql://postgres:postgres123@postgres:5432/scraping_db?schema=public&sslmode=disable
  ```

---

## ENTRYPOINT PHASE (10-15 min)

### Create entrypoint.sh
- [ ] Create new file: `entrypoint.sh` at repository root
- [ ] Copy full content from DOCKER_AUTO_MIGRATION_PLAN.md section 2.1
- [ ] Make executable: `chmod +x entrypoint.sh`
- [ ] Verify syntax: `bash -n entrypoint.sh`
- [ ] Verify line endings are Unix (LF, not CRLF)

---

## DOCKERFILE UPDATE PHASE (15-45 min)

### gateway/Dockerfile (19 → 26 lines)
- [ ] Add to line 1: `RUN apk add --no-cache openssl netcat-openbsd`
- [ ] Add before line 18:
  ```dockerfile
  COPY ../entrypoint.sh /usr/local/bin/entrypoint.sh
  RUN chmod +x /usr/local/bin/entrypoint.sh
  ```
- [ ] Replace lines 18-19 with:
  ```dockerfile
  ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
  CMD ["node", "dist/main"]
  ```

### identity/Dockerfile (42 → 46 lines)
- [ ] Add `netcat-openbsd` to line 27 apk install
- [ ] Add before EXPOSE:
  ```dockerfile
  COPY ../entrypoint.sh /usr/local/bin/entrypoint.sh
  RUN chmod +x /usr/local/bin/entrypoint.sh
  ```
- [ ] Replace CMD with ENTRYPOINT + CMD

### whatsapp/Dockerfile (19 → 26 lines)
- [ ] Same as gateway/Dockerfile

### slack/Dockerfile (19 → 26 lines)
- [ ] Same as gateway/Dockerfile

### notion/Dockerfile (19 → 26 lines)
- [ ] Same as gateway/Dockerfile

### instagram/Dockerfile (12 → 26 lines)
- [ ] Add netcat-openbsd to apk install
- [ ] Add entrypoint.sh copy
- [ ] Replace CMD with ENTRYPOINT + CMD

### tiktok/Dockerfile (11 → 26 lines)
- [ ] Add netcat-openbsd to apk install
- [ ] Add entrypoint.sh copy
- [ ] Replace CMD with ENTRYPOINT + CMD

### facebook/Dockerfile (11 → 26 lines)
- [ ] Add netcat-openbsd to apk install
- [ ] Add entrypoint.sh copy
- [ ] Replace CMD with ENTRYPOINT + CMD

### scrapping/Dockerfile (32 → 70 lines) ⭐ OPTIMIZATION
- [ ] Replace entire file with multi-stage Alpine version from section 5.2

---

## DOCKER-COMPOSE PHASE (45-60 min)

### Update all service environment sections
For each of these services, add to environment block:
- [ ] gateway (lines 91-96)
  - [ ] Add: `POSTGRES_HOST: ${POSTGRES_HOST:-postgres}`
  - [ ] Add: `POSTGRES_PORT: ${POSTGRES_PORT:-5432}`
  - [ ] Add: `POSTGRES_USER: ${POSTGRES_USER:-postgres}`
  - [ ] Add: `POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-postgres123}`
  - [ ] Add: `SERVICE_NAME: gateway`

- [ ] identity (lines 115-120)
  - [ ] Add same 5 env vars
  - [ ] Change SERVICE_NAME to: `identity`

- [ ] whatsapp (lines 139-148)
  - [ ] Add same 5 env vars
  - [ ] Change SERVICE_NAME to: `whatsapp`

- [ ] slack (lines 167-174)
  - [ ] Add same 5 env vars
  - [ ] Change SERVICE_NAME to: `slack`

- [ ] notion (lines 193-199)
  - [ ] Add same 5 env vars
  - [ ] Change SERVICE_NAME to: `notion`

- [ ] instagram (lines 218-227)
  - [ ] Add same 5 env vars
  - [ ] Change SERVICE_NAME to: `instagram`

- [ ] tiktok (lines 246-254)
  - [ ] Add same 5 env vars
  - [ ] Change SERVICE_NAME to: `tiktok`

- [ ] facebook (lines 273-282)
  - [ ] Add same 5 env vars
  - [ ] Change SERVICE_NAME to: `facebook`

- [ ] scraping (lines 301-315)
  - [ ] Add: `SCRAPING_DATABASE_URL: postgresql://postgres:postgres123@postgres:5432/scraping_db?schema=public&sslmode=disable`
  - [ ] Add: same 5 env vars as other services
  - [ ] Change SERVICE_NAME to: `scraping`

### Verify docker-compose.yml
- [ ] Syntax check: `docker-compose config > /dev/null && echo "✓ Valid"`
- [ ] No duplicate keys
- [ ] All indentation correct (2 spaces)

---

## TESTING PHASE (60-120 min)

### Startup Test
- [ ] Run: `docker-compose up -d`
- [ ] Wait 30 seconds for PostgreSQL health check
- [ ] Check: `docker-compose ps` (all containers should be running)

### PostgreSQL Verification
- [ ] Run: `docker-compose exec postgres psql -U postgres -l | grep _db`
- [ ] Verify: Shows all 9 databases (gateway, identity, whatsapp, slack, notion, instagram, tiktok, facebook, scraping, email)

### Service Log Verification
- [ ] Gateway: `docker-compose logs gateway | grep "✓ SUCCESS"`
- [ ] Identity: `docker-compose logs identity | grep "✓ SUCCESS"`
- [ ] WhatsApp: `docker-compose logs whatsapp | grep "✓ SUCCESS"`
- [ ] Slack: `docker-compose logs slack | grep "✓ SUCCESS"`
- [ ] Notion: `docker-compose logs notion | grep "✓ SUCCESS"`
- [ ] Instagram: `docker-compose logs instagram | grep "✓ SUCCESS"`
- [ ] TikTok: `docker-compose logs tiktok | grep "✓ SUCCESS"`
- [ ] Facebook: `docker-compose logs facebook | grep "✓ SUCCESS"`
- [ ] Scraping: `docker-compose logs scraping | grep "✓ SUCCESS"`

### API Connectivity Tests
- [ ] Gateway: `curl -s http://localhost:3000/health 2>&1 | head -5`
- [ ] Identity: `curl -s http://localhost:3010/health 2>&1 | head -5`
- [ ] WhatsApp: `curl -s http://localhost:3001/health 2>&1 | head -5`
- [ ] Slack: `curl -s http://localhost:3002/health 2>&1 | head -5`
- [ ] Notion: `curl -s http://localhost:3003/health 2>&1 | head -5`
- [ ] Instagram: `curl -s http://localhost:3004/health 2>&1 | head -5`
- [ ] TikTok: `curl -s http://localhost:3005/health 2>&1 | head -5`
- [ ] Facebook: `curl -s http://localhost:3006/health 2>&1 | head -5`
- [ ] Scraping: `curl -s http://localhost:3008/health 2>&1 | head -5`

### Database Schema Verification
- [ ] Run: `docker-compose exec postgres psql -U postgres -d gateway_db -c "\dt"`
- [ ] Verify: Shows tables from prisma migrations
- [ ] Repeat for: identity_db, whatsapp_db, slack_db, notion_db, instagram_db, tiktok_db, facebook_db, scraping_db

### Entrypoint Script Verification
- [ ] Check startup sequence in logs: `docker-compose logs --timestamps | grep "Startup sequence"`
- [ ] Verify migration messages: `docker-compose logs | grep "Running pending database migrations"`
- [ ] No error messages in: `docker-compose logs | grep "ERROR"`

### Stability Check (5-10 minutes)
- [ ] Monitor logs: `docker-compose logs -f --tail=100` (no errors for 5 min)
- [ ] Check container restarts: `docker-compose ps` (no restarts)
- [ ] Verify services responding: Multiple API calls to each service

---

## TROUBLESHOOTING DURING TEST

| Symptom | Check | Fix |
|---------|-------|-----|
| Container keeps restarting | Logs: `docker-compose logs [service]` | Check entrypoint.sh syntax |
| "Waiting for PostgreSQL" loops | Check: `docker-compose logs postgres` | Verify POSTGRES_HOST=postgres in compose |
| Migration fails | Logs: `docker-compose logs gateway \| grep -A5 migration` | Drop DB: `docker-compose exec postgres psql -U postgres -c "DROP DATABASE [service]_db;"`; Restart service |
| entrypoint.sh not found | Build logs: `docker-compose build --no-cache gateway` | Verify `COPY ../entrypoint.sh` is in Dockerfile |
| Permission denied on script | Logs: `docker-compose logs gateway` | Verify `RUN chmod +x /usr/local/bin/entrypoint.sh` in Dockerfile |
| CRLF line ending errors | On Windows: `dos2unix entrypoint.sh` | Or recreate file with Unix line endings |

---

## POST-TEST (120+ min)

### Cleanup
- [ ] Remove old backups (if stable): `rm docker-compose.yml.backup init-db.sql.backup`
- [ ] Commit changes: 
  ```bash
  git add init-db.sql .env entrypoint.sh gateway/Dockerfile identity/Dockerfile whatsapp/Dockerfile slack/Dockerfile notion/Dockerfile instagram/Dockerfile tiktok/Dockerfile facebook/Dockerfile scrapping/Dockerfile docker-compose.yml
  git commit -m "feat: implement auto-migrations and optimize scraping service"
  ```

### Document Results
- [ ] Record startup times (should be 2-3 min first run)
- [ ] Record image sizes (should see 46% reduction in total)
- [ ] Note any service-specific issues
- [ ] Update team on successful deployment

---

## VERIFICATION COMMANDS (Keep for Reference)

```bash
# Full status check
docker-compose ps && echo "---" && \
docker-compose logs postgres | grep "database system is ready" && echo "---" && \
docker-compose logs gateway | grep "✓ SUCCESS" && echo "---" && \
curl -s http://localhost:3000/health | jq .

# Check all databases exist
docker-compose exec postgres psql -U postgres -lq | grep _db

# Check all services are healthy (5+ min after startup)
for service in gateway identity whatsapp slack notion instagram tiktok facebook scraping; do
  echo "Testing $service..."
  curl -s http://localhost:3000/health 2>&1 | head -2
done

# Cleanup old images (after verification)
docker image prune -a --force --filter "until=24h"

# View build time comparison
time docker-compose build scrapping
```

---

## ROLLBACK COMMANDS (If Needed)

```bash
# Stop current stack
docker-compose down -v

# Restore backups
cp docker-compose.yml.backup docker-compose.yml
cp init-db.sql.backup init-db.sql
rm entrypoint.sh

# Restore Dockerfiles from git
git checkout gateway/Dockerfile identity/Dockerfile whatsapp/Dockerfile slack/Dockerfile notion/Dockerfile instagram/Dockerfile tiktok/Dockerfile facebook/Dockerfile scrapping/Dockerfile docker-compose.yml .env

# Restart
docker-compose up -d
```

---

**Estimated Total Time**: 2-3 hours  
**Difficulty Level**: Medium (straightforward edits, high value)  
**Risk Level**: Low (backed up, can rollback easily)  
**Benefit**: Fully automated migrations, 46% smaller images, cleaner deployment
