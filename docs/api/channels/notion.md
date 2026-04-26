# Notion

Operaciones contra la API de Notion. El microservicio `notion` (puerto 3003) consume del exchange `channels` y dialoga con `api.notion.com` usando tu `NOTION_INTEGRATION_TOKEN`. A diferencia de los otros canales, Notion soporta **3 operaciones distintas** (no solo enviar mensaje), seleccionables vía el campo `operation`.

## Operaciones disponibles

| Operación | `operation` value | Vía | Estado |
|---|---|---|---|
| Crear página nueva | `create_page` | `POST /api/v1/messages/send` | ✅ disponible |
| Crear tarea en database | `create_task` | `POST /api/v1/messages/send` | ✅ disponible |
| Invitar miembro | `invite_member` | `POST /api/v1/messages/send` | ✅ disponible |
| Listar databases accesibles | — | — | ⚠️ falta endpoint |
| Leer estructura de una página | — | — | ⚠️ falta endpoint |
| Update de página existente | — | — | ⚠️ falta endpoint |

---

## ✅ Crear página

### `POST /api/v1/messages/send`

```json
{
  "channel": "notion",
  "recipients": ["abc123-def456-..."],
  "operation": "create_page",
  "message": "Notas de reunión 25 de abril",
  "metadata": {
    "parent_page_id": "abc123-def456-...",
    "title": "Reunión Q2 — Estrategia",
    "icon": "📝"
  }
}
```

| Campo | Tipo | Requerido | Notas |
|---|---|---|---|
| `channel` | string | ✅ | siempre `"notion"` |
| `recipients` | string[] | ✅ | un array con el ID donde se crea (puede ser el `parent_page_id` para consistencia) |
| `operation` | string | ✅ | `"create_page"` |
| `message` | string | ✅ | contenido inicial / título por default si no hay `metadata.title` |
| `metadata.parent_page_id` | string | ✅ | UUID de la página parent en Notion (sacalo del URL: `notion.so/Mi-Pagina-abc123def456` → ID es `abc123def456`) |
| `metadata.title` | string | optional | título de la página (default: el `message`) |
| `metadata.icon` | string | optional | emoji que aparece como icono |

**Response (`202 Accepted`):** mismo shape genérico. La URL real de la página llega después por RabbitMQ event (no la tenés en la respuesta inmediata).

> Para conseguir el `notionPageUrl` después: hacé polling en `GET /api/v1/messages/:id` — el `metadata` debería poblarse cuando Notion responda. (Si no se popula, es porque la integración interna `scrapping → notion` consume esa respuesta antes — pedile al backend que también la guarde en el `Message`).

---

## ✅ Crear tarea (en database)

### `POST /api/v1/messages/send`

```json
{
  "channel": "notion",
  "recipients": ["database-uuid"],
  "operation": "create_task",
  "message": "Revisar PR #1234",
  "metadata": {
    "database_id": "database-uuid-de-tu-tabla-de-tasks",
    "title_property": "Name",
    "due_date": "2026-04-30T23:59:00.000Z",
    "assignee_ids": ["notion-user-uuid"],
    "priority": "High"
  }
}
```

| Campo | Tipo | Requerido | Notas |
|---|---|---|---|
| `operation` | string | ✅ | `"create_task"` |
| `message` | string | ✅ | título de la tarea |
| `metadata.database_id` | string | ✅ | UUID de la database de Notion donde se inserta |
| `metadata.title_property` | string | optional | nombre de la columna que es el título (default: `"Name"`) |
| `metadata.due_date` | string ISO | optional | timestamp de vencimiento |
| `metadata.assignee_ids` | string[] | optional | UUIDs de personas en Notion |
| `metadata.priority` | string | optional | depende de tu schema de DB (`"High"`, `"Medium"`, `"Low"`) |

> ⚠️ Las propiedades extra (priority, etc.) deben existir EN la database de Notion antes. Si tu database no tiene una columna `Priority`, mandar el campo no falla pero queda ignorado.

