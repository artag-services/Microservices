# TikTok

Publicación de videos vía TikTok Content Posting API. El microservicio `tiktok` (puerto 3005) consume del exchange `channels` y publica usando el `TIKTOK_ACCESS_TOKEN` de un creator account autorizado.

> ⚠️ TikTok **no es para mensajería** — es para publicar videos en feeds. Si querés mandar mensajes directos a usuarios de TikTok, no es posible (la API no lo soporta para developers).

## Operaciones disponibles

| Operación | Vía | Estado |
|---|---|---|
| Publicar video en cuenta(s) | `POST /api/v1/messages/send` | ✅ disponible |
| Consultar estado de publicación | `GET /api/v1/messages/:id` | ✅ disponible (limitado — ver abajo) |
| Listar creator accounts autorizados | — | ⚠️ falta endpoint |
| Status detallado del video (views, comments) | — | ⚠️ falta endpoint |
| Update de privacidad post-publicación | — | ⚠️ falta endpoint |
| Recibir webhooks de TikTok | — | ❌ no implementado |

---

## ✅ Publicar video

### `POST /api/v1/messages/send`

```json
{
  "channel": "tiktok",
  "recipients": ["open_id-del-creador"],
  "message": "Mira este nuevo video! 🔥 #fyp #contenido",
  "metadata": {
    "videoUrl": "https://example.com/mi-video.mp4",
    "coverUrl": "https://example.com/thumbnail.jpg",
    "privacy_level": "PUBLIC_TO_EVERYONE",
    "disable_comment": false,
    "disable_duet": false,
    "disable_stitch": false,
    "video_cover_timestamp_ms": 2000
  }
}
```

| Campo | Tipo | Requerido | Notas |
|---|---|---|---|
| `channel` | string | ✅ | siempre `"tiktok"` |
| `recipients` | string[] | ✅ | array de `open_id` (uno por creator account autorizado). Si pasás 3, se publica el mismo video en las 3 cuentas. |
| `message` | string | ✅ | caption del video — incluí hashtags acá |
| `metadata.videoUrl` | string | ✅ | **URL pública** de un .mp4 — TikTok lo descarga del internet |
| `metadata.coverUrl` | string | optional | URL de imagen de portada |
| `metadata.privacy_level` | enum | optional | `"PUBLIC_TO_EVERYONE"` (default), `"MUTUAL_FOLLOW_FRIENDS"`, `"SELF_ONLY"` (privado, solo vos lo ves) |
| `metadata.disable_duet` | boolean | optional | bloquear que otros hagan duet del video |
| `metadata.disable_comment` | boolean | optional | bloquear comentarios |
| `metadata.disable_stitch` | boolean | optional | bloquear stitches |
| `metadata.video_cover_timestamp_ms` | number | optional | momento (en ms) del video para autogenerar el thumbnail si no pasás `coverUrl` |

> ⚠️ **Importante:** `videoUrl` debe estar en el body como `metadata.videoUrl`, **no como `mediaUrl`**. Es distinto del resto de los canales.

> ⚠️ **NO se valida `videoUrl` en el gateway hoy** — si el video no es accesible, el envío "se acepta" pero falla en TikTok sin que te enteres con el polling normal. Pedile al backend que valide la URL antes (HEAD request) si te importa.

**Response (`202 Accepted`):** mismo shape genérico.

---

## ✅ Consultar estado

### `GET /api/v1/messages/:id`

```json
{
  "id": "f47ac10b-...",
  "channel": "tiktok",
  "recipients": ["open_id"],
  "message": "Caption...",
  "status": "SENT",
  "createdAt": "...",
  "updatedAt": "..."
}
```

`status` posibles:
- `PENDING` — encolado
- `SENT` — TikTok aceptó el video y lo publicó
- `FAILED` — error (videoUrl inválido, formato no soportado, cuenta sin permisos)

> ⚠️ **No hay datos del video publicado** (URL de TikTok, video_id, métricas) en este response. TikTok los devuelve pero el sistema no los persiste todavía. Si los necesitás, pedile al backend que extienda el modelo para guardar `tiktok_video_id` y exponer un endpoint `GET /api/v1/messages/tiktok/:id/details`.

---

## ⚠️ Lo que NO podés hacer hoy desde el frontend

| Quiero… | Estado | Notas |
|---|---|---|
| Listar las cuentas de TikTok que autoricé | falta endpoint | hardcodear los `open_id` en el front (no ideal) |
| Ver views, likes, comments del video | falta endpoint | imposible hoy |
| Cambiar privacy de un video ya publicado | falta endpoint | imposible hoy |
| Borrar un video publicado | falta endpoint | imposible hoy |
| Subir el video como multipart upload | ❌ | TikTok requiere URL pública (no es limitación nuestra) |
| Programar publicación a futuro | usar [scheduler](../scheduler.md) | crea una tarea con `targetRoutingKey: "channels.tiktok.send"` |
| Mandar DMs en TikTok | ❌ | la API de TikTok no lo permite |
| Postear stories | ❌ | la API no lo soporta |

---

## Restricciones de TikTok

- **Formato de video**: MP4 con codec H.264, audio AAC. Vertical 9:16 recomendado (1080x1920).
- **Duración**: 3 segundos a 10 minutos.
- **Tamaño**: hasta 4GB.
- **Caption**: máx 2200 caracteres, hashtags incluidos.
- **Hashtags**: máx 50 por video.
- **Sandbox mode**: las primeras semanas tu app está en sandbox y solo podés publicar a la cuenta del developer. Para publicar a creators externos hay que pasar el review de TikTok.

---

## Errores comunes

| Síntoma | Causa probable |
|---|---|
| `status: FAILED` con `INVALID_FILE_FORMAT` | el video no es MP4 H.264 |
| `status: FAILED` con `URL_OWNERSHIP_UNVERIFIED` | tu dominio del `videoUrl` no está verificado en TikTok Developer Portal |
| `status: FAILED` con `SPAM_RISK_USER_BANNED_FROM_POSTING` | la cuenta está suspendida temporalmente |
| `status: FAILED` con `VIDEO_PULL_FAILED` | TikTok no pudo descargar el video — chequear que la URL es pública y devuelve el archivo (no una página HTML) |
| El video se publica pero queda como "draft" | `privacy_level: "SELF_ONLY"` — está privado, solo el creator lo ve. Cambialo si querés que sea público. |
| Video no aparece en feed pero `status: SENT` | TikTok puede tardar minutos en procesarlo — refrescar la app después de un rato |

---

## Ejemplo cURL completo

```bash
curl -X POST http://localhost:3000/api/v1/messages/send \
  -H "Content-Type: application/json" \
  -d '{
    "channel": "tiktok",
    "recipients": ["open_id-de-mi-cuenta"],
    "message": "Probando publicación desde el sistema 🚀 #test",
    "metadata": {
      "videoUrl": "https://mi-cdn.com/video-vertical.mp4",
      "privacy_level": "PUBLIC_TO_EVERYONE",
      "disable_comment": false
    }
  }'
```
