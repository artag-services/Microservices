# Docker Auto-Migration - Visual Implementation Guide

A visual companion to the main implementation documents.

---

## Architecture Overview

### Before Implementation
```
┌─────────────────────────────────────────────────────────────┐
│                    Docker Container                         │
├─────────────────────────────────────────────────────────────┤
│  CMD ["node", "dist/main"]                                  │
│                       ↓                                      │
│  Application starts immediately                             │
│  ⚠️  Database schema not synced!                            │
│  ⚠️  Manual migration steps required                        │
└─────────────────────────────────────────────────────────────┘
```

### After Implementation
```
┌─────────────────────────────────────────────────────────────┐
│                    Docker Container                         │
├─────────────────────────────────────────────────────────────┤
│  ENTRYPOINT ["entrypoint.sh"]                               │
│  CMD ["node", "dist/main"]                                  │
│                       ↓                                      │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ entrypoint.sh                                       │   │
│  ├─────────────────────────────────────────────────────┤   │
│  │ 1. Wait for PostgreSQL (infinite retry)            │   │
│  │    🔄 Checking: postgres:5432                      │   │
│  │    ✅ Connected!                                    │   │
│  │                                                     │   │
│  │ 2. Generate Prisma client                          │   │
│  │    🔄 Running: pnpm prisma:generate                │   │
│  │    ✅ Done!                                         │   │
│  │                                                     │   │
│  │ 3. Run pending migrations                          │   │
│  │    🔄 Running: pnpm prisma:migrate deploy          │   │
│  │    ✅ 3 migrations applied                          │   │
│  │                                                     │   │
│  │ 4. Start application                               │   │
│  │    🔄 Running: node dist/main                      │   │
│  │    ✅ Listening on port 3000                        │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  Application running with synced database schema           │
│  ✅ Fully automated, zero manual steps                     │
└─────────────────────────────────────────────────────────────┘
```

---

## Implementation Timeline

```
Day 0 (Preparation)
├─ 10:00 - Read DOCKER_AUTO_MIGRATION_PLAN.md
├─ 10:30 - Review DOCKERFILE_CHANGES_REFERENCE.md
├─ 11:00 - Create backups
└─ 11:15 - Ready to execute

Day 1 (Execution - Evening, ~3 hours)
├─ 18:00 - Phase 1: Database initialization (5 min)
│         └─ init-db.sql modified ✓
├─ 18:05 - Phase 2: Create entrypoint.sh (10 min)
│         └─ File created & tested ✓
├─ 18:15 - Phase 3: Update 8 Dockerfiles (30 min)
│         ├─ gateway ✓
│         ├─ identity ✓
│         ├─ whatsapp ✓
│         ├─ slack ✓
│         ├─ notion ✓
│         ├─ instagram ✓
│         ├─ tiktok ✓
│         └─ facebook ✓
├─ 18:45 - Phase 4: Optimize scraping (15 min)
│         └─ Full rewrite, multi-stage build ✓
├─ 19:00 - Phase 5: Update docker-compose.yml (15 min)
│         └─ Environment variables added ✓
├─ 19:15 - Phase 6: Testing (45 min)
│         ├─ Build services
│         ├─ Start containers
│         ├─ Verify logs
│         └─ Test endpoints
├─ 20:00 - Verification & cleanup (15 min)
│         ├─ Stability check
│         ├─ Remove backups
│         └─ Commit changes
└─ 20:15 - Complete ✅

Day 2 (Monitoring)
├─ 08:00 - Check logs from overnight
├─ 12:00 - Verify no issues
└─ 17:00 - Production confidence ✅
```

---

## File Changes Visualization

### What Changes Where

