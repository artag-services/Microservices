# Database Schema Audit Report

**Generated:** 2026-04-22  
**Scope:** Comparing PostgreSQL actual tables vs Prisma schema definitions across all microservices

---

## Executive Summary

| Service | Tables Synced | Enums Synced | Overall Status | Action Required |
|---------|---------------|--------------|----------------|-----------------|
| **gateway_db** | 2/10 (20%) | 2/6 (33%) | ⚠️ Incomplete | HIGH - Run Prisma migration |
| **identity_db** | 4/18 (22%) | 0/12 (0%) | ⚠️ Incomplete | HIGH - Missing AI/Message models |
| **whatsapp_db** | 9/9 (100%) | 5/5 (100%) | ✅ Fully Synced | None - OK |
| **instagram_db** | 11/11 (100%) | 5/5 (100%) | ✅ Fully Synced | None - OK |
| **notion_db** | 0/4 (0%) | 0/1 (0%) | 🔴 CRITICAL | CRITICAL - Database empty, run migrations |
| **slack_db** | 0/4 (0%) | 0/1 (0%) | 🔴 CRITICAL | CRITICAL - Database empty, run migrations |
| **facebook_db** | 1/4 (25%) | 1/1 (100%) | ⚠️ Incomplete | MEDIUM - Missing legacy tables |
| **tiktok_db** | 1/4 (25%) | 1/1 (100%) | ⚠️ Incomplete | MEDIUM - Missing legacy tables |
| **scraping_db** | -/- | -/- | ❌ No Schema | N/A - No Prisma schema exists |

---

## Detailed Analysis by Service

### 🔴 CRITICAL PRIORITY

#### **notion_db** - COMPLETELY EMPTY
```
Expected: 4 tables (days_off, inventory, n8n_vectors, NotionOperation)
Actual:   0 tables
Missing:  100% of tables
```

**Issue:** Database exists but is completely empty. No tables have been created.

**Expected Schema:**
- `days_off` (legacy reference table)
- `inventory` (legacy reference table)
- `n8n_vectors` (legacy reference table)
- `NotionOperation` (service-specific)
- Enum: `NotionOpStatus`

**Impact:** 🔴 CRITICAL - Notion service cannot store operations, integration is broken.

**Fix:**
```bash
cd notion
npm run prisma:migrate
```

---

#### **slack_db** - COMPLETELY EMPTY
```
Expected: 4 tables (days_off, inventory, n8n_vectors, SlackMessage)
Actual:   0 tables
Missing:  100% of tables
```

**Issue:** Database exists but is completely empty. No tables have been created.

**Expected Schema:**
- `days_off` (legacy reference table)
- `inventory` (legacy reference table)
- `n8n_vectors` (legacy reference table)
- `SlackMessage` (service-specific)
- Enum: `SlackMessageStatus`

**Impact:** 🔴 CRITICAL - Slack service cannot send or store messages.

**Fix:**
```bash
cd slack
npm run prisma:migrate
```

---

#### **scraping_db** - NO SCHEMA FILE
```
Status: Scraping service has NO prisma/schema.prisma file
```

**Issue:** Cannot validate database structure - unknown if service uses Prisma at all.

**Status:** Database is empty (no tables/enums).

**Impact:** ❌ UNKNOWN - Unable to determine if this is expected or a problem.

**Next Steps:**
1. Check if scraping service uses Prisma ORM
2. If yes, add `prisma/schema.prisma` file
3. If no, document the ORM used (TypeORM, MikroORM, etc.)

---

### 🟠 HIGH PRIORITY

#### **gateway_db** - MAJOR TABLES MISSING
```
Expected: 10 tables, 6 enums
Actual:   2 tables, 2 enums
Missing:  8 tables (80%), 4 enums (67%)
```

**Present Tables:**
- ✅ `Message`
- ✅ `IgMessage`

**Present Enums:**
- ✅ `MessageStatus`
- ✅ `IgMessageStatus`

**Missing Tables (80%):**
- ❌ `Conversation` (core feature)
- ❌ `ConversationMessage` (core feature)
- ❌ `ConversationAIResponse` (core feature)
- ❌ `N8NRateLimit` (rate limiting)
- ❌ `User` (user management)
- ❌ `UserIdentity` (identity resolution)
- ❌ `AIResponse` (AI audit trail)
- ❌ `AIResponseChunk` (chunked responses)

**Missing Enums (67%):**
- ❌ `ConvStatus`
- ❌ `AIResponseStatus`
- ❌ `ChunkStatus`
- ❌ `MessageSender`

