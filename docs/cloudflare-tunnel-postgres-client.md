# Conectarte a la base de datos Postgres remota vía Cloudflare Tunnel

Este documento explica cómo conectar tu backend a una base de datos Postgres que está alojada en otro server, usando un túnel seguro de Cloudflare. **No necesitás abrir puertos en tu firewall ni VPN clásico**. Solo instalás un pequeño daemon (`cloudflared`) que se encarga de mantener la conexión.

---

## Datos que vas a recibir del admin

Antes de empezar, el admin del Postgres te tiene que dar 4 cosas:

| Dato | Ejemplo |
|---|---|
| Hostname del túnel | `db.artagdev.com.co` |
| Database | `dzjean533_db` |
| User | `dzjean533` |
| Password | `••••••••` (en algún lugar seguro) |

Sin esos 4 datos no podés avanzar. Pedíselos primero.

---

## Cómo funciona — diagrama mental

```
┌─────────────────────────┐                      ┌──────────────────────┐
│ TU SERVER (backend)     │                      │ SERVER DEL ADMIN     │
│                         │                      │                      │
│  Tu app Node/Python/Go  │                      │  Postgres            │
│         │               │                      │      ▲               │
│         ▼               │                      │      │               │
│  localhost:5432         │   ─── Cloudflare ───▶│  cloudflared listen  │
│         ▲               │       (HTTPS)        │                      │
│         │               │                      └──────────────────────┘
│  cloudflared (daemon)   │
│                         │
└─────────────────────────┘
```

- El admin ya tiene `cloudflared` corriendo en su server, expuesto en `db.artagdev.com.co`
- **Vos** instalás `cloudflared` en TU server y lo configurás para que abra `localhost:5432` que tunelea hacia el Postgres remoto
- Tu backend conecta a `localhost:5432` como si Postgres fuera local — Cloudflare hace la magia transparente por debajo

---

## Paso 1 — Instalar `cloudflared` en tu server

Ejecutá los comandos según tu sistema operativo:

### Linux (Ubuntu/Debian/etc.)
```bash
# Descargar el binario oficial
sudo curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared

# Hacerlo ejecutable
sudo chmod +x /usr/local/bin/cloudflared

# Verificar que se instaló
cloudflared --version
```

Tenés que ver algo como `cloudflared version 2024.x.x`.

### macOS
```bash
brew install cloudflared
cloudflared --version
```

### Windows
Descargá el `.msi` de https://github.com/cloudflare/cloudflared/releases/latest, instalalo. Después en PowerShell:
```powershell
cloudflared --version
```

---

## Paso 2 — Probar el túnel manualmente (test rápido)

Antes de hacer la configuración permanente, asegurate que el túnel funciona. Abrí una terminal y corré:

```bash
cloudflared access tcp --hostname db.artagdev.com.co --url 127.0.0.1:5432
```

Reemplazá `db.artagdev.com.co` por el hostname real que te pasaron.

**Lo que debería pasar:**
- La terminal queda abierta sin mostrar errores (es normal — está escuchando)
- Si te pide login con browser, abrílo y autorizá (ver sección **Si pide login** abajo)

**En OTRA terminal**, probá conectarte:

```bash
# Si tenés psql instalado:
psql -h 127.0.0.1 -p 5432 -U dzjean533 -d dzjean533_db -W
# Te pide la password → pegala → si entrás al prompt dzjean533_db=> ✅ funciona
```

Si no tenés psql, usá netcat para verificar al menos que el puerto responde:
```bash
nc -vz 127.0.0.1 5432
# debería decir: Connection to 127.0.0.1 5432 port [tcp/postgresql] succeeded!
```

✅ **Si conectaste, el túnel funciona.** Volvé a la primera terminal y matá el proceso con `Ctrl+C` — ahora vamos a hacerlo permanente.

### Si pide login

Si la primera terminal abre el browser y te pide login con email, **eso significa que el admin configuró un Cloudflare Access policy** (auth basada en email). Tenés 2 opciones:

