# Scraping — `/v1/scraping/*`

Web scraping con Puppeteer (Chromium headless) usando el container `browserless/chrome`. **v2** (2026-04-27): nuevo DTO con strategies, persistencia en DB con TTL automático, **session persistence** en Redis, y **lifecycle events** en tiempo real vía SSE.

**Backend:** scrapping-service (puerto 3008).

## Operaciones disponibles

| Operación | Vía | Estado |
|---|---|---|
| Crear tarea de scraping | `POST /api/v1/scraping/tasks` | ✅ disponible |
| Listar tareas | `GET /api/v1/scraping/tasks` | ✅ disponible |
| Ver una tarea | `GET /api/v1/scraping/tasks/:id` | ✅ disponible |
| Borrar tarea | `DELETE /api/v1/scraping/tasks/:id` | ✅ disponible |
| Cleanup manual de expiradas | `POST /api/v1/scraping/cleanup-expired` | ✅ disponible |
| Recibir notificación de completado | **SSE** `GET /api/v1/events?topics=scraping:<jobId>` | ✅ disponible |

> **Patrón de uso recomendado**: abrí el SSE primero, después POSTeás la tarea. Cuando complete, el SSE te empuja el resultado push-style. No necesitás hacer polling.

## ✅ Crear tarea

### `POST /api/v1/scraping/tasks`

**Patrón:** Fire-and-forget · `202 Accepted`

```json
{
  "url": "https://example.com/products",
  "userId": "scristxyz",
  "strategy": "extract",
  "selectors": {
    "title": "h1",
    "price": ".price",
    "image": { "css": "img.hero", "attr": "src" },
    "rating": { "xpath": "//div[@aria-label='rating']/@data-value" }
  },
  "performance": {
    "blockResources": true,
    "timeoutMs": 30000
  },
  "lifecycle": {
    "expiresAfterMs": 3600000,
    "metadata": { "campaign": "abril-2026" }
  }
}
```

**Response (`202 Accepted`):**

```json
{
  "jobId": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "accepted": true,
  "subscribeTo": "scraping:f47ac10b-58cc-4372-a567-0e02b2c3d479"
}
```

Usá el `subscribeTo` con el endpoint de eventos: ver [events.md](./events.md).

### Estructura del DTO completo

| Campo | Tipo | Requerido | Descripción |
|---|---|---|---|
| `url` | string (URL) | ✅ | URL completa con protocolo |
| `userId` | string | optional | tu identificador de usuario |
| `strategy` | enum | ✅ | ver tabla abajo |
| `selectors` | objeto | depende | ver "Selectores" |
| `search` | objeto | si strategy=search/login_then_search | input/submit + query |
| `login` | objeto | si strategy=login_then_* | credenciales + selectores + sessionKey opcional |
| `flow` | array | si strategy=custom_flow | pasos declarativos (navigate/click/type/wait/scroll/extract) |
| `output` | objeto | optional | a dónde mandar el resultado además del SSE |
| `performance` | objeto | optional | blockResources, cacheTtlMs, timeoutMs |
| `lifecycle` | objeto | optional | expiresAfterMs (default 24h), metadata |

### Strategies

| `strategy` | Para qué sirve |
|---|---|
| `auto` | Extracción "inteligente" sin selectores — title, sections, links, text |
| `extract` | Extracción específica vía CSS/XPath (requiere `selectors`) |
| `search` | Buscar un término en el sitio (requiere `search` + `selectors`) |
| `login_then_extract` | Login + extracción (requiere `login` + `selectors`) |
| `login_then_search` | Login + buscar + extraer (requiere `login` + `search` + `selectors`) |
| `custom_flow` | Pasos arbitrarios — para flujos complejos (requiere `flow`) |

### Selectores

Cuatro formatos soportados en el campo `selectors`:

```json
{
  "titulo": "h1",                                      // CSS plano → textContent
  "precio": ".price",
  "imagen": { "css": "img.hero", "attr": "src" },      // CSS + atributo
  "rating": { "xpath": "//div[@class='r']/@data-rating" },  // XPath
  "boton":  { "text": "Comprar ahora" }                 // Buscar por texto contenido
}
```

