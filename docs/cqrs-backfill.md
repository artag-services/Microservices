# Backfill del read model (Mongo) desde los Postgres de cada productor

El sync-service sólo recibe los `data.*` events que se emiten **a partir** de su despliegue. Para popular Mongo con todo lo que ya hay en cada Postgres, hay que re-emitir esos eventos. Esta doc explica el patrón y deja stubs para implementar.

## Por qué hace falta

Cada microservicio publica `data.<service>.<entity>.<action>` después de cada write. Antes de que sync existiera, esas publicaciones tampoco ocurrían (o si ocurrían, no había consumidor). Resultado: tu Mongo arranca vacío y se va llenando sólo con actividad nueva.

Si querés que el front muestre **todos los usuarios históricos** desde el día 1, hay que hacer backfill.

## Estrategia: admin endpoint por productor

Cada servicio expone un `POST /admin/backfill-events?secret=...` que:
1. Recorre TODAS las filas de las tablas relevantes en su Postgres (paginadas).
2. Por cada fila, construye el payload CQRS canónico y publica el event a RabbitMQ.
3. Devuelve `{ scanned: N, published: M }`.

Como los projectors son **idempotentes** (upsert por id), reemitir es seguro. Si corrés el backfill 2 veces, la segunda no duplica nada.

## Esqueleto (ejemplo para identity)

```ts
// identity/src/admin/backfill.controller.ts
import { Controller, Headers, Logger, Post, UnauthorizedException } from '@nestjs/common'
import { ConfigService } from '@nestjs/config'
import { PrismaService } from '../prisma/prisma.service'
import { RabbitMQService } from '../rabbitmq/rabbitmq.service'

@Controller('admin')
export class BackfillController {
  private readonly logger = new Logger(BackfillController.name)

  constructor(
    private readonly prisma: PrismaService,
    private readonly rabbitmq: RabbitMQService,
    private readonly config: ConfigService,
  ) {}

  @Post('backfill-events')
  async backfill(@Headers('x-admin-token') token?: string) {
    const expected = this.config.get<string>('ADMIN_BACKFILL_TOKEN')
    if (!expected || token !== expected) throw new UnauthorizedException()

    let scanned = 0
    let published = 0
    const PAGE = 500

    for (let skip = 0; ; skip += PAGE) {
      const users = await this.prisma.user.findMany({
        skip,
        take: PAGE,
        where: { deletedAt: null },
        include: { identities: true },
      })
      if (users.length === 0) break
      scanned += users.length

      for (const u of users) {
        for (const i of u.identities) {
          await this.rabbitmq.publish('data.identity.user.linked', {
            userId: u.id,
            channel: i.channel,
            channelUserId: i.channelUserId,
            displayName: i.displayName ?? u.realName ?? null,
            realName: u.realName ?? null,
            avatarUrl: i.avatarUrl ?? null,
            linkedAt: i.updatedAt.toISOString(),
          })
          published++
        }
      }
    }

    // Then deletes
    for (let skip = 0; ; skip += PAGE) {
      const deleted = await this.prisma.user.findMany({
        skip,
        take: PAGE,
        where: { deletedAt: { not: null } },
      })
      if (deleted.length === 0) break
      for (const u of deleted) {
        await this.rabbitmq.publish('data.identity.user.deleted', {
          userId: u.id,
          reason: 'soft-delete',
          deletedAt: u.deletedAt!.toISOString(),
        })
        published++
      }
    }

    this.logger.log(`Backfill done: scanned=${scanned} published=${published}`)
    return { scanned, published }
  }
}
```

Wirearlo en el `AppModule` del servicio.

## Por servicio — qué emitir

| Servicio | Tablas a recorrer | Routing keys a emitir |
|---|---|---|
| **identity** | `User` + `UserIdentity` | `data.identity.user.linked` por cada (user, identity), `data.identity.user.deleted` para soft-deleted |
| **whatsapp** | `Conversation` + `ConversationMessage` | `data.whatsapp.conversation.created` por cada conv, `data.whatsapp.message.received` por cada msg `sender=USER` |
| **instagram** | `Conversation` + `ConversationMessage` | `data.instagram.conversation.created`, `data.instagram.message.received` |
| **scrapping** | `ScrapingJob` | `data.scraping.task.completed` o `data.scraping.task.failed` según status |
| **email** | `EmailMessage` + `InboundEmail` | `data.email.message.sent` por cada outbound (con todos los lifecycle dates), `data.email.message.received` por cada inbound |
| **slack** | `SlackMessage` | `data.slack.message.sent` por cada fila |
| **agent** | `Conversation` + `Message` (rol USER / final ASSISTANT) | `data.agent.conversation.created`, `data.agent.message.received`, `data.agent.message.sent` |