- **Loguearte con browser cada vez** (incómodo para un backend) — anda y autorizá con el email que el admin agregó al policy
- **Pedile al admin un Service Token** — lo agregás al comando con `--service-token-id` y `--service-token-secret` y nunca más necesitás browser. Ver sección **Service Token** al final.

Si NO te pide login, no hay Access policy y la única auth es la password de Postgres. Sigue al paso 3 directo.

---

## Paso 3 — Hacer el túnel persistente con `systemd` (Linux)

El `cloudflared access tcp` que corriste en el paso 2 muere cuando cerrás la terminal. Para que arranque solo y se mantenga vivo cuando reinicies el server, lo registrás como servicio de systemd.

### 3.1) Crear el archivo del servicio

```bash
sudo tee /etc/systemd/system/cf-postgres.service > /dev/null <<'EOF'
[Unit]
Description=Cloudflare Tunnel - Postgres forward
After=network.target

[Service]
ExecStart=/usr/local/bin/cloudflared access tcp --hostname db.artagdev.com.co --url 127.0.0.1:5432
Restart=always
RestartSec=5
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF
```

⚠️ **Reemplazá `db.artagdev.com.co`** por el hostname real que te pasó el admin. Si no lo cambiás, no va a conectar a nada.

### 3.2) Activar y arrancar el servicio

```bash
sudo systemctl daemon-reload
sudo systemctl enable cf-postgres
sudo systemctl start cf-postgres

# Verificar que está corriendo
sudo systemctl status cf-postgres
```

Esperás ver `active (running)` en verde.

### 3.3) Verificar de nuevo que el puerto está vivo

```bash
nc -vz 127.0.0.1 5432
# debe responder: Connection to 127.0.0.1 5432 port [tcp/postgresql] succeeded!
```

✅ **Listo.** Tu server ahora tiene acceso permanente a Postgres remoto vía `localhost:5432`. Va a sobrevivir reboots, network blips, etc.

### Comandos útiles del servicio

```bash
# Ver logs en vivo
sudo journalctl -u cf-postgres -f

# Reiniciar
sudo systemctl restart cf-postgres

# Detener (sin desactivar)
sudo systemctl stop cf-postgres

# Desactivar para que NO arranque al boot
sudo systemctl disable cf-postgres
```

### macOS (alternativa con `launchd`)

Si estás en Mac y querés algo similar, usá launchd. Pegame y te paso el `.plist` listo. Para empezar podés correr `cloudflared access tcp ...` en una sesión `tmux`/`screen` que no se cierre.

---

## Paso 4 — Conectar tu backend

Tu backend conecta a `127.0.0.1:5432` como si Postgres fuera local. Acá ejemplos en distintos lenguajes:

### Connection string (universal — para `.env`)

```env
DATABASE_URL=postgresql://dzjean533:TU_PASSWORD@127.0.0.1:5432/dzjean533_db?sslmode=disable
```

> ⚠️ `sslmode=disable` es necesario porque la encriptación ya la hace Cloudflare en el camino. Si tu Postgres remoto requiere SSL, cambialo a `sslmode=require` y ajustá según corresponda.

### Node.js (con `pg`)

```javascript
import { Pool } from 'pg'

const pool = new Pool({
  host: '127.0.0.1',
  port: 5432,
  database: 'dzjean533_db',
  user: 'dzjean533',
  password: process.env.DB_PASSWORD,
  ssl: false,
})

const result = await pool.query('SELECT NOW()')
console.log(result.rows)
```

### Node.js (con Prisma)

`schema.prisma`:
```prisma
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}
```

`.env`:
```env
DATABASE_URL="postgresql://dzjean533:TU_PASSWORD@127.0.0.1:5432/dzjean533_db?schema=public&sslmode=disable"
```

### Python (con psycopg2)

```python
import psycopg2

conn = psycopg2.connect(
    host="127.0.0.1",
    port=5432,
    database="dzjean533_db",
    user="dzjean533",
    password="TU_PASSWORD",
)
cur = conn.cursor()
cur.execute("SELECT NOW()")
print(cur.fetchone())
```

### Python (con SQLAlchemy)

