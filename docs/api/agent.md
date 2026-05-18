# Agent — `/v1/agent/*`

Chat con un agente conversacional (vendor-neutral: Anthropic, OpenAI o cualquier provider OpenAI-compatible — Nvidia, Groq, etc). El agente tiene memoria persistente por usuario y orquesta llamadas a otros microservicios via tool-use.

**Backend:** agent-service (puerto 3008). Provider activo: el `AI_PROVIDER` del `.env` (`anthropic` / `openai` / `openai-compatible`).

## Endpoints

### `POST /v1/agent/chat`
**Patrón:** RPC · `200 OK`

Manda un mensaje al agente, devuelve la respuesta final + las tools que usó.

```json
{
  "message": "Mandame un email a scristxyz@gmail.com con el asunto 'hola' y cuerpo '¿cómo va?'",
  "conversationId": "conv-uuid-existente-opcional",
  "userId": "u_xyz-opcional",
  "enableStreaming": false
}
```

| Campo | Tipo | Requerido | Notas |
|---|---|---|---|
| `message` | string | ✅ | el prompt del usuario |
| `conversationId` | string | optional | si lo omitís, crea una conversación nueva |
| `userId` | string | optional | atá la conversación a un usuario para que tenga memoria propia |
| `enableStreaming` | boolean | optional | si `true`, además de la respuesta final, se publican `agent:text-delta` por SSE en `agent:<conversationId>` |

**Response:**
```json
{
  "conversationId": "conv-uuid",
  "messageId": "msg-uuid",
  "finalText": "Listo, envié el email. El ID es e_abc.",
  "toolsUsed": [
    { "name": "email_send", "input": { "to": "...", "subject": "..." }, "output": { "id": "e_abc" } }
  ],
  "model": "claude-opus-4-7",
  "usage": { "inputTokens": 234, "outputTokens": 89 },
  "createdAt": "2026-05-16T..."
}
```

> Con `enableStreaming: true`, hacé fetch al endpoint **Y abrí un SSE en paralelo** a `/api/v1/events?topics=agent:<conversationId>`. Los deltas llegan por SSE mientras el POST sigue esperando el `finalText`. Ver [events.md](./events.md).

---

