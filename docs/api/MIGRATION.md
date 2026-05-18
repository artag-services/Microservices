# Migración — qué cambió para el frontend

Resumen de los cambios recientes en el API. Todo este doc está organizado **por feature**, no por archivo — querés saber "¿cómo listo emails ahora?" → mirás la sección Emails.

## TL;DR

- **Las lecturas (GET) se consolidaron en `/v1/query/*`.** Los GET viejos en `/v1/identity/users`, `/v1/conversations`, `/v1/emails`, `/v1/scraping/tasks`, `/v1/agent/conversations` **fueron removidos**.
- **Las acciones (POST/PATCH/DELETE) siguen iguales** en sus paths originales (`/v1/messages/send`, `/v1/identity/resolve`, etc.).
- **CORS configurable** vía `CORS_ALLOWED_ORIGINS` en el server.
- **Backfill** disponible para popular Mongo con datos pre-existentes (`POST /admin/backfill-events` en cada servicio, con `X-Admin-Token`).
- **Path bug arreglado**: `/v1/conversations` antes resolvía a `/api/api/v1/conversations` por un doble prefix. Ahora es `/api/v1/conversations`.

---

## 1. Read model unificado — `/v1/query/*`

Antes: cada microservicio tenía su propio GET y el gateway proxeaba por RabbitMQ RPC.
Ahora: hay un Sync Service que consume eventos `data.*` y mantiene **un read model en MongoDB**. El gateway proxea `/v1/query/*` a ese servicio.

### Tabla de migración rápida

| Necesidad | Antes (❌ ya no existe) | Ahora (✅ usar esto) |
|---|---|---|
| Listar todos los usuarios | `GET /v1/identity/users` | `GET /v1/query/users` |
| Perfil unificado de un usuario (con identities cross-channel) | `GET /v1/identity/users/:id` | `GET /v1/query/users/:userId` |
| Conversaciones de un usuario | (no existía cross-channel) | `GET /v1/query/users/:userId/conversations?channel=whatsapp` |
| Lista de conversaciones del sistema | `GET /v1/conversations` | `GET /v1/query/conversations?channel=...` |
| Detalle de conversación | `GET /v1/conversations/:id` | `GET /v1/query/conversations/:id` |
| Mensajes de una conversación | `GET /v1/conversations/:id/messages` | `GET /v1/query/conversations/:id/messages` |
| Listar emails (in + out) | `GET /v1/emails` / `GET /v1/emails/inbound` | `GET /v1/query/emails?direction=inbound` |
| Detalle de email | `GET /v1/emails/:id` | `GET /v1/query/emails/:id` |
| Emails de un usuario | (no existía) | `GET /v1/query/users/:userId/emails` |
| Listar scrapings | `GET /v1/scraping/tasks?userId=...` | `GET /v1/query/scraping-tasks?status=completed` |
| Detalle de scraping | `GET /v1/scraping/tasks/:id` | `GET /v1/query/scraping-tasks/:id` |
| Scrapings de un usuario | (no existía cross-listing) | `GET /v1/query/users/:userId/scraping-tasks` |
| Listar conversaciones del agente | `GET /v1/agent/conversations` | `GET /v1/query/conversations?channel=agent` |
| Búsqueda cross-collection | (no existía) | `GET /v1/query/search?q=...` |

### Endpoints que SE QUEDARON en sus paths originales

Estos GETs **no migraron** porque devuelven info que el read model no tiene:

- `GET /v1/agent/conversations/:id` — devuelve los `tool_use` blocks del agente (el read model los strippea)
- `GET /v1/agent/memories` — memorias internas del agente (no aplica al cross-channel)
- `GET /v1/identity/report` — aggregate roll-up on-the-fly
- `GET /v1/messages/:id` — audit de POSTs propios del gateway
- `GET /v1/emails/domains` — config (no data)
- `GET /v1/scheduler/*` — BullMQ jobs, read model propio
- `GET /v1/messages/instagram/conversations` — live call a IG API

### Shapes — qué viene en cada response

#### Usuario unificado (`GET /v1/query/users/:userId`)

```json
{
  "id": "u_xyz",
  "displayName": "Cris",
  "realName": null,
  "avatarUrl": null,
  "identities": [
    { "channel": "whatsapp",  "channelUserId": "573205711428", "displayName": "Cris", "linkedAt": "..." },
    { "channel": "instagram", "channelUserId": "1782739...",   "displayName": "@scristx", "linkedAt": "..." },
    { "channel": "email",     "channelUserId": "cris@gmail.com", "displayName": null, "linkedAt": "..." }
  ],
  "conversationCount": 8,
  "messageCount": 142,
  "firstSeenAt": "...",
  "lastSeenAt":  "...",
  "deletedAt": null,
  "mergedInto": null
}
```

