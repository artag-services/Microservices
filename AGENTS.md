# Agents Guide

## Repository Structure
This is a **microservices composition repository** using Git submodules, not a traditional monorepo.

**Services** (each a separate git submodule):
- `gateway` (port 3000) – API Gateway, RabbitMQ orchestration
- `identity` (port 3010) – User identity resolution
- `whatsapp` (port 3001) – Meta WhatsApp Cloud API integration
- `slack` (port 3002) – Slack Bot integration
- `notion` (port 3003) – Notion API integration
- `instagram` (port 3004) – Meta Instagram Graph API integration
- `tiktok` (port 3005) – TikTok for Developers integration
- `facebook` (port 3006) – Meta Messenger Platform integration
- `scrapping` (port 3008) – Puppeteer-based web scraping with extensible notification adapters

**Infrastructure**: RabbitMQ (message broker), Neon PostgreSQL (one connection per service)

## Cloning & Initialization
```bash
git clone <repo-url>
git submodule update --init --recursive
```
Submodules are independent git repos; use `git submodule foreach` for batch operations across all services.

## Environment Configuration
- Single `.env` file at repository root controls all services
- Each service reads: `<SERVICE>_PORT`, `<SERVICE>_DATABASE_URL`, service-specific API tokens
- Shared: `RABBITMQ_URL`, `RABBITMQ_EXCHANGE`, `RABBITMQ_USER`, `RABBITMQ_PASS`
- **Warning**: `.env` contains demo credentials and real API tokens – do NOT commit with secrets

## Local Development

### Start Full System
```bash
docker-compose up
```
Starts RabbitMQ (port 5672, management UI 15672) + all services, waits for RabbitMQ health check.

### Per-Service Commands
All services use NestJS. Use `workdir` parameter when running commands:

```bash
# Watch mode (live reload)
npm run start:dev

# Build production
npm run build

# Lint & fix
npm run lint

# Prisma ORM (each service has own schema)
npm run prisma:generate    # Regenerate client
npm run prisma:migrate     # Run pending migrations
npm run prisma:studio      # Open Prisma Studio (local DB viewer)
```

### Testing (Scraping Service Only)
```bash
# In scrapping/ directory
npm test                # Run unit tests
npm run test:watch     # Watch mode
npm run test:e2e       # E2E tests (requires services running)
```

## Key Architecture Details

### RabbitMQ Integration
- **Exchange**: `channels` (configurable via `RABBITMQ_EXCHANGE`)
- **Task Queues**: 
  - `scraping.task` – Scraping service consumes here
  - `whatsapp_direct_messages` – Scraping sends notifications here
- All services depend on RabbitMQ health check before starting (see docker-compose.yml)

### Database & Migrations
- Each service has separate PostgreSQL database connection (via `*_DATABASE_URL`)
- Each has own `prisma/` directory with `schema.prisma` and migration files
- Migrations run automatically in Dockerfile: `RUN pnpm prisma:generate && pnpm build`
- To add migration: `npm run prisma:migrate` (runs pending migrations to database)

### Package Manager
- Uses `pnpm`, not npm/yarn
- Dockerfiles: `RUN npm install -g pnpm && pnpm install --frozen-lockfile`
- Lockfile: `pnpm-lock.yaml` (commit this, not `package-lock.json`)

### Scraping Service Specifics
- **Browser Pool**: Configurable via `PUPPETEER_MAX_POOL_SIZE` (default 5)
- **Timeout**: `PUPPETEER_TIMEOUT` (default 30000ms)
- **Rate Limiting**: `RATE_LIMIT_DAILY` + `RATE_LIMIT_WINDOW_HOURS` prevent abuse
- **Adapter Pattern**: Extensible notification system (Email, Slack, Notion, Discord, etc.)
  - Adapters implement `NotificationAdapter` interface
  - Auto-discovered in `notifications.module.ts`
  - Usage: `notificationService.send(adapterName, userId, message)`
- **Puppeteer Plugins**: Uses stealth mode (`puppeteer-extra-plugin-stealth`) + resource blocking

### CQRS / Sync Service (Query Side)

**Problem:** All services use fire-and-forget pattern. The frontend has no unified place to query cross-service data (e.g., "show all conversations for a user across WhatsApp + Instagram + Messenger").

**Solution:** CQRS with MongoDB as the read model.

```
WRITE SIDE (existing)           READ SIDE (new)
┌──────────┐                    ┌──────────────────┐
│ WhatsApp │──data.*.event──→   │   Sync Service   │
│ Instagram│──data.*.event──→   │   (port 3012)    │
│ Identity │──data.*.event──→   │   CQRS Read      │
│ Scrapping│──data.*.event──→   │   NestJS + Mongoose
│ Slack    │──data.*.event──→   └────────┬─────────┘
│ ...      │                              │ escribe
└──────────┘                              ▼
                                    ┌──────────┐
                                    │ MongoDB  │
                                    │ Read     │
                                    │ Model    │
                                    └────┬─────┘
                                         │ consulta (HTTPS)
                                         ▼
                                    ┌──────────┐
                                    │ Gateway  │
                                    │ GET /v1/ │
                                    │ query/*  │
                                    └──────────┘
```

