# Messages — `/v1/messages/*`

Envío unificado de mensajes a cualquier canal soportado. El gateway recibe una request "agnóstica" y la rutea al microservicio del canal correspondiente vía RabbitMQ.

**Canales soportados:** `whatsapp`, `instagram`, `slack`, `notion`, `tiktok`, `facebook`

## Endpoints

### `POST /v1/messages/send`
**Patrón:** Fire-and-forget · `202 Accepted`

Envía un mensaje a uno o más destinatarios en un canal específico.

```json
{
  "channel": "whatsapp",
  "recipients": ["573205711428", "573211234567"],
  "message": "Hola, este es un mensaje de prueba",
  "mediaUrl": "https://example.com/image.jpg",
  "metadata": {
    "campaignId": "abril-2026",
    "internal": true
  }
}
```

| Campo | Tipo | Requerido | Notas |
|---|---|---|---|
| `channel` | enum | ✅ | uno de: `whatsapp`, `instagram`, `slack`, `notion`, `tiktok`, `facebook` |
| `recipients` | string[] | ✅ | mínimo 1, formato según canal (ver abajo) |
| `message` | string | ✅ | texto del mensaje |
| `operation` | string | optional | solo para `notion` (`create_page`, `update_page`, etc.) |
| `mediaUrl` | string | optional | URL pública de imagen/audio/video — no todos los canales lo soportan |
| `metadata` | objeto JSON libre | optional | tags propios, no se mandan al canal |

**Formato de `recipients` por canal:**

| Canal | Formato | Ejemplo |
|---|---|---|
| `whatsapp` | número con código de país, sin `+` | `"573205711428"` |
| `instagram` | IGSID (Instagram Scoped User ID) | `"17841472713425441"` |
| `slack` | channel ID o user ID de Slack | `"C0123456"` o `"U0123456"` |
| `facebook` | PSID (Page-Scoped User ID) | `"123456789012345"` |
| `tiktok` | tiktok user id | `"abc123..."` |
| `notion` | page id o database id de Notion | `"abc123..."` |

**Response:**
```json
{
  "id": "uuid-interno-del-mensaje",
  "accepted": true,
  "channel": "whatsapp",
  "recipients": ["573205711428"],
  "message": "...",
  "status": "PENDING",
  "createdAt": "2026-04-25T18:42:11.123Z"
}
```

> El `id` te sirve para consultar el estado después con `GET /v1/messages/:id`.

---

### `GET /v1/messages/:id`
**Patrón:** RPC · `200 OK`

Estado de un mensaje específico.

**Response:**
```json
{
  "id": "uuid",
  "channel": "whatsapp",
  "recipients": ["573205711428"],
  "message": "...",
  "status": "SENT",
  "createdAt": "...",
  "updatedAt": "..."
}
```

`status` posibles: `PENDING`, `SENT`, `FAILED`, `PARTIAL` (algunos destinatarios OK, otros no).

---

### `GET /v1/messages/instagram/conversations`
**Patrón:** RPC · `200 OK`

Lista las conversaciones activas en Instagram (los IGSIDs con los que tu cuenta ha hablado).

**Response:**
```json
[
  {
    "conversationId": "...",
    "igsid": "17841...",
    "username": "fulano"
  }
]
```

Útil para mostrar al usuario una lista de "con quién puedo escribir" sin tener que pedir el IGSID a mano.

---

### `POST /v1/messages/instagram/:igsid`
**Patrón:** Fire-and-forget · `202 Accepted`

Envío directo a un IGSID específico (atajo más cómodo que `POST /send` con `channel: "instagram"`).

```json
{
  "message": "Hola desde el frontend",
  "mediaUrl": "https://..."
}
```

**Response:**
```json
{
  "messageId": "...",
  "igsid": "17841...",
  "status": "SENT",
  "timestamp": "..."
}
```

---

## Lo que SÍ podés hacer

- Enviar a múltiples destinatarios de un solo canal en una request (`recipients: [...]`)
- Mostrar UI tipo "compose message" con select de canal y campo dinámico de destinatario
- Tracking de envíos por id
- Adjuntar media (imagen/audio) vía URL pública
- Listar conversaciones de Instagram para autocompletar destinatarios

## Lo que NO podés hacer

- ❌ Multi-canal en una sola request (un mensaje a WhatsApp + Instagram simultáneamente). Tenés que hacer dos requests.
- ❌ Programar envíos a futuro **desde este endpoint**. Para eso usá [scheduler](./scheduler.md) con `targetRoutingKey: "channels.whatsapp.send"` (o el canal correspondiente).
- ❌ Listar mensajes (no hay `GET /v1/messages` sin id). Solo podés consultar uno específico.
- ❌ Editar/borrar un mensaje ya enviado.
- ❌ Recibir respuestas de los usuarios (eso llega vía webhooks de cada canal — lo procesa el backend).
- ❌ Mandar plantillas de WhatsApp con variables desde aquí. Hay un flujo separado para templates (no expuesto en API actualmente).
- ❌ Adjuntar archivos como upload (multipart). Solo URL pública.

## Verificar status post-envío

Como es fire-and-forget, el `202` solo significa "encolado". Para saber si llegó realmente:

1. Guardá el `id` que te devolvió el `POST /send`
2. Polling o websocket: `GET /v1/messages/:id` cada 1-2s hasta que `status` sea distinto de `PENDING`
3. Mejor: suscribite a eventos `channels.whatsapp.events.*` (no expuesto al frontend hoy — requiere websocket bridge en el gateway)