```
Repository Root
│
├── entrypoint.sh                    ⭐ NEW (180 lines)
│   ├─ Waits for PostgreSQL
│   ├─ Runs Prisma generate
│   ├─ Runs migrations
│   └─ Starts application
│
├── init-db.sql
│   └─ +3 lines: CREATE DATABASE scraping_db;
│
├── .env
│   └─ +1 line: SCRAPING_DATABASE_URL=...
│
├── docker-compose.yml
│   └─ +50 lines: Environment variables for all services
│
├── gateway/
│   └─ Dockerfile (+7 lines)
│       ├─ Add netcat-openbsd
│       ├─ Copy entrypoint.sh
│       └─ Replace CMD with ENTRYPOINT + CMD
│
├── identity/
│   └─ Dockerfile (+4 lines)
│       └─ Same as gateway (multi-stage)
│
├── whatsapp/
│   └─ Dockerfile (+7 lines)
│       └─ Same as gateway
│
├── slack/
│   └─ Dockerfile (+7 lines)
│       └─ Same as gateway
│
├── notion/
│   └─ Dockerfile (+7 lines)
│       └─ Same as gateway
│
├── instagram/
│   └─ Dockerfile (+14 lines)
│       └─ Same as gateway
│
├── tiktok/
│   └─ Dockerfile (+15 lines)
│       └─ Same as gateway
│
├── facebook/
│   └─ Dockerfile (+15 lines)
│       └─ Same as gateway
│
└── scrapping/
    └─ Dockerfile (FULL REWRITE)
        ├─ Multi-stage build: builder + runtime
        ├─ Alpine base (not Debian)
        ├─ Alpine chromium (not Debian chromium)
        ├─ Significantly smaller final image
        └─ -77% size reduction (2.05GB → 0.48GB)
```

---

## Dependency Graph

### What Must Happen In Order

```
Level 1: Database Setup
┌─────────────────────┐
│   init-db.sql       │  Creates all 9 databases
│   Create scraping_db│
└──────────┬──────────┘
           │
Level 2: Environment Configuration
           ↓
┌─────────────────────┐
│   .env              │  Adds SCRAPING_DATABASE_URL
│   .env              │  (or already has POSTGRES_* vars)
└──────────┬──────────┘
           │
Level 3: Entrypoint Script
           ↓
┌─────────────────────┐
│   entrypoint.sh     │  Created at root level
│   (new file)        │  Referenced by all Dockerfiles
└──────────┬──────────┘
           │
Level 4: Update All Dockerfiles
           ↓
┌─────────────────────────────┐
│ All 9 Dockerfiles          │
├─ gateway/Dockerfile         │
├─ identity/Dockerfile        │
├─ whatsapp/Dockerfile        │
├─ slack/Dockerfile           │
├─ notion/Dockerfile          │
├─ instagram/Dockerfile       │
├─ tiktok/Dockerfile          │
├─ facebook/Dockerfile        │
└─ scrapping/Dockerfile       │
   (Copy entrypoint.sh path)   │
   (Add ENTRYPOINT directive) │
└──────────┬──────────┘
           │
Level 5: Update docker-compose.yml
           ↓
┌─────────────────────┐
│ docker-compose.yml  │
│ Add env vars to all │
│ service definitions │
└──────────┬──────────┘
           │
Level 6: Build & Test
           ↓
┌─────────────────────┐
│ docker-compose up   │
│ Verify all services │
│ Check logs          │
│ Test endpoints      │
└─────────────────────┘
```

---

## Service Startup Flow (New)

```
User runs: docker-compose up -d
    │
    ↓
┌─────────────────────────────────┐
│ PostgreSQL starts               │
│ (init-db.sql runs)              │
│ Creates 9 databases ✓           │
└────────────┬────────────────────┘
             │
             ↓
┌─────────────────────────────────┐
│ Each Service Container Starts   │
├─────────────────────────────────┤
│                                 │
│ ENTRYPOINT: /entrypoint.sh      │
│ CMD: ["node", "dist/main"]      │
│                                 │
└────────────┬────────────────────┘
             │
             ↓
    ┌────────────────────┐
    │  entrypoint.sh     │
    └────────┬───────────┘
             │
    ┌────────┴───────────┐
    │                    │
    ↓                    ↓
 STEP 1              STEP 2
 Wait for            Generate
 PostgreSQL          Prisma
 ✓ Connected         ✓ Done
    │                    │
    └────────┬───────────┘
             │
             ↓
    ┌────────────────────┐
    │   STEP 3           │
    │ Run Migrations     │
    │ ✓ 3 applied        │
    └────────┬───────────┘
             │
             ↓
    ┌────────────────────┐
    │   STEP 4           │
    │ Start Application  │
    │ ✓ Listening 3000   │
    └────────┬───────────┘
             │
             ↓
    Service Ready ✅
    Database Synced ✅
    No Manual Steps ✅
```

