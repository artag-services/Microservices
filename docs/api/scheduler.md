# Scheduler — `/v1/schedules/*`

Tareas programadas (cron, intervalo, una sola vez). El scheduler es **agnóstico**: cuando una tarea dispara, publica el `payload` que vos definiste al `targetRoutingKey` que vos elegiste. Eso significa que podés programar cualquier acción que el resto del sistema sepa hacer (mandar email, mandar WhatsApp, hacer scraping, llamar a Notion, etc.) sin que el scheduler sepa nada de esos servicios.

**Backend:** scheduler-service (puerto 3009) usando BullMQ + Redis.

## Conceptos

- **`scheduleType`** — `CRON`, `INTERVAL`, o `ONCE`
- **`targetRoutingKey`** — el routing key de RabbitMQ donde se publicará el payload cuando dispare. Ej: `channels.email.send`, `channels.whatsapp.send`, `channels.scraping.task`
- **`payload`** — el JSON que se publica tal cual cuando dispara. Debe coincidir con lo que el servicio destino espera consumir.
- **`status`** — `ACTIVE`, `PAUSED`, `COMPLETED`, `FAILED`
- **`maxLatenessMs`** — ventana de gracia. Si el scheduler estuvo caído y el disparo se demora más que esto, se salta (no spammea al usuario).

## Endpoints

### `POST /v1/schedules`
**Patrón:** RPC · `200 OK`

Crear una tarea programada.

```json
{
  "name": "Recordatorio diario por email",
  "description": "Envía resumen diario al usuario",
  "scheduleType": "CRON",
  "cronExpression": "0 9 * * *",
  "timezone": "America/Bogota",
  "targetRoutingKey": "channels.email.send",
  "payload": {
    "to": ["scristxyz@gmail.com"],
    "subject": "Tu resumen del día",
    "html": "<p>Aquí tu resumen...</p>"
  },
  "maxLatenessMs": 300000,
  "maxRetries": 3,
  "retryBackoffMs": 60000
}
```

| Campo | Tipo | Requerido | Notas |
|---|---|---|---|
| `name` | string | ✅ | identificador humano |
| `description` | string | optional | |
| `scheduleType` | enum | ✅ | `CRON` \| `INTERVAL` \| `ONCE` |
| `cronExpression` | string | si `scheduleType=CRON` | sintaxis cron de 5 campos (`* * * * *`) |
| `intervalMs` | number | si `scheduleType=INTERVAL` | mínimo 1000 (1s) |
| `runAt` | string ISO | si `scheduleType=ONCE` | timestamp futuro |
| `timezone` | string | optional | default: `America/Bogota`. Importante para CRON. |
| `targetExchange` | string | optional | default: `channels` |
| `targetRoutingKey` | string | ✅ | dónde publicar el payload al disparar |
| `payload` | objeto | ✅ | JSON libre — el shape del mensaje a publicar |
| `maxRetries` | number | optional | reintentos si falla la publicación |
| `retryBackoffMs` | number | optional | delay entre reintentos |
| `maxLatenessMs` | number | optional | default `300000` (5 min). Si el disparo se demora más, se salta. |
| `createdBy` | string | optional | metadata libre |

**Response:** modelo `ScheduledTask` completo con `id`, `nextFireAt`, `bullSchedulerId`, etc.

---

### `GET /v1/schedules`
**Patrón:** RPC · `200 OK`

Lista todas las tareas (sin paginación — devuelve hasta el límite que la DB aguante).

**Response:** `ScheduledTask[]`

---

### `GET /v1/schedules/:id`
**Patrón:** RPC · `200 OK`

Detalle de una tarea. Incluye stats (`fireCount`, `failureCount`, `lastFiredAt`, `lastStatus`, `nextFireAt`).

---

### `GET /v1/schedules/:id/runs`
**Patrón:** RPC · `200 OK`

Historial de ejecuciones de la tarea.

**Query params:**
- `limit` (default 50)

**Response:**
```json
[
  {
    "id": "uuid",
    "taskId": "uuid",
    "scheduledFor": "2026-04-25T09:00:00.000Z",
    "firedAt": "2026-04-25T09:00:00.123Z",
    "latencyMs": 123,
    "status": "SUCCESS",
    "publishedTo": "channels.email.send",
    "idempotencyKey": "...",
    "error": null
  }
]
```

`status`: `SUCCESS`, `FAILED`, `SKIPPED_LATE` (excedió `maxLatenessMs`).

---

### `PATCH /v1/schedules/:id`
**Patrón:** RPC · `200 OK`

Actualizar la tarea. Todos los campos del POST son opcionales aquí. Si cambiás `cronExpression`, `intervalMs`, `runAt` o `timezone`, el scheduler re-registra el job en BullMQ.

```json
{
  "cronExpression": "0 18 * * *",
  "payload": { ... }
}
```

---

### `POST /v1/schedules/:id/pause`
**Patrón:** RPC · `200 OK`

Para una tarea sin borrarla. Sale de BullMQ (no dispara más) pero queda en la DB con `status: PAUSED` y todo su historial.

**Response:** `ScheduledTask` con `status: "PAUSED"`.

---

