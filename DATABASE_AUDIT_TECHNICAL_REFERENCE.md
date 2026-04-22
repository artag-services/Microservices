# Database Schema Audit - Technical Reference

**Date:** 2026-04-22  
**Purpose:** Detailed mapping of database state vs schema definitions

---

## Quick Reference Table

| Service | Schema Status | DB Status | Tables | Enums | Action |
|---------|---------------|-----------|--------|-------|--------|
| gateway_db | ✓ Defined | ⚠️ Partial | 2/10 | 2/6 | Run `prisma:migrate` |
| identity_db | ✓ Defined | ⚠️ Partial | 4/18 | 0/12 | Review schema + migrate |
| whatsapp_db | ✓ Defined | ✓ Complete | 9/9 | 5/5 | None |
| instagram_db | ✓ Defined | ✓ Complete | 11/11 | 5/5 | None |
| notion_db | ✓ Defined | ✗ Empty | 0/4 | 0/1 | Run `prisma:migrate` |
| slack_db | ✓ Defined | ✗ Empty | 0/4 | 0/1 | Run `prisma:migrate` |
| facebook_db | ✓ Defined | ⚠️ Partial | 1/4 | 1/1 | Run `prisma:migrate` |
| tiktok_db | ✓ Defined | ⚠️ Partial | 1/4 | 1/1 | Run `prisma:migrate` |
| scraping_db | ✗ Missing | ✗ Empty | 0/? | 0/? | Add schema file |

---

## Service-by-Service Details

### 1. GATEWAY_DB

**Prisma Schema Location:** `gateway/prisma/schema.prisma`

**Expected Models:**
```
- Message (with MessageStatus enum)
- IgMessage (with IgMessageStatus enum)
- Conversation (with ConvStatus enum)
- ConversationMessage (with MessageSender enum)
- ConversationAIResponse (with AIResponseStatus, ChunkStatus enums)
- User
- UserIdentity
- AIResponse
- AIResponseChunk
- N8NRateLimit
```

**Database Reality:**
```
Tables in gateway_db:
- Message ✓
- IgMessage ✓

Enums in gateway_db:
- MessageStatus ✓
- IgMessageStatus ✓

Missing Tables:
- Conversation ✗
- ConversationMessage ✗
- ConversationAIResponse ✗
- User ✗
- UserIdentity ✗
- AIResponse ✗
- AIResponseChunk ✗
- N8NRateLimit ✗

Missing Enums:
- ConvStatus ✗
- AIResponseStatus ✗
- ChunkStatus ✗
- MessageSender ✗
```

**Migration Command:**
```bash
cd gateway
npm run prisma:generate
npm run prisma:migrate
```

**Impact:** Conversation system not working. Cannot track AI responses. User management broken.

---

### 2. IDENTITY_DB

**Prisma Schema Location:** `identity/prisma/schema.prisma`

**⚠️ ARCHITECTURAL ISSUE:** This schema contains models from OTHER services!

**Local Identity Models (Expected):**
```
- User ✓ (actually in DB)
- UserIdentity ✓ (actually in DB)
- UserContact ✓ (actually in DB)
- NameHistory ✓ (actually in DB)
```

**Foreign Models in identity_db Schema (NOT in DB):**
```
- Message (from gateway)
- WaMessage (from whatsapp)
- SlackMessage (from slack)
- NotionOperation (from notion)
- IgMessage (from instagram)
- TikTokPost (from tiktok)
- FbMessage (from facebook)
- EmailMessage (from email service)
- AIResponse (from whatsapp/instagram)
- AIResponseChunk (from whatsapp/instagram)
- N8NRateLimit (from whatsapp/instagram)
- Conversation (from whatsapp/instagram)
- ConversationMessage (from whatsapp/instagram)
- ConversationAIResponse (from whatsapp/instagram)
```

**Why This Is Wrong:**
In a microservices architecture:
1. Each service owns its database
2. Each service owns its models
3. Services communicate via APIs, not shared databases
4. Shared database = tight coupling = architectural debt

