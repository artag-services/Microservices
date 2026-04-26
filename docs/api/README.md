# API del Gateway — referencia para frontend

Esta carpeta documenta el **único API público del proyecto**: el gateway. El frontend NUNCA llama directo a los microservicios — solo al gateway, que internamente publica/consume en RabbitMQ y orquesta todo.

## Base URL

```
https://<tu-dominio-del-gateway>/api
```

Localmente: `http://localhost:3000/api`. El prefijo `/api` lo agrega el gateway globalmente; todas las rutas documentadas lo asumen.

## Endpoints por servicio

| Área | Doc | Endpoints |
|---|---|---|
| Identidad de usuarios | [identity.md](./identity.md) | `/v1/identity/*` |
| Envío de mensajes (genérico) | [messages.md](./messages.md) | `/v1/messages/*` |
| **📚 Por canal** (WhatsApp / Slack / Notion / Instagram / TikTok / Facebook) | [channels/](./channels/) | guías prácticas con ejemplos copy-paste por canal |
| Conversaciones (chat rooms) | [conversations.md](./conversations.md) | `/v1/conversations/*` ⚠️ ver nota |
| Web scraping | [scraping.md](./scraping.md) | `/v1/scraping/*` |
| Email transaccional | [email.md](./email.md) | `/v1/emails/*` |
| Tareas programadas | [scheduler.md](./scheduler.md) | `/v1/schedules/*` |
| Webhooks (proveedores externos) | [webhooks.md](./webhooks.md) | `/webhooks/*` — **NO usar desde frontend** |

## Convenciones que aplican a TODO el API

### Patrones de respuesta — RPC vs fire-and-forget

Cada endpoint sigue uno de dos patrones. Importa para el frontend porque cambia cómo manejar la respuesta:

| Patrón | Status | Cuándo se usa | Implicación para el frontend |
|---|---|---|---|
| **RPC** | `200 OK` | Cuando la respuesta del microservicio es relevante (lecturas, creaciones que devuelven el objeto creado) | El gateway espera la respuesta sobre RabbitMQ antes de responderte. Latencia típica 50-300ms. **Puede tardar hasta 30s y hacer timeout** si el microservicio destino está caído. |
| **Fire-and-forget** | `202 Accepted` | Acciones que no necesitan respuesta inmediata (eliminar, disparar, encolar) | El gateway publica al broker y te responde al instante. **No sabés si el trabajo se completó** — solo que se encoló. Para verificar después, consultá el recurso (ej: `GET /v1/emails/:id`). |

Cada endpoint en la documentación está marcado con su patrón.

### Formato de error

Cuando algo falla, el gateway responde con JSON consistente:

```json
{
  "statusCode": 400,
  "timestamp": "2026-04-25T18:42:11.123Z",
  "path": "/api/v1/emails",
  "message": "Validation failed: ..."
}
```

Códigos comunes:
- `400 Bad Request` — body o query inválido (validación de DTO)
- `401 Unauthorized` — solo en webhooks de Resend/Slack si firma inválida
- `404 Not Found` — recurso inexistente o ruta mal escrita
- `500 Internal Server Error` — error en el microservicio destino o en el gateway
- **Timeout (~30s, sin status específico)** — si un endpoint RPC no recibe respuesta del microservicio

### Validación

Todos los DTOs usan `class-validator` con `whitelist: true, forbidNonWhitelisted: true`. Esto significa:
- Cualquier campo que **NO** está declarado en el DTO causa `400`. No mandes campos extra "por las dudas".
- Los tipos se validan estrictamente: si un endpoint pide `to: string[]`, mandar `to: "x@y.com"` (string suelto) falla.

## Autenticación

**No hay autenticación activa todavía.** El gateway tiene JWT wireado (`@nestjs/passport`, `@nestjs/jwt`) pero está comentado en el módulo. Cualquiera con acceso a la URL puede llamar cualquier endpoint.

Cuando se active, todos los endpoints `/v1/*` requerirán `Authorization: Bearer <jwt>`. Los `/webhooks/*` seguirán sin auth (los proveedores externos validan vía firma HMAC).

## CORS

**El gateway NO tiene CORS configurado.** Si el frontend corre en otro origen (ej: `https://app.tudominio.com` y gateway en `https://gateway.tudominio.com`), las peticiones desde el navegador van a fallar con error CORS.

Soluciones:
1. **Servir frontend y API bajo el mismo dominio** (recomendado en prod — Cloudflare Tunnel + dos hostnames apuntando al mismo gateway)
2. Pedirle al backend que active CORS — un cambio de 3 líneas en `gateway/src/main.ts`:
   ```ts
   app.enableCors({
     origin: ['https://app.tudominio.com'],
     credentials: true,
   });
   ```
3. **Para desarrollo local**: usar un proxy del dev server (Vite/Next/Webpack) que tunelee `/api/*` al gateway

## Headers que siempre debés mandar

```
Content-Type: application/json
```

Todos los endpoints aceptan y devuelven JSON.

## Idempotencia

Algunos endpoints aceptan un `idempotencyKey` en el body (ej: `POST /v1/emails`). Si reenviás la misma request con el mismo key, no se duplica el efecto — te devuelve el resultado original. Útil para frontends donde el usuario puede dar doble-click al botón "Enviar".

## Rate limiting

**No hay rate limiting global.** Cada microservicio puede tener el suyo (ej: scraping limita a 10 req/día por usuario). Tu frontend debería implementar debounce/throttle en botones que disparan acciones costosas (envío de email, scraping).