> Antes la respuesta venía como `{ user, identities, contacts, nameHistory }`. Ahora es **flat**: `identities` está dentro del objeto principal. No hay `contacts` ni `nameHistory` en el read model.

#### Conversación

```json
{
  "id": "conv-abc",
  "userId": "u_xyz",
  "channel": "whatsapp",
  "channelUserId": "573205711428",
  "topic": "Soporte",
  "status": "ACTIVE",
  "aiEnabled": true,
  "agentAssigned": null,
  "messageCount": 12,
  "aiMessageCount": 8,
  "firstMessageAt": "...",
  "lastMessageAt": "..."
}
```

#### Mensaje

```json
{
  "id": "msg-id",
  "conversationId": "conv-abc",
  "userId": "u_xyz",
  "channel": "whatsapp",
  "channelUserId": "573205711428",
  "sender": "USER",         // o "BOT" | "AGENT" | "SYSTEM"
  "content": "hola",
  "mediaUrl": null,
  "externalId": "wamid.xxx",
  "occurredAt": "..."
}
```

#### Email (inbound + outbound en la misma colección)

```json
{
  "id": "uuid",
  "direction": "outbound",  // o "inbound"
  "domain": "artagdev.com.co",
  "fromAddress": "soporte@artagdev.com.co",
  "toAddresses": ["scristxyz@gmail.com"],
  "subject": "Welcome",
  "status": "DELIVERED",    // sólo outbound
  "sentAt": "...",
  "deliveredAt": "...",
  "openedAt": null,
  "occurredAt": "...",
  // inbound-only extras:
  // "fromName", "toAlias", "textBody", "htmlBody", "attachments"
}
```

#### Scraping task

```json
{
  "id": "task-uuid",
  "userId": "u_xyz",
  "url": "https://xataka.com",
  "title": "Xataka",
  "status": "completed",     // o "failed"
  "notionPageUrl": "https://notion.so/...",
  "durationMs": 4321,
  "error": null,
  "occurredAt": "..."
}
```

### Paginación

Cursor-based en todos los endpoints `list`:

```js
const first = await fetch('/api/v1/query/users?limit=50')
const items = await first.json()
const lastId = items[items.length - 1].id
const next = await fetch(`/api/v1/query/users?cursor=${lastId}&limit=50`)
```

### Filtros

| Endpoint | Filtros |
|---|---|
| `/v1/query/conversations` | `?channel=whatsapp\|instagram\|agent` |
| `/v1/query/users/:id/conversations` | `?channel=...` |
| `/v1/query/users/:id/emails` | `?direction=inbound\|outbound` |
| `/v1/query/emails` | `?direction`, `?domain`, `?status` |
| `/v1/query/scraping-tasks` | `?status=completed\|failed` |

### Errores

- `200` OK
- `404` — recurso no existe o está soft-deleted (sync filtra automáticamente)
- `503 Read model unavailable` — sync service caído, timeout (10s) o problemas de auth interna entre gateway↔sync

---

## 2. Acciones (writes) — sin cambios en los paths

Estos siguen exactamente como antes:

```js
// Mensajes
POST /api/v1/messages/send         // { channel, recipients[], message, mediaUrl? }

// Identidad
POST   /api/v1/identity/resolve    // { channel, channelUserId, displayName?, phone?, ... }
POST   /api/v1/identity/merge      // { primaryUserId, secondaryUserId, reason }
DELETE /api/v1/identity/users/:id  // soft delete
PATCH  /api/v1/identity/users/:id/ai-settings  // { aiEnabled }

// Conversations (lifecycle)
POST   /api/v1/conversations              // { channel, channelUserId?, topic?, aiEnabled? }
PATCH  /api/v1/conversations/:id          // { aiEnabled?, agentAssigned?, status? }
DELETE /api/v1/conversations/:id          // archive

// Email
POST /api/v1/emails                       // { to[], subject, html, text?, ... }
POST /api/v1/emails/inbound/cleanup-expired

// Scraping
POST   /api/v1/scraping/tasks             // { url, strategy, ... }
DELETE /api/v1/scraping/tasks/:id

// Agent
POST   /api/v1/agent/chat                 // { message, conversationId?, enableStreaming? }
DELETE /api/v1/agent/conversations/:id
DELETE /api/v1/agent/memories/:userId/:key
```

Patrones de response:
- `200 OK` cuando devolvemos algo útil (resolveIdentity, agent chat)
- `202 Accepted` cuando es fire-and-forget (mandar mensaje, scraping, etc.)
- `503` cuando un servicio destino está caído

---

## 3. Real-time — SSE + WebSocket

Sin cambios estructurales. Recordá que tenés DOS canales:

**SSE (`/v1/events`)** — todo lo de cross-service:
```js
const es = new EventSource('/api/v1/events?topics=scraping:*,email:*,agent:*')
es.addEventListener('scraping:completed', (e) => { ... })
es.addEventListener('email:delivered',   (e) => { ... })
es.addEventListener('email:inbound',     (e) => { ... })   // NUEVO topic
es.addEventListener('agent:text-delta',  (e) => { ... })
```

**Socket.IO** — status de mensajes (`/v1/messages/send`):
```js
import { io } from 'socket.io-client'
const socket = io(API_URL, { transports: ['websocket'] })
socket.on(`message:${id}`, (status) => { ... })
```

Detalles completos en [events.md](./events.md) y [frontend-nextjs.md](./frontend-nextjs.md).

---

## 4. CORS

Si el front corre en otro origen, el server tiene que listar tu origen en `CORS_ALLOWED_ORIGINS`. Pedirle al admin que agregue en el `.env` del server:

```env
CORS_ALLOWED_ORIGINS=http://localhost:3000,https://app.tudominio.com,http://192.168.x.x:3000
```

Y `docker-compose restart gateway`. Sin la variable, el gateway acepta cualquier origen (cómodo en dev, inseguro en prod).

---

## 5. Backfill — opcional, sólo si querés ver data histórica

El read model se llena automáticamente con eventos nuevos. Si el sistema tenía data en Postgres antes de que se configurara el sync, el read model arranca vacío para esos datos.

Para popularlo, cada productor expone un endpoint admin:

```bash
# Una vez, post-deploy:
TOKEN=$(grep ADMIN_BACKFILL_TOKEN .env | cut -d= -f2)
for svc_port in identity:3010 whatsapp:3001 instagram:3004 slack:3002 scrapping:3008 email:3007 agent:3011; do
  name="${svc_port%:*}"
  port="${svc_port#*:}"
  echo "Backfilling $name..."
  curl -X POST "http://localhost:$port/admin/backfill-events" \
    -H "X-Admin-Token: $TOKEN"
done
```

Cada uno devuelve `{ service, scanned, published, durationMs }`. Es **idempotente** — podés correrlo cualquier número de veces. Los projectors hacen `upsert` por id.

Ver [cqrs-backfill.md](../cqrs-backfill.md) para detalles.

---

## 6. Path bug arreglado

`POST /v1/conversations` antes daba 404 porque el controller declaraba `@Controller('api/v1/conversations')` y el gateway ya tiene prefix global `api` → la ruta real era `/api/api/v1/conversations` (con `api` duplicado). **Ya está arreglado** — usá `/api/v1/conversations` como el resto.

---

## 7. Migración del cliente — checklist

Si tu cliente todavía hace los GETs viejos, vas a recibir `404 Cannot GET ...`. Reemplazos directos:

```js
// ANTES                                          // AHORA
fetch('/api/v1/identity/users')                → fetch('/api/v1/query/users')
fetch('/api/v1/identity/users/u_xyz')          → fetch('/api/v1/query/users/u_xyz')
fetch('/api/v1/conversations')                 → fetch('/api/v1/query/conversations')
fetch('/api/v1/conversations/c/messages')      → fetch('/api/v1/query/conversations/c/messages')
fetch('/api/v1/emails')                        → fetch('/api/v1/query/emails')
fetch('/api/v1/emails/abc')                    → fetch('/api/v1/query/emails/abc')
fetch('/api/v1/emails/inbound')                → fetch('/api/v1/query/emails?direction=inbound')
fetch('/api/v1/scraping/tasks')                → fetch('/api/v1/query/scraping-tasks')
fetch('/api/v1/scraping/tasks/abc')            → fetch('/api/v1/query/scraping-tasks/abc')
fetch('/api/v1/agent/conversations')           → fetch('/api/v1/query/conversations?channel=agent')
fetch('/api/v1/agent/conversations/abc')       // SE QUEDA — tool blocks
fetch('/api/v1/agent/memories?userId=...')     // SE QUEDA — agent-internal
```

Y considerá agregar el cursor-based pagination si antes usabas `offset` (no se soporta más).

---

## 8. ¿Auth?

Sigue **sin estar activa**. El gateway tiene JWT cableado (`@nestjs/passport`, `@nestjs/jwt`) pero comentado. Cuando se active, todos los `/v1/*` van a requerir `Authorization: Bearer <jwt>`. Los webhooks (`/webhooks/*`) seguirán sin auth (validan firma HMAC).

Cuando esto cambie, esta sección se actualiza.

---

## Referencias

- [query.md](./query.md) — referencia completa del read model
- [events.md](./events.md) — SSE + agent streaming
- [frontend-nextjs.md](./frontend-nextjs.md) — guía paso-a-paso con hooks
- [cqrs-backfill.md](../cqrs-backfill.md) — cómo seedear Mongo con datos viejos
- [AGENTS.md](../../AGENTS.md) — tabla de routing keys `data.*`