**Current State:**
- Only 4 identity-core tables exist: User, UserIdentity, UserContact, NameHistory
- 0 foreign tables exist in database
- Schema defines both, but nothing's migrated

**Recommendation:**
1. Create identity-only schema with just the 4 core tables
2. Run `prisma:migrate` for those
3. Remove all foreign models from this schema
4. Each service should use its own database

**Temporary Fix:**
```bash
# Just migrate the identity core tables
cd identity
npm run prisma:generate
npm run prisma:migrate
```

---

### 3. WHATSAPP_DB

**Prisma Schema Location:** `whatsapp/prisma/schema.prisma`

**Status:** ✅ **FULLY SYNCED - PRODUCTION READY**

**All Expected Tables Present:**
```
✓ WaMessage
✓ User
✓ UserIdentity
✓ AIResponse
✓ AIResponseChunk
✓ N8NRateLimit
✓ Conversation
✓ ConversationMessage
✓ ConversationAIResponse
```

**All Expected Enums Present:**
```
✓ WaMessageStatus
✓ AIResponseStatus
✓ ChunkStatus
✓ ConvStatus
✓ MessageSender
```

**No Action Required:** Everything is correctly migrated and synchronized.

---

### 4. INSTAGRAM_DB

**Prisma Schema Location:** `instagram/prisma/schema.prisma`

**Status:** ✅ **FULLY SYNCED - PRODUCTION READY**

**All Expected Tables Present:**
```
✓ IgMessage
✓ User
✓ UserIdentity
✓ UserContact
✓ NameHistory
✓ AIResponse
✓ AIResponseChunk
✓ N8NRateLimit
✓ Conversation
✓ ConversationMessage
✓ ConversationAIResponse
```

**All Expected Enums Present:**
```
✓ IgMessageStatus
✓ AIResponseStatus
✓ ChunkStatus
✓ ConvStatus
✓ MessageSender
```

**No Action Required:** Everything is correctly migrated and synchronized.

---

### 5. NOTION_DB

**Prisma Schema Location:** `notion/prisma/schema.prisma`

**Status:** 🔴 **CRITICAL - COMPLETELY EMPTY**

**Expected Models:**
```
- days_off (legacy reference)
- inventory (legacy reference)
- n8n_vectors (legacy reference)
- NotionOperation (service-specific)
```

**Expected Enums:**
```
- NotionOpStatus
```

**Actual Database State:**
```
✗ No tables exist
✗ No enums exist
✗ Database completely empty
```

**Why This Happened:**
Either migrations were never run, or database was truncated.

**Fix:**
```bash
cd notion
npm run prisma:generate
npm run prisma:migrate
```

**Verify:**
```bash
npm run prisma:studio
# Should show: days_off, inventory, n8n_vectors, NotionOperation
```

**Impact:** CRITICAL - Notion service cannot function without its database.

---

### 6. SLACK_DB

**Prisma Schema Location:** `slack/prisma/schema.prisma`

**Status:** 🔴 **CRITICAL - COMPLETELY EMPTY**

**Expected Models:**
```
- days_off (legacy reference)
- inventory (legacy reference)
- n8n_vectors (legacy reference)
- SlackMessage (service-specific)
```

**Expected Enums:**
```
- SlackMessageStatus
```

**Actual Database State:**
```
✗ No tables exist
✗ No enums exist
✗ Database completely empty
```

**Fix:**
```bash
cd slack
npm run prisma:generate
npm run prisma:migrate
```

**Verify:**
```bash
npm run prisma:studio
# Should show: days_off, inventory, n8n_vectors, SlackMessage
```

**Impact:** CRITICAL - Slack service cannot function without its database.

---

### 7. FACEBOOK_DB

**Prisma Schema Location:** `facebook/prisma/schema.prisma`

