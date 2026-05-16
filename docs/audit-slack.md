# Auditoría — `slack` microservice

Fecha: 2026-05-16

## Resumen

Slack es estructuralmente más simple que WhatsApp/Instagram (no hay AI/N8N, no hay rate limiting, no hay cache de conversaciones). Pero tiene problemas más serios de **correctness y seguridad** que de performance:

- **Auto-replies de test** que enviarían DMs y mensajes a cada usuario/canal en producción (spam masivo + posible loop infinito en DMs)
- **Webhook controller muerto** que duplica al gateway y viola la regla de arquitectura "webhooks → gateway only"
- **Pollución de tabla outbound** (`SlackMessage`) con eventos de auditoría
- **Bug**: `thread_ts` vacío al dar bienvenida a miembros nuevos
- **`.js` files committeados** en `src/` (artefactos de compilación viejos)

`@slack/web-api` ya hace HTTP keep-alive + retries internamente, así que las optimizaciones de perf de WhatsApp/Instagram no aplican igual aquí.

---

## 🔴 Hallazgos críticos (fix en esta iteración)

### 1. **Auto-replies de "test" que harían spam en producción**
`SlackEventHandlerService` envía mensajes automáticos en cada evento:
- **DM ack**: cada DM recibida → bot responde "Got your message: ..."  → **loop infinito**: si el bot está en su propio DM, va a responder a su propia respuesta indefinidamente
- **Channel welcome**: cada canal nuevo → bot envía mensaje de bienvenida
- **Member welcome**: cada miembro que se une → bot menciona al usuario (con bug, ver #4)
- **App mention default reply**: cada @bot sin keyword → "Bot received your mention"
- **Team join welcome DM**: cada nuevo miembro del workspace → DM "Welcome to the workspace!"

**Fix:** quitar todo el código marcado como `Test:` / `Test response:`. El servicio debe sólo loguear el evento, no responder automáticamente. La lógica de respuesta es del consumidor (gateway/agent/n8n), no del listener de Slack.

### 2. **`WebhookController` muerto y duplicado**
`/webhook/slack` en este servicio recibe POSTs directos, pero `processEvent()` sólo loguea — nunca publica a RabbitMQ. Los eventos reales llegan al gateway y se bridgean por RMQ (que es lo que el `SlackListener` consume).

Además viola la regla de CLAUDE.md / memoria: "webhooks land at gateway and bridge to services via RabbitMQ events; never expose microservice HTTP to providers".

**Fix:** borrar `WebhookModule` entero. El gateway es la entrada única.

### 3. **Pollución de `SlackMessage` con eventos de auditoría**
`logEventToMessages()` inserta cada evento como un registro `status='SENT'` en la tabla `SlackMessage`. Esa tabla es para **mensajes salientes propios**, no para audit de eventos entrantes. Métricas, dashboards y queries futuras se van a corromper.

**Fix:** quitar `logEventToMessages`. Loguear con `Logger` (structured) y, si hace falta persistencia de eventos en el futuro, agregar un modelo `SlackEvent` aparte.

### 4. **Bug: `thread_ts` vacío**
```ts
await this.slack.postThreadReply(channelId, welcomeMsg, '', false)
```
`thread_ts=''` no es un thread válido → la API de Slack puede tirar error o, peor, postear como mensaje top-level en el canal (spam adicional al bug del #1).

**Fix:** este auto-reply se elimina entero con #1, así que el bug desaparece.

### 5. **`enableShutdownHooks()` faltante**
NestJS no cierra prolijamente RabbitMQ/Prisma al recibir SIGTERM.
**Fix:** `app.enableShutdownHooks()` en main.ts.

### 6. **Stale `.js` files committeados en `src/`**
Hay 6 `.js` files alongside `.ts` sources (residuos de `tsc` viejo). Confunde lecturas y no se rebuilden — `nest build` los ignora pero el repo queda sucio.

**Fix:** borrar.

---

## 🟡 Hallazgos medios

### 7. **WebClient sin config explícita**
`new WebClient(token)` usa defaults (30s timeout, retries automáticos). Está OK pero conviene hacerlo configurable por env.

**Fix:** pasar `{ timeout, retryConfig }` desde `ConfigService`.

### 8. **Webhook signature verification implementada pero no llamada**
`verifySignature()` existe pero ningún controller la usa. Se elimina con #2.

### 9. **`postMessage` con bloque image + section** envía el `alt_text` igual al texto principal — accessibility floja, pero no crítico.

---

## 🟢 Hallazgos menores (no fix por ahora)

### 10. **No hay rate limiting propio**
Slack API tiene rate limits propios y el SDK ya hace backoff. Suficiente.

### 11. **Sin circuit breaker**
WebClient ya hace retries con jitter. Suficiente para esta escala.

### 12. **Event handler tiene 15 casos en un switch** — funciona, pero un map de `eventType → handler` sería más limpio. Cosmético.

---

## Cambios aplicados en esta iteración

1. ✅ **Removido todo el auto-reply de test** del event handler (DM ack, channel welcome, member welcome, app-mention default, team-join DM)
2. ✅ **Borrado `WebhookModule` entero** (gateway es la entrada única)
3. ✅ **`logEventToMessages` removido** — eventos sólo se loguean, no se persisten en `SlackMessage`
4. ✅ **WebClient configurable** via `SLACK_API_TIMEOUT_MS` y `SLACK_API_MAX_RETRIES`
5. ✅ **`enableShutdownHooks()`** en main.ts
6. ✅ **Borrados 6 `.js` files** stale de `src/`
7. ✅ **Event handler simplificado** — ahora sólo loguea estructuradamente y deja que otros consumers procesen
8. ✅ **Lazy debug logging** donde había evaluación de strings pesados

## Próximos pasos (no implementados ahora)

- [ ] Si hace falta audit persistente de eventos: agregar modelo `SlackEvent`
- [ ] Health endpoint formal (/health) con check de Slack API + RabbitMQ + DB
- [ ] Adapter pattern si querés soportar Discord/Teams además de Slack
- [ ] Tests para `SlackService` (sólo si va a prod)
- [ ] Métricas Prometheus

## Nuevas env vars (con defaults sanos)

| Variable | Default | Descripción |
|---|---|---|
| `SLACK_API_TIMEOUT_MS` | `30000` | Timeout HTTP a Slack |
| `SLACK_API_MAX_RETRIES` | `3` | Reintentos automáticos del SDK |