---

## Size Reduction Visualization

### Scrapping Service Image Size

```
Before:
┌─────────────────────────────────────────────────────────┐
│ node:20 (full image)                    ~1.2 GB         │
├─────────────────────────────────────────────────────────┤
│ Dependencies (apt: chromium, fonts)     ~0.55 GB        │
├─────────────────────────────────────────────────────────┤
│ Node modules                            ~0.20 GB        │
├─────────────────────────────────────────────────────────┤
│ Build output                            ~0.10 GB        │
├─────────────────────────────────────────────────────────┤
│ Total Image Size                        ~ 2.05 GB       │
└─────────────────────────────────────────────────────────┘

After:
┌─────────────────────────────────────────────────────────┐
│ node:20-alpine (builder, discarded)    ~0 GB (not kept) │
├─────────────────────────────────────────────────────────┤
│ node:20-alpine (runtime)                ~0.15 GB        │
├─────────────────────────────────────────────────────────┤
│ Dependencies (apk: chromium, fonts)     ~0.08 GB        │
├─────────────────────────────────────────────────────────┤
│ Node modules (prod only)                ~0.15 GB        │
├─────────────────────────────────────────────────────────┤
│ Build output (from builder)             ~0.10 GB        │
├─────────────────────────────────────────────────────────┤
│ Total Image Size                        ~ 0.48 GB       │
└─────────────────────────────────────────────────────────┘

                ⬇️ 77% Reduction ⬇️
                1.57 GB Saved!
```

### Total System Size

```
All 9 Services Combined:

BEFORE:                              AFTER:
gateway:     ~550 MB                 gateway:     ~380 MB
identity:    ~550 MB                 identity:    ~380 MB
whatsapp:    ~550 MB                 whatsapp:    ~380 MB
slack:       ~550 MB                 slack:       ~380 MB
notion:      ~550 MB                 notion:      ~380 MB
instagram:   ~550 MB                 instagram:   ~380 MB
tiktok:      ~550 MB                 tiktok:      ~380 MB
facebook:    ~550 MB                 facebook:    ~380 MB
scrapping:   ~2,050 MB               scrapping:   ~480 MB
──────────────                       ──────────────
TOTAL:       ~6,500 MB               TOTAL:       ~3,500 MB

                 46% Total Reduction
                 3 GB Saved Per Deployment!
```

---

## Rollback Flowchart

```
Issue Detected?
    │
    ├─ YES ──→ Severity Check
    │              │
    │              ├─ Critical (services not starting)
    │              │    └─→ IMMEDIATE ROLLBACK
    │              │
    │              ├─ High (migrations failing)
    │              │    └─→ IMMEDIATE ROLLBACK
    │              │
    │              └─ Low (specific service issue)
    │                  └─→ DEBUG FIRST
    │
    └─ NO ──→ Continue Monitoring

Rollback Procedure (< 5 minutes):
    │
    ├─ 1. Stop current: docker-compose down -v
    ├─ 2. Restore backups: cp *.backup original files
    ├─ 3. Git restore:    git checkout [modified files]
    ├─ 4. Remove new file: rm entrypoint.sh
    ├─ 5. Restart:        docker-compose up -d
    └─ 6. Verify:         docker-compose ps
        
Back to Previous State ✅
```

---

## Checklist - At a Glance

