# Auditoría — `notion` microservice

Fecha: 2026-05-16

## Resumen

`notion` es el servicio más simple del stack: una sola entrada (`channels.notion.send` → `execute`) que dispatcha a 3 operaciones. Usa el SDK oficial `@notionhq/client` así que la parte HTTP/auth está cubierta. Los problemas son de **correctness y robustez** (no de perf):

- Webhook controller dead que viola la regla "webhooks → gateway only"
- `invite_member` es un placeholder que falla silenciosamente (hace un `pages.update` con properties vacías y solo loguea un warn)
- Si la operación falla, el `NotionListener` **no publica nada al scrapping service** → el flujo scrapping→notion→whatsapp se queda colgado
- Sin retry on 429 (Notion rate-limits a 3 req/s/integration; el SDK no auto-reintenta)
- `messageId @@unique` rompe idempotencia: reintentar con mismo `messageId` tira `P2002` en vez de devolver el resultado anterior
- `enableShutdownHooks()` faltante

---

## 🔴 Hallazgos críticos (fix en esta iteración)

### 1. **Listener no publica failure al scrapping service**
```ts
if (response.status === 'SUCCESS') {
  this.rabbitmq.publish(ROUTING_KEYS.SCRAPPING_NOTION_RESPONSE, { ... })
}
```
Si la operación falla (token inválido, parent_page_id incorrecto, rate-limit, etc), el `scrapping` service nunca se entera. Sigue esperando indefinidamente la confirmación, y el flujo scrapping → notion → whatsapp se rompe sin alarmas.

**Fix:** publicar `SCRAPPING_NOTION_RESPONSE` con `status: 'FAILED'` y `error` cuando falla, así el consumer puede decidir reintentar o avisar al usuario.

### 2. **`invite_member` está roto en silencio**
La operación hace un `pages.update({ properties: {} })` (no-op) y loguea un warning. El frontend o caller recibe `status: 'SUCCESS'` con un `notionId` que no representa una invitación real.

**Fix:** tirar `BadRequestException` claro: "invite_member no está soportado vía Notion integration tokens; usar OAuth user tokens". Mejor que mentir un SUCCESS.

### 3. **No idempotencia en `messageId`**
El schema tiene `messageId @unique`. Si el caller hace retry de un mensaje fallido con el mismo `messageId`, el `prisma.notionOperation.create` tira `P2002 Unique constraint failed`. El error se reporta como FAILED — pero la causa real es "ya lo intentamos", no "el Notion API falló".

**Fix:** lookup por `messageId` primero. Si existe + SUCCESS → devolver el resultado cacheado. Si existe + FAILED → reusar el registro y reintentar. Si no existe → crear y ejecutar.

### 4. **WebhookController dead + viola arquitectura**
`/webhook/notion` solo loguea. No hay flujo real (Notion no manda webhooks tradicionales; las "automations" son otra cosa). Viola la regla "webhooks land at gateway only".

**Fix:** borrar `WebhookModule` entero.

### 5. **Sin retry en rate-limit (429) de Notion**
Notion rate-limita a **3 requests/segundo por integration**. Es fácil tocarlo cuando hay scrapping batch + notion creates concurrentes. El SDK no auto-reintenta.

**Fix:** wrapper con retry exponencial en 429/5xx con `Retry-After` header respect.

### 6. **`enableShutdownHooks()` faltante** en main.ts
**Fix:** misma corrección que en los otros servicios.

---

## 🟡 Hallazgos medios

### 7. **Timeout no configurable**
`new NotionClient({ auth: token })` usa el default del SDK (60s). Bajo carga, workers de RabbitMQ pueden quedar colgados.

**Fix:** pasar `timeoutMs` explícito (default 30s, configurable).

### 8. **`(dto.metadata as any)?.userId`** en listener — sloppy pero funciona. Cosmético.

### 9. **`splitTextIntoChunks`** hardcodea `maxLength = 2000`. Notion permite 2000 chars por bloque pero también podrías mandar más bloques. OK, no urgente.

---

## 🟢 Hallazgos menores (no fix por ahora)

### 10. **Sin health endpoint** — útil para monitoring
### 11. **Sin métricas Prometheus**
### 12. **Tablas pre-existentes** (`days_off`, `inventory`, `n8n_vectors`) en `schema.prisma` — ya marcadas "never drop", solo es ruido visual
### 13. **`operationHandlers` tipo dispatch** es bueno pero las metadatas son loose-typed. Type safety mejorable con generics, pero no urgente

---

## Cambios aplicados en esta iteración

1. ✅ **`NotionApiClient`** wrapper con retry exponencial en 429/5xx (respeta `Retry-After`)
2. ✅ **Timeout configurable** via `NOTION_API_TIMEOUT_MS` (default 30s)
3. ✅ **Retries configurables** via `NOTION_API_MAX_RETRIES` (default 3)
4. ✅ **Listener publica failure** al scrapping service (status FAILED + error)
5. ✅ **Idempotency en `execute()`** — lookup por messageId, devuelve cached SUCCESS o reusa registro FAILED
6. ✅ **`invite_member` ahora tira `BadRequestException`** explicando que no está soportado vía integration tokens
7. ✅ **`enableShutdownHooks()`** en main.ts
8. ✅ **Borrado `WebhookModule`** (webhooks land at gateway)

## Próximos pasos (no implementados ahora)

- [ ] Si necesitás invite real: implementar via Notion OAuth (user tokens)
- [ ] Health endpoint
- [ ] Métricas Prometheus
- [ ] Tests unitarios para `NotionService` + `NotionApiClient`
- [ ] Más operaciones: `update_page`, `delete_page`, `query_database`, `append_block`

## Nuevas env vars (con defaults sanos)

| Variable | Default | Descripción |
|---|---|---|
| `NOTION_API_TIMEOUT_MS` | `30000` | Timeout HTTP a Notion |
| `NOTION_API_MAX_RETRIES` | `3` | Reintentos en 429/5xx |
| `NOTION_API_RETRY_BASE_MS` | `500` | Backoff inicial (exponencial 1x, 2x, 4x, ...) |
