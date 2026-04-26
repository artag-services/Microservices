# Scraping — `/v1/scraping/*`

Web scraping con Puppeteer (Chromium headless). El backend tiene un pool de browsers, plugins anti-detección (stealth), y un sistema de adapters para enviar el resultado a distintos destinos (Notion, WhatsApp, Email).

**Backend:** scrapping-service (puerto 3008). Usa el container `browserless/chrome` para ejecutar las sesiones.

## Endpoints

### `POST /v1/scraping/tasks`
**Patrón:** Fire-and-forget · `202 Accepted`

Encola una tarea de scraping. Es asincrónica — el browser puede tardar 5-60s en cargar la página.

```json
{
  "url": "https://www.xataka.com/",
  "type": "simple",
  "userId": "573205711428"
}
```

| Campo | Tipo | Requerido | Notas |
|---|---|---|---|
| `url` | string (URL válida) | ✅ | URL completa con protocolo |
| `type` | enum | optional | `simple`, `login`, `search`, `login+search`, `extract`. Default: `simple` |
| `instructions` | objeto | optional | obligatorio si `type` ≠ `simple`. Ver formatos abajo. |
| `userId` | string | optional | a quién notificar cuando termine (default: el `PERSONAL_WHATSAPP_NUMBER` del .env) |

**Response:**
```json
{
  "requestId": "uuid",
  "message": "Scraping task queued",
  "timestamp": "2026-04-25T..."
}
```

---

#### Formato de `instructions` por tipo

**`type: "simple"`** — solo extracción de meta + links + texto principal:
```json
{
  "url": "https://example.com",
  "type": "simple"
}
```
*No requiere `instructions`.*

**`type: "extract"`** — extrae elementos específicos vía CSS selectors:
```json
{
  "url": "https://shop.com/products",
  "type": "extract",
  "instructions": {
    "selectors": {
      "title": "h1.product-title",
      "price": ".price",
      "rating": ".stars span"
    }
  }
}
```

**`type: "search"`** — busca un término dentro del sitio:
```json
{
  "url": "https://amazon.com",
  "type": "search",
  "instructions": {
    "query": "laptop gaming",
    "selectors": {
      "searchInput": "input[name='field-keywords']",
      "submitBtn": "input.nav-input[type='submit']"
    }
  }
}
```

**`type: "login"` o `"login+search"`** — sesión autenticada:
```json
{
  "url": "https://shop.com",
  "type": "login+search",
  "instructions": {
    "login": {
      "username": "user@email.com",
      "password": "password",
      "selectors": {
        "username": "#email",
        "password": "#pass",
        "submit": "button[type=submit]"
      }
    },
    "search": {
      "query": "term",
      "selectors": { ... }
    }
  }
}
```

> ⚠️ Las credenciales viajan en el body en plaintext. Si usás `login`, asegurate de que la conexión es HTTPS y no logueás el body.

---

### `POST /v1/scraping/notify-notion` (uso interno)
**Patrón:** Fire-and-forget · `202 Accepted`

> ⚠️ **No es para el frontend.** Lo usa el scrapping-service internamente para notificarle al gateway que terminó un scraping y quiere mandar el resultado a Notion. Documentado por completitud.

```json
{
  "userId": "573205711428",
  "title": "Xataka",
  "url": "https://www.xataka.com/",
  "data": { ... },
  "notionPageId": "abc123..."
}
```

---

## Resultado del scraping (cómo se entrega)

El endpoint `POST /tasks` solo encola. **El resultado NO te lo devuelve por HTTP.** En su lugar, el flujo es:

```
POST /v1/scraping/tasks  →  scraping (Puppeteer hace su trabajo, puede tardar 30-60s)
                                ↓ datos crudos
                            DataCleanupService (limpia duplicados, etc.)
                                ↓ datos limpios
                            NotionAdapter publica a channels.notion.send
                                ↓
                            notion-service crea página
                                ↓ link de Notion
                            scraping consume la respuesta
                                ↓
                            WhatsAppAdapter manda el link al userId
```

El usuario final recibe el link a la página de Notion por **WhatsApp**, no por la API.

Si querés ver el resultado desde el frontend, las opciones son:
1. **Esperar el push de WhatsApp** y mostrarlo cuando llegue (necesita el módulo de webhooks de WhatsApp + websocket al frontend — no existe hoy)
2. **Consultar Notion directamente** (sabés el `userId` y podés guardar las páginas creadas en tu DB)
3. Pedirle al backend que exponga `GET /v1/scraping/tasks/:requestId` (no existe hoy)

---

## Rate limiting

El scrapping-service tiene rate limiting por usuario:
- `RATE_LIMIT_DAILY=10` (default) — máximo 10 scraping/día por `userId`
- `RATE_LIMIT_WINDOW_HOURS=24` — ventana móvil

Si te excedés, el `POST /tasks` te devuelve `202` igual (el rate limit se evalúa después del encolado), pero el job nunca se ejecuta y el usuario recibe un mensaje de "límite excedido" por WhatsApp.

> No hay endpoint para consultar tu cuota actual. Limitalo en el frontend si querés UX más prolija.

---

## Lo que SÍ podés hacer

- Disparar scraping de una URL pública desde el frontend
- Configurar selectores custom para extraer campos específicos
- Scraping con login (carrito de compra, dashboard interno, etc.) — pero ojo con las credenciales
- Búsqueda dentro del sitio antes de extraer

## Lo que NO podés hacer

- ❌ Recibir el resultado del scraping por HTTP. Va por WhatsApp/Notion.
- ❌ Cancelar un job en curso.
- ❌ Listar tus jobs activos / historial. No hay `GET /tasks` ni `GET /tasks/:id`.
- ❌ Subir cookies/session manualmente. El login lo hace Puppeteer rellenando el form cada vez.
- ❌ Capturas de pantalla / PDFs como output. Solo extracción de datos textuales.
- ❌ Scrapear sitios que requieren JavaScript pesado más allá de lo razonable (TikTok, IG feed, etc. — usar las APIs oficiales para eso).
- ❌ Saltar el rate limit desde el cliente (se aplica server-side).