**Status:** ⚠️ **INCOMPLETE - PRIMARY TABLE EXISTS, LEGACY MISSING**

**Expected Models:**
```
- days_off (legacy reference)
- inventory (legacy reference)
- n8n_vectors (legacy reference)
- FbMessage (service-specific)
```

**Actual Database State:**
```
✓ FbMessage exists
✗ days_off missing
✗ inventory missing
✗ n8n_vectors missing
✓ FbMessageStatus enum exists
```

**Current Functionality:**
- Facebook messaging works (primary function)
- Legacy reference tables unavailable

**Fix:**
```bash
cd facebook
npm run prisma:migrate
# This will create missing legacy tables
```

**Note:** The schema marks these as "Pre-existing tables (never drop)" but they don't exist. Either:
1. They were never created, or
2. They were deleted, or
3. They should be created from a different source

---

### 8. TIKTOK_DB

**Prisma Schema Location:** `tiktok/prisma/schema.prisma`

**Status:** ⚠️ **INCOMPLETE - PRIMARY TABLE EXISTS, LEGACY MISSING**

**Expected Models:**
```
- days_off (legacy reference)
- inventory (legacy reference)
- n8n_vectors (legacy reference)
- TikTokPost (service-specific)
```

**Actual Database State:**
```
✓ TikTokPost exists
✗ days_off missing
✗ inventory missing
✗ n8n_vectors missing
✓ TikTokPostStatus enum exists
```

**Current Functionality:**
- TikTok posting works (primary function)
- Legacy reference tables unavailable

**Fix:**
```bash
cd tiktok
npm run prisma:migrate
# This will create missing legacy tables
```

---

### 9. SCRAPING_DB

**Prisma Schema Location:** ❌ **DOES NOT EXIST**

**Status:** ❌ **NO SCHEMA FILE - UNKNOWN STATE**

**Database Reality:**
```
✗ No tables
✗ No enums
✗ Database completely empty
```

**Questions to Resolve:**
1. Does scraping service use Prisma ORM?
2. If yes, where is the schema file?
3. If no, what ORM does it use (TypeORM, MikroORM, Sequelize, raw SQL)?

**Investigation Steps:**
```bash
# 1. Check scraping service structure
cd scrapping
ls -la

# 2. Check package.json for ORM
grep -E "@prisma|typeorm|mikro|sequelize" package.json

# 3. Check service initialization
grep -r "prisma\|database\|orm" src/ | head -20

# 4. Check if prisma directory exists
ls -la prisma/ 2>/dev/null || echo "No prisma directory"
```

**Possible Scenarios:**

**Scenario A: Scraping uses Prisma**
```bash
# Initialize Prisma
cd scrapping
npm install @prisma/client
npx prisma init

# Create schema.prisma based on service needs
# Then run migration
npm run prisma:generate
npm run prisma:migrate
```

**Scenario B: Scraping uses Different ORM**
- Document which ORM in README
- Ensure database tables are created appropriately
- Update architecture docs

**Scenario C: Scraping Doesn't Use Database**
- Document this decision
- Verify this is intentional
- If data persistence needed, add appropriate database layer

---

## Legacy Tables Investigation

Three services have "Pre-existing tables (never drop)" in their schemas:
- `days_off` - employee vacation/sick days
- `inventory` - product inventory
- `n8n_vectors` - vector embeddings for n8n

**Current State:**
| Service | days_off | inventory | n8n_vectors |
|---------|----------|-----------|------------|
| gateway | - | - | - |
| identity | - | - | - |
| whatsapp | - | - | - |
| instagram | - | - | - |
| notion | Missing | Missing | Missing |
| slack | Missing | Missing | Missing |
| facebook | Missing | Missing | Missing |
| tiktok | Missing | Missing | Missing |

**Where These Should Live:**
These appear to be reference tables that should exist in ALL databases or NONE. They're marked "pre-existing" suggesting they came from a previous system.