> 📖 **Listar conversaciones del agente** se movió al read model unificado:
> - [`GET /v1/query/conversations?channel=agent`](./query.md#get-v1queryconversations) — todas
> - [`GET /v1/query/users/:userId/conversations?channel=agent`](./query.md#get-v1queryusersuseridconversations) — del usuario
>
> El endpoint específico de abajo se mantiene porque devuelve los `tool_use` / `tool_result` blocks, que el read model NO proyecta.

### `GET /v1/agent/conversations/:id`
**Patrón:** RPC · `200 OK`

Detalle + historial **con tool blocks** (vista deep-dive del agente). Para el resumen cross-channel sin internals, usá `/v1/query/conversations/:id`.

```json
{
  "id": "conv-uuid",
  "userId": "u_xyz",
  "title": "...",
  "messages": [
    { "id": "msg1", "role": "user", "content": "...", "createdAt": "..." },
    { "id": "msg2", "role": "assistant", "content": "...", "toolUses": [...], "createdAt": "..." }
  ],
  "createdAt": "..."
}
```

---

### `DELETE /v1/agent/conversations/:id`
**Patrón:** RPC · `200 OK`

Borra una conversación entera (y sus mensajes).

---

### `GET /v1/agent/memories?userId=<id>&type=<optional>`
**Patrón:** RPC · `200 OK`

Lista las memorias persistentes que el agente guardó del usuario (preferencias, hechos, etc.). El `type` es opcional para filtrar (`preference`, `fact`, `goal`, ...).

```json
[
  { "key": "favorite-color", "value": "azul", "type": "preference", "createdAt": "..." },
  { "key": "github-user", "value": "scris", "type": "fact", "createdAt": "..." }
]
```

---

### `DELETE /v1/agent/memories/:userId/:key`
**Patrón:** RPC · `200 OK`

Borra una memoria específica del usuario. Útil para "olvidate de X".

---

## Streaming via SSE

Cuando hacés `POST /v1/agent/chat` con `enableStreaming: true`, los siguientes eventos llegan en tiempo real via [SSE](./events.md) en el topic `agent:<conversationId>`:

| Event | Cuándo | Payload |
|---|---|---|
| `agent:message-started` | Empieza a generar | `{ conversationId, messageId, model }` |
| `agent:text-delta` | Cada chunk de texto | `{ conversationId, messageId, delta }` |
| `agent:tool-use-start` | Agente decide usar una tool | `{ conversationId, toolName, input }` |
| `agent:tool-use-end` | Tool terminó (ok o error) | `{ conversationId, toolName, output, error? }` |
| `agent:message-completed` | Respuesta final | `{ conversationId, messageId, finalText, usage }` |
| `agent:error` | Falla irrecuperable | `{ conversationId, error }` |

### Ejemplo: chat con streaming

```js
const conversationId = crypto.randomUUID()

// 1) Abrí SSE PRIMERO para no perderte el primer delta
const es = new EventSource(`/api/v1/events?topics=agent:${conversationId}`)

es.addEventListener('agent:text-delta', (e) => {
  const { delta } = JSON.parse(e.data)
  appendToChatUI(delta) // ir mostrando texto a medida que llega
})

es.addEventListener('agent:tool-use-start', (e) => {
  const { toolName, input } = JSON.parse(e.data)
  showToolBadge(`Usando ${toolName}…`)
})

es.addEventListener('agent:message-completed', (e) => {
  const { finalText, usage } = JSON.parse(e.data)
  hideToolBadge()
  es.close()
})

// 2) Dispará el POST (no esperás bloqueado, pero el `finalText` viene acá también)
const res = await fetch('/api/v1/agent/chat', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    conversationId,
    message: 'Listame mis últimos 3 emails enviados',
    enableStreaming: true,
  }),
})
const { finalText, toolsUsed } = await res.json()
console.log('Tools que usó:', toolsUsed)
```

---

## Tools disponibles para el agente

El agente puede invocar (vía tool-use) cualquier otro microservicio del stack. Las tools típicas que tiene wireadas:

- `email_send` — `POST /v1/emails`
- `email_get` — `GET /v1/emails/:id`
- `scraping_start` — `POST /v1/scraping/tasks`
- `scheduler_create` — `POST /v1/schedules`
- `whatsapp_send` / `instagram_send` / `slack_send` — vía `POST /v1/messages`
- `memory_save` / `memory_recall` — su propia memoria persistente
- `identity_lookup` — `GET /v1/identity/:userId`

> Si el agente intenta llamar una tool que NO existe o devuelve error, lo verás en `toolsUsed[].error` y se le devuelve al modelo para que reintente o explique al usuario.

---

## Errores comunes

| Síntoma | Causa probable |
|---|---|
| Timeout ~30s | El provider AI está lento o caído. Reintentá; el correlationId no se reusa. |
| `400 message is required` | Mandaste el POST sin `message` o vacío. |
| `finalText` vacío + `error` en payload | El provider tiró error (rate limit, API key inválida, etc.). Revisar logs del agent-service. |
| Streaming no llega | Te suscribiste al SSE DESPUÉS de mandar el POST y el agente respondió rapidísimo. Suscribite primero o usá un `conversationId` predecible. |
| Tool falló pero el agente no avisó | Mirá `toolsUsed[].error`. El agente puede decidir continuar sin contarte. |

---

## Lo que SÍ podés hacer

- Conversación multi-turno con memoria por usuario
- Streaming token-by-token vía SSE
- Tools server-side (el agente actúa, no solo responde)
- Persistencia: todas las conversaciones quedan en DB
- Memorias persistentes (preferencias, hechos) que sobreviven entre conversaciones
- Cambiar de provider sin tocar el frontend (Anthropic ↔ OpenAI ↔ Groq, etc. — sólo cambia el `.env`)

## Lo que NO podés hacer

- ❌ Modificar las tools desde el frontend (son server-side)
- ❌ Pasar el JWT del usuario a las tools (todavía no hay scoping por usuario en las tools)
- ❌ Voice (audio in/out) — el provider lo soporta pero no está expuesto acá
- ❌ Subir archivos al agente (imágenes, PDFs) — no expuesto todavía
- ❌ Cancelar un mensaje en streaming (el modelo termina solo)
