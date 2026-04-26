# Instagram

Mensajería directa vía Meta Instagram Graph API. El microservicio `instagram` (puerto 3004) consume del exchange `channels` y dialoga con `graph.instagram.com` usando tu `INSTAGRAM_PAGE_TOKEN`.

**Es el único canal con rutas dedicadas** (además de la genérica) — algunas operaciones tienen su propio endpoint.

## Operaciones disponibles

| Operación | Vía | Estado |
|---|---|---|
| Listar conversaciones activas | `GET /api/v1/messages/instagram/conversations` | ✅ disponible |
| Enviar DM a un IGSID específico | `POST /api/v1/messages/instagram/:igsid` | ✅ disponible |
| Enviar DM (genérico) | `POST /api/v1/messages/send` | ✅ disponible |
| Consultar estado de un mensaje | `GET /api/v1/messages/:id` | ✅ disponible |
| Toggle IA por conversación | — | ⚠️ falta endpoint |
| Asignar agente humano | — | ⚠️ falta endpoint |
| Obtener perfil de usuario (nombre, avatar) | — | ⚠️ falta endpoint |
| Historial de mensajes con un usuario | — | ⚠️ falta endpoint |
| Recibir DMs entrantes | webhooks (no frontend) | ✅ procesa internamente |

---

## ✅ Listar conversaciones activas

### `GET /api/v1/messages/instagram/conversations`

Sin params. Devuelve los IGSIDs con los que tu cuenta de Instagram Business ha tenido al menos un intercambio.

**Response (`200 OK`):**

```json
[
  {
    "conversationId": "ig-conversation-uuid",
    "igsid": "17841472713425441",
    "username": "fulano_de_tal"
  },
  {
    "conversationId": "ig-conversation-uuid-2",
    "igsid": "17841999888777666",
    "username": "otra_persona"
  }
]
```

**Útil para:** popular un dropdown "Selecciona destinatario" sin que el usuario tenga que copiar IGSIDs a mano.

---

## ✅ Enviar DM a un IGSID específico (atajo)

### `POST /api/v1/messages/instagram/:igsid`

Donde `:igsid` es el Instagram Scoped User ID (lo conseguís del listado de arriba o de un webhook).

```json
{
  "message": "Hola, vi tu comentario y quería responderte por aquí",
  "mediaUrl": "https://example.com/imagen.jpg"
}
```

| Campo | Tipo | Requerido |
|---|---|---|
| `message` | string | ✅ |
| `mediaUrl` | string | optional (URL de imagen) |

**Response (`202 Accepted`):**

```json
{
  "messageId": "msg-uuid",
  "igsid": "17841472713425441",
  "status": "SENT",
  "timestamp": "2026-04-25T18:42:11.123Z"
}
```

> Este endpoint es más limpio que el genérico y devuelve algunos campos útiles (`igsid`, `timestamp`) que el genérico no incluye.

---

## ✅ Enviar DM (genérico, alternativo)

### `POST /api/v1/messages/send`

Mismo resultado que el endpoint específico, pero con el formato unificado:

```json
{
  "channel": "instagram",
  "recipients": ["17841472713425441", "17841999888777666"],
  "message": "Mensaje a múltiples usuarios",
  "mediaUrl": "https://example.com/imagen.jpg"
}
```

| Campo | Tipo | Requerido | Notas |
|---|---|---|---|
| `channel` | string | ✅ | siempre `"instagram"` |
| `recipients` | string[] | ✅ | array de IGSIDs |
| `message` | string | ✅ | texto del DM |
| `mediaUrl` | string | optional | URL pública de imagen |

> Usá este si querés enviar a múltiples usuarios con una sola request. Usá el específico (`/instagram/:igsid`) si vas a uno solo y querés response más limpio.

---

## ✅ Consultar estado

### `GET /api/v1/messages/:id`

Mismo formato que los otros canales. `status` puede ser `PENDING`, `SENT`, `FAILED`, `PARTIAL`.

---

## ⚠️ Lo que NO podés hacer hoy desde el frontend

| Quiero… | Estado | Workaround |
|---|---|---|
| Activar/desactivar IA por conversación | falta endpoint | usa el módulo [identity](../identity.md) con `PATCH /api/v1/identity/users/:userId/ai-settings` (es per-usuario, no per-conversación) |
| Asignar un operador humano a una conversación | falta endpoint específico de Instagram | usa el módulo [conversations](../conversations.md) con `PATCH /api/v1/conversations/:id` |
| Ver el perfil del usuario (nombre, avatar) | falta endpoint | el `username` aparece en el listado de conversaciones, pero no hay endpoint para perfil completo |
| Historial de DMs con alguien | falta endpoint | usa `GET /api/v1/conversations/:id/messages` (módulo agnóstico) |
| Ver comentarios en posts | falta consumer | webhook entra al sistema pero no se procesa |
| Reaccionar a stories | falta endpoint | imposible hoy |
| Subir imagen como upload | ❌ | solo URL pública |

---

## Webhooks entrantes (informativo)

Instagram manda 8 tipos de eventos al gateway en `POST /api/webhooks/instagram`:

- **Mensaje recibido** (`channels.instagram.events.message`) — el sistema resuelve identidad y dispara IA si está habilitada
- **Comentario en post** (`channels.instagram.events.comment`) — stub
- **Reacción a story/post** (`channels.instagram.events.reaction`) — stub
- **Mensaje visto** (`channels.instagram.events.seen`) — stub
- **Click en referral link** (`channels.instagram.events.referral`) — stub
- **Opt-in para DMs** (`channels.instagram.events.optin`) — stub
- **Handover de control** (`channels.instagram.events.handover`) — stub

Solo "mensaje recibido" tiene lógica completa hoy. Los demás están como stubs (entran al sistema pero no actualizan estado).

---

## Sobre los IGSIDs

Instagram identifica usuarios con **IGSIDs** (Instagram Scoped User IDs). Características:

- Es un número largo tipo `"17841472713425441"`
- Es **único por App** — el mismo usuario tiene un IGSID distinto si lo ve otra app de Instagram (es "scoped")
- Solo lo conseguís cuando el usuario te escribe primero (vía webhook). **No podés iniciar conversación** desde tu lado a un IGSID que no te haya escrito antes (limitación de la plataforma de Meta).
- El `username` (`@fulano`) NO sirve como recipient — solo el IGSID

---

## Errores comunes

| Síntoma | Causa probable |
|---|---|
| `status: FAILED` con error de "user not found" | el IGSID no es válido o pertenece a otra app |
| Mensaje se manda OK pero el usuario nunca recibe | el usuario nunca te escribió — Meta solo permite responder a conversaciones iniciadas por el usuario |
| `GET /conversations` devuelve array vacío | tu cuenta de Instagram Business no ha tenido conversaciones, o el `INSTAGRAM_PAGE_TOKEN` no tiene scope `instagram_manage_messages` |
| `400 Validation failed` | falta `message` o el `igsid` está mal formado |
| Imagen no se muestra | la URL no es pública o no es directa a un .jpg/.png (no acepta URLs que requieren JS) |

---

## Ejemplo cURL completo

```bash
# Atajo (recomendado para enviar a uno):
curl -X POST http://localhost:3000/api/v1/messages/instagram/17841472713425441 \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Hola desde el sistema",
    "mediaUrl": "https://example.com/saludo.jpg"
  }'

# Genérico (para múltiples):
curl -X POST http://localhost:3000/api/v1/messages/send \
  -H "Content-Type: application/json" \
  -d '{
    "channel": "instagram",
    "recipients": ["17841472713425441", "17841999888777666"],
    "message": "Anuncio para todos"
  }'
```