---

## ✅ Invitar miembro

### `POST /api/v1/messages/send`

```json
{
  "channel": "notion",
  "recipients": ["page-uuid-opcional"],
  "operation": "invite_member",
  "message": "Te invito a colaborar en este proyecto",
  "metadata": {
    "email": "colaborador@empresa.com",
    "page_id": "page-uuid-opcional"
  }
}
```

| Campo | Tipo | Requerido |
|---|---|---|
| `operation` | string | ✅ `"invite_member"` |
| `metadata.email` | string | ✅ |
| `metadata.page_id` | string | optional (a qué página dar acceso) |

> ⚠️ Esta operación puede tener limitaciones según el plan de Notion. En el plan Free no podés invitar via API a guests externos.

---

## ⚠️ Lo que NO podés hacer hoy desde el frontend

| Quiero… | Estado | Workaround |
|---|---|---|
| Listar las databases que mi integración puede ver | falta endpoint | obtener IDs del UI de Notion y pasarlos hardcodeados al front |
| Listar páginas children de una página | falta endpoint | imposible hoy |
| Update de propiedades de una página existente | falta endpoint | imposible hoy |
| Borrar (archivar) una página | falta endpoint | imposible hoy |
| Buscar páginas por texto | falta endpoint | imposible hoy |
| Operaciones batch (crear 50 tareas de un saque) | falta endpoint | hacer 50 requests individuales |
| Adjuntar archivos a una página | falta soporte en DTO | imposible hoy |
| Embeber bloques específicos (toggle, code, callout) | falta soporte en DTO | el contenido se inserta como texto plano |

---

## Webhooks entrantes (informativo)

Notion soporta webhooks (`POST /api/webhooks/notion`) para 18 tipos de eventos:

- **Página**: created, content_updated, properties_updated, moved, deleted, undeleted, locked, unlocked
- **Database**: created
- **Data source** (nuevo en 2025): created, content_updated, moved, deleted, undeleted, schema_updated
- **Comentarios**: created, updated, deleted

El sistema los recibe y publica internamente, pero hoy nadie los consume todavía. Si tu front quiere reaccionar a "alguien editó esta página", el backend tiene que agregar un consumer.

---

## Errores comunes

| Síntoma | Causa probable |
|---|---|
| `status: FAILED` con `unauthorized` | el `NOTION_INTEGRATION_TOKEN` no tiene acceso a la página/database. Solución: ir a la página en Notion, click "Share" arriba a la derecha, agregar tu integración. |
| `400 Validation failed: operation must be one of...` | mandaste un `operation` que no existe — solo `create_page`, `create_task`, `invite_member` |
| Página se crea pero queda vacía | `message` está vacío y no hay `metadata.title`, o el contenido no es texto plano |
| Tarea se crea pero el due date no aparece | la columna en tu Notion DB no es de tipo "Date" o se llama distinto |

---

## Cómo conseguir los UUIDs de Notion

**De una página:**
URL en el navegador → `notion.so/My-Page-Name-abc123def4567890abc123def4567890`
El UUID es la cadena hex al final, sin guiones medios. Notion también lo acepta con guiones (`abc123de-f456-7890-abc1-23def4567890`).

**De una database:**
Abrir la database como página completa (no embed) → mismo método.

**De un usuario:**
Ir a Settings → People → click en el usuario → la URL contiene su UUID.

---

## Ejemplo cURL completo (crear página)

```bash
curl -X POST http://localhost:3000/api/v1/messages/send \
  -H "Content-Type: application/json" \
  -d '{
    "channel": "notion",
    "recipients": ["336a9ff3e074807a9cc1cd3ef9aead2b"],
    "operation": "create_page",
    "message": "Resumen de la reunión",
    "metadata": {
      "parent_page_id": "336a9ff3e074807a9cc1cd3ef9aead2b",
      "title": "Reunión Q2 2026",
      "icon": "🗓"
    }
  }'
```
