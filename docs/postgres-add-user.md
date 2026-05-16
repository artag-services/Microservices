# Crear un usuario nuevo en Postgres + su base de datos

Guía para agregar un usuario a tu Postgres del server remoto, crearle su base de datos propia y darle permisos completos sobre ella.

**Caso del que parte esta guía:**
- Server remoto donde corre `docker-compose` con Postgres
- Usuario admin existente: `postgres` (password `postgres123`, viene del `.env`)
- Nuevo usuario a crear: para `dzjean533@gmail.com`

> ⚠️ **Sobre el username**: Postgres acepta `@` y `.` en nombres de rol pero **te obligan a poner comillas dobles cada vez** que los uses, lo cual es un dolor. Mi recomendación: usar `dzjean533` como role name y guardar el email como un comentario / metadata. Si insistís en usar el email completo, te dejo la versión alternativa al final.

---

## Paso 0 — Conectarse al server

Desde tu máquina local:

```bash
ssh tu-usuario@tu-server
```

Una vez adentro, andá al directorio del proyecto:

```bash
cd ~/Microservices
```

---

## Paso 1 — Generar una password segura para el nuevo usuario

```bash
openssl rand -base64 24
```

Te imprime algo tipo `kXc8Yv9PqM3wF7nA2bR5tL6sJ4hG1dE0`. **Copialo y guardalo en algún lugar seguro** (1Password, Bitwarden, lo que uses) — no la vas a poder ver de nuevo.

A partir de acá voy a usar `<PASSWORD_GENERADO>` como placeholder. Reemplazá por el real en cada comando.

---

## Paso 2 — Entrar al contenedor de Postgres

```bash
docker-compose exec postgres psql -U postgres
```

Te aparece el prompt de psql:
```
psql (15.x)
Type "help" for help.

postgres=#
```

A partir de acá ejecutás SQL.

---

## Paso 3 — Crear el rol (usuario) con password

Dentro de psql:

```sql
CREATE ROLE dzjean533 WITH LOGIN PASSWORD '<PASSWORD_GENERADO>';
```

Esperás:
```
CREATE ROLE
```

Opcional pero recomendado — agregá un comentario con el email para no perder la asociación:

```sql
COMMENT ON ROLE dzjean533 IS 'dzjean533@gmail.com';
```

---

## Paso 4 — Crear la base de datos para ese usuario

```sql
CREATE DATABASE dzjean533_db OWNER dzjean533;
```

Esperás:
```
CREATE DATABASE
```

> Le pongo `dzjean533_db` siguiendo la convención del resto del proyecto (`gateway_db`, `email_db`, etc.). Si querés otro nombre, cambialo.

---

## Paso 5 — Dar permisos completos sobre la DB nueva

Como ya lo pusiste como `OWNER` en el paso anterior, **ya tiene permisos completos** sobre la DB. Pero por las dudas, refuerzo:

```sql
GRANT ALL PRIVILEGES ON DATABASE dzjean533_db TO dzjean533;
```

Si querés que también tenga permisos en el schema `public` (default donde Postgres pone las tablas):

```sql
\c dzjean533_db
GRANT ALL ON SCHEMA public TO dzjean533;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO dzjean533;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO dzjean533;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO dzjean533;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO dzjean533;
```

> Las dos últimas líneas (`ALTER DEFAULT PRIVILEGES`) son importantes — hacen que **todas las tablas/secuencias futuras** que se creen en ese schema le den permisos al usuario automáticamente. Sin esto, cuando creás tablas nuevas hay que volver a hacer GRANT cada vez.

---

## Paso 6 — Salir de psql

```sql
\q
```

Te devuelve a la shell normal del server.

---

## Paso 7 — Verificar conexión con el nuevo usuario

Desde el server (no desde el contenedor):

```bash
docker-compose exec postgres psql -U dzjean533 -d dzjean533_db -W
```

Te pide la password — pegás la que generaste en el Paso 1.

Esperás:
```
psql (15.x)
Type "help" for help.

dzjean533_db=>
```

Para probar permisos, creá una tabla de prueba:

```sql
CREATE TABLE test_table (id INT, name TEXT);
INSERT INTO test_table VALUES (1, 'hola');
SELECT * FROM test_table;
DROP TABLE test_table;
\q
```

Si todo eso corre sin errores → permisos OK ✅

---

## Datos de conexión para entregarle al usuario

Una vez verificado, esto es lo que el usuario `dzjean533@gmail.com` necesita para conectarse:

| Campo | Valor |
|---|---|
| Host | `<IP-pública-o-dominio-de-tu-server>` |
| Puerto | `5432` |
| Database | `dzjean533_db` |
| Username | `dzjean533` |
| Password | `<PASSWORD_GENERADO>` |
| SSL | recomendado (depende de tu setup — ver abajo) |

**Connection string** (formato URI):
```
postgresql://dzjean533:<PASSWORD>@<HOST>:5432/dzjean533_db
```

Para usarlo desde Prisma (`.env`):
```env
DATABASE_URL="postgresql://dzjean533:<PASSWORD>@<HOST>:5432/dzjean533_db?schema=public"
```

---

## ⚠️ IMPORTANTE — Acceso desde fuera del server

Tu Postgres está corriendo en el contenedor `postgres` y por default **solo escucha conexiones desde la misma máquina** (incluso si Docker mapea el puerto 5432 a la host).

Si `dzjean533@gmail.com` necesita conectarse **desde su laptop directamente al server**, hace falta uno de estos:

### Opción A — SSH tunnel (recomendado, no expone Postgres a internet)

El usuario corre en SU máquina:
```bash
ssh -L 5432:localhost:5432 tu-usuario@tu-server
```

Luego en otro terminal de su máquina conecta como si fuera local:
```
host: localhost
port: 5432
```

Sin riesgos de exposición pública. Necesita acceso SSH al server.

### Opción B — Exponer Postgres públicamente (más riesgo)

1. En `docker-compose.yml`, el postgres ya tiene `ports: ['5432:5432']` — eso solo lo expone al loopback de la host por default.
2. Si querés exponerlo al mundo, abrir el puerto 5432 en tu firewall del server (`ufw allow 5432`).
3. Editar `pg_hba.conf` del Postgres para aceptar conexiones desde IPs externas:
   ```bash
   docker-compose exec postgres bash
   echo "host all all 0.0.0.0/0 scram-sha-256" >> /var/lib/postgresql/data/pg_hba.conf
   exit
   docker-compose restart postgres
   ```
4. ⚠️ **Cuidado** — esto expone Postgres a internet. **Activá SSL** y **firewall por IP** si vas por este camino.

**Mi recomendación: Opción A (SSH tunnel).** Más seguro y no expone nada.

---

## Cómo BORRAR el usuario y su DB después (rollback)

Si querés deshacer todo:

```bash
docker-compose exec postgres psql -U postgres
```

```sql
DROP DATABASE dzjean533_db;
DROP ROLE dzjean533;
\q
```

---

## Versión alternativa — usando `dzjean533@gmail.com` como role name

Si insistís en usar el email completo como nombre del rol, todo lo de arriba aplica pero **siempre tenés que poner comillas dobles**:

```sql
CREATE ROLE "dzjean533@gmail.com" WITH LOGIN PASSWORD '<PASSWORD>';
CREATE DATABASE "dzjean533@gmail.com_db" OWNER "dzjean533@gmail.com";
GRANT ALL PRIVILEGES ON DATABASE "dzjean533@gmail.com_db" TO "dzjean533@gmail.com";
\c "dzjean533@gmail.com_db"
GRANT ALL ON SCHEMA public TO "dzjean533@gmail.com";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "dzjean533@gmail.com";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO "dzjean533@gmail.com";
```

Conexión:
```
postgresql://dzjean533%40gmail.com:<PASSWORD>@<HOST>:5432/dzjean533%40gmail.com_db
```

(El `@` se URL-encodea como `%40`.)

**No la recomiendo** — es feo cada vez que tenés que tocar SQL. El usuario simple es mucho más práctico.

---

## Resumen — los 5 comandos clave

Si querés copiar-pegar rápido (asumiendo `dzjean533` como username y reemplazando `<PASSWORD>`):

```bash
# 1. Entrar al contenedor postgres como admin
docker-compose exec postgres psql -U postgres
```

```sql
-- 2-5. Crear todo en una sola ejecución
CREATE ROLE dzjean533 WITH LOGIN PASSWORD '<PASSWORD>';
COMMENT ON ROLE dzjean533 IS 'dzjean533@gmail.com';
CREATE DATABASE dzjean533_db OWNER dzjean533;
GRANT ALL PRIVILEGES ON DATABASE dzjean533_db TO dzjean533;
\c dzjean533_db
GRANT ALL ON SCHEMA public TO dzjean533;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO dzjean533;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO dzjean533;
\q
```

Listo. ✅