**Decision Needed:**
1. Are these tables actually used?
2. Should they be in all services or migrated to a reference database?
3. If used, restore from backup or recreate
4. If not used, remove from all schemas

---

## Migration Checklist

### CRITICAL (Week 1)
- [ ] Notion: `npm run prisma:migrate`
- [ ] Slack: `npm run prisma:migrate`
- [ ] Investigate Scraping service

### HIGH (Week 1-2)
- [ ] Gateway: `npm run prisma:migrate`
- [ ] Identity: Review & fix schema architecture
- [ ] Identity: `npm run prisma:migrate` (core tables only)

### MEDIUM (Week 2-3)
- [ ] Facebook: `npm run prisma:migrate`
- [ ] TikTok: `npm run prisma:migrate`
- [ ] WhatsApp: Verify (no changes needed)
- [ ] Instagram: Verify (no changes needed)

### VERIFICATION (Week 3)
- [ ] Test all services in staging
- [ ] Run integration tests
- [ ] Verify data integrity
- [ ] Document any data loss or issues

---

## Prisma Commands Reference

```bash
# Generate Prisma client from schema
npm run prisma:generate

# Run pending migrations
npm run prisma:migrate

# Interactive Prisma migration
npm run prisma:migrate -- --name <migration_name>

# Open database viewer
npm run prisma:studio

# Introspect existing database
npx prisma db pull

# Reset database (destructive!)
npm run prisma:reset

# View migration status
npx prisma migrate status

# Create migration without applying
npx prisma migrate dev --create-only
```

---

## Connection Strings

All services use Neon PostgreSQL with connection pooling:

```
Protocol:  postgresql://
User:      postgres
Pass:      postgres123
Host:      postgres (Docker) or neon host (Production)
Port:      5432
SSL:       disable (Local) or required (Production)

Format:    postgresql://user:pass@host:port/database?schema=public&sslmode=disable
```

**Local Databases:**
```
gateway_db:    postgresql://postgres:postgres123@postgres:5432/gateway_db?schema=public&sslmode=disable
identity_db:   postgresql://postgres:postgres123@postgres:5432/identity_db?schema=public&sslmode=disable
whatsapp_db:   postgresql://postgres:postgres123@postgres:5432/whatsapp_db?schema=public&sslmode=disable
instagram_db:  postgresql://postgres:postgres123@postgres:5432/instagram_db?schema=public&sslmode=disable
notion_db:     postgresql://postgres:postgres123@postgres:5432/notion_db?schema=public&sslmode=disable
slack_db:      postgresql://postgres:postgres123@postgres:5432/slack_db?schema=public&sslmode=disable
facebook_db:   postgresql://postgres:postgres123@postgres:5432/facebook_db?schema=public&sslmode=disable
tiktok_db:     postgresql://postgres:postgres123@postgres:5432/tiktok_db?schema=public&sslmode=disable
scraping_db:   postgresql://postgres:postgres123@postgres:5432/scraping_db?schema=public&sslmode=disable
```

---

## Troubleshooting

### Problem: "No schema file found"
```bash
# Check if file exists
ls -la <service>/prisma/schema.prisma

# If missing, initialize Prisma
cd <service>
npx prisma init
```

### Problem: "Migration pending"
```bash
# See pending migrations
npx prisma migrate status

# Apply migrations
npm run prisma:migrate
```

### Problem: "Prisma client out of sync"
```bash
# Regenerate client
npm run prisma:generate
```

### Problem: "Column does not exist"
```bash
# Introspect database to refresh schema
npx prisma db pull

# Then regenerate
npm run prisma:generate
```

---

## Performance Notes

- All services use indexes on common query fields
- WhatsApp & Instagram have Conversation querying (complex queries on status + lastMessageAt)
- Gateway has minimal indexes (legacy data)
- Rate limiting tables use composite unique constraints for efficiency

---

**Report Version:** 1.0  
**Last Updated:** 2026-04-22  
**Maintained By:** OpenCode Database Audit System