**Schema File:** `gateway/prisma/schema.prisma` (exists, but not fully migrated)

**Impact:** 🟠 HIGH - Conversation system is completely non-functional. AI response tracking not working.

**Fix:**
```bash
cd gateway
npm run prisma:migrate
```

---

#### **identity_db** - CORE AI/MESSAGE MODELS MISSING
```
Expected: 18 tables, 12 enums
Actual:   4 tables, 0 enums
Missing:  14 tables (78%), 12 enums (100%)
```

**Present Tables:**
- ✅ `User` (identity service core)
- ✅ `UserIdentity` (channel identities)
- ✅ `UserContact` (contact info)
- ✅ `NameHistory` (audit trail)

**Present Enums:**
- ❌ NONE (0%)

**Missing Tables (78%):**
The identity_db schema includes models from OTHER services:
- ❌ `AIResponse`, `AIResponseChunk`, `N8NRateLimit` (AI models)
- ❌ `Message`, `WaMessage`, `SlackMessage` (Message models)
- ❌ `NotionOperation`, `IgMessage`, `TikTokPost`, `FbMessage`, `EmailMessage` (Service-specific)
- ❌ `Conversation`, `ConversationMessage`, `ConversationAIResponse` (Conversation models)

**⚠️ Schema Design Issue Detected:**
The `identity_db` schema contains models from multiple other services. This is NOT a standard microservice pattern and indicates a schema design problem. These models should exist only in their respective service databases, NOT in identity_db.

**Schema File:** `identity/prisma/schema.prisma` (exists but contains non-identity models)

**Impact:** 🟠 HIGH - Identity service only has its core 4 tables. The extra models in the schema are architectural issues.

**Fix:**
```bash
# First, remove foreign service models from identity schema
# Then run migration for the 4 core tables only
cd identity
npm run prisma:migrate
```

**Recommendation:** Review and fix the identity_db schema - it should only contain:
- `User`
- `UserIdentity`
- `UserContact`
- `NameHistory`

---

### 🟡 MEDIUM PRIORITY

#### **facebook_db** - MISSING LEGACY REFERENCE TABLES
```
Expected: 4 tables, 1 enum
Actual:   1 table, 1 enum
Missing:  3 legacy reference tables (75% legacy missing)
```

**Present:**
- ✅ `FbMessage`
- ✅ Enum: `FbMessageStatus`

**Missing Legacy Reference Tables:**
- ❌ `days_off`
- ❌ `inventory`
- ❌ `n8n_vectors`

**Schema File:** `facebook/prisma/schema.prisma` (has legacy table definitions)

**Impact:** 🟡 MEDIUM - Service works for its primary function (FbMessage), but legacy reference tables are missing. These are marked as "Pre-existing tables (never drop)" but don't exist.

**Fix:**
```bash
cd facebook
npm run prisma:migrate
# OR manually create legacy tables if they exist in another database
```

---

#### **tiktok_db** - MISSING LEGACY REFERENCE TABLES
```
Expected: 4 tables, 1 enum
Actual:   1 table, 1 enum
Missing:  3 legacy reference tables (75% legacy missing)
```

**Present:**
- ✅ `TikTokPost`
- ✅ Enum: `TikTokPostStatus`

**Missing Legacy Reference Tables:**
- ❌ `days_off`
- ❌ `inventory`
- ❌ `n8n_vectors`

**Schema File:** `tiktok/prisma/schema.prisma` (has legacy table definitions)

**Impact:** 🟡 MEDIUM - Service works for its primary function (TikTokPost), but legacy reference tables are missing. These are marked as "Pre-existing tables (never drop)" but don't exist.

**Fix:**
```bash
cd tiktok
npm run prisma:migrate
```

---

### ✅ FULLY SYNCED (No Action Required)

#### **whatsapp_db** - PERFECT SYNC
```
Expected: 9 tables, 5 enums
Actual:   9 tables, 5 enums
Status:   100% synchronized
```

**All Tables Present:**
- ✅ `WaMessage`
- ✅ `User`
- ✅ `UserIdentity`
- ✅ `AIResponse`
- ✅ `AIResponseChunk`
- ✅ `N8NRateLimit`
- ✅ `Conversation`
- ✅ `ConversationMessage`
- ✅ `ConversationAIResponse`

**All Enums Present:**
- ✅ `WaMessageStatus`
- ✅ `AIResponseStatus`
- ✅ `ChunkStatus`
- ✅ `ConvStatus`
- ✅ `MessageSender`

**Status:** ✅ **PRODUCTION-READY** - No action needed

---

