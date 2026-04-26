# Facebook

Mensajería vía Meta Messenger Platform (la "página de Facebook" responde a los mensajes que le envían). El microservicio `facebook` (puerto 3006) consume del exchange `channels` y publica usando el `FACEBOOK_PAGE_ACCESS_TOKEN` de tu Page.

## Operaciones disponibles

| Operación | Vía | Estado |
|---|---|---|
| Enviar mensaje vía Page | `POST /api/v1/messages/send` | ✅ disponible |
| Consultar estado de un mensaje | `GET /api/v1/messages/:id` | ✅ disponible |
| Listar conversaciones activas | — | ⚠️ falta endpoint |
| Obtener perfil de un PSID | — | ⚠️ falta endpoint |
| Handover a un agente humano | — | ⚠️ falta endpoint |
| Recibir mensajes entrantes | — | ❌ webhook no implementado todavía |

---

## ✅ Enviar mensaje

### `POST /api/v1/messages/send`

```json
{
  "channel": "facebook",
  "recipients": ["123456789012345"],
  "message": "Hola, gracias por escribir a nuestra Página",
  "mediaUrl": "https://example.com/imagen.jpg",
  "metadata": {
    "messaging_type": "RESPONSE"
  }
}
```

| Campo | Tipo | Requerido | Notas |
|---|---|---|---|
| `channel` | string | ✅ | siempre `"facebook"` |
| `recipients` | string[] | ✅ | array de PSIDs (Page-Scoped User IDs) |
| `message` | string | ✅ | texto del mensaje |
| `mediaUrl` | string | optional | URL pública de imagen |
| `metadata.messaging_type` | enum | optional | `"RESPONSE"` (default), `"UPDATE"`, `"MESSAGE_TAG"` |
| `metadata.tag` | string | required si `messaging_type=MESSAGE_TAG` | uno de `"CONFIRMED_EVENT_UPDATE"`, `"POST_PURCHASE_UPDATE"`, `"ACCOUNT_UPDATE"` |

**Response (`202 Accepted`):** mismo shape genérico.

### Sobre `messaging_type` (importante)

Meta tiene reglas estrictas sobre cuándo podés mandar mensajes:

| Type | Cuándo usar | Restricción |
|---|---|---|
| `RESPONSE` | Respondiendo a un mensaje del usuario en las últimas 24h | Default — no necesita tag |
| `UPDATE` | Notificación proactiva al usuario | Solo dentro de la ventana de 24h |
| `MESSAGE_TAG` | Fuera de la ventana de 24h, para casos específicos | **Requiere `tag`** + el caso debe coincidir con el tag |

**Tags válidos:**
- `CONFIRMED_EVENT_UPDATE` — recordatorio de evento confirmado
- `POST_PURCHASE_UPDATE` — actualización de compra (envío, etc.)
- `ACCOUNT_UPDATE` — cambio en la cuenta del usuario (no marketing)

> ⚠️ Si abusás de los tags (mandando marketing genérico), Meta puede restringir tu Page. Solo úsalos para los casos legítimos que cubren.

---

## ✅ Consultar estado

### `GET /api/v1/messages/:id`

Mismo shape que los otros canales. `status` puede ser `PENDING`, `SENT`, `FAILED`, `PARTIAL`.

---

## ⚠️ Lo que NO podés hacer hoy desde el frontend

| Quiero… | Estado | Workaround |
|---|---|---|
| Listar las conversaciones activas de mi Page | falta endpoint | imposible hoy desde el front — el operador tiene que ir a Meta Business Manager |
| Ver el nombre/avatar del usuario detrás de un PSID | falta endpoint | hardcodear o pedir al backend que lo agregue |
| Historial de mensajes con un PSID | falta endpoint | usar `GET /api/v1/conversations/:id/messages` (agnóstico al canal) |
| Hacer handover a un agente humano (desactivar bot) | falta endpoint | imposible hoy |
| Recibir mensajes entrantes en tiempo real | webhook no implementado | el sistema no procesa todavía mensajes que llegan a tu Page de Facebook — pedile al backend que active el consumer |
| Subir imagen como upload | ❌ | solo URL pública |
| Quick replies / botones | ❌ | el DTO actual no soporta structured messages — solo texto plano + imagen |
| Send Sponsored Messages | ❌ | requiere features avanzadas de Meta no implementadas |

---

## Webhooks entrantes (informativo)

> ❌ **El microservicio facebook NO procesa webhooks entrantes hoy.** El gateway tiene un controller en `POST /api/webhooks/facebook` que recibe los eventos de Messenger pero no los publica a ningún routing key (a diferencia de WhatsApp e Instagram que sí). Esto significa que **mensajes que tu Page recibe de usuarios no llegan a tu sistema**.

Para que funcione, hace falta:
1. Definir routing keys (`channels.facebook.events.message`, etc.) en `gateway/src/rabbitmq/constants/queues.ts` y en `facebook/src/rabbitmq/constants/queues.ts`
2. Implementar el consumer en el microservicio `facebook` similar a como lo hacen `whatsapp` e `instagram`
3. Hacer que el `facebook.webhook.controller.ts` del gateway publique los eventos al exchange

---

## Sobre los PSIDs

Facebook identifica usuarios con **PSIDs** (Page-Scoped User IDs):

- Número largo tipo `"123456789012345"`
- Es **único por Page** — el mismo usuario tiene un PSID distinto si interactúa con otra Page
- Solo lo obtenés cuando el usuario te escribe primero (vía webhook) — pero como el webhook no funciona todavía, **no tenés forma fácil de descubrir PSIDs desde el sistema**
- En el meantime: andá a Meta Business Manager → Inbox → click en una conversación → el PSID aparece en la URL

---

## Errores comunes

| Síntoma | Causa probable |
|---|---|
| `status: FAILED` con `(#10) Application does not have permission` | tu app no tiene `pages_messaging` permission aprobado por Meta |
| `status: FAILED` con `(#100) recipient not found` | PSID inválido o pertenece a otra Page |
| Mensaje se envía pero el usuario nunca lo recibe | el usuario nunca te escribió en las últimas 24h y no usaste un `messaging_type=MESSAGE_TAG` válido |
| `FACEBOOK_PAGE_ACCESS_TOKEN` venció | los Page tokens son de larga duración pero igual pueden expirar — regenerar en Meta Business |

---

## Ejemplo cURL completo

```bash
# Respuesta dentro de la ventana de 24h:
curl -X POST http://localhost:3000/api/v1/messages/send \
  -H "Content-Type: application/json" \
  -d '{
    "channel": "facebook",
    "recipients": ["123456789012345"],
    "message": "Gracias por escribirnos. Pronto te respondemos.",
    "metadata": { "messaging_type": "RESPONSE" }
  }'

# Notificación de compra fuera de la ventana de 24h:
curl -X POST http://localhost:3000/api/v1/messages/send \
  -H "Content-Type: application/json" \
  -d '{
    "channel": "facebook",
    "recipients": ["123456789012345"],
    "message": "Tu pedido #456 fue despachado. Tracking: ABC123",
    "metadata": {
      "messaging_type": "MESSAGE_TAG",
      "tag": "POST_PURCHASE_UPDATE"
    }
  }'
```
