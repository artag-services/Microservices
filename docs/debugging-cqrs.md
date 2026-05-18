# Diagnóstico CQRS — por qué no veo data en `/v1/query/*`

Si el front consulta `/v1/query/users` o `/v1/query/conversations` y siempre devuelve `[]`, este doc te lleva paso a paso a encontrar dónde se cortó el flow.

## Antes que nada — entendé QUÉ dispara cada evento

Esta es la confusión más común:

| Lo que hacés | Dispara identidad? | Crea conversación en el read model? |
|---|---|---|
| `POST /v1/messages/send` (mandar mensaje desde el front a un número WhatsApp) | ❌ NO | ❌ NO |
| `POST /v1/identity/resolve` (con channel + channelUserId) | ✅ SI | — |
| Recibir un msg INBOUND (alguien te escribe a tu número de WhatsApp) | ✅ SI | ✅ SI (whatsapp lo crea) |
| `POST /v1/conversations` con `{channel, channelUserId}` | — | ✅ SI (después del fix) |

**Si SÓLO has hecho `POST /v1/messages/send`, no hay nada en el read model y eso es esperado.** Mandar mensajes outbound no crea usuarios — porque sólo conocés el número del destinatario, no son usuarios tuyos hasta que ellos te respondan.

## Test rápido — forzar un user nuevo

```bash
# 1. Crear un user manualmente (no hace falta inbound real)
curl -X POST https://micro.artagdev.com.co/api/v1/identity/resolve \
  -H "Content-Type: application/json" \
  -d '{
    "channel": "whatsapp",
    "channelUserId": "573205711428",
    "displayName": "Test Manual",
    "phone": "+573205711428"
  }'
# → 202 Accepted

# 2. Esperar 1-2 segundos (RabbitMQ → identity → sync)
sleep 2

# 3. Consultar el read model
curl https://micro.artagdev.com.co/api/v1/query/users | jq
# → debería traer 1 user con displayName "Test Manual"
```

Si el step 3 devuelve `[]`, algo está roto en el flow. Seguir abajo.

## Checkpoint 1 — Está corriendo todo?

```bash
docker-compose ps
```

Debés ver `Up` y `(healthy)` en todos estos:
- `mongo`
- `rabbitmq`
- `postgres-local`
- `gateway`
- `identity-service`
- `sync-service`

Si alguno está `Restarting` o `Exited`, mirá sus logs:
```bash
docker-compose logs --tail 50 sync
docker-compose logs --tail 50 identity
```

## Checkpoint 2 — Sync arrancó y se suscribió?

```bash
docker-compose logs sync | grep -E "Sync consumer ready|listening|Connected"
```

Esperás:
```
[Bootstrap] Sync service running on port 3012
[RabbitMQService] Connected to RabbitMQ — exchange [channels]
[SyncConsumer] Sync consumer ready — listening to data.#
```

Si falta `Sync consumer ready — listening to data.#`, sync no se suscribió. Reiniciá:
```bash
docker-compose restart sync
docker-compose logs -f sync
```

## Checkpoint 3 — Mongo tiene contenido?

```bash
docker-compose exec mongo mongo -u admin -p mongopass123 --quiet --eval "
use query_service;
print('unified_users:        ' + db.unified_users.countDocuments({}));
print('unified_conversations:' + db.unified_conversations.countDocuments({}));
print('unified_messages:     ' + db.unified_messages.countDocuments({}));
print('unified_emails:       ' + db.unified_emails.countDocuments({}));
print('event_log:            ' + db.event_log.countDocuments({}));
"
```

Tres casos:
- **`event_log: 0`** — sync NUNCA recibió ningún evento `data.*`. Ningún productor está emitiendo. Ver checkpoint 4.
- **`event_log: > 0` pero `unified_users: 0`** — sync recibe pero el projector falla. Mirá logs:
  ```bash
  docker-compose logs sync | grep -iE "Projection failed|error"
  ```
- **`unified_users: > 0`** — el read model SÍ tiene data. El problema está en el gateway → sync HTTP. Saltá a checkpoint 5.

## Checkpoint 4 — Algún productor está emitiendo?

