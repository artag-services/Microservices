# Microservices

Plataforma multi-canal de mensajería + automatización. Cada integración (WhatsApp, Slack, Notion, Instagram, etc.) es un microservicio independiente; un gateway único expone HTTP y todo lo demás corre sobre RabbitMQ.

## Quick start

```bash
git clone https://github.com/artag-services/Microservices.git
cd Microservices
git submodule update --init --recursive

cp .env.example .env   # editá con tus credenciales reales
docker-compose up -d
```

UIs disponibles después de levantar:
- Gateway HTTP — http://localhost:3000/api
- RabbitMQ Management — http://localhost:15672 (admin / password)
- pgAdmin — http://localhost:5050
- Bull Board (scheduler) — http://localhost:3009/admin/queues
- Mailpit (dev) — http://localhost:8025 (solo si usás `--profile dev`)

## Servicios

| Servicio | Puerto | Función |
|---|---|---|
| `gateway` | 3000 | Único punto HTTP público. Orquesta todo vía RabbitMQ. |
| `whatsapp` | 3001 | Meta WhatsApp Cloud API |
| `slack` | 3002 | Slack Bot API |
| `notion` | 3003 | Notion API (crea páginas, lee DBs) |
| `instagram` | 3004 | Meta Instagram Graph API |
| `tiktok` | 3005 | TikTok for Developers |
| `facebook` | 3006 | Meta Messenger Platform |
| `email` | 3007 | Email transaccional (Resend / SMTP) |
| `scrapping` | 3008 | Web scraping con Puppeteer |
| `scheduler` | 3009 | Tareas programadas (BullMQ + Redis) |
| `identity` | 3010 | Unificación de identidades cross-canal |
| `agent` | 3011 | Orquestador AI (Anthropic / OpenAI) |
| `sync` | 3012 | CQRS Read Model — MongoDB |

Más infra: PostgreSQL (puerto 5432), RabbitMQ (5672), Redis (6379), **MongoDB (27017)**, Browserless Chrome (3222).

## Stack

- **NestJS 10** + TypeScript (todos los servicios)
- **pnpm** (lockfile = `pnpm-lock.yaml`)
- **Prisma 5** — schema y DB por servicio
- **PostgreSQL** — una base por servicio (`<servicio>_db`)
- **MongoDB 7** — read model desnormalizado (CQRS)
- **RabbitMQ** — exchange `channels` (topic), backbone de mensajería
- **Redis** — backend de BullMQ para el scheduler
- **Docker Compose** — orquestación local

## Arquitectura en una imagen

```
         ┌──────────┐
         │ Frontend │
         └────┬─────┘
              │ HTTPS (reads)
              ▼
         ┌──────────┐    ┌─────────────────────────────┐
         │  Gateway │ ←─ │ Webhooks externos           │
         │ (HTTP)   │    │ (Resend, Meta, Slack, etc.) │
         └────┬─────┘    └─────────────────────────────┘
          ╱   │    ╲
         ╱    │     ╲
        ╱     │      ╲
       ╱      │       ╲
      ▼       ▼        ▼
┌─────────┐ ┌─────────┐ ┌──────────┐
│ Sync    │ │ RabbitMQ│ │ Servicios│  (whatsapp, ig, slack,
│ Service │ │ (events) │ │ (write)  │   notion, scrapping...)
│ CQRS    │ └────┬─────┘ └────┬─────┘
│ Read    │      │            │
│ (Mongo) │      │            │ publican data.* events
└─────────┘      │            ▼
             ┌───┴──────────────────────────┐
             │  Each service writes to its   │
             │  own PostgreSQL DB            │
             └──────────────────────────────┘

Gateway consulta Sync Service por HTTPS directo (excepción única).
Servicios NUNCA se hablan directo — siempre vía RabbitMQ.
```

**Reglas duras de la arquitectura** (no romper sin consenso):

1. Los servicios **NUNCA se hablan directo entre sí** — siempre vía `channels` exchange en RabbitMQ.
2. El gateway es el **único punto HTTP público** — incluyendo webhooks de proveedores externos.
3. Cada servicio es un **submódulo Git independiente** con su propio repo, DB, Dockerfile y schema.
4. **Toda escritura publica un evento `data.*`** — el Sync Service los escucha para mantener el read model en MongoDB.
5. **Sync Service es la excepción HTTP** — el Gateway lo consulta por HTTPS para TODAS las lecturas. Es el único servicio con REST directo al Gateway.
6. **MongoDB no es fuente de verdad** — la source of truth es PostgreSQL de cada servicio. MongoDB es un read model desnormalizado.

