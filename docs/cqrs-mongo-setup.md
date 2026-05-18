# Mongo replica-set setup (única vez, después de pullear)

Si estás viendo este error en `sync` cuando llega un evento `data.*`:

```
Prisma needs to perform transactions, which requires your MongoDB server
to be run as a replica set.
```

…es porque Mongo está corriendo como **standalone** y Prisma necesita un **replica set** (aunque sea de un solo nodo) para hacer transactions, que usa internamente al escribir documents con embedded types (`UnifiedUser.identities`, etc.).

Este doc explica el paso de migración. **Lo hacés una sola vez** — el estado queda persistido en el volumen de mongo.

## Por qué replica set + sin auth

| Decisión | Razón |
|---|---|
| **Replica set** (un solo nodo, `rs0`) | Prisma usa transactions internas — sólo funcionan con replica set, no con standalone |
| **mongo:4.4** | mongo 5+ requiere CPU con AVX, algunos VPS no exponen esa instrucción |
| **Sin auth de root** | Mongo + replSet + auth requiere `--keyFile`, que es PITA cross-platform via bind mount. Como este mongo sólo vive en la red interna de docker (`microservices-network`) y nadie de afuera puede llegarle, omitir auth está OK para dev. Si necesitás auth, mirá la sección final. |

## Migración paso a paso

```bash
cd ~/Microservices
git pull   # trae el nuevo docker-compose.yml + .env

# 1) Bajar mongo y sync. Mongo viejo (standalone) no es compatible con
#    los datos en disk si lo reiniciás como replica set, así que hay que
#    limpiar el volumen. Como apenas estábamos arrancando con el read
#    model, no perdés nada importante (todo se repuebla con backfill).
docker-compose down mongo sync

# 2) Nuke del volumen — única vez
docker volume rm microservices-2_mongo_data 2>/dev/null || \
docker volume rm microservices_mongo_data 2>/dev/null || \
docker volume ls | grep mongo
# (si el nombre cambia según cómo lo nombró docker-compose, listalos y borrá el que es)

# 3) Levantar SÓLO mongo en modo replica set (todavía no está iniciado)
docker-compose up -d mongo

# 4) Esperar 5 segundos para que mongod arranque
sleep 5

# 5) Iniciar el replica set (esto es la pieza clave)
docker-compose exec mongo mongo --quiet --eval '
  rs.initiate({
    _id: "rs0",
    members: [{ _id: 0, host: "mongo:27017" }]
  })
'
# Esperás algo tipo: { "ok": 1 } o ya inicializado.

# 6) Verificar que el set está OK
docker-compose exec mongo mongo --quiet --eval 'rs.status().ok'
# → 1

# 7) Esperar a que el healthcheck pase (puede tomar ~15-30s)
until [ "$(docker inspect mongo --format='{{.State.Health.Status}}')" = "healthy" ]; do
  echo "Esperando mongo healthy..."
  sleep 5
done
echo "Mongo está healthy"

# 8) Levantar sync y todo lo demás
docker-compose up -d sync
docker-compose logs --tail 30 sync
# Esperás "Sync consumer ready — listening to data.#"
```

## Test inmediato

```bash
# Disparar identity
curl -X POST https://micro.artagdev.com.co/api/v1/identity/resolve \
  -H "Content-Type: application/json" \
  -d '{"channel":"whatsapp","channelUserId":"573205711428","displayName":"Test","phone":"+573205711428"}'

# Esperar
sleep 2

# Ver Mongo
docker-compose exec mongo mongo --quiet --eval "
use query_service;
print('unified_users count: ' + db.unified_users.countDocuments({}));
db.unified_users.find({}).limit(3).forEach(d => printjson(d));
"

# Ver via gateway
curl https://micro.artagdev.com.co/api/v1/query/users | jq
```

## Backfill (opcional — si tenías data antes en los Postgres)

Una vez que el read model funciona end-to-end, poblá Mongo con todo lo histórico:

```bash
TOKEN=$(grep '^ADMIN_BACKFILL_TOKEN=' .env | cut -d= -f2)
for entry in identity:3010 whatsapp:3001 instagram:3004 slack:3002 \
             scrapping:3008 email:3007 agent:3011; do
  name="${entry%:*}"; port="${entry#*:}"
  echo "== Backfilling $name =="
  curl -s -X POST "http://localhost:$port/admin/backfill-events" \
    -H "X-Admin-Token: $TOKEN" | jq -c .
done
```

## Si querés auth en mongo después

1. Agregá al compose:
   ```yaml
   environment:
     MONGO_INITDB_ROOT_USERNAME: admin
     MONGO_INITDB_ROOT_PASSWORD: <pass>
   command: ['mongod', '--replSet', 'rs0', '--bind_ip_all', '--keyFile', '/etc/mongo-keyfile']
   volumes:
     - mongo_data:/data/db
     - ./mongo-keyfile:/etc/mongo-keyfile:ro
   ```
2. Generá el keyfile:
   ```bash
   openssl rand -base64 756 > mongo-keyfile
   chmod 400 mongo-keyfile
   # En Docker Desktop / Windows hace falta:
   docker run --rm -v "$(pwd)/mongo-keyfile:/k" mongo:4.4 chown 999:999 /k
   ```
3. Actualizá `SYNC_DATABASE_URL` y `MONGO_URI` para incluir las creds:
   ```
   mongodb://admin:<pass>@mongo:27017/query_service?replicaSet=rs0&directConnection=true&authSource=admin
   ```

Pero, repito, no es necesario para una red interna de docker.

## Troubleshooting

| Síntoma | Causa | Fix |
|---|---|---|
| `rs.status().ok` devuelve `0` o `MongoServerError: not running with --replSet` | El compose no se actualizó | `docker-compose down mongo && docker-compose up -d --force-recreate mongo` |
| `rs.initiate()` dice "already initialized" | Ya está iniciado, no es problema | Seguí con el step 8 |
| Mongo container restart-loops | Volumen viejo (de standalone) incompatible | Step 2 del proceso (`docker volume rm`) |
| Sync sigue tirando "needs replica set" | El sync agarró la conexión vieja | `docker-compose restart sync` |
| Healthcheck nunca pasa a healthy | `rs.initiate()` no se corrió | Step 5 |