```bash
# Disparar manualmente un identity.resolve
curl -X POST https://micro.artagdev.com.co/api/v1/identity/resolve \
  -H "Content-Type: application/json" \
  -d '{"channel":"whatsapp","channelUserId":"test-debug-1","displayName":"Debug"}'

# Tail identity en otra terminal
docker-compose logs --tail 20 -f identity
```

Deberías ver:
```
[IdentityService] No match found, creating new user for identity test-debug-1
[IdentityService] Created UnifiedUser <uuid> ...
[RabbitMQService] Message published to data.identity.user.created
[RabbitMQService] Message published to data.identity.user.linked
```

Si NO ves los `Message published`, el publish está fallando silenciosamente. Mirá si hay errores:
```bash
docker-compose logs identity | grep -iE "error|failed"
```

## Checkpoint 5 — Gateway → sync HTTP funciona?

```bash
# Probar directamente el sync (necesitás el token)
TOKEN=$(grep '^SYNC_INTERNAL_AUTH_TOKEN=' .env | cut -d= -f2)
curl -i http://localhost:3012/internal/query/users \
  -H "X-Internal-Auth: $TOKEN"
```

- `200 OK` con JSON → el sync responde bien, el problema está en el QueryClient del gateway
- `401 Unauthorized` → token mismatch (regenerá el .env, restart gateway + sync)
- Connection refused → sync no está exponiendo el puerto 3012

```bash
# Probar el endpoint público (via gateway)
curl https://micro.artagdev.com.co/api/v1/query/users
```

- Si el directo a sync devuelve data pero el gateway no → el gateway-sync auth falla. Logs:
  ```bash
  docker-compose logs gateway | grep -iE "QueryClient|sync.*401|sync.*Unauthorized"
  ```

## Checkpoint 6 — Inspeccionar el event_log para ver qué entró

```bash
docker-compose exec mongo mongo -u admin -p mongopass123 --quiet --eval "
use query_service;
db.event_log.find({}).sort({consumedAt: -1}).limit(10).forEach(function(d) {
  print(d.consumedAt.toISOString() + ' ' + d.status + '\t' + d.routingKey);
  if (d.errorReason) print('  ERROR: ' + d.errorReason);
});
"
```

Te muestra los últimos 10 eventos consumidos. Si están todos como `OK`, el flujo entra bien y debería haber data en las collections. Si hay `ERROR`, mirá el `errorReason`.

## Forzar un backfill — popular Mongo desde Postgres viejo

Si tu Postgres ya tiene users (de antes de configurar sync), el read model arranca vacío. Hacé backfill:

```bash
TOKEN=$(grep '^ADMIN_BACKFILL_TOKEN=' .env | cut -d= -f2)
for entry in identity:3010 whatsapp:3001 instagram:3004 slack:3002 \
             scrapping:3008 email:3007 agent:3011; do
  name="${entry%:*}"; port="${entry#*:}"
  echo "== Backfilling $name =="
  curl -s -X POST "http://localhost:$port/admin/backfill-events" \
    -H "X-Admin-Token: $TOKEN" | jq -c .
done

# Verificar
sleep 5
curl https://micro.artagdev.com.co/api/v1/query/users | jq length
```

## Bug ya conocido y arreglado — POST /v1/conversations

Antes este endpoint escribía en una tabla LOCAL del gateway que nadie más leía. **Ya está arreglado** — ahora emite `data.<channel>.conversation.created` para que sync lo proyecte.

Necesitás rebuild del gateway en el server:
```bash
cd ~/Microservices
git pull
docker-compose up -d --build gateway sync
```

## Bug ya conocido y arreglado — sync sólo proyectaba whatsapp/instagram/agent

Antes, si emitías `data.facebook.conversation.created` o `data.tiktok.message.received`, sync NO los proyectaba (sólo dejaba el evento en `event_log`). **Ya está arreglado** — sync ahora extrae el `channel` del routing key y proyecta cualquier valor.

## Si nada de lo anterior funciona

Pegame el output de:
```bash
docker-compose ps
docker-compose logs --tail 30 sync
docker-compose logs --tail 30 identity
docker-compose exec mongo mongo -u admin -p mongopass123 --quiet --eval \
  "use query_service; db.event_log.find({}).sort({consumedAt:-1}).limit(5).forEach(d => print(JSON.stringify(d)))"
```

Con eso se puede pinpointear el fallo exacto.
