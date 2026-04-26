# Webhooks — `/webhooks/*`

> ⚠️ **Estos endpoints NO son para el frontend.** Son los puntos de entrada que los proveedores externos (Meta, Slack, Notion, Resend) usan para notificarle al sistema que ocurrió algo (mensaje recibido, email entregado, etc.). Documentado solo para que entiendas qué pasa "del otro lado".

Patrón general:
1. Provider externo manda `POST /api/webhooks/<provider>` con su payload + headers de firma
2. Gateway valida la firma HMAC (cada provider usa su propio esquema)
3. Si OK, gateway publica un evento a `channels.<service>.events.<tipo>` en RabbitMQ
4. El microservicio correspondiente consume y actualiza state / dispara acciones

Esta es la implementación de **Ley #1** del proyecto: solo el gateway está expuesto a internet, los microservicios viven en la red interna.

## Resumen

| Provider | URL | Verificación firma | Publica a |
|---|---|---|---|
| Meta WhatsApp | `POST /api/webhooks/whatsapp` | X-Hub-Signature-256 (HMAC-SHA256) | `channels.whatsapp.events.*` |
| Meta Instagram | `POST /api/webhooks/instagram` | X-Hub-Signature-256 (HMAC-SHA256) | `channels.instagram.events.*` |
| Meta Facebook (no doc dedicada — mismo patrón) | `POST /api/webhooks/facebook` | X-Hub-Signature-256 | `channels.facebook.events.*` |
| Slack | `POST /api/webhooks/slack` | HMAC-SHA256 con timestamp + signing secret | `channels.slack.events.*` |
| Notion | `POST /api/webhooks/notion` | verification_token (handshake) | `channels.notion.events.*` |
| Resend | `POST /api/webhooks/resend` | Svix HMAC (`svix-id` + `svix-timestamp` + `svix-signature`) | `channels.email.webhook.resend` |

## Handshakes (verificación inicial al configurar el webhook)

Algunos providers verifican la URL antes de empezar a mandar eventos. Eso lo hace el gateway automáticamente:

### Meta (WhatsApp / Instagram / Facebook)
`GET /api/webhooks/<provider>?hub.mode=subscribe&hub.verify_token=<TOKEN>&hub.challenge=<token>`
→ Si el `verify_token` coincide con `<PROVIDER>_WEBHOOK_VERIFY_TOKEN` en `.env`, devuelve el `challenge`.

### Notion
Primer `POST` con body `{ "verification_token": "secret_..." }` → se logea en consola, lo copiás al `.env` como `NOTION_WEBHOOK_VERIFICATION_TOKEN`.

### Slack
Primer `POST` con body `{ "type": "url_verification", "challenge": "..." }` → devuelve el challenge.

### Resend
No tiene handshake — solo registrás la URL y empieza a mandar eventos firmados con Svix.

## Firma HMAC (qué pasa si no coincide)

- **Resend**: 401 Unauthorized (configurado en este proyecto)
- **Slack**: 401 Unauthorized + log de warning
- **Meta**: por ahora simplificado, no rechaza estrictamente — TODO endurecer
- **Notion**: token en body, no header — verificación manual

## Lo que el frontend SÍ puede hacer

- Si necesitás reaccionar en tiempo real a eventos externos (mensaje nuevo de WhatsApp, email entregado, etc.) la opción correcta es:
  1. Suscribirse a un **websocket en el gateway** que retransmita los broadcasts de `channels.*.events.*` (no implementado hoy — habría que agregar un módulo websocket-bridge)
  2. O hacer **polling** del recurso (ej: `GET /v1/emails/:id` cada N segundos para ver si cambió `status`)

## Lo que el frontend NO puede ni debe hacer

- ❌ Llamar directamente a `/api/webhooks/*` desde el navegador. Está pensado solo para los servidores de los providers.
- ❌ Confiar en estos endpoints para nada — pueden cambiar / agregar firmas más estrictas en cualquier momento.
- ❌ Falsificar eventos (no podés firmar correctamente sin el secret de cada provider).

## Si querés ver eventos llegando en tiempo real

Mientras desarrollás, podés:
```bash
docker-compose logs -f gateway | grep -i webhook
docker-compose logs -f <servicio> | grep -i event
```

Verás cada evento entrante + cómo se rutea al servicio correspondiente.