## Ejecución

```bash
# Genera un token random
openssl rand -hex 32
# → "abc123..." → ponelo en .env como ADMIN_BACKFILL_TOKEN, redeploy

# Por cada servicio:
curl -X POST -H "X-Admin-Token: $ADMIN_BACKFILL_TOKEN" \
  http://localhost:3010/admin/backfill-events    # identity
curl -X POST -H "X-Admin-Token: $ADMIN_BACKFILL_TOKEN" \
  http://localhost:3001/admin/backfill-events    # whatsapp
# ... etc.
```

**Verificación:**

```bash
# Antes del backfill
docker-compose exec mongo mongosh -u admin -p mongopass123 \
  --eval "use query_service; db.unified_users.countDocuments({})"
# 0

# Despues
docker-compose exec mongo mongosh -u admin -p mongopass123 \
  --eval "use query_service; db.unified_users.countDocuments({})"
# 1234
```

## Cuidados

1. **Throttling**: con 100k+ filas pegándole rápido al broker podés tirar el RabbitMQ. Considerá un `await sleep(10)` cada N publishes.
2. **Auth**: protegé el endpoint con un token de un solo uso (`ADMIN_BACKFILL_TOKEN`). Idealmente removelo del código después.
3. **Replay durante operación normal**: el backfill puede correr con tráfico real en simultáneo — los projectors son idempotentes y los updates con `lastSeenAt > existing.lastSeenAt` evitan que el backfill pise datos más nuevos.
4. **Eventos `*.deleted`**: emitir DESPUÉS de los `created`/`linked`, no antes — así el orden simula la realidad.

## Estado de implementación

| Servicio | Endpoint `/admin/backfill-events` | Eventos emitidos |
|---|---|---|
| identity (port 3010) | ✅ | `data.identity.user.linked` (per identity), `data.identity.user.deleted` (per soft-deleted user) |
| whatsapp (port 3001) | ✅ | `data.whatsapp.conversation.created` (per conv), `data.whatsapp.message.received` (per USER msg) |
| instagram (port 3004) | ✅ | `data.instagram.conversation.created`, `data.instagram.message.received` |
| slack (port 3002) | ✅ | `data.slack.message.sent` (per outbound msg) |
| scrapping (port 3008) | ✅ | `data.scraping.task.{completed,failed}` (skips QUEUED/RUNNING) |
| email (port 3007) | ✅ | `data.email.message.sent` (per outbound, all lifecycle dates in one event), `data.email.message.received` (per inbound) |
| agent (port 3011) | ✅ | `data.agent.conversation.{created,deleted}`, `data.agent.message.received` (per USER), `data.agent.message.sent` (per FINAL ASSISTANT) |

## Comando todo-en-uno

```bash
# Desde la raíz del repo, después de setear ADMIN_BACKFILL_TOKEN en .env
TOKEN=$(grep ADMIN_BACKFILL_TOKEN .env | cut -d= -f2)

for entry in identity:3010 whatsapp:3001 instagram:3004 slack:3002 scrapping:3008 email:3007 agent:3011; do
  name="${entry%:*}"
  port="${entry#*:}"
  echo "== $name =="
  curl -s -X POST "http://localhost:$port/admin/backfill-events" \
    -H "X-Admin-Token: $TOKEN" | jq .
done
```

Cada llamada devuelve `{ service, scanned, published, durationMs }`. Es **idempotente** — re-ejecutar es seguro.

## Apagar el endpoint después

Cuando termines el backfill, **borrá** o rotá la `ADMIN_BACKFILL_TOKEN` del `.env` para invalidarla. El guard hace fail-closed si la var está vacía, así que el endpoint queda inaccesible automáticamente sin tener que tocar código.

```bash
# En el .env del server:
ADMIN_BACKFILL_TOKEN=

docker-compose restart identity whatsapp instagram slack scraping email agent
```

Verificar que está cerrado:
```bash
curl -i -X POST http://localhost:3010/admin/backfill-events
# HTTP/1.1 401 Unauthorized
# {"message":"Admin endpoints disabled (no token configured)"}
```
