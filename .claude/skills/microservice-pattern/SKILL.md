---
name: microservice-pattern
description: Use this skill ANY time the user wants to create a new microservice, add a new service to this composition repo, or wire two services together. Enforces the project's mandatory architecture: NestJS + Prisma + own Postgres DB + RabbitMQ-only communication via the gateway. Trigger phrases include "create a new microservice", "agregar un microservicio", "nuevo servicio", "wire up X service", "let me add a service for X". The user explicitly asked that this pattern be applied without exception.
---

# Microservice pattern (mandatory for this repo)

This is a composition repo of Git submodules. Every service follows the same blueprint. **Do not deviate without the user's explicit consent** — they chose this pattern for separability (any service must be movable to its own infra without rewiring others).

## The two laws

1. **Services NEVER communicate directly with each other.** No HTTP, no gRPC, no shared DB. The only allowed inter-service channel is the RabbitMQ topic exchange `channels`. The gateway is the sole HTTP entry point for clients **and the sole receiver of inbound webhooks** from external providers (Resend, Notion, Meta, Slack, etc.). The gateway validates signatures, then publishes a `channels.<service>.events.<thing>` message; the destination microservice consumes it. Never expose a microservice's HTTP port to an external provider.

2. **Every service is a separate Git submodule.** Its remote is `https://github.com/artag-services/<name>.git` (or `<name>-service.git` for older ones — match what the user gives you, don't invent). It has its own `package.json`, Dockerfile, `entrypoint.sh`, and Prisma schema.

## Stack (do not vary)

| Concern | Choice |
|---|---|
| Framework | NestJS 10 |
| Language | TypeScript 5 (strict) |
| Package manager | pnpm (lockfile = `pnpm-lock.yaml`) |
| ORM | Prisma 5, schema per service |
| DB | PostgreSQL — own database per service (`<name>_db` on shared Postgres in dev, Neon in prod) |
| Schema sync on boot | `prisma db push --accept-data-loss --skip-generate` (NOT `migrate deploy` — see CLAUDE.md decision) |
| Messaging | `amqplib` directly (the existing services don't use `@nestjs/microservices`) |
| Exchange | topic `channels`, durable, name configurable via `RABBITMQ_EXCHANGE` |

For tasks that need a queue/scheduler/job-system, also add `bullmq` + `ioredis` + `@nestjs/bullmq`. Redis is already in `docker-compose.yml`.

## The communication contract

There are **three** legitimate message patterns. Pick one per endpoint, never invent a fourth.

### 1. Fire-and-forget (one-way action)

Gateway publishes, service consumes, no reply. HTTP returns `202 Accepted` immediately.

```ts
// Gateway side
await this.rabbitmq.publish(ROUTING_KEYS.X_DO, { ...payload });
return { accepted: true };
```

### 2. RPC (request-response with correlationId)

Use this for reads or writes that must return data. Reuses `RequestResponseManager` (gateway/src/identity/services/request-response.manager.ts) — provide a fresh instance per service module so promise maps don't cross-contaminate.

```ts
// Gateway side
const { correlationId, promise } = this.rrm.createRequest();
await this.rabbitmq.publish(ROUTING_KEYS.X_GET, { correlationId, ...args });
return promise; // resolves when service publishes the response

// Service side
async handle(env: { correlationId?: string; ... }) {
  try {
    const data = await doWork(env);
    if (env.correlationId) this.respond(env.correlationId, true, data);
  } catch (err) {
    if (env.correlationId) this.respond(env.correlationId, false, { error: err.message });
  }
}
respond(correlationId, success, data) {
  this.rabbitmq.publish(ROUTING_KEYS.X_RESPONSE, { correlationId, success, ...data });
}
```

The gateway has a per-service response listener (e.g. `gateway/src/scheduler/services/scheduler-response.listener.ts`) that subscribes to the service's `RESPONSE` routing key and resolves promises by correlationId.

### 3. Broadcast event (1-to-N)

A service publishes to a routing key like `channels.<service>.events.<thing>`. Any number of subscribers can bind their own queues to it. Use this for things like "task fired", "page created".

## Routing key & queue conventions

- Routing keys: `channels.<service>.<action>` (kebab-case action allowed: `channels.scheduler.trigger-now`).
- Queues: `<service>.<action>` (no `channels.` prefix, no kebab).
- Response routing key: `channels.<service>.response`.
- Response queue (gateway-side): `gateway.<service>.responses`.
- Always declare both routing key and queue in `<service>/src/rabbitmq/constants/queues.ts` AND in `gateway/src/rabbitmq/constants/queues.ts`. The two files must agree — they are the public contract.

## Skeleton when creating a new service `<name>`

Mirror an existing service's tree (e.g. `notion/` or `scheduler/`) — do not invent a new layout:

```
<name>/
├── prisma/schema.prisma           # own models, datasource = env("<NAME>_DATABASE_URL")
├── src/
│   ├── main.ts                    # bootstrap NestJS, ValidationPipe, HttpExceptionFilter
│   ├── app.module.ts              # imports ConfigModule, PrismaModule, RabbitMQModule, <feature>Module
│   ├── prisma/                    # PrismaModule + PrismaService (global)
│   ├── rabbitmq/
│   │   ├── rabbitmq.module.ts     # global
│   │   ├── rabbitmq.service.ts    # connect + publish + subscribe (copy from notion verbatim)
│   │   ├── constants/queues.ts    # ROUTING_KEYS, QUEUES, RABBITMQ_EXCHANGE
│   │   └── <name>.consumer.ts     # subscribes to its inbound keys
│   ├── <feature>/                 # the actual business logic module
│   └── common/filters/http-exception.filter.ts
├── Dockerfile                     # node:20-alpine, pnpm, prisma:generate, build
├── entrypoint.sh                  # wait Postgres → prisma:generate → prisma:push → exec
├── package.json                   # MUST include "prisma:push": "prisma db push --accept-data-loss --skip-generate"
├── tsconfig.json
└── nest-cli.json
```

## Step-by-step when adding a new service

1. **Create the GitHub repo** under `artag-services/<name>` (the user does this, ask for the URL).
2. **Scaffold locally** at `<repo-root>/<name>/` matching the skeleton above. Copy from the closest existing service.
3. **Pick a port** in the 30XX range that isn't used (check `.env` and `docker-compose.yml` for taken ones). Add `<NAME>_PORT` and `<NAME>_DATABASE_URL` to root `.env`.
4. **Add the database** to `init-db.sql` (`CREATE DATABASE <name>_db;`).
5. **Add the service** to root `docker-compose.yml` mirroring the existing entries (depends_on postgres + rabbitmq, env_file `.env`, network `microservices-network`).
6. **Define routing keys** in BOTH `<name>/src/rabbitmq/constants/queues.ts` AND `gateway/src/rabbitmq/constants/queues.ts`.
7. **Add the gateway integration**:
   - `gateway/src/<name>/services/<name>-response.listener.ts` (only if the service uses RPC reads)
   - `gateway/src/v1/<name>/<name>.controller.ts` (HTTP endpoints)
   - `gateway/src/v1/<name>/<name>.service.ts` (publishes via RabbitMQ; awaits via `RequestResponseManager` if RPC)
   - `gateway/src/v1/<name>/<name>.module.ts` (provides a fresh `RequestResponseManager` instance)
   - Wire into `gateway/src/app.module.ts` imports
8. **Initial commit + push of the new submodule**:
   ```bash
   cd <name>
   git init -b main
   git add . && git commit -m "feat: initial commit"
   git remote add origin https://github.com/artag-services/<name>.git
   git push -u origin main
   ```
9. **Convert to submodule** of the parent:
   ```bash
   cd ..
   mv <name> <name>.bak
   git submodule add https://github.com/artag-services/<name>.git <name>
   rm -rf <name>.bak
   git add .gitmodules <name> docker-compose.yml init-db.sql
   git commit -m "feat: add <name> submodule + infra"
   ```
10. **Commit gateway changes**: inside `gateway/` commit + push, then bump the ref in the parent.

## Hard rules — NEVER do these

- ❌ Direct HTTP from one service to another (gateway is the only client of services, and only via RabbitMQ).
- ❌ Sharing a Prisma schema or DB across services.
- ❌ Using `npm`/`yarn` — pnpm only.
- ❌ Committing changes that touch a submodule without first committing inside the submodule and bumping the ref in the parent.
- ❌ Editing the root-level `entrypoint.sh` expecting it to affect containers — each service has its OWN `<service>/entrypoint.sh` that the Dockerfile copies. Edit per-service.
- ❌ Replacing `prisma db push` with `migrate deploy` in `entrypoint.sh` — the user explicitly chose `db push` for idempotent boot-time sync.

## Quick references

- [CLAUDE.md](../../../CLAUDE.md) — repo overview
- [AGENTS.md](../../../AGENTS.md) — deep dive on existing flows
- [docker-compose.yml](../../../docker-compose.yml) — ground truth for service wiring
- `gateway/src/identity/services/request-response.manager.ts` — the RPC promise manager to reuse
- `scheduler/` — newest reference implementation showing all three patterns end-to-end