Si el selector matchea 1 elemento → devuelve string. Si matchea N → devuelve array.

### `login` — con persistencia de sesión

```json
"login": {
  "usernameSelector": "#email",
  "passwordSelector": "#password",
  "submitSelector": "button[type=submit]",
  "username": "user@email.com",
  "password": "secret",
  "sessionKey": "linkedin-mainacct",
  "successSelector": ".feed-identity"
}
```

- **`sessionKey`**: si lo pasás, después del login exitoso las cookies+localStorage se guardan en Redis con TTL de 7 días bajo `<dominio>:<sessionKey>`. La PRÓXIMA vez que mandes una tarea con la misma `sessionKey`, el scraper salta el login y reusa la sesión cacheada.
- **`successSelector`**: selector que solo aparece cuando estás logueado. Sirve para verificar si la sesión cacheada sigue válida — si no aparece, el scraper hace login fresh.

⚠️ **El password se redacta** (`[REDACTED]`) antes de guardarse en la DB. Solo se usa en runtime y se descarta.

### `flow` — pasos declarativos (custom_flow)

```json
"flow": [
  { "type": "navigate", "url": "https://example.com" },
  { "type": "wait", "selector": ".loaded", "timeoutMs": 5000 },
  { "type": "click", "selector": ".accept-cookies" },
  { "type": "type", "selector": "#search", "text": "laptop", "delayMs": 50 },
  { "type": "click", "selector": "button[type=submit]" },
  { "type": "wait", "selector": ".results" },
  { "type": "scroll", "toBottom": true },
  { "type": "extract", "selectors": { "products": ".product-card .title" } }
]
```

| Step type | Campos |
|---|---|
| `navigate` | `url` |
| `click` | `selector` |
| `type` | `selector`, `text`, `delayMs?` |
| `wait` | `selector?` (espera elemento) o `sleepMs?` (espera tiempo) — `timeoutMs?` |
| `scroll` | `toBottom?: boolean` o `px?: number` |
| `extract` | `selectors` (acumula en el resultado) |

### `output` — a dónde mandar el resultado

```json
"output": {
  "targets": ["event"],
  "notion":   { "parentPageId": "abc123", "title": "Producto", "icon": "🛒" },
  "whatsapp": { "to": "573205711428" },
  "email":    { "to": ["alguien@x.com"], "subject": "Resultado" }
}
```

- `event` (default si no pasás nada) — publica `channels.scraping.events.completed`. **Esto es lo que el SSE retransmite a tu frontend.**
- `notion` — además crea una página en Notion (requiere config)
- `whatsapp` — además manda mensaje (requiere `to`)
- `email` — además manda email (requiere `to`)

Es opt-in: si no pasás `output`, **solo** se emite el evento. El frontend recibe el resultado via SSE.

### `performance`

```json
"performance": {
  "blockResources": true,    // bloquea imagen/CSS/font/media → 3-5x más rápido (default true)
  "cacheTtlMs": 60000,       // misma URL+strategy en este TTL devuelve cached (default 0 = off)
  "timeoutMs": 30000         // timeout de navegación/wait (default 60000)
}
```

### `lifecycle`

```json
"lifecycle": {
  "expiresAfterMs": 86400000,           // 24h (default)
  "metadata": { "tag": "valor libre" }
}
```

El job se borra de la DB cuando `expiresAt` < `now()` y se ejecuta el cleanup. Para correr el cleanup automático cada hora:

```bash
curl -X POST http://localhost:3000/api/v1/schedules \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Scraping cleanup",
    "scheduleType": "CRON",
    "cronExpression": "0 * * * *",
    "targetRoutingKey": "channels.scraping.cleanup-expired",
    "payload": {}
  }'
```

## ✅ Listar tareas

### `GET /api/v1/scraping/tasks?limit=50&userId=scristxyz`

**Response (`200 OK`):** array de jobs (más recientes primero).

```json
[
  {
    "id": "uuid",
    "userId": "scristxyz",
    "url": "https://example.com",
    "strategy": "extract",
    "status": "SUCCESS",
    "result": { "title": "...", "price": "..." },
    "startedAt": "...",
    "completedAt": "...",
    "durationMs": 2341,
    "expiresAt": "2026-04-28T...",
    "createdAt": "..."
  }
]
```

