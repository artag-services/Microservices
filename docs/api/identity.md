# Identity — `/v1/identity/*`

Sistema de unificación de identidades de usuarios a través de múltiples canales (WhatsApp, Slack, Instagram, etc.). Un mismo usuario humano puede tener varias `Identity` (una por canal donde te escribe), todas vinculadas a un único `User`.

**Backend:** identity-service (puerto 3010)

## Conceptos

- **`User`** — el "humano" único en tu sistema. Tiene `id` (uuid), `aiEnabled`, timestamps.
- **`Identity`** — cómo el humano aparece en un canal específico. `{ channel, channelUserId, displayName, avatarUrl, trustScore }`. Un User puede tener N identidades.
- **`channel`** — string libre: `"whatsapp"`, `"instagram"`, `"slack"`, `"facebook"`, `"tiktok"`, etc.
- **`channelUserId`** — el id del usuario EN ese canal (ej: número de WhatsApp `+573205711428`, IGSID de Instagram, slack user id).
- **`trustScore`** (0.0–1.0) — qué tan seguro estás de que esa identidad realmente pertenece a ese User. Útil cuando vinculás identidades por inferencia.

## Endpoints

### `POST /v1/identity/resolve`
**Patrón:** Fire-and-forget · `202 Accepted`

Crea o vincula una identidad. Si el `channelUserId` en ese `channel` ya existe, lo actualiza; si no, crea un nuevo `User` + `Identity`.

```json
{
  "channel": "whatsapp",
  "channelUserId": "573205711428",
  "displayName": "Chris",
  "phone": "+573205711428",
  "email": "scristxyz@gmail.com",
  "username": "chris_dev",
  "avatarUrl": "https://...",
  "trustScore": 0.95,
  "metadata": { "source": "first_message" }
}
```

| Campo | Tipo | Requerido |
|---|---|---|
| `channel` | string | ✅ |
| `channelUserId` | string | ✅ |
| `displayName` | string | optional |
| `phone` | string | optional |
| `email` | string (email válido) | optional |
| `username` | string | optional |
| `avatarUrl` | string | optional |
| `trustScore` | number 0.0–1.0 | optional |
| `metadata` | objeto JSON libre | optional |

**Response:**
```json
{ "success": true, "message": "Identity resolution queued" }
```

> ⚠️ Como es fire-and-forget, NO te devuelve el id del User creado. Si necesitás el id inmediatamente, usá `GET /v1/identity/users` después con filtro por canal.

---

### `GET /v1/identity/users`
**Patrón:** RPC · `200 OK`

Lista todos los usuarios con filtros opcionales.

**Query params:**
| Param | Tipo | Default |
|---|---|---|
| `channel` | string | (todos) |
| `includeDeleted` | boolean | `false` |

**Ejemplo:** `GET /api/v1/identity/users?channel=whatsapp`

**Response:**
```json
[
  {
    "id": "uuid",
    "aiEnabled": true,
    "createdAt": "...",
    "identities": [
      {
        "channel": "whatsapp",
        "channelUserId": "573205711428",
        "displayName": "Chris",
        "trustScore": 0.95
      }
    ]
  }
]
```

---

### `GET /v1/identity/users/:userId`
**Patrón:** RPC · `200 OK`

Devuelve un usuario específico con todas sus identidades, contactos, e historial de nombres.

**Response:**
```json
{
  "user": { "id": "...", "aiEnabled": true, ... },
  "identities": [...],
  "contacts": [...],
  "nameHistory": [...]
}
```

`404` si el `userId` no existe.

---

### `POST /v1/identity/merge`
**Patrón:** Fire-and-forget · `202 Accepted`

Fusiona dos usuarios en uno. El `secondaryUserId` se borra (soft-delete) y todas sus identidades/contactos se transfieren al `primaryUserId`.

```json
{
  "primaryUserId": "uuid-del-que-queda",
  "secondaryUserId": "uuid-del-que-se-borra",
  "reason": "Mismo usuario detectado por número de teléfono"
}
```

| Campo | Tipo | Requerido |
|---|---|---|
| `primaryUserId` | string (uuid) | ✅ |
| `secondaryUserId` | string (uuid) | ✅ |
| `reason` | string | ✅ |

---

### `DELETE /v1/identity/users/:userId`
**Patrón:** Fire-and-forget · `202 Accepted`

Soft-delete del usuario. No borra físicamente, marca como eliminado. Las identidades quedan vinculadas pero el User no aparece en listados (a menos que pidas `includeDeleted=true`).

---

### `GET /v1/identity/report`
**Patrón:** RPC · `200 OK`

Reporte agregado del sistema de identidades.

**Response:**
```json
{
  "totalUsers": 1234,
  "usersByChannel": {
    "whatsapp": 800,
    "instagram": 300,
    "slack": 134
  },
  "deletedUsers": 12,
  "averageIdentitiesPerUser": 1.4
}
```

Útil para dashboards.

---

### `PATCH /v1/identity/users/:userId/ai-settings`
**Patrón:** Fire-and-forget · `202 Accepted`

Activa/desactiva el procesamiento por IA para ese usuario (cuando le llegue un mensaje en cualquier canal).

```json
{ "aiEnabled": false }
```

---

## Lo que SÍ podés hacer desde el front

- Mostrar lista paginada de usuarios filtrada por canal
- Buscar un usuario y ver todas sus identidades en un solo lugar
- Disparar merge de dos usuarios (ej: el operador del CRM detecta que dos perfiles son la misma persona)
- Toggle de "responder con IA" por usuario
- Dashboard con métricas de `GET /report`

## Lo que NO podés hacer

- ❌ Modificar campos individuales de una identidad (no hay `PATCH /identities/:id`). Para cambiar trustScore o displayName tenés que volver a llamar `POST /resolve` con los mismos `channel` + `channelUserId` y los nuevos valores.
- ❌ Borrar una identidad específica sin borrar al usuario entero.
- ❌ Hard-delete (borrado físico). Todo es soft-delete.
- ❌ Conocer el `userId` inmediatamente después de `resolve` (es fire-and-forget) — tenés que consultar después.
- ❌ Listar identidades sueltas (sin agrupar por usuario). El listado siempre está User-centric.