```python
from sqlalchemy import create_engine

engine = create_engine(
    "postgresql://dzjean533:TU_PASSWORD@127.0.0.1:5432/dzjean533_db"
)
```

### Go (con `pgx`)

```go
import "github.com/jackc/pgx/v5"

conn, err := pgx.Connect(ctx, "postgres://dzjean533:TU_PASSWORD@127.0.0.1:5432/dzjean533_db?sslmode=disable")
```

### Probar con tu backend

Levantá tu app, hacé que ejecute una query simple (`SELECT NOW()` o lo que tengas en migraciones) y ver que conecte sin errores.

---

## Troubleshooting

### `connection refused`
El daemon `cloudflared` no está corriendo.
```bash
sudo systemctl status cf-postgres
sudo journalctl -u cf-postgres --tail 30
```

### `password authentication failed`
La password de Postgres está mal. NO es problema de Cloudflare. Verificá con el admin.

### El service no arranca: `failed to dial`
El hostname del túnel está mal o el admin no configuró su lado. Pedile al admin que confirme:
- TCP route activa en su Cloudflare Tunnel
- URL apunta a `localhost:5432` (o `postgres:5432` si su Postgres está en docker)

### `websocket: bad handshake` en logs
Tu DNS no está resolviendo `db.artagdev.com.co`. Probá:
```bash
nslookup db.artagdev.com.co
# tiene que devolver IPs de Cloudflare (1.1.1.x o similar)
```

### El servicio se cae cada cierto tiempo
Revisá logs con `journalctl -u cf-postgres -f`. Cloudflared se reconecta solo gracias a `Restart=always`, pero si hay algo persistente avisá al admin.

### `permission denied` al instalar
Los comandos `sudo curl` y `sudo chmod` requieren permisos de root. Si tu user no tiene `sudo`, pedile al admin de tu server que los corra.

---

## Service Token (auth para backends, sin browser)

Si el admin configuró Cloudflare Access en su lado y te pide login con browser cada vez (impráctico para un backend), pedíle un **Service Token**. Te va a dar 2 valores:

```
CF-Access-Client-Id:     abc123.access
CF-Access-Client-Secret: xxxxxxxxxxxxxxxxxxxxxx
```

Modificá el `ExecStart` del systemd unit:

```bash
sudo nano /etc/systemd/system/cf-postgres.service
```

Cambialo a:

```ini
ExecStart=/usr/local/bin/cloudflared access tcp \
    --hostname db.artagdev.com.co \
    --url 127.0.0.1:5432 \
    --service-token-id abc123.access \
    --service-token-secret xxxxxxxxxxxxxxxxxxxxxx
```

Reload + restart:
```bash
sudo systemctl daemon-reload
sudo systemctl restart cf-postgres
```

Ahora autentica solo, sin browser, con el token.

---

## Resumen — los 4 comandos clave

Si querés copiar-pegar rápido (cambiando el hostname y la password):

```bash
# 1. Instalar
sudo curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
sudo chmod +x /usr/local/bin/cloudflared

# 2. Crear servicio (cambiar HOSTNAME)
sudo tee /etc/systemd/system/cf-postgres.service > /dev/null <<'EOF'
[Unit]
Description=Cloudflare Tunnel - Postgres
After=network.target
[Service]
ExecStart=/usr/local/bin/cloudflared access tcp --hostname db.artagdev.com.co --url 127.0.0.1:5432
Restart=always
RestartSec=5
User=nobody
Group=nogroup
[Install]
WantedBy=multi-user.target
EOF

# 3. Activar
sudo systemctl daemon-reload && sudo systemctl enable --now cf-postgres

# 4. Verificar
nc -vz 127.0.0.1 5432
```

Después conectás tu backend a:
```
postgresql://dzjean533:TU_PASSWORD@127.0.0.1:5432/dzjean533_db?sslmode=disable
```

Listo. ✅

---

## Si algo no funciona

Pegame:
1. Output de `sudo systemctl status cf-postgres`
2. Output de `sudo journalctl -u cf-postgres --tail 30`
3. Output de `nc -vz 127.0.0.1 5432`

Y avisame al admin para que verifique su lado.
