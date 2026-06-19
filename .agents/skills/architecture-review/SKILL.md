---
name: architecture-review
description: Perform a thorough architecture review of a microservice in this composition repository. Use this skill when the user asks to review, audit, classify, grade, or evaluate a service's architecture, code quality, or adherence to hexagonal architecture patterns. Covers hexagonal boundaries, port completeness, use case coverage, error handling, type safety, extensibility, DI wiring, dead code, naming conventions, and cross-service symmetry.
license: Complete terms in LICENSE.txt
---

This skill guides a comprehensive architecture review of any microservice in the Microservices-2 composition repository. The review evaluates 10 dimensions and produces a scored report with prioritized issues.

## Dimensions to Evaluate

### 1. Hexagonal Boundaries (weight: 2/10)
- Domain layer (`domain/`) must be pure TypeScript — zero NestJS decorators (`@Injectable`, `@Inject`, `@OnModuleInit`)
- Entities should contain only domain logic, no framework or infrastructure imports
- Use cases (`domain/services/`) must import only port interfaces — no concrete implementations
- Adapters (`infrastructure/`) implement ports, never the reverse
- Dependencies must flow inward: Consumer → UseCase → Port ← Adapter

**What to check:**
- Do any domain files import from `@nestjs/*`?
- Do any domain files import concrete classes from `infrastructure/`?
- Do adapters depend on other concrete infrastructure classes instead of ports?
- Are there any `try/catch` blocks in domain layer that swallow errors?

### 2. Port Completeness (weight: 1.5/10)
Every external dependency needs a port: database, cache, message queue, AI service, API clients, rate limiter, logger.

**What to check:**
- List all ports in `domain/ports/`
- For each external call in a use case, is there a corresponding port?
- For each adapter in `infrastructure/`, does it implement a port?
- Are there any concrete imports in use cases that bypass ports?
- Compare port count against WhatsApp (the reference service)

### 3. Use Case Coverage (weight: 1.5/10)
All business logic should live in use cases (`domain/services/`), not in consumers or adapters.

**What to check:**
- List all use cases in `domain/services/`
- Compare against what the consumer (`application/consumers/`) does
- Is there business logic in consumers (e.g., routing decisions, data transformation)?
- Are webhook/HTTP handlers thin (pass-through to queue)?
- Are all event types handled by some use case?

### 4. Cross-Service Symmetry (weight: 1/10)
All services should follow the same patterns unless divergence is justified.

**What to check:**
- Compare port list against WhatsApp (the reference service)
- Compare use case signatures and behavior
- Compare consumer subscription structure (queues, routing keys)
- Compare DI wiring in `app.module.ts`
- Any divergence must have a documented justification

### 5. Error Handling & Resilience (weight: 1.5/10)
Errors should be caught, logged, and handled appropriately. No silent failures.

**What to check:**
- Are consumer handlers wrapped in try/catch?
- Do they NACK on failure (or dead-letter)?
- Are there empty catch blocks?
- Are there stub handlers (`async () => { /* stub */ }`)?
- Is there retry logic with backoff?
- Are transient errors distinguished from permanent failures?
- What happens when RabbitMQ is down?

### 6. Type Safety (weight: 1/10)
Strong typing catches bugs at compile time.

**What to check:**
- Are there `as any` casts? (check all infrastructure files)
- Are DTOs validated at runtime? (class-validator, Zod, etc.)
- Are RabbitMQ payloads typed or `Record<string, unknown>`?
- Are there unused imports?
- Are Prisma operations properly typed (`Prisma.XYZUpdateInput`)?
- Are there `as unknown as SomeType` casts in consumers?

### 7. Extensibility (weight: 1/10)
How easy is it to add a new channel (Telegram), AI provider, or persistence layer?

**What to check:**
- Are channel-specific strings hardcoded in use cases?
- Can you add `IMessageSender` + `IProfileRepository` for a new channel without touching existing code?
- Can you swap AI provider with a new `IAIService` implementation?
- Are routing keys channel-scoped or hardcoded?

### 8. DI Wiring (weight: 1/10)
NestJS dependency injection should be correct and consistent.

**What to check:**
- Are all adapters registered as providers in `app.module.ts`?
- Are all use cases provided via `useFactory` (to keep domain decorator-free)?
- Are string injection tokens used? (`'IMessageRepository'`) — fragile but accepted.
- Are there circular dependencies?
- Are `@Global()` modules used correctly? (PrismaModule, RabbitMQModule)

### 9. Dead Code & Orphaned References (weight: 0.5/10)
Unused code creates confusion and maintenance burden.

**What to check:**
- Unused imports in all source files
- DTOs that are no longer imported or used
- Old controllers/services still registered in modules
- Files in the service that aren't imported by anything
- Commented-out code blocks

### 10. Naming & Conventions (weight: 0.5/10)
Consistency reduces cognitive load.

**What to check:**
- Kebab-case filenames with consistent suffixes (`entity.ts`, `usecase.ts`, `repository.ts`)
- PascalCase classes, camelCase methods/variables
- `I`-prefixed port interfaces
- `Prisma`-prefixed repository implementations
- Routing key patterns: `channels.<service>.<action>`, `data.<service>.<entity>.<event>`
- Mixed languages in comments/logs (should be consistent)

## Severity Classification

| Severity | Description | Action |
|----------|-------------|--------|
| 🔴 Critical | Data loss, silent failures, security issue | Fix immediately |
| 🟠 Major | Architecture violation, degraded resilience, inconsistency | Fix this iteration |
| 🟡 Minor | Code smell, tech debt, cosmetic | Fix when convenient |

## Scoring Matrix

Each dimension scored 0.0–2.0:
- 2.0: Excellent — no issues found
- 1.5: Good — minor issues only
- 1.0: Adequate — one or two moderate issues
- 0.5: Weak — several issues, needs attention
- 0.0: Failing — fundamental problems

Weighted total = sum(score × weight) / 2 × 10

Typical ranges:
- 9.0–10.0: Outstanding
- 7.0–8.9: Good (production-ready with some tech debt)
- 5.0–6.9: Needs improvement
- <5.0: Requires significant rework