```
PHASE 1: PREPARATION
├─ [ ] Read main document
├─ [ ] Create backups
└─ [ ] 5 minutes elapsed

PHASE 2: DATABASE
├─ [ ] Update init-db.sql (+3 lines)
├─ [ ] Update .env (+1 line)
└─ [ ] 5 minutes elapsed

PHASE 3: ENTRYPOINT
├─ [ ] Create entrypoint.sh (180 lines)
├─ [ ] Make executable
├─ [ ] Test syntax
└─ [ ] 10 minutes elapsed

PHASE 4: DOCKERFILES (30 minutes)
├─ [ ] gateway/Dockerfile
├─ [ ] identity/Dockerfile
├─ [ ] whatsapp/Dockerfile
├─ [ ] slack/Dockerfile
├─ [ ] notion/Dockerfile
├─ [ ] instagram/Dockerfile
├─ [ ] tiktok/Dockerfile
├─ [ ] facebook/Dockerfile
└─ [ ] scrapping/Dockerfile (FULL REWRITE)

PHASE 5: DOCKER-COMPOSE (15 minutes)
├─ [ ] Add POSTGRES_* vars to all services
├─ [ ] Add SERVICE_NAME to all services
├─ [ ] Add SCRAPING_DATABASE_URL
└─ [ ] Verify syntax

PHASE 6: TESTING (45 minutes)
├─ [ ] Build images
├─ [ ] Start containers
├─ [ ] Check PostgreSQL logs
├─ [ ] Verify all services started
├─ [ ] Check migration logs
├─ [ ] Test API endpoints
└─ [ ] 5-minute stability check

COMPLETION
├─ [ ] Remove old backups
├─ [ ] Git commit changes
└─ ✅ DONE!
```

---

## Key Commands Quick Reference

```bash
# Create backups
cp docker-compose.yml docker-compose.yml.backup
cp init-db.sql init-db.sql.backup

# Make entrypoint executable
chmod +x entrypoint.sh

# Test entrypoint syntax
bash -n entrypoint.sh

# Build all services
docker-compose build

# Start services
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs [service-name]

# Test service
curl http://localhost:3000/health

# Check database
docker-compose exec postgres psql -U postgres -l | grep _db

# Verify migrations
docker-compose logs gateway | grep migration

# Cleanup (if needed)
docker-compose down -v

# Rollback
cp *.backup originals && git checkout [files]
```

---

## Common Error - Quick Fixes

```
❌ ERROR: Can't find entrypoint.sh

FIX: Verify file exists at root:
    ls -la entrypoint.sh
    ls -la /usr/local/bin/entrypoint.sh (in container)

---

❌ ERROR: PostgreSQL connection timeout

FIX: Check PostgreSQL is running:
    docker-compose logs postgres
    docker-compose exec postgres pg_isready

---

❌ ERROR: Permission denied on entrypoint.sh

FIX: Make executable:
    chmod +x entrypoint.sh
    RUN chmod +x /usr/local/bin/entrypoint.sh (in Dockerfile)

---

❌ ERROR: Migration fails with "relation already exists"

FIX: Drop and recreate database:
    docker-compose exec postgres psql -U postgres
    DROP DATABASE gateway_db;
    docker-compose restart gateway

---

❌ ERROR: netcat-openbsd: command not found

FIX: Verify it's in apk install:
    RUN apk add --no-cache openssl netcat-openbsd

---

❌ ERROR: CRLF line ending issues (Windows)

FIX: Convert to Unix line endings:
    dos2unix entrypoint.sh
    
Or use Git:
    git config core.autocrlf true
```

---

## Success Indicators

### Logs Should Show
```
[✓ SUCCESS - gateway] PostgreSQL is ready!
[✓ SUCCESS - gateway] Prisma client generated successfully
[✓ SUCCESS - gateway] Database migrations completed successfully
[✓ SUCCESS - gateway] Startup sequence completed, launching gateway

[Nest] Listening on port 3000
```

### Commands Should Return
```bash
$ docker-compose ps
NAME                    STATUS
postgres-local          Up (healthy)
rabbitmq                Up (healthy)
gateway                 Up
identity                Up
whatsapp                Up
slack                   Up
notion                  Up
instagram               Up
tiktok                  Up
facebook                Up
scraping                Up

$ curl http://localhost:3000/health
{"status":"ok"}
```

---

**Version**: 1.0  
**Created**: 2026-04-17  
**For Team**: Use alongside main implementation documents