Ver [.claude/skills/microservice-pattern/SKILL.md](.claude/skills/microservice-pattern/SKILL.md) (también espejado en [.agent/](.agent/skills/microservice-pattern.md/SKILL.md)) para el patrón completo cuando agregues un servicio nuevo.

## Documentación

| Necesito… | Ir a |
|---|---|
| **Construir un frontend** | [docs/api/README.md](docs/api/README.md) — referencia HTTP completa |
| Entender el repo desde cero | [CLAUDE.md](CLAUDE.md) (si lo tenés local) o [AGENTS.md](AGENTS.md) |
| Deep dive de flujos (scraping → notion → whatsapp, etc.) | [AGENTS.md](AGENTS.md) |
| Agregar un microservicio nuevo | skill `microservice-pattern` (links arriba) |
| Configuración de Docker / variables | [docker-compose.yml](docker-compose.yml) + [.env](.env) |
| Schema de DBs por servicio | `<servicio>/prisma/schema.prisma` |

## Comandos comunes

```bash
# Levantar todo
docker-compose up -d

# Solo infra (Postgres + RabbitMQ + Redis)
docker-compose up -d postgres rabbitmq redis

# Solo un servicio (con sus deps)
docker-compose up -d gateway email

# Modo dev con Mailpit (no envía emails reales)
docker-compose --profile dev up -d

# Logs en vivo
docker-compose logs -f <servicio>

# Rebuild después de cambios
docker-compose build --no-cache <servicio>
docker-compose up -d <servicio>

# Trabajar en un servicio específico
cd <servicio>
pnpm install
pnpm start:dev          # watch mode
pnpm prisma:studio      # explorar la DB
```

## Configuración

Todo vive en un único `.env` en la raíz. Cada servicio toma de ahí lo que necesita (mapeado en `docker-compose.yml`).

**Convenciones:**
- `<SERVICIO>_PORT` — puerto del servicio
- `<SERVICIO>_DATABASE_URL` — connection string de su DB
- Tokens de proveedores: `RESEND_API_KEY`, `WHATSAPP_API_TOKEN`, `NOTION_INTEGRATION_TOKEN`, etc.

Cambios al `.env` requieren `docker-compose restart <servicio>` para tomar efecto.

> ⚠️ El `.env` está en `.gitignore`. Nunca lo commitees. Para producción usá un secret manager.

## Trabajar con submódulos

Como cada servicio es un repo independiente, modificar código adentro implica dos commits:

```bash
# 1) Commit dentro del submódulo
cd <servicio>
git add . && git commit -m "feat: ..."
git push origin main

# 2) Bumpear el ref en el padre
cd ..
git add <servicio>
git commit -m "chore: bump <servicio> ref"
git push origin main
```

Para sincronizar todos los submódulos al último de cada uno:
```bash
git submodule update --remote --recursive
```

## Estado actual del proyecto

- ✅ 12 microservicios funcionando + infraestructura completa (PostgreSQL + MongoDB + RabbitMQ + Redis)
- ✅ Patrón RPC sobre RabbitMQ con `correlationId` (ver `gateway/src/identity/services/request-response.manager.ts`)
- ✅ Patrón fire-and-forget para acciones asincrónicas
- ✅ CQRS read model con MongoDB + Sync Service (Fase 0 — infra lista)
- ✅ Webhooks de proveedores externos verificados con HMAC (Resend, Slack)
- ✅ Schema sync idempotente al boot (`prisma db push`)
- ✅ Tareas programadas con BullMQ + Redis
- ⏳ JWT auth wireado pero comentado — pendiente activar
- ⏳ CORS no configurado — pendiente si el frontend va en otro dominio
- ⏳ WebSocket bridge para eventos en tiempo real al frontend — pendiente
- ⏳ Eventos `data.*` en servicios productores — pendiente (Fase 1)
- ⏳ Sync Service — pendiente de crear (Fase 2)
- ⏳ Gateway endpoints `/v1/query/*` — pendiente (Fase 3)
- ⏳ Unificación cross-channel en MongoDB — pendiente (Fase 4)