**RabbitMQ Event Contract (data.* events):**
Every service that persists data MUST publish an event when data changes. Sync-service binds a single queue (`sync.data.all`) to pattern `data.#` and dispatches per routing key.

| Routing Key | Producer | Sync target | Notes |
|---|---|---|---|
| `data.identity.user.created` | identity | UnifiedUser (create) | First time a User appears (any channel). |
| `data.identity.user.linked` | identity | UnifiedUser (upsert + merge identities[]) | Emitted on every resolveIdentity AND post-merge for each reparented identity. |
| `data.identity.user.deleted` | identity | UnifiedUser (tombstone) | `reason: 'soft-delete' \| 'merged'`; on merge carries `mergedInto`. |
| `data.whatsapp.conversation.created` | whatsapp | UnifiedConversation (upsert snapshot) | Emitted on create AND on every ai-toggle / agent-assign (re-emits full snapshot). |
| `data.whatsapp.message.received` | whatsapp | UnifiedMessage (sender=USER) | One per incoming user message. |
| `data.instagram.conversation.created` | instagram | UnifiedConversation | Same pattern as whatsapp. |
| `data.instagram.message.received` | instagram | UnifiedMessage (sender=USER) | |
| `data.slack.message.sent` | slack | UnifiedMessage (sender=BOT, channel=slack) | Emitted on every chat.postMessage (success + failure). No conversation server-side. |
| `data.scraping.task.created` | scrapping | ScrapingTaskSummary (status=queued) | |
| `data.scraping.task.started` | scrapping | ScrapingTaskSummary (status=started) | |
| `data.scraping.task.completed` | scrapping | ScrapingTaskSummary (status=completed) | Includes `title` (from result.data), `durationMs`, `notionPageUrl`. |
| `data.scraping.task.failed` | scrapping | ScrapingTaskSummary (status=failed) | Same projector as completed; routes on status field. |
| `data.email.message.sent` | email | UnifiedEmail (direction=outbound, upsert by emailId) | Re-emitted on EVERY status change (sent/delivered/bounced/opened/clicked/complained/failed) — sync layers fields onto the same doc. |
| `data.email.message.received` | email | UnifiedEmail (direction=inbound) | One per inbound; re-emitted only on identity backfill. |
| `data.agent.conversation.created` | agent | UnifiedConversation (channel=agent) | Fires once per chat — uses `wasCreated` detection via createdAt===updatedAt. |
| `data.agent.conversation.deleted` | agent | UnifiedConversation (status=DELETED) | Soft delete; QueryService filters. |
| `data.agent.message.received` | agent | UnifiedMessage (sender=USER) | User turn. |
| `data.agent.message.sent` | agent | UnifiedMessage (sender=BOT) | **Only final assistant replies** — intermediate tool-loop iterations are NOT projected. |
| `data.notion.operation.created` | notion | — (future: NotionOperationRecord) | Operation persisted; status=PENDING. No sync projector yet. |
| `data.notion.operation.completed` | notion | — (future: NotionOperationRecord) | Operation SUCCESS; carries `notionId`. No sync projector yet. |
| `data.notion.operation.failed` | notion | — (future: NotionOperationRecord) | Operation FAILED; carries `error`. No sync projector yet. |

**Producer-side rule:** emit AFTER your Postgres write has committed. Build the payload from the persisted row, not the inbound DTO — the row reflects any in-flight transformations (trust-score name updates, status changes, etc.).

**Idempotency:** all projectors upsert by id (`userId`, `conversationId`, `messageId`, `emailId`, `taskId`). Replaying events is safe. Counters that should NOT inflate on replay (e.g. `messageCount`) only bump on first-time create.

**Sync Service responsibilities:**
1. Listen to all `data.*` events from RabbitMQ
2. Transform + merge data into denormalized MongoDB documents
3. Expose REST API consumed ONLY by the Gateway (no external HTTP)

**Gateway query endpoints (future):**
```
GET /v1/query/users/:userId → unified user profile (cross-channel)
GET /v1/query/users/:userId/conversations → all conversations
GET /v1/query/conversations/:id/messages → messages in a conversation
GET /v1/query/search?q=... → full-text search across channels
```

**MongoDB Infrastructure:**
- Image: `mongo:7`
- Container: `mongo`
- Port: 27017
- Volumes: `mongo_data:/data/db`
- Credentials: configured via `.env` (`MONGO_USER`, `MONGO_PASS`, `MONGO_URI`)

