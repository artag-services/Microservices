# Read model — `/v1/query/*`

Endpoints unificados de **lectura** cross-service. Devuelven datos que viven en el **read model de MongoDB**, alimentado por el Sync Service vía eventos `data.*` de cada microservicio.

**Backend:** sync-service (puerto 3012, sólo accesible internamente desde el gateway). Mongo collections expuestas: `unified_users`, `unified_conversations`, `unified_messages`, `scraping_task_summaries`.

> El frontend NUNCA llama directo al sync-service. Sólo a `/v1/query/*` del gateway.

## Lecturas vs Escrituras

| Necesidad | Endpoint |
|---|---|
| **Leer** un usuario, conversación, mensaje, scraping previo | `/v1/query/*` (este doc) |
| **Escribir** (enviar mensaje, programar tarea, scrapear) | `/v1/messages`, `/v1/scraping`, `/v1/emails`, `/v1/scheduler`, etc. |
| **Eventos real-time** | `/v1/events` (SSE) o WS `message:<id>` |

## Endpoints

### `GET /v1/query/users/:userId`
**Patrón:** RPC · `200 OK` / `404 Not Found`

Perfil unificado del usuario con TODAS sus identidades por canal.

```json
{
  "id": "u_xyz",
  "displayName": "Cris",
  "realName": null,
  "avatarUrl": null,
  "identities": [
    { "channel": "whatsapp",  "channelUserId": "573205711428", "displayName": "Cris", "linkedAt": "..." },
    { "channel": "instagram", "channelUserId": "1782739...",   "displayName": "@scristx", "linkedAt": "..." }
  ],
  "conversationCount": 8,
  "messageCount": 142,
  "firstSeenAt": "2026-03-04T...",
  "lastSeenAt":  "2026-05-16T..."
}
```

---

### `GET /v1/query/users?limit=50&cursor=<id>`
Lista de usuarios ordenados por `lastSeenAt` desc. Paginación por cursor (`id` del último item).

---

### `GET /v1/query/users/:userId/conversations?limit=50&cursor=<id>`
Todas las conversaciones del usuario, cross-channel, ordenadas por `lastMessageAt` desc.

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
    "messageCount": 12,
    "lastMessageAt": "2026-05-16T..."
  }
]
```

---

### `GET /v1/query/users/:userId/scraping-tasks?limit=50&cursor=<id>`
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
    "occurredAt": "2026-05-16T..."
  }
]
```

---

### `GET /v1/query/conversations/:id`
Detalle de una conversación.

### `GET /v1/query/conversations/:id/messages?limit=50&cursor=<id>`
Mensajes de la conversación, ascendentes por `occurredAt`.

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
    "occurredAt": "2026-05-16T..."
  }
]
```

---

### `GET /v1/query/search?q=<term>&limit=50`
Búsqueda cross-channel sobre `content` de mensajes y `topic` de conversaciones. Case-insensitive substring (no full-text indexing aún).

```json
{
  "messages":      [ {...}, {...} ],
  "conversations": [ {...} ]
}
```

---

## Errores

| Status | Cuándo |
|---|---|
| `404` | Recurso no existe en el read model |
| `503 Read model unavailable` | Sync service caído, tiraron timeout (10s) o problemas de auth interna entre gateway↔sync |

## Latencia esperada

Esto **no** es un RPC cross-service — el gateway sólo hace una sola llamada HTTP keep-alive al sync-service que va directo a Mongo. Latencias típicas: **5-20ms** para queries simples por id, **20-80ms** para listas pequeñas.

## Lo que NO podés hacer todavía

- ❌ Full-text search real (Mongo Atlas Search o índices `$text`) — está pendiente
- ❌ Filtrar conversaciones por canal o status desde el endpoint (sin query param `channel`/`status`)
- ❌ Sort customizable (todo viene en el orden definido por el sync — `lastMessageAt desc` o `occurredAt asc`)
- ❌ Crear/editar/borrar a través de `/v1/query/*` — es read-only. Las escrituras viven en los endpoints específicos por canal/feature.

## Detalles internos (referencia)

El frontend no necesita esto, pero por si auditás:

- El gateway proxea cada request a `GET http://sync:3012/internal/query/*` con header `X-Internal-Auth: <SYNC_INTERNAL_AUTH_TOKEN>`.
- El sync-service rechaza con 401 si el header no matchea.
- El sync-service consume el bus de RabbitMQ con binding pattern `data.#` y proyecta cada evento a Mongo. Latencia event→read típica: ~10-50ms.
- Si un microservicio NO publica su `data.<service>.<entity>.<action>` event, sus datos NO aparecen acá. Hoy publican: identity (parcial), próximos a wirear: whatsapp/instagram/scrapping. Ver `AGENTS.md` y `docs/audit-*.md`.
