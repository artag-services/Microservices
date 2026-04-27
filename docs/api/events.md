# Events (SSE) — `/v1/events`

Server-Sent Events bus reusable. Suscribite por **topic** y recibís push real-time desde cualquier servicio fire-and-forget (scraping, email, scheduler, future). Una sola conexión cubre todos los servicios.

## Endpoint

### `GET /api/v1/events?topics=<comma-separated>`

**Response:** stream `Content-Type: text/event-stream` que NO se cierra. Cada evento tiene formato SSE estándar:

```
event: scraping:completed
data: {"jobId":"abc","success":true,"data":{...},...}

event: email:delivered
data: {"emailId":"xyz",...}
```

### Sintaxis de topics

| Topic | Significado |
|---|---|
| `scraping:abc-uuid` | eventos de UN scraping específico |
| `email:xyz-uuid` | eventos de UN email específico |
| `scheduler:task-uuid` | eventos de UNA tarea programada |
| `scraping:*` | TODOS los eventos de scraping (debug / dashboard) |
| `email:*` | TODOS los eventos de email |
| `*` | TODOS los eventos del sistema (use sparingly) |

Múltiples topics separados por coma:

```
GET /api/v1/events?topics=scraping:abc,scraping:def,email:xyz
```

## Eventos que recibís

### Scraping

| `event` | Cuándo | Payload |
|---|---|---|
| `scraping:queued` | Job persistido, antes de ejecutar | `{ jobId, url, userId }` |
| `scraping:started` | Puppeteer arranca | `{ jobId, url, userId }` |
| `scraping:completed` | Scraping exitoso | `{ jobId, url, success: true, data: {...}, durationMs, ... }` |
| `scraping:failed` | Error o timeout | `{ jobId, url, success: false, error: "...", ... }` |

### Email

| `event` | Cuándo | Payload |
|---|---|---|
| `email.sent` / `email.delivered` / `email.bounced` / etc. | Cuando llega el webhook de Resend | `{ emailId, providerMessageId, type, occurredAt, ... }` |

### Scheduler

| `event` | Cuándo | Payload |
|---|---|---|
| `scheduler:task-fired` | Cuando una tarea programada dispara | `{ taskId, executionId, status, firedAt, publishedTo }` |

## Ejemplo en el frontend (vanilla JS)

```js
const events = new EventSource('/api/v1/events?topics=scraping:*,email:*')

events.addEventListener('scraping:completed', (e) => {
  const data = JSON.parse(e.data)
  console.log('Scraping listo:', data.jobId, data.data)
  // updateUI(data)
})

events.addEventListener('scraping:failed', (e) => {
  const data = JSON.parse(e.data)
  console.error('Scraping falló:', data.error)
})

events.addEventListener('email:delivered', (e) => {
  const data = JSON.parse(e.data)
  console.log('Email entregado:', data.emailId)
})

// Auto-reconnect ocurre solo (nativo del navegador)
events.onerror = (err) => console.warn('SSE temporary disconnect', err)

// Para cerrar: events.close()
```

## React/Vue example

```jsx
// React hook
function useScrapingJob(jobId) {
  const [state, setState] = useState({ status: 'pending', data: null })

  useEffect(() => {
    if (!jobId) return
    const es = new EventSource(`/api/v1/events?topics=scraping:${jobId}`)

    es.addEventListener('scraping:started', () =>
      setState((s) => ({ ...s, status: 'running' })),
    )
    es.addEventListener('scraping:completed', (e) => {
      const payload = JSON.parse(e.data)
      setState({ status: 'success', data: payload.data })
      es.close()
    })
    es.addEventListener('scraping:failed', (e) => {
      const payload = JSON.parse(e.data)
      setState({ status: 'failed', error: payload.error })
      es.close()
    })

    return () => es.close()
  }, [jobId])

  return state
}
```

## Patrón recomendado: SSE primero, request después

Para evitar perderse el evento si el job termina antes de que abras el SSE:

```js
// 1) Conectá ANTES de pedir el job
const events = new EventSource(`/api/v1/events?topics=scraping:*`)
let pendingJobId = null

events.addEventListener('scraping:completed', (e) => {
  const data = JSON.parse(e.data)
  if (data.jobId === pendingJobId) {
    handleResult(data)
    events.close()
  }
})

// 2) Después pedí el job y filtrá por jobId
const { jobId } = await fetch('/api/v1/scraping/tasks', { ... }).then(r => r.json())
pendingJobId = jobId
```

Alternativa: usá topic específico desde el principio si conocés el jobId. Pero como el `jobId` lo asigna el server, es más fácil suscribirse a `scraping:*` primero.

## Heartbeat y reconnection

- El servidor manda un comentario `: heartbeat <ts>\n\n` cada **25 segundos** para mantener viva la conexión a través de Cloudflare/proxies (que cierran conexiones idle a los 60-100s)
- El navegador **reconecta solo** si la conexión se cae (3 segundos de delay por default, configurable via `Last-Event-ID` header — no implementado del lado server todavía, los eventos perdidos durante un disconnect se pierden)
- Si necesitás replay de eventos perdidos, hacé `GET /api/v1/scraping/tasks/:id` después de la reconexión para ver el estado actual

## CORS

El gateway **no tiene CORS configurado**. Si tu frontend está en otro dominio, `EventSource` va a fallar igual que cualquier fetch. Soluciones en [README.md de docs/api](./README.md).

## ⚠️ Limitaciones

- No hay autenticación por ahora — cualquiera con la URL puede suscribirse a `*` y ver TODO. Activar JWT cuando se implemente auth.
- No hay replay de eventos perdidos (durante disconnect)
- No hay filtros por payload (solo por topic key)
- Los topics no son persistentes — si te desconectás y reconectás, tenés que re-suscribirte
- Si el servidor reinicia, todas las conexiones se caen — el navegador reconecta solo
