# Read model — `/v1/query/*`

**Esta es la única doc que necesita leer el front para hacer GETs.** Devuelve datos cross-service desde el **read model en MongoDB**, alimentado por el Sync Service vía eventos `data.*` de cada microservicio.

**Backend:** sync-service (puerto 3012, sólo accesible internamente desde el gateway).
**Colecciones Mongo:** `unified_users`, `unified_conversations`, `unified_messages`, `unified_emails`, `scraping_task_summaries`, `event_log`.

## Por qué `/v1/query/*` en vez de pegarle a cada microservicio

Antes había `/v1/identity/users`, `/v1/email`, `/v1/scraping/tasks`, `/v1/agent/conversations`, `/v1/conversations/...` — cada uno hablando con su microservicio por RabbitMQ RPC. **Esos GETs ya no existen.**

| Lectura | Endpoint nuevo |
|---|---|
| Listar usuarios | `GET /v1/query/users` |
| Detalle de usuario (con identities cross-channel) | `GET /v1/query/users/:userId` |
| Conversaciones de un usuario (whatsapp + instagram + agent) | `GET /v1/query/users/:userId/conversations` |
| Emails de un usuario | `GET /v1/query/users/:userId/emails` |
| Scrapings de un usuario | `GET /v1/query/users/:userId/scraping-tasks` |
| Una conversación | `GET /v1/query/conversations/:id` |
| Mensajes de una conversación | `GET /v1/query/conversations/:id/messages` |
| Un email (inbound o outbound) | `GET /v1/query/emails/:id` |
| Un scraping específico | `GET /v1/query/scraping-tasks/:id` |
| Búsqueda cross-collection | `GET /v1/query/search?q=...` |

**Lo que sigue en endpoints específicos** (porque no aplica al read model):
- `GET /v1/agent/conversations/:id` — detalle del agente CON `tool_use` blocks (el read model strippea esos)
- `GET /v1/agent/memories` — memorias del agente (no son cross-channel)
- `GET /v1/identity/report` — aggregate roll-up on-the-fly
- `GET /v1/scheduler/...` — jobs de BullMQ (no van al read model)
- `GET /v1/messages/:id` — tabla `Message` propia del gateway (audit de POSTs)
- `GET /v1/emails/domains` — config (no data)

---

## Endpoints

### `GET /v1/query/users`
List de usuarios, más recientes (`lastSeenAt`) primero. Soft-deleted users no aparecen.

**Query params:**
- `limit` (default 50, max 200)
- `cursor` — id del último item para paginar

```json
[
  { "id": "u_xyz", "displayName": "Cris", "identities": [...], "lastSeenAt": "..." }
]
```

---

