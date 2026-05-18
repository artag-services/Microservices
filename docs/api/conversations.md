# Conversations — `/v1/conversations/*`

Sistema de "salas de conversación" — agrupa los mensajes intercambiados con un usuario en un canal específico. Una conversación tiene historial, estado (abierta/cerrada), agente asignado, configuración de IA, etc. Pensado para casos tipo CRM/helpdesk.

## Endpoints

> 📖 **Las lecturas de conversaciones se movieron al read model:**
> - Lista cross-channel: [`GET /v1/query/conversations?channel=whatsapp`](./query.md#get-v1queryconversations)
> - Detalle: [`GET /v1/query/conversations/:id`](./query.md#get-v1queryconversationsid)
> - Mensajes (cronológico asc): [`GET /v1/query/conversations/:id/messages`](./query.md#get-v1queryconversationsidmessages)
> - Por usuario: [`GET /v1/query/users/:userId/conversations`](./query.md#get-v1queryusersuseridconversations)

---

### `POST /v1/conversations`
**Patrón:** RPC · `200 OK`

Crear una conversación manualmente (normalmente se crean automáticamente cuando llega un mensaje, pero podés iniciar una desde el frontend).

```json
{
  "channel": "whatsapp",
  "channelUserId": "573205711428",
  "topic": "Onboarding nuevo cliente",
  "aiEnabled": false
}
```

| Campo | Tipo | Requerido |
|---|---|---|
| `channel` | string | ✅ |
| `channelUserId` | string | optional |
| `topic` | string | optional |
| `aiEnabled` | boolean | optional (default: backend decide) |

**Response:** modelo `Conversation` recién creado.

---

### `PATCH /v1/conversations/:conversationId`
**Patrón:** RPC · `200 OK`

Actualizar configuración de la conversación.

```json
{
  "aiEnabled": false,
  "agentAssigned": "operator-uuid",
  "status": "CLOSED"
}
```

| Campo | Tipo | Notas |
|---|---|---|
| `aiEnabled` | boolean | toggle IA para esta conversación |
| `agentAssigned` | string | uuid del operador humano que la maneja |
| `status` | enum | `OPEN`, `CLOSED`, `WAITING`, `ARCHIVED` |

Todos los campos son opcionales — solo cambia los que mandás.

---

### `DELETE /v1/conversations/:conversationId`
**Patrón:** Soft-delete local · `200 OK`

Archiva la conversación (no la borra físicamente).

**Response:** `{ "success": true }`

---

## Lo que SÍ podés hacer

- Mostrar lista tipo "Inbox" con paginación, filtros por canal y por status
- Vista detalle de una conversación con su historial completo de mensajes
- Asignar un agente humano y desactivar IA cuando un operador toma el control
- Crear conversación manualmente para iniciativas outbound (no esperar a que el cliente escriba primero)
- Cerrar/archivar conversaciones resueltas

## Lo que NO podés hacer

- ❌ Enviar un mensaje DESDE este endpoint. Para enviar, usá [`POST /v1/messages/send`](./messages.md). Este módulo solo gestiona la conversación, no el envío.
- ❌ Recibir mensajes en tiempo real (no hay websocket aquí — necesitás polling o un módulo aparte que el backend no expone aún).
- ❌ Buscar full-text dentro de los mensajes.
- ❌ Bulk operations (cerrar 50 conversaciones de un saque). Tenés que iterar.
- ❌ Restaurar una conversación archivada vía API. Tenés que consultarla con un filtro especial (no documentado, probablemente `?status=ARCHIVED`).
- ❌ Editar/borrar mensajes individuales de una conversación.

## Notas de arquitectura

A diferencia de la mayoría de los endpoints del gateway, **conversations consulta la DB del gateway directamente** (no via RabbitMQ). Eso es porque las salas de conversación son un concepto del gateway, no de un microservicio específico. Los mensajes adentro de cada conversación sí viven en la DB del microservicio del canal correspondiente (whatsapp_db, instagram_db, etc.) — cuando pedís `GET /:id/messages`, el gateway hace la query cross-DB.
