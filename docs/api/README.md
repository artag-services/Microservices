# API del Gateway — referencia para frontend

Esta carpeta documenta el **único API público del proyecto**: el gateway. El frontend NUNCA llama directo a los microservicios — solo al gateway.

## Base URL

```
https://<tu-dominio-del-gateway>/api
```

Localmente: `http://localhost:3000/api`. El prefijo `/api` lo agrega el gateway globalmente.

## Donde miras qué

> **TL;DR:** Para LEER datos del sistema, sólo necesitás `query.md`. Para ESCRIBIR/disparar acciones (mandar mensaje, programar tarea, etc.), mirás la doc del recurso específico.

| Área | Doc | Para qué sirve |
|---|---|---|
| **📖 LECTURAS cross-service (read model — Mongo via CQRS)** | [query.md](./query.md) | **`/v1/query/*`** — TODOS los GETs del sistema. Users, conversations, messages, emails, scraping-tasks, search |
| Real-time (SSE) | [events.md](./events.md) | `/v1/events` — UNA conexión cubre scraping + email + scheduler + agent + WS de mensajes |
| Identidad (acciones) | [identity.md](./identity.md) | `/v1/identity/{resolve,merge,users/:id,users/:id/ai-settings}` — POST / DELETE / PATCH. Los GET viejos están en `query.md`. |
| Envío de mensajes (genérico) | [messages.md](./messages.md) | `/v1/messages/send` — disparar mensaje a cualquier canal |
| Guías por canal (WhatsApp / Slack / Notion / Instagram / TikTok / Facebook) | [channels/](./channels/) | ejemplos copy-paste por canal |
| Conversations (acciones) | [conversations.md](./conversations.md) | `/v1/conversations` — crear/actualizar/archivar. Los GETs están en `query.md`. |
| Scraping (acciones) | [scraping.md](./scraping.md) | `/v1/scraping/tasks` — disparar job. Los GETs están en `query.md`. |
| Email (acciones) | [email.md](./email.md) | `POST /v1/emails`, `GET /v1/emails/domains`, cleanup-expired. Los GETs de mensajes están en `query.md`. |
| Tareas programadas | [scheduler.md](./scheduler.md) | `/v1/schedules/*` (su read model propio, BullMQ) |
| **Agente con tools** | [agent.md](./agent.md) | `/v1/agent/{chat,memories}` + `GET /v1/agent/conversations/:id` (detalle con tool blocks). Resto via query. |
| Webhooks (proveedores externos) | [webhooks.md](./webhooks.md) | `/webhooks/*` — **NO usar desde frontend** |
| Frontend Next.js | [frontend-nextjs.md](./frontend-nextjs.md) | guía con hooks, Socket.IO, SSE, ejemplo end-to-end |
| **🆕 Migración para el front (cambios recientes)** | [MIGRATION.md](./MIGRATION.md) | qué se rompió, qué se movió, cómo migrar las llamadas existentes |

## El cambio importante (mayo 2026)

Antes existían `GET /v1/identity/users`, `GET /v1/email`, `GET /v1/scraping/tasks`, `GET /v1/agent/conversations`, `GET /v1/conversations`. **Todos esos GETs ya no existen** — fueron reemplazados por `/v1/query/*`.

**¿Por qué?** Cross-service joins eran imposibles (cada microservicio sólo conoce su propio Postgres). Ahora un Sync Service consume eventos `data.*` y mantiene un read model unificado en MongoDB. El gateway proxea `/v1/query/*` a ese servicio. El resultado: un único endpoint da "todas las conversaciones del usuario X" sin importar de qué canal vienen.

Las acciones (POST / PATCH / DELETE) siguen iguales, pegándole al microservicio correspondiente vía RabbitMQ.

## Convenciones que aplican a TODO el API

### Patrones de respuesta — RPC vs fire-and-forget

| Patrón | Status | Cuándo se usa | Implicación para el frontend |
|---|---|---|---|
| **RPC** | `200 OK` | Lecturas (`/v1/query/*`) y acciones que necesitan respuesta inmediata | Latencia típica 5-300ms; timeout a los 30s |
| **Fire-and-forget** | `202 Accepted` | Acciones que no necesitan respuesta inmediata (mandar email, encolar scraping, resolver identidad) | El gateway publica al broker y responde al instante. Para confirmar el resultado: SSE en `/v1/events` |

### Formato de error

```json
{
  "statusCode": 400,
  "timestamp": "...",
  "path": "/api/v1/emails",
  "message": "Validation failed: ..."
}
```

Códigos comunes: `400`, `401` (webhooks con firma inválida), `404` (no existe o soft-deleted), `503` (Read model unavailable: sync caído), timeout ~30s en RPCs si el microservicio destino está caído.

### Validación

DTOs con `class-validator` (`whitelist: true, forbidNonWhitelisted: true`). Cualquier campo no declarado dispara `400`. No mandes campos extra "por las dudas".

## Autenticación

**No hay auth activa todavía.** El gateway tiene JWT cableado (`@nestjs/passport`, `@nestjs/jwt`) pero comentado. Cuando se active, todos los `/v1/*` requerirán `Authorization: Bearer <jwt>`. Los `/webhooks/*` seguirán sin auth (validan firma HMAC).

## CORS

Activable via env: `CORS_ALLOWED_ORIGINS=http://localhost:3000,https://app.tudominio.com` en el `.env` del server, luego `docker-compose restart gateway`. Sin la var, el gateway acepta cualquier origen (cómodo en dev, inseguro en prod).

## Idempotencia

Algunos endpoints aceptan `idempotencyKey` (ej: `POST /v1/emails`). Reenviar con el mismo key devuelve el resultado original sin duplicar el efecto.

## Rate limiting

Sin rate limit global. Cada microservicio puede tener el suyo (ej: scraping limita 10 req/día por usuario). El front debería hacer debounce en botones costosos.