### `GET /v1/query/users/:userId`
Perfil unificado con todas las identities cross-channel.

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
  "firstSeenAt": "2026-03-04T...",
  "lastSeenAt":  "2026-05-16T...",
  "deletedAt": null,
  "mergedInto": null
}
```

**404** si no existe o `deletedAt` está seteado.

---

### `GET /v1/query/users/:userId/conversations`
Conversaciones cross-channel del usuario. Ordenadas por `lastMessageAt desc`. Excluye `status: DELETED`.

**Query params:**
- `channel` — filtrar por canal (`whatsapp`, `instagram`, `agent`)
- `limit`, `cursor`

```json
[
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
    "lastMessageAt": "2026-05-16T..."
  }
]
```

---

### `GET /v1/query/users/:userId/emails`
Emails asociados al usuario (inbound + outbound).

**Query params:**
- `direction` — `inbound` | `outbound` (omitir = both)
- `limit`, `cursor`

---

### `GET /v1/query/users/:userId/scraping-tasks`
Histórico de scraping jobs del usuario.

```json
[
  {
    "id": "task-uuid",
    "userId": "u_xyz",
    "url": "https://xataka.com",
    "title": "Xataka",
    "status": "completed",
    "notionPageUrl": "https://notion.so/...",
    "durationMs": 4321,
    "occurredAt": "..."
  }
]
```

---

### `GET /v1/query/conversations`
Todas las conversaciones del sistema (admin / debug). Excluye soft-deleted.

**Query params:**
- `channel` — filtra por canal
- `limit`, `cursor`

---

### `GET /v1/query/conversations/:id`
Detalle de UNA conversación. Cross-channel summary — sin tool blocks ni internals del agent.

**404** si no existe o está soft-deleted.

---

### `GET /v1/query/conversations/:id/messages`
Mensajes de la conversación, **ascendentes por `occurredAt`** (orden cronológico del chat).

```json
[
  {
    "id": "msg-id",
    "conversationId": "conv-abc",
    "userId": "u_xyz",
    "channel": "whatsapp",
    "channelUserId": "573205711428",
    "sender": "USER",
    "content": "hola",
    "mediaUrl": null,
    "externalId": "wamid.xxx",
    "occurredAt": "..."
  },
  {
    "id": "msg-id-2",
    "sender": "BOT",
    "content": "Hola Cris, ¿en qué te ayudo?",
    "..."
  }
]
```

`sender` values: `USER` | `BOT` | `AGENT` | `SYSTEM`.

---

### `GET /v1/query/emails`
Lista de emails (inbound + outbound, todos los dominios).

**Query params:**
- `direction` — `inbound` | `outbound`
- `domain` — filtra por dominio (`artagdev.com.co`, `lumenxlabs.com.co`, ...)
- `status` — outbound lifecycle: `SENT` | `DELIVERED` | `BOUNCED` | `OPENED` | `CLICKED` | `COMPLAINED` | `FAILED`
- `limit`, `cursor`

```json
[
  {
    "id": "uuid",
    "direction": "outbound",
    "domain": "artagdev.com.co",
    "fromAddress": "soporte@artagdev.com.co",
    "toAddresses": ["scristxyz@gmail.com"],
    "subject": "Welcome",
    "provider": "resend",
    "providerMessageId": "re_xxx",
    "status": "DELIVERED",
    "sentAt": "...",
    "deliveredAt": "...",
    "openedAt": null,
    "userId": null,
    "occurredAt": "..."
  },
  {
    "id": "uuid",
    "direction": "inbound",
    "domain": "artagdev.com.co",
    "fromAddress": "alguien@gmail.com",
    "fromName": "Alguien",
    "toAddresses": ["hola@artagdev.com.co"],
    "toAlias": "hola",
    "subject": "Una pregunta",
    "textBody": "...",
    "htmlBody": "...",
    "userId": "u_xyz",
    "attachments": [{"name": "file.pdf", "contentType": "application/pdf", "size": 1234}],
    "occurredAt": "..."
  }
]
```

---

### `GET /v1/query/emails/:id`
Un email en detalle (mismo shape que `list`).

**404** si no existe.

---

### `GET /v1/query/scraping-tasks`
Lista de scraping jobs.

**Query params:**
- `status` — `completed` | `failed`
- `limit`, `cursor`

---

### `GET /v1/query/scraping-tasks/:id`
Un scraping task. **404** si no existe.

---

### `GET /v1/query/search`
Búsqueda case-insensitive substring sobre:
- `unified_messages.content`
- `unified_conversations.topic` (sólo no-DELETED)
- `unified_emails.subject` + `textBody` + `fromAddress`

**Query params:**
- `q` (mín 2 chars; si menos, devuelve listas vacías)
- `limit` por sub-collection (default 50, max 200)

```json
{
  "messages":      [ {...}, {...} ],
  "conversations": [ {...} ],
  "emails":        [ {...} ]
}
```

> **Nota perf:** hoy usa regex queries (sin index). A partir de ~100k docs por colección, crear `$text` indexes manualmente en Mongo y switcheamos a `$text` aggregation:
> ```js
> db.unified_messages.createIndex({ content: "text" })
> db.unified_emails.createIndex({ subject: "text", textBody: "text" })
> ```

---

## Errores

| Status | Cuándo |
|---|---|
| `200` | OK |
| `404` | Recurso no existe (o está soft-deleted) |
| `503 Read model unavailable` | Sync service caído, timeout (10s) o auth interna entre gateway↔sync rota |

## Latencia esperada

- Lookup por id: **5-15ms** (HTTP keep-alive entre gateway y sync + Mongo indexed query)
- Lista pequeña (50 docs): **20-50ms**
- Search: **50-300ms** dependiendo del tamaño (regex scan, no full-text aún)

## Paginación

Cursor-based con el `id` del último item:

```js
// React example
async function loadMore(lastId) {
  const res = await fetch(`/api/v1/query/users?cursor=${lastId}&limit=50`)
  return res.json()
}
```

## Detalles internos (para auditar)

- Gateway proxea cada request a `GET http://sync:3012/internal/query/*` con header `X-Internal-Auth: <SYNC_INTERNAL_AUTH_TOKEN>`.
- Sync rechaza con 401 si el header no matchea.
- Sync consume el bus de RabbitMQ con binding pattern `data.#` y proyecta cada evento a Mongo. Latencia event→read típica: **~10-50ms**.
- Si un microservicio NO publica su `data.<service>.<entity>.<action>` event, sus datos NO aparecen acá. Hoy publican: identity, whatsapp, instagram, scrapping, email, slack, agent. Ver `AGENTS.md` para la tabla completa.

## Backfill de datos pre-existentes

El read model **sólo se llena con eventos nuevos**. Para popular Mongo con todo lo que ya tenés en cada Postgres, hay que re-emitir los eventos. Patrones:

### Opción A — Admin endpoint por producer (recomendado)
Cada servicio expone un `POST /admin/backfill-events` autenticado que recorre su DB y re-publica los `data.*` events. El operador llama una vez por servicio post-deploy.

### Opción B — Script one-shot
Conectarse a cada Postgres y emitir directo al RabbitMQ desde un script aparte. Más invasivo, no recomendado.

Como los projectors son idempotentes (upsert por id), reemitir es seguro.