## Common Workflows

### Add New Feature to One Service
```bash
cd <service>
npm run start:dev        # Start watch mode
# Edit code...
npm run lint             # Check before commit
npm run build            # Test build
```

### Update a Submodule Remote
```bash
git submodule sync
git submodule update --remote
```

### Run All Tests (Future)
Scripts like `npm test` exist in scrapping service; others use placeholder. Extend as needed.

### Database Schema Changes
```bash
cd <service>
# Edit prisma/schema.prisma
npm run prisma:migrate  # Creates + applies migration
```

### Docker Build & Push
Each service can be built independently:
```bash
docker build -f <service>/Dockerfile -t <registry>/<service>:<tag> .
```

## Development Gotchas

1. **Submodules are separate repos** – Changes in submodule directories won't auto-commit to parent. Use:
   ```bash
   cd <service>
   git add .
   git commit -m "..."
   git push origin main
   cd ..
   git add <service>
   git commit -m "chore: bump <service> ref"
   ```

2. **Environment isolation** – Changing `.env` affects all running services; restart with `docker-compose restart`

3. **Prisma schema per service** – Don't share schema files; each service owns its database models

4. **RabbitMQ dependency** – Services won't start without RabbitMQ; docker-compose enforces this via health checks

5. **Credentials in source** – Demo tokens in `.env` are examples; production must use secrets manager

6. **Neon pooler connections** – DB URLs use `&channel_binding=require`; required for cloud PostgreSQL

7. **CQRS: toda escritura publica un evento `data.*`** – Cada servicio que persiste datos DEBE publicar un evento a RabbitMQ con routing key `data.<servicio>.<entidad>.<accion>`. El Sync Service los escucha para actualizar MongoDB. Sin evento, el dato no existe en el read model.

8. **Sync Service es la única excepción HTTP directa** – Los microservicios NUNCA se hablan directo por HTTP. EXCEPCIÓN: el Gateway consulta al Sync Service por HTTPS para todas las lecturas. El Sync Service nunca es llamado por nadie más.

9. **MongoDB no es fuente de verdad** – La source of truth sigue siendo PostgreSQL de cada servicio. MongoDB es solo un read model desnormalizado. Si hay discrepancia, el dato correcto está en PostgreSQL.

10. **No escribir directo a MongoDB desde los servicios** – Solo el Sync Service escribe en MongoDB. Los servicios productores solo publican eventos a RabbitMQ.

## Existing Docs
- `scrapping/README.md` – Architecture, adapter pattern, performance tips
- `scrapping/USAGE.md`, `INTEGRATION.md`, `EXTENSION_GUIDE.md` – Scraping service specifics
- `docker-compose.yml` – Service definitions, ports, environment injection

---

## 🆕 Scrapping → Notion Integration (Auto-Notification Flow)

### Overview
When a web scraping task completes successfully, the result is automatically:
1. **Cleaned** (trash data removed)
2. **Sent to Notion** (creates a new page)
3. **User notified** (WhatsApp message sent when Notion confirms)

### Architecture Flow

```
┌──────────────────────┐
│ Scraping Request     │
│ (user: 573205711428) │
└──────────┬───────────┘
           ↓
┌──────────────────────┐
│ Puppeteer Scrapes    │
│ Website              │
└──────────┬───────────┘
           ↓
┌──────────────────────┐
│ ✨ DataCleanupService │  Remove duplicates, "text" field,
│ Clean raw data       │  empty fields, redundant content
└──────────┬───────────┘
           ↓
┌──────────────────────┐
│ ✨ NotionAdapter     │  Sends cleaned data to Notion
│ Queue to Notion      │  via RabbitMQ exchange
└──────────┬───────────┘
           │ channels.notion.send
           ↓
┌──────────────────────┐
│ Notion Service       │  Creates page in Notion
│ Creates Page         │
└──────────┬───────────┘
           │ Generates notionPageUrl
           ↓
┌──────────────────────┐
│ Publishes Response   │  Sends success to scrapping queue
│ channels.scrapping   │  (includes notionPageUrl)
│ .notion-response     │
└──────────┬───────────┘
           ↓
┌──────────────────────────────────┐
│ ✨ NotionResponseConsumer        │  Listens for responses
│ Triggers WhatsApp notification   │
└──────────┬───────────────────────┘
           │ PERSONAL_WHATSAPP_NUMBER
           ↓
┌──────────────────────────────────┐
│ WhatsApp Adapter                 │  Sends to your personal number
│ Send Direct via Gateway          │  "✅ Scraping in Notion: URL..."
└──────────────────────────────────┘
```

### Configuration

