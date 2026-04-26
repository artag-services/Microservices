# Slack

Mensajería vía Slack Bot API. El microservicio `slack` (puerto 3002) consume del exchange `channels` y publica usando el `SLACK_BOT_TOKEN` de tu Slack App.

## Operaciones disponibles

| Operación | Vía | Estado |
|---|---|---|
| Enviar mensaje a canal o DM | `POST /api/v1/messages/send` | ✅ disponible |
| Consultar estado de un mensaje | `GET /api/v1/messages/:id` | ✅ disponible |
| Listar canales del workspace | — | ⚠️ falta endpoint |
| Historial de mensajes en thread | — | ⚠️ falta endpoint |
| Agregar reacción a un mensaje | — | ⚠️ falta endpoint |
| Recibir eventos (mensajes, reacciones, joins) | webhooks (no frontend) | ✅ procesa internamente |

---

## ✅ Enviar mensaje

### `POST /api/v1/messages/send`

```json
{
  "channel": "slack",
  "recipients": ["C0123456789"],
  "message": "Hola desde el sistema :wave:",
  "metadata": {}
}
```

Mensaje a un usuario directo:

```json
{
  "channel": "slack",
  "recipients": ["U0123456789"],
  "message": "Recordatorio: tu reporte está listo"
}
```

Mensaje con imagen:

```json
{
  "channel": "slack",
  "recipients": ["C0123456789"],
  "message": "Captura del dashboard",
  "mediaUrl": "https://example.com/dashboard.png"
}
```

| Campo | Tipo | Requerido | Notas |
|---|---|---|---|
| `channel` | string | ✅ | siempre `"slack"` |
| `recipients` | string[] | ✅ | channel ID o user ID de Slack |
| `message` | string | ✅ | soporta markdown de Slack (negrita `*texto*`, código `\`texto\``, emoji `:smile:`) |
| `mediaUrl` | string | optional | URL pública de imagen — Slack la attach automáticamente |
| `metadata` | object | optional | configuración extra |

**Response (`202 Accepted`):** mismo shape que los otros canales (ver [README](./README.md#patrón-de-respuesta-común)).

### Formato de `recipients`

Slack identifica todo con IDs que empiezan con una letra:

| Tipo | Empieza con | Cómo obtenerlo |
|---|---|---|
| Public channel | `C` | Click en el nombre del canal en Slack → "View channel details" → ID al final |
| Private channel (group) | `G` | Mismo método |
| Direct message a usuario | `U` | Click en el perfil del usuario → "View full profile" → "More" → "Copy member ID" |
| Group DM (mpim) | `D` | (no se obtiene fácil desde la UI de Slack) |

> ⚠️ El bot debe estar **invitado al canal** para poder postear. Si no, devuelve `not_in_channel`. Para canales públicos: `/invite @nombre-de-tu-bot`. Para DMs a usuarios: el bot tiene que tener el scope `chat:write` y el usuario debe estar en el workspace.

### Markdown soportado

```
*negrita*
_cursiva_
~tachado~
`código inline`
```bloque de código```
> cita
:emoji_name:
<https://link.com|texto del link>
<@U0123456789>     ← mención de usuario
<#C0123456789>     ← mención de canal
```

---

## ✅ Consultar estado de un mensaje

### `GET /api/v1/messages/:id`

Mismo shape que [WhatsApp](./whatsapp.md#-consultar-estado-de-un-mensaje). `status` puede ser `PENDING`, `SENT`, `FAILED`, `PARTIAL`.

> ⚠️ Slack no devuelve "delivered" ni "read" — solo "enviado al servidor". El sistema marca `SENT` cuando Slack acepta el mensaje. Si te interesa saber si alguien lo leyó, vas a tener que basarte en reacciones o respuestas.

---

## ⚠️ Lo que NO podés hacer hoy desde el frontend

| Quiero… | Estado | Cómo se hace hoy |
|---|---|---|
| Listar los canales del workspace | falta endpoint | hardcodear los IDs en el front (no ideal) |
| Buscar usuarios por nombre / email | falta endpoint | el front pide el ID al usuario admin |
| Postear en un thread (replies) | parcialmente — el campo `thread_ts` no está en el DTO | pedirle al backend que lo agregue al `metadata` y use `chat.postMessage` con `thread_ts` |
| Editar un mensaje ya enviado | falta endpoint | imposible hoy |
| Borrar un mensaje | falta endpoint | imposible hoy |
| Subir un archivo (no solo URL) | ❌ | solo URL pública en `mediaUrl` |
| Agregar reacciones (`:fire:`) | falta endpoint | imposible hoy |

---

## Webhooks entrantes (informativo)

Slack manda 15 tipos de eventos al gateway en `POST /api/webhooks/slack`. Cada uno se procesa internamente:

| Categoría | Eventos |
|---|---|
| **Mensajes** | mensaje en canal público, en grupo, DM, multi-DM, mención al bot |
| **Canales** | creado, borrado, renombrado, usuario se unió |
| **Reacciones** | agregada, removida |
| **Usuarios** | perfil actualizado, nuevo en el workspace |
| **Archivos** | subido, borrado |

El gateway verifica firma HMAC con `SLACK_SIGNING_SECRET` y rechaza con 401 si no coincide.

---

## Errores comunes

| Síntoma | Causa probable |
|---|---|
| `status` queda en `FAILED` con `not_in_channel` | el bot no está invitado al canal — mandalo con `/invite @bot` |
| `status: FAILED` con `channel_not_found` | el ID del canal está mal escrito o el bot no tiene visibilidad |
| `status: FAILED` con `invalid_auth` | `SLACK_BOT_TOKEN` venció o tiene scopes insuficientes |
| Mensaje se envía pero sin formato | usaste markdown de GitHub (`**negrita**`) en vez del de Slack (`*negrita*`) |
| El bot puede leer pero no escribir | falta scope `chat:write` en la app de Slack |

---

## Ejemplo cURL completo

```bash
curl -X POST http://localhost:3000/api/v1/messages/send \
  -H "Content-Type: application/json" \
  -d '{
    "channel": "slack",
    "recipients": ["C0123456789"],
    "message": ":wave: Hola desde el sistema"
  }'
```
