# Documentación por canal — para frontend

Esta carpeta es **self-contained**: copiala entera al repo del frontend y vas a tener todo lo que necesitás para integrar cada canal sin tener que mirar el resto del proyecto.

## Cómo está organizado

Un archivo por canal/microservicio. Cada uno explica:

- **Qué hace este canal** (en una línea)
- **Operaciones disponibles HOY** vía gateway (✅) vs lo que el backend soporta pero falta exponer (⚠️)
- **URL + JSON body + response** de cada operación, copy-paste-able
- **Formato de los IDs de destinatarios** (cada canal usa el suyo)
- **Webhooks entrantes** (eventos que el canal manda al sistema — informativo, no es para que el front los llame)
- **Errores comunes**

| Canal | Doc | Operaciones HOY |
|---|---|---|
| WhatsApp | [whatsapp.md](./whatsapp.md) | Enviar mensaje (texto / media) |
| Slack | [slack.md](./slack.md) | Enviar mensaje a canal o DM |
| Notion | [notion.md](./notion.md) | Crear página / crear tarea / invitar miembro |
| Instagram | [instagram.md](./instagram.md) | Listar conversaciones, enviar DM directo o por gateway |
| TikTok | [tiktok.md](./tiktok.md) | Publicar video |
| Facebook | [facebook.md](./facebook.md) | Enviar mensaje vía Page |

## Base URL (para todos los archivos)

```
https://<tu-dominio-del-gateway>/api
```

Localmente: `http://localhost:3000/api`. El prefijo `/api` ya está incluido en todos los ejemplos.

## Headers comunes (siempre)

```
Content-Type: application/json
```

No hay autenticación todavía. Cuando se active será un `Authorization: Bearer <jwt>` adicional.

## Patrón de respuesta común

Todos los endpoints de envío devuelven **`202 Accepted`** con un body así:

```json
{
  "id": "uuid-interno-del-mensaje",
  "accepted": true,
  "channel": "whatsapp",
  "recipients": ["..."],
  "message": "...",
  "status": "PENDING",
  "createdAt": "2026-04-25T18:42:11.123Z"
}
```

`status` empieza en `PENDING` y va cambiando (`SENT`, `FAILED`, `PARTIAL`) a medida que el microservicio destino procesa. Para verificar status final:

```
GET /api/v1/messages/:id
```

Esto es **fire-and-forget** — el `202` solo significa "encolado", no "entregado". Para entrega real necesitás:
1. Polling: `GET /api/v1/messages/:id` cada 1-2 segundos
2. O esperar webhooks del canal externo (que llegan al sistema pero no se propagan al frontend hoy)

## El "patrón generic" vs "endpoints específicos por canal"

Hoy el gateway expone principalmente **un endpoint generic** para todos los canales:

```
POST /api/v1/messages/send
```

Con un campo `channel` que decide a qué microservicio rutear. Es funcional pero el frontend tiene que conocer qué `channel` mandar y los formatos de cada uno. Cada doc por canal te muestra cómo llamar este endpoint para ESE canal específicamente.

**Solo Instagram tiene rutas dedicadas extra** (`/v1/messages/instagram/conversations` y `/v1/messages/instagram/:igsid`). Los demás canales podrían tener rutas dedicadas en el futuro — cada doc lista las que faltan agregar.

## Sin paginación, sin búsqueda

Casi nada está paginado todavía. `GET /api/v1/messages/:id` solo trae uno por id. No hay listado general de mensajes ni full-text search. Tu frontend va a tener que mantener su propia caché si querés mostrar inbox o historial.

## Más documentación

Si tu frontend va a tocar más que solo canales:
- [../identity.md](../identity.md) — usuarios y vinculación cross-canal
- [../email.md](../email.md) — emails transaccionales
- [../scheduler.md](../scheduler.md) — tareas programadas (podés programar envíos de WhatsApp/email/etc.)
- [../scraping.md](../scraping.md) — web scraping
- [../README.md](../README.md) — convenciones globales (RPC vs fire-and-forget, errores, CORS)
