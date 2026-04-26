# WhatsApp

Mensajería vía Meta WhatsApp Cloud API. El microservicio `whatsapp` (puerto 3001) consume del exchange `channels` y dialoga con la Cloud API de Meta usando los tokens de tu cuenta de WhatsApp Business.

## Operaciones disponibles

| Operación | Vía | Estado |
|---|---|---|
| Enviar mensaje (texto / media) | `POST /api/v1/messages/send` | ✅ disponible |
| Consultar estado de un mensaje | `GET /api/v1/messages/:id` | ✅ disponible |
| Enviar plantilla pre-aprobada | — | ⚠️ backend lo soporta, falta endpoint en gateway |
| Listar conversaciones activas | — | ⚠️ falta endpoint |
| Obtener perfil de usuario | — | ⚠️ falta endpoint |
| Recibir mensajes entrantes | webhooks (no frontend) | ✅ procesa internamente |

---

## ✅ Enviar mensaje

### `POST /api/v1/messages/send`

```json
{
  "channel": "whatsapp",
  "recipients": ["573205711428"],
  "message": "Hola, este es un mensaje de prueba",
  "mediaUrl": "https://example.com/imagen.jpg",
  "metadata": {
    "campaignId": "abril-2026"
  }
}
```

| Campo | Tipo | Requerido | Notas |
|---|---|---|---|
| `channel` | string | ✅ | siempre `"whatsapp"` |
| `recipients` | string[] | ✅ | mín 1, números con código de país sin `+` (ej: `"573205711428"`) |
| `message` | string | ✅ | texto del mensaje |
| `mediaUrl` | string | optional | URL pública de imagen, video o documento |
| `metadata` | object | optional | tags propios, no se mandan a WhatsApp |

**Response (`202 Accepted`):**

```json
{
  "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "accepted": true,
  "channel": "whatsapp",
  "recipients": ["573205711428"],
  "message": "Hola, este es un mensaje de prueba",
  "status": "PENDING",
  "createdAt": "2026-04-25T18:42:11.123Z"
}
```

### Formato de `recipients`

WhatsApp espera el número **con código de país, sin `+`, sin espacios, sin guiones**:

| ❌ Incorrecto | ✅ Correcto |
|---|---|
| `"+57 320 5711428"` | `"573205711428"` |
| `"320-571-1428"` | `"573205711428"` |
| `"3205711428"` (sin país) | `"573205711428"` |

### Limitaciones conocidas

- **Ventana de 24h**: WhatsApp solo permite mandar mensajes libres si el usuario te escribió primero en las últimas 24 horas. Fuera de esa ventana necesitás usar plantillas pre-aprobadas (no expuestas todavía).
- **Plantillas**: si el usuario nunca te escribió, el envío va a fallar silenciosamente con error de "fuera de ventana". Solución temporal: pedirle que te escriba primero, o pedir al backend que exponga el endpoint de templates.
- **Rate limit de Meta**: ~80 mensajes por segundo por número. Si te excedés, errores 429.
- **Media size**: imágenes hasta 5MB, video hasta 16MB, documentos hasta 100MB.

---

## ✅ Consultar estado de un mensaje

### `GET /api/v1/messages/:id`

Donde `:id` es el `id` que te devolvió el `POST /send`.

**Response (`200 OK`):**

```json
{
  "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "channel": "whatsapp",
  "recipients": ["573205711428"],
  "message": "Hola...",
  "status": "SENT",
  "createdAt": "2026-04-25T18:42:11.123Z",
  "updatedAt": "2026-04-25T18:42:14.567Z"
}
```

`status` posibles:
- `PENDING` — encolado, todavía no procesado
- `SENT` — enviado a Meta, en su cola
- `FAILED` — error al enviar (ej: número inválido, fuera de ventana 24h)
- `PARTIAL` — algunos destinatarios OK, otros no (cuando hay múltiples)

> ⚠️ **No hay `DELIVERED` ni `READ`** todavía. Meta manda esos eventos pero el sistema no los persiste en este modelo. Si los necesitás, pedile al backend que los agregue (los webhooks `channels.whatsapp.events.message_echo` ya entran al sistema, solo falta consumirlos).

---

## ⚠️ Lo que NO podés hacer hoy desde el frontend

| Quiero… | Estado | Cómo se hace hoy |
|---|---|---|
| Mandar plantilla pre-aprobada | falta endpoint gateway | manda mensaje normal y si la respuesta es `FAILED` por ventana de 24h, mostrá un mensaje al usuario |
| Listar las conversaciones que tengo abiertas | falta endpoint | usá el módulo [conversations](../conversations.md) que es agnóstico al canal |
| Ver historial de mensajes con un usuario | falta endpoint | usá `GET /api/v1/conversations/:id/messages` |
| Ver delivery / read receipts | falta consumer en backend | no posible hoy |
| Enviar múltiples a la vez | ✅ usá `recipients: ["...", "..."]` | hasta el rate limit de Meta |
| Adjuntar archivos como upload (multipart) | ❌ | solo URL pública |

---

## Webhooks entrantes (informativo — el frontend no los llama)

WhatsApp manda eventos al gateway en `POST /api/webhooks/whatsapp` cuando:

- Llega un mensaje nuevo (`channels.whatsapp.events.message`) — el sistema resuelve identidad y opcionalmente dispara IA
- Cambio de número de teléfono (`channels.whatsapp.events.phone_number_update`) — actualiza identidad
- Llamadas (`channels.whatsapp.events.calls`) — stub
- Status de plantillas (`channels.whatsapp.events.template_update`) — stub
- Alertas de cuenta (`channels.whatsapp.events.alerts`) — stub

Si el front necesita reaccionar a "mensaje recibido" en tiempo real, hay que agregar un WebSocket bridge en el gateway que retransmita estos eventos.

---

## Errores comunes

| Síntoma | Causa probable |
|---|---|
| `400 Validation failed` | `recipients` no es array, falta `message`, o el número trae `+` |
| `status` queda en `FAILED` | número fuera de ventana de 24h, o número inválido |
| El mensaje "se envía" pero el usuario nunca lo recibe | Meta puede silenciosamente bloquear si tu número de WhatsApp Business tiene mala reputación. Verificá el quality rating en el Meta Business Manager. |
| `500 Internal Server Error` | el microservicio whatsapp está caído o el `WHATSAPP_API_TOKEN` venció |

---

## Ejemplo cURL completo

```bash
curl -X POST http://localhost:3000/api/v1/messages/send \
  -H "Content-Type: application/json" \
  -d '{
    "channel": "whatsapp",
    "recipients": ["573205711428"],
    "message": "Test desde curl"
  }'
```
