# Email — `/v1/emails/*`

Envío de emails transaccionales. El backend usa un patrón de **adapters**: en producción manda con [Resend](https://resend.com), en dev podés capturar con [Mailpit](https://mailpit.axllent.org/) sin gastar créditos. Tracking completo de lifecycle (sent → delivered → opened → clicked) vía webhooks.

**Backend:** email-service (puerto 3007). Provider activo: `EMAIL_PROVIDER=resend` en `.env`.

## Endpoints

### `POST /v1/emails`
**Patrón:** RPC · `200 OK`

Envía un email. Espera la respuesta del provider antes de devolver.

```json
{
  "to": ["scristxyz@gmail.com"],
  "cc": ["copia@dominio.com"],
  "bcc": ["oculto@dominio.com"],
  "from": "Soporte <soporte@artagdev.com.co>",
  "replyTo": "respondeme@artagdev.com.co",
  "subject": "Bienvenido a la plataforma",
  "html": "<h1>Hola!</h1><p>Tu cuenta está lista.</p>",
  "text": "Hola! Tu cuenta está lista.",
  "idempotencyKey": "welcome-user-uuid-2026-04-25",
  "metadata": {
    "campaign": "onboarding-abril",
    "userId": "u_xyz"
  }
}
```

| Campo | Tipo | Requerido | Notas |
|---|---|---|---|
| `to` | string[] | ✅ | mín 1, máx 50 emails válidos |
| `cc` | string[] | optional | emails válidos |
| `bcc` | string[] | optional | emails válidos |
| `from` | string | optional | si lo omitís, usa `EMAIL_FROM_NAME <EMAIL_FROM>` del `.env` |
| `replyTo` | string | optional | email válido |
| `subject` | string | ✅ | asunto |
| `html` | string | optional | cuerpo HTML — recomendado |
| `text` | string | optional | versión texto plano (fallback para clientes sin HTML) |
| `idempotencyKey` | string | optional | si reenvías la misma key, devuelve el original sin reenviar |
| `metadata` | objeto | optional | JSON libre, queda guardado en tu DB para analytics |

**Response:**
```json
{
  "id": "uuid-en-tu-db",
  "to": ["scristxyz@gmail.com"],
  "from": "Artag <noreply@artagdev.com.co>",
  "subject": "...",
  "provider": "resend",
  "providerMessageId": "id-de-resend",
  "status": "SENT",
  "sentAt": "2026-04-25T...",
  "createdAt": "2026-04-25T..."
}
```

> El `from` debe ser de un dominio **verificado en Resend**. Si tu dominio es `artagdev.com.co` y mandás `from: "x@otra-cosa.com"`, Resend lo rechaza con error.

---

### `GET /v1/emails`
**Patrón:** RPC · `200 OK`

Lista emails enviados (más recientes primero).

**Query params:**
- `limit` (default 50)

**Response:** array de emails (mismo shape que `POST` response, sin el `events`).

---

### `GET /v1/emails/:id`
**Patrón:** RPC · `200 OK`

Detalle de un email específico, incluyendo su historial de eventos.

**Response:**
```json
{
  "id": "uuid",
  "to": ["..."],
  "subject": "...",
  "status": "DELIVERED",
  "providerMessageId": "...",
  "sentAt": "...",
  "deliveredAt": "...",
  "openedAt": null,
  "events": [
    {
      "id": "uuid",
      "type": "email.delivered",
      "occurredAt": "2026-04-25T...",
      "rawPayload": { ... }
    }
  ]
}
```

`status` posibles:
- `QUEUED` — guardado en DB pero todavía no enviado al provider
- `SENT` — provider lo aceptó, está en su cola
- `DELIVERED` — provider confirmó entrega al MTA destino
- `BOUNCED` — el destinatario rechazó (mailbox inexistente, full, etc.)
- `COMPLAINED` — el destinatario lo marcó como spam
- `FAILED` — error al enviar (API key inválida, etc.)
- `OPENED` / `CLICKED` — solo si activaste tracking en Resend

> El `status` empieza en `SENT` y va cambiando a medida que llegan webhooks de Resend. Si querés saber el estado final, hacé polling o suscribite a los eventos broadcast (`channels.email.events.*`) desde otro servicio.

---

## Idempotencia

Si mandás dos requests `POST /v1/emails` con el mismo `idempotencyKey`, la segunda **no envía un nuevo email** — te devuelve el registro de la primera. Útil cuando:
- El usuario hace doble-click en "Enviar"
- Tu frontend reintenta una request fallida y no quiere duplicar
- Un mismo evento de negocio puede disparar varios envíos accidentales

**Recomendación:** usar un key derivado del evento de negocio, no un random:
- ✅ `idempotencyKey: "welcome-{userId}"`
- ✅ `idempotencyKey: "invoice-{invoiceId}"`
- ❌ `idempotencyKey: uuid()` (no idempotiza nada)

---

## Webhook tracking (cómo cambia el `status`)

Resend manda webhooks a `/api/webhooks/resend` cuando ocurre algo (delivered, bounced, opened, etc.). El gateway:
1. Verifica firma HMAC con `RESEND_WEBHOOK_SECRET` (rechaza inválidos con 401)
2. Publica el evento a `channels.email.webhook.resend`
3. El email-service consume y actualiza el `EmailMessage` correspondiente

El frontend no se entera directo del webhook — tenés que pollear `GET /v1/emails/:id` o suscribirte a los broadcast (futuro WS bridge).

---

## Lo que SÍ podés hacer

- Enviar email transaccional con HTML + texto plano
- A múltiples destinatarios (TO/CC/BCC) hasta 50
- Override del `from` por email (siempre que sea de un dominio verificado)
- Idempotencia para evitar duplicados
- Tracking de delivered/bounced/opened/clicked
- Listar y consultar histórico
- Adjuntar metadata custom para analytics propios
- En dev: capturar TODO con Mailpit (UI en `:8025`) cambiando `EMAIL_PROVIDER=smtp`

## Lo que NO podés hacer

- ❌ Adjuntar archivos (Resend SDK los soporta, pero el DTO actual no expone el campo `attachments`)
- ❌ Programar envío a futuro **desde este endpoint**. Usá [scheduler](./scheduler.md) con `targetRoutingKey: "channels.email.send"`.
- ❌ Cancelar un email ya enviado al provider.
- ❌ Reenviar un email anterior (no hay endpoint "resend"). Tenés que hacer otro `POST /v1/emails`.
- ❌ Templates con variables tipo `Hola {{nombre}}`. Tenés que generar el HTML en el frontend o backend antes de mandar.
- ❌ A/B testing nativo.
- ❌ Listas / contactos. Esto es transaccional, no marketing — para newsletters usá un servicio aparte (Loops, Mailchimp, ...).
- ❌ Recibir emails (inbound). Para eso hace falta DNS MX + Cloudflare Email Routing → webhook al gateway. No está implementado todavía.

## Errores comunes

| Síntoma | Causa probable |
|---|---|
| `400 Validation failed` | `to` no es array, falta `subject`, email mal formado |
| `500 Resend error: ...` | `from` no es de dominio verificado, API key inválida, dominio en sandbox solo permite enviar a tu propia dirección |
| Email se queda en `SENT` y nunca llega a `DELIVERED` | Webhook no configurado en Resend dashboard, o `RESEND_WEBHOOK_SECRET` faltante en server, o URL del webhook no apunta correctamente |
| Email a destino externo falla en sandbox | Resend tiene un sandbox mode hasta que te aprueben — solo podés enviar a tu propio email registrado |