### `POST /v1/schedules/:id/resume`
**Patrón:** RPC · `200 OK`

Reactiva una tarea pausada. Vuelve a registrarse en BullMQ.

---

### `POST /v1/schedules/:id/trigger`
**Patrón:** Fire-and-forget · `202 Accepted`

Dispara la tarea **ahora**, ignorando su schedule. Útil para testing o re-ejecutar una tarea fallida.

**Response:** `{ "accepted": true }`

---

### `DELETE /v1/schedules/:id`
**Patrón:** Fire-and-forget · `202 Accepted`

Borra la tarea de BullMQ + de la DB (cascade borra el historial de `TaskExecution`).

---

## Cron expressions útiles

| Expresión | Significado |
|---|---|
| `*/2 * * * *` | cada 2 minutos |
| `0 * * * *` | cada hora en punto |
| `0 9 * * *` | todos los días a las 9:00 AM |
| `0 9 * * 1-5` | lunes a viernes a las 9:00 AM |
| `30 14 * * 5` | viernes a las 14:30 |
| `0 0 1 * *` | día 1 de cada mes a medianoche |
| `0 */6 * * *` | cada 6 horas en punto |

Validador: https://crontab.guru

## Combinando scheduler con otros servicios

El poder real está en mandar mensajes a otros endpoints del sistema:

**Email recurrente:**
```json
{
  "scheduleType": "CRON",
  "cronExpression": "0 9 * * 1",
  "targetRoutingKey": "channels.email.send",
  "payload": { "to": ["..."], "subject": "...", "html": "..." }
}
```

**WhatsApp recurrente:**
```json
{
  "scheduleType": "CRON",
  "cronExpression": "0 8 * * *",
  "targetRoutingKey": "channels.whatsapp.send",
  "payload": { "to": "573205711428", "message": "Buenos días" }
}
```

**Scraping diario:**
```json
{
  "scheduleType": "CRON",
  "cronExpression": "0 6 * * *",
  "targetRoutingKey": "channels.scraping.task",
  "payload": { "url": "https://...", "type": "extract", "instructions": {...} }
}
```

> **Importante:** el `payload` debe coincidir con el shape que el consumer del servicio destino espera. Mirá la doc del servicio destino para saber el formato.

## Idempotencia automática

Cada disparo lleva un `idempotencyKey` derivado de `${taskId}-${scheduledFor.toISOString()}`. Si BullMQ reintenta un job (worker crash, etc.), el segundo disparo se detecta como duplicado por el `unique constraint` en `TaskExecution.idempotencyKey` y no se ejecuta dos veces. El email/WhatsApp/etc. recibe el `idempotencyKey` inyectado en su payload — los servicios que lo soportan (como email) lo usan para no duplicar.

## Misfire policy (qué pasa si el scheduler estuvo caído)

Si el disparo programado era a las 9:00 y el scheduler vuelve a las 9:30:
- Si el delay (`9:30 - 9:00 = 30 min`) ≤ `maxLatenessMs` → dispara tarde
- Si excede → se salta y queda registrado como `SKIPPED_LATE` en `TaskExecution`

Default `maxLatenessMs = 300000` (5 min). Para tareas críticas tipo "alerta médica" usá un valor bajo (60000 = 1 min). Para reportes diarios podés usar varias horas.

## Lo que SÍ podés hacer

- Programar acciones a cualquier servicio que tenga un consumer en RabbitMQ
- Tres modos: cron (recurrente sintaxis estándar), interval (cada N ms), one-shot (en una fecha)
- Pausar / reanudar / disparar manualmente / borrar
- Ver historial de ejecuciones con latencia
- Retry automático con backoff
- Misfire protection (no spammear si estuvo caído mucho tiempo)

## Lo que NO podés hacer

- ❌ Tareas con dependencias entre sí (BullMQ tiene flows, pero no está expuesto). Si la tarea B debe correr cuando A termina, programalas por separado.
- ❌ Modificar el `idempotencyKey` que se inyecta automáticamente (es derivado del taskId + scheduledFor).
- ❌ Disparar al mismo target con N réplicas paralelas (cada job lo agarra una sola réplica del scheduler).
- ❌ Pasar variables dinámicas en el payload (`{{user.name}}`). El payload es estático, lo que mandás al crear es lo que se publica siempre.
- ❌ Programar a una zona horaria distinta para distintos disparos del mismo cron. La timezone es por tarea.
- ❌ Listar paginado o filtrar por status. `GET /` te trae todas, vos filtrás en el frontend.
- ❌ Editar el historial de `TaskExecution`. Es read-only.

## UI de monitoreo en vivo (Bull Board)

El scheduler expone una UI web en `http://<scheduler>:3009/admin/queues` que muestra:
- Jobs en cola, activos, completados, fallidos
- Próximos disparos
- Historial de cada job con su payload
- Pausar/retry manual desde la UI

Esta UI **no pasa por el gateway**. Si tu server remoto solo expone gateway vía Cloudflare Tunnel, podés hacer port-forward por SSH:
```bash
ssh -L 3009:localhost:3009 usuario@server
# luego abrís http://localhost:3009/admin/queues
```