`status`: `QUEUED` → `RUNNING` → `SUCCESS` | `FAILED`

## ✅ Ver una tarea

### `GET /api/v1/scraping/tasks/:id`

Mismo shape que el listado, un solo objeto. `404` si no existe.

## ✅ Borrar tarea

### `DELETE /api/v1/scraping/tasks/:id` → `202 Accepted`

## ✅ Cleanup expiradas (admin)

### `POST /api/v1/scraping/cleanup-expired` → `200 OK { deleted: N }`

## Ejemplos por caso de uso

### Caso 1: scraping simple con SSE

```js
// 1) Abrí SSE primero
const events = new EventSource('/api/v1/events?topics=scraping:*')
events.addEventListener('scraping:completed', (e) => {
  const data = JSON.parse(e.data)
  console.log('Listo:', data.data) // los selectores extraídos
})

// 2) Dispará la tarea
fetch('/api/v1/scraping/tasks', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    url: 'https://news.ycombinator.com',
    strategy: 'extract',
    selectors: { titles: '.titleline a' }
  })
})
```

### Caso 2: login + reusar sesión próxima vez

```json
{
  "url": "https://example.com/dashboard",
  "strategy": "login_then_extract",
  "login": {
    "usernameSelector": "#email",
    "passwordSelector": "#password",
    "submitSelector": "button[type=submit]",
    "username": "user@email.com",
    "password": "secret",
    "sessionKey": "example-mainacct",
    "successSelector": ".dashboard-header"
  },
  "selectors": {
    "balance": ".account-balance",
    "transactions": ".tx-row"
  }
}
```

Primera vez: hace login, guarda sesión.
Segunda vez con la misma `sessionKey`: salta login (ahorra ~10 segundos + reduce detección).

### Caso 3: paginación con custom_flow

```json
{
  "url": "https://example.com/products",
  "strategy": "custom_flow",
  "flow": [
    { "type": "wait", "selector": ".product-grid" },
    { "type": "extract", "selectors": { "page1": ".product .title" } },
    { "type": "click", "selector": "a.next-page" },
    { "type": "wait", "selector": ".product-grid", "timeoutMs": 5000 },
    { "type": "extract", "selectors": { "page2": ".product .title" } }
  ]
}
```

## ⚠️ Lo que NO podés hacer hoy

| Quiero… | Estado | Workaround |
|---|---|---|
| Cancelar un job en curso | falta endpoint | esperar timeout o que termine |
| Resolver Captcha (reCAPTCHA, Turnstile, etc.) | ❌ | usar service externo (2Captcha, Anti-Captcha) — no integrado |
| Rotar IPs (residential proxies) | ❌ | Fase 3 |
| 2FA/TOTP en login | ❌ | Fase 3 |
| Sitios con detección agresiva (LinkedIn, Facebook con baja tolerancia) | ⚠️ funciona a veces | session persistence + delays manuales ayudan; sin proxies residential = ban rápido |
| Capturar screenshots / PDFs | falta soporte en DTO | imposible hoy |
| Subir archivos en flow | ❌ | Puppeteer lo soporta pero el DSL no lo expone |

## Errores comunes

| Síntoma | Causa probable |
|---|---|
| `400 Validation failed: strategy must be a valid enum value` | escribiste mal `strategy` (casing matters) |
| `status: FAILED` con "TimeoutError" | el sitio tarda más que `performance.timeoutMs` (default 60s) — subir o usar `performance.blockResources: true` |
| `status: FAILED` con "selector not found" | el sitio cambió de HTML — ajustar `selectors` |
| Login falla silenciosamente | el sitio detectó el bot — agregar `successSelector` para detectarlo, considerar `login.sessionKey` para reusar manual login, o ir a Fase 3 con proxies |
| `status: FAILED` con "Browser page acquisition timeout" | pool saturado — subir `PUPPETEER_MAX_POOL_SIZE` |

## Ver también

- **[events.md](./events.md)** — SSE para recibir eventos de scraping en el frontend
- **[scheduler.md](./scheduler.md)** — programar scrapings recurrentes y el cleanup automático