**In `.env` (root):**
```bash
# Required for Notion integration
NOTION_INTEGRATION_TOKEN=ntn_...  # From Notion Integration Token
PERSONAL_WHATSAPP_NUMBER=573205711428  # Your WhatsApp number

# Optional: Specify parent page for new pages
NOTION_PARENT_PAGE_ID=abc123xyz  # If not set, creates under database
```

### Services Involved

| Service | Role | Key Files |
|---------|------|-----------|
| **scrapping** | Initiates pipeline, cleans data | `src/utils/data-cleanup.service.ts`, `src/notifications/adapters/notion.adapter.ts`, `src/queue/rabbitmq.consumer.ts` |
| **notion** | Receives request, creates page, publishes response | `src/notion/notion.listener.ts`, `src/rabbitmq/constants/queues.ts` |
| **scrapping** | Listens for response, sends WhatsApp notification | `src/queue/notion-response.consumer.ts` |

### RabbitMQ Contracts

**Scrapping → Notion:**
- **Exchange**: `channels` (topic)
- **Routing Key**: `channels.notion.send`
- **Queue**: `notion.send`
- **Payload**: 
  ```json
  {
    "messageId": "scraping-uuid",
    "operation": "create_page",
    "message": "{cleaned JSON data}",
    "metadata": {
      "parent_page_id": "notion_page_id",
      "title": "Xataka",
      "icon": "🔗",
      "userId": "573205711428",
      "url": "https://www.xataka.com/"
    }
  }
  ```

**Notion → Scrapping:**
- **Exchange**: `channels` (topic)
- **Routing Key**: `channels.scrapping.notion-response`
- **Queue**: `scrapping.notion-response`
- **Payload**:
  ```json
  {
    "messageId": "scraping-uuid",
    "operation": "notion_page_created",
    "status": "SUCCESS",
    "notionId": "page-id-xyz",
    "notionPageUrl": "https://notion.so/pageid",
    "timestamp": "2026-04-13T15:30:00Z",
    "userId": "573205711428"
  }
  ```

### Data Cleanup Details

**Removed:**
- ❌ `text` field (too long, redundant with sections)
- ❌ Duplicate sections
- ❌ Empty/null fields
- ❌ Invalid links (missing href)
- ❌ Duplicate links by URL

**Kept:**
- ✅ `title` (page title)
- ✅ `sections[]` (unique, non-empty)
- ✅ `links[]` (deduplicated by URL, max 20)

**Example Input vs Output:**
```typescript
// Input (from Puppeteer)
{
  title: "Xataka",
  sections: ["Section 1", "Section 1", "Magnet"],
  links: [...many with duplicates],
  text: "very long raw HTML text..." // ← REMOVED
}

// Output (after cleanup)
{
  title: "Xataka",
  sections: ["Section 1", "Magnet"],
  links: [
    { href: "https://...", text: "Link 1" },
    // ... max 20 links, no duplicates
  ]
}
```

### Notification Content

When Notion page is created successfully, you receive:
```
✅ *Tu scraping está en Notion*

📄 La página fue creada exitosamente
🔗 Ver en Notion: https://notion.so/pageid

⏰ 13/04/2026 15:30:25
```

### Common Issues & Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| NotionAdapter sends nothing | `NOTION_INTEGRATION_TOKEN` not set | Add to `.env` |
| No WhatsApp notification | `PERSONAL_WHATSAPP_NUMBER` not in `.env` | Add number with country code |
| Page not created in Notion | `NOTION_PARENT_PAGE_ID` invalid | Verify page ID exists in Notion |
| Duplicate sections in Notion | Cleanup didn't run | Check `DataCleanupService` logs |
| Timeout during scraping | Puppeteer pool exhausted | Increase `PUPPETEER_MAX_POOL_SIZE` |

### Extending the Integration

To add new adapters or behaviors:

1. **Add new notification adapter** (e.g., Discord, Slack):
   - Create `src/notifications/adapters/discord.adapter.ts`
   - Implement `NotificationAdapter` interface
   - Register in `AppModule`

2. **Change Notion page structure**:
   - Modify `CleanedScrapingData` interface in `data-cleanup.service.ts`
   - Update Notion service's `createPage()` method

3. **Custom cleanup rules**:
   - Edit `DataCleanupService.cleanup()` method
   - Add new deduplication or filtering logic

### Logging

Service logs scraping pipeline:
```
[RabbitMQConsumer] Processing scraping request: req-123
[DataCleanupService] Data cleaned: title=Xataka, sections=10, links=15
✅ Notion notification sent for user 573205711428
[NotionListener] Processing Notion operation [create_page] | messageId: scraping-xyz
✅ Notion page created and response published to scrapping service: messageId=scraping-xyz
[NotionResponseConsumer] Received Notion response: messageId=scraping-xyz, status=SUCCESS
📱 Sending WhatsApp notification to 573205711428
✅ WhatsApp notification sent for Notion success: messageId=scraping-xyz
```