#### **instagram_db** - PERFECT SYNC
```
Expected: 11 tables, 5 enums
Actual:   11 tables, 5 enums
Status:   100% synchronized
```

**All Tables Present:**
- ✅ `IgMessage`
- ✅ `User`
- ✅ `UserIdentity`
- ✅ `UserContact`
- ✅ `NameHistory`
- ✅ `AIResponse`
- ✅ `AIResponseChunk`
- ✅ `N8NRateLimit`
- ✅ `Conversation`
- ✅ `ConversationMessage`
- ✅ `ConversationAIResponse`

**All Enums Present:**
- ✅ `IgMessageStatus`
- ✅ `AIResponseStatus`
- ✅ `ChunkStatus`
- ✅ `ConvStatus`
- ✅ `MessageSender`

**Status:** ✅ **PRODUCTION-READY** - No action needed

---

## Action Items by Priority

### 🔴 CRITICAL (Do Immediately)

1. **notion_db Migration**
   ```bash
   cd notion
   npm run prisma:migrate
   npm run prisma:generate
   ```

2. **slack_db Migration**
   ```bash
   cd slack
   npm run prisma:migrate
   npm run prisma:generate
   ```

3. **Investigate scraping_db**
   - Determine if scraping service uses Prisma
   - Add schema file if needed
   - Create database tables

### 🟠 HIGH (Do Soon)

4. **gateway_db Migration**
   ```bash
   cd gateway
   npm run prisma:migrate
   npm run prisma:generate
   ```

5. **identity_db Schema Review**
   - Review why identity_db contains models from other services
   - Fix schema architecture
   - Run migration for core identity tables only

### 🟡 MEDIUM (Schedule)

6. **facebook_db Migration**
   ```bash
   cd facebook
   npm run prisma:migrate
   npm run prisma:generate
   ```

7. **tiktok_db Migration**
   ```bash
   cd tiktok
   npm run prisma:migrate
   npm run prisma:generate
   ```

---

## Observations & Recommendations

### 1. **Architectural Concern: identity_db Schema**
The `identity_db` schema contains models from all other services (Message, WaMessage, IgMessage, AIResponse, Conversation, etc.). This is unusual for a microservice architecture where:
- Each service should own its database
- Each service should own its models
- Cross-service queries should go through APIs, not shared databases

**Recommendation:** 
- Review if this is intentional (shared database pattern)
- If not, separate the schemas into their respective service databases
- Consider if identity_db should be a reference database only

### 2. **Legacy Reference Tables Pattern**
Multiple services have "legacy" reference tables (`days_off`, `inventory`, `n8n_vectors`) that are marked "never drop" but:
- They exist inconsistently across services
- Some services have them in schema but not in database
- Unclear if these are truly needed or legacy cruft

**Recommendation:**
- Verify if these tables are actually used
- If used, ensure they're migrated consistently
- If not used, remove from schemas to reduce clutter

### 3. **Scraping Service Mystery**
The scraping service has no Prisma schema file at all. 

**Recommendation:**
- Clarify if scraping uses Prisma or different ORM
- Add appropriate schema files
- Document decision

### 4. **Migration Strategy**
Services are in various states of migration:
- WhatsApp & Instagram: Fully migrated ✅
- Others: Partially or not migrated

**Recommendation:**
- Create a migration timeline
- Execute in order of criticality (notion, slack first)
- Verify each migration in staging before production

---

## Database Connection Strings (from .env)

```
gateway_db:     postgresql://postgres:postgres123@postgres:5432/gateway_db
identity_db:    postgresql://postgres:postgres123@postgres:5432/identity_db
whatsapp_db:    postgresql://postgres:postgres123@postgres:5432/whatsapp_db
instagram_db:   postgresql://postgres:postgres123@postgres:5432/instagram_db
notion_db:      postgresql://postgres:postgres123@postgres:5432/notion_db
slack_db:       postgresql://postgres:postgres123@postgres:5432/slack_db
facebook_db:    postgresql://postgres:postgres123@postgres:5432/facebook_db
tiktok_db:      postgresql://postgres:postgres123@postgres:5432/tiktok_db
scraping_db:    postgresql://postgres:postgres123@postgres:5432/scraping_db
```

---

## How to Run Migrations

For each service that needs migration:

```bash
# 1. Navigate to service
cd <service>

# 2. Generate Prisma client
npm run prisma:generate

# 3. Run migrations
npm run prisma:migrate

# 4. Verify in Prisma Studio
npm run prisma:studio
```

---

**Report Generated:** 2026-04-22  
**Generated By:** OpenCode Database Audit  
**Status:** Ready for action
