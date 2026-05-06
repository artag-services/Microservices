# Cloudflare Email Worker — código y setup

Este worker se despliega en cada zona de Cloudflare (una por dominio) y reenvía los emails entrantes al gateway con HMAC.

## Setup en cada cuenta de Cloudflare (hacé esto 2 veces, una por dominio)

### 1. Activar Email Routing
- DNS → Email → **Email Routing → Get Started**
- Cloudflare agrega los MX records automáticamente
- Verificá que el dominio quedó "Active"

### 2. Crear el Worker
- Workers → **Create Application** → **Hello World** template
- Nombrelo `email-inbound-<domain>` (ej: `email-inbound-artagdev`)
- Reemplazá el código con `worker.js` de abajo
- Variables de entorno (Settings → Variables):
  - `GATEWAY_URL` = `https://gateway.artagdev.com.co/api/webhooks/email/inbound`
  - `INBOUND_SECRET` = el mismo valor de `INBOUND_EMAIL_WEBHOOK_SECRET` en tu `.env`
  - `DOMAIN` = `artagdev.com.co` (o el dominio que corresponda a este worker)

### 3. Conectar Email Routing → Worker
- DNS → Email → Email Routing → **Routes**
- Add **Catch-all** address (o reglas específicas como `info@*`)
- Action: **Send to a Worker** → seleccionás el worker recién creado

## `worker.js`

```javascript
// Cloudflare Email Worker — bridges incoming emails to the gateway via HMAC.
// Requires `postal-mime` to parse the raw RFC 5322 message.

import PostalMime from 'postal-mime'

export default {
  async email(message, env, ctx) {
    try {
      const parsed = await PostalMime.parse(message.raw)

      const payload = {
        domain: env.DOMAIN,
        toAddress: message.to,
        toAlias: message.to.split('@')[0],
        fromAddress: message.from,
        fromName: parsed.from?.name,
        subject: parsed.subject,
        textBody: parsed.text,
        htmlBody: parsed.html,
        headers: Object.fromEntries(message.headers ?? []),
        attachments: (parsed.attachments ?? []).map(a => ({
          name: a.filename,
          contentType: a.mimeType,
          size: a.content?.byteLength,
        })),
        metadata: {
          messageId: parsed.messageId,
          receivedVia: 'cloudflare-worker',
        },
      }

      const body = JSON.stringify(payload)
      const signature = await hmacSha256Hex(env.INBOUND_SECRET, body)

      const response = await fetch(env.GATEWAY_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Inbound-Signature': signature,
        },
        body,
      })

      if (!response.ok) {
        console.error(`Gateway returned ${response.status}: ${await response.text()}`)
        // Don't reject — worker errors bounce the email back to sender, which is bad UX.
        // Log and accept; the gateway will retry from RabbitMQ if it's a transient issue.
      } else {
        console.log(`Forwarded ${message.from} → ${message.to} to gateway`)
      }
    } catch (err) {
      console.error('Email worker failed:', err.stack ?? err)
      // Same: accept the email anyway, dropping data is better than bouncing
    }
  },
}

async function hmacSha256Hex(secret, message) {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(message))
  return Array.from(new Uint8Array(sig))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('')
}
```

## `package.json` del worker

Como el worker usa `postal-mime`, necesitás un proyecto npm:

```json
{
  "name": "email-inbound-worker",
  "version": "1.0.0",
  "main": "worker.js",
  "dependencies": {
    "postal-mime": "^2.2.0"
  }
}
```

Y `wrangler.toml`:
```toml
name = "email-inbound-artagdev"
main = "worker.js"
compatibility_date = "2025-01-15"
```

Deploy con `wrangler deploy`.

> **Alternativa sin postal-mime**: si no querés un proyecto npm, podés enviar el raw email body sin parsear. Modificá el worker para enviar `rawMessage: await readBody(message.raw)` y parseálo del lado del gateway con una librería de Node (ej: `mailparser`). Más complejo en el gateway pero más simple en el worker.

## Cómo generar el `INBOUND_EMAIL_WEBHOOK_SECRET`

```bash
openssl rand -hex 32
```

Pegá el mismo valor en:
1. Tu `.env` del server: `INBOUND_EMAIL_WEBHOOK_SECRET=<valor>`
2. Variables del worker en Cloudflare account A: `INBOUND_SECRET=<valor>`
3. Variables del worker en Cloudflare account B: `INBOUND_SECRET=<valor>` (mismo valor)

Cuando rotes el secret: actualizás los 3 lugares y reiniciás gateway.

## Test

1. Mandá un email a `info@artagdev.com.co` desde Gmail
2. Cloudflare lo recibe → ejecuta el worker → POST al gateway
3. Gateway verifica HMAC → publica `channels.email.inbound.received`
4. Email service consume → guarda en `InboundEmail` table
5. Consultá el resultado:
   ```bash
   curl http://localhost:3000/api/v1/emails/inbound | jq
   ```

## Logs útiles

```bash
# Worker logs
wrangler tail email-inbound-artagdev

# Gateway logs
docker-compose logs -f gateway | grep -i inbound

# Email service logs
docker-compose logs -f email | grep -i inbound
```
