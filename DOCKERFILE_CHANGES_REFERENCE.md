# Dockerfile Changes - Line-by-Line Reference

Use this file to make precise edits to each Dockerfile.

---

## Summary Table

| Service | Current Lines | New Lines | Change Type | Complexity |
|---------|---------------|-----------|------------|------------|
| gateway | 19 | 26 | Standard Update | ⭐ Easy |
| identity | 42 | 46 | Multi-stage Update | ⭐ Easy |
| whatsapp | 19 | 26 | Standard Update | ⭐ Easy |
| slack | 19 | 26 | Standard Update | ⭐ Easy |
| notion | 19 | 26 | Standard Update | ⭐ Easy |
| instagram | 12 | 26 | Standard Update | ⭐ Easy |
| tiktok | 11 | 26 | Standard Update | ⭐ Easy |
| facebook | 11 | 26 | Standard Update | ⭐ Easy |
| scrapping | 32 | 70 | Full Rewrite | ⭐⭐ Medium |

---

## 1. gateway/Dockerfile

**Current** (19 lines):
```dockerfile
FROM node:20-alpine

RUN apk add --no-cache openssl

RUN npm install -g pnpm

WORKDIR /app

COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile

COPY . .

RUN pnpm prisma:generate
RUN pnpm build

EXPOSE 3000

CMD ["node", "dist/main"]
```

**Changes to make**:
1. Line 3: `RUN apk add --no-cache openssl` → `RUN apk add --no-cache openssl netcat-openbsd`
2. After line 12 (COPY . .), add 2 new lines:
   ```dockerfile
   # Copy entrypoint script from root
   COPY ../entrypoint.sh /usr/local/bin/entrypoint.sh
   RUN chmod +x /usr/local/bin/entrypoint.sh
   ```
3. Line 18-19: Replace `CMD ["node", "dist/main"]` with:
   ```dockerfile
   ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
   CMD ["node", "dist/main"]
   ```
4. Optional: Comment out lines 14-15 (pnpm commands happen in entrypoint now)

**Result** (26 lines):
```dockerfile
FROM node:20-alpine

RUN apk add --no-cache openssl netcat-openbsd

RUN npm install -g pnpm

WORKDIR /app

COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile

COPY . .

# Copy entrypoint script from root
COPY ../entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Prisma generation and build happen in entrypoint
# RUN pnpm prisma:generate
RUN pnpm build

EXPOSE 3000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["node", "dist/main"]
```

---

## 2. identity/Dockerfile

**Current** (42 lines):
```dockerfile
FROM node:20-alpine AS builder

WORKDIR /app

# Install pnpm
RUN npm install -g pnpm

# Copy package files
COPY package.json pnpm-lock.yaml ./

# Install dependencies
RUN pnpm install --frozen-lockfile

# Copy source
COPY prisma ./prisma
COPY src ./src
COPY tsconfig.json nest-cli.json ./

# Generate Prisma client and build
RUN pnpm prisma:generate
RUN pnpm build

# Production stage
FROM node:20-alpine

# Install OpenSSL and other runtime dependencies for Prisma
RUN apk add --no-cache openssl

WORKDIR /app

RUN npm install -g pnpm

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --prod --frozen-lockfile

COPY prisma ./prisma
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules/.pnpm /app/node_modules/.pnpm

EXPOSE 3010

CMD ["node", "dist/main"]
```

**Changes to make**:
1. Line 27: `RUN apk add --no-cache openssl` → `RUN apk add --no-cache openssl netcat-openbsd`
2. After line 38 (COPY --from=builder...), add 2 new lines:
   ```dockerfile
   # Copy entrypoint script from root context
   COPY ../entrypoint.sh /usr/local/bin/entrypoint.sh
   RUN chmod +x /usr/local/bin/entrypoint.sh
   ```
3. Line 42: Replace `CMD ["node", "dist/main"]` with:
   ```dockerfile
   ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
   CMD ["node", "dist/main"]
   ```

**Result** (46 lines):
```dockerfile
FROM node:20-alpine AS builder

WORKDIR /app

# Install pnpm
RUN npm install -g pnpm

# Copy package files
COPY package.json pnpm-lock.yaml ./

# Install dependencies
RUN pnpm install --frozen-lockfile

# Copy source
COPY prisma ./prisma
COPY src ./src
COPY tsconfig.json nest-cli.json ./

# Generate Prisma client and build
RUN pnpm prisma:generate
RUN pnpm build

# Production stage
FROM node:20-alpine

# Install OpenSSL and netcat for PostgreSQL connection check
RUN apk add --no-cache openssl netcat-openbsd

WORKDIR /app

RUN npm install -g pnpm

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --prod --frozen-lockfile

COPY prisma ./prisma
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules/.pnpm /app/node_modules/.pnpm

# Copy entrypoint script from root context
COPY ../entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3010

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["node", "dist/main"]
```

---

## 3. whatsapp/Dockerfile

**Current** (19 lines):
```dockerfile
FROM node:20-alpine

RUN apk add --no-cache openssl

RUN npm install -g pnpm

WORKDIR /app

COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile

COPY . .

RUN pnpm prisma:generate
RUN pnpm build

EXPOSE 3001

CMD ["node", "dist/main"]
```

**Changes**: Identical to gateway/Dockerfile
- Line 3: Add `netcat-openbsd`
- After line 12: Add entrypoint.sh copy
- Line 18-19: Replace CMD with ENTRYPOINT + CMD

**Result** (26 lines):
```dockerfile
FROM node:20-alpine

RUN apk add --no-cache openssl netcat-openbsd

RUN npm install -g pnpm

WORKDIR /app

COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile

COPY . .

# Copy entrypoint script from root
COPY ../entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Prisma generation and build happen in entrypoint
# RUN pnpm prisma:generate
RUN pnpm build

EXPOSE 3001

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["node", "dist/main"]
```

---

## 4. slack/Dockerfile

**Current** (19 lines):
```dockerfile
FROM node:20-alpine

RUN apk add --no-cache openssl

RUN npm install -g pnpm

WORKDIR /app

COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile

COPY . .

RUN pnpm prisma:generate
RUN pnpm build

EXPOSE 3002

CMD ["node", "dist/main"]
```

**Changes**: Identical to gateway/Dockerfile
- Line 3: Add `netcat-openbsd`
- After line 12: Add entrypoint.sh copy
- Line 18-19: Replace CMD with ENTRYPOINT + CMD
- Line 17: EXPOSE 3002 (not 3000)

**Result** (26 lines):
```dockerfile
FROM node:20-alpine

RUN apk add --no-cache openssl netcat-openbsd

RUN npm install -g pnpm

WORKDIR /app

COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile

COPY . .

# Copy entrypoint script from root
COPY ../entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Prisma generation and build happen in entrypoint
# RUN pnpm prisma:generate
RUN pnpm build

EXPOSE 3002

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["node", "dist/main"]
```

---

## 5. notion/Dockerfile

**Current** (19 lines):
```dockerfile
FROM node:20-alpine

RUN apk add --no-cache openssl

RUN npm install -g pnpm

WORKDIR /app

COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile

COPY . .

RUN pnpm prisma:generate
RUN pnpm build

EXPOSE 3003

CMD ["node", "dist/main"]
```

**Changes**: Identical to gateway/Dockerfile
- Line 3: Add `netcat-openbsd`
- After line 12: Add entrypoint.sh copy
- Line 18-19: Replace CMD with ENTRYPOINT + CMD
- Line 17: EXPOSE 3003 (not 3000)

**Result** (26 lines):
```dockerfile
FROM node:20-alpine

RUN apk add --no-cache openssl netcat-openbsd

RUN npm install -g pnpm

WORKDIR /app

COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile

COPY . .

# Copy entrypoint script from root
COPY ../entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Prisma generation and build happen in entrypoint
# RUN pnpm prisma:generate
RUN pnpm build

EXPOSE 3003

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["node", "dist/main"]
```

---

## 6. instagram/Dockerfile

**Current** (12 lines):
```dockerfile
FROM node:20-alpine
RUN apk add --no-cache openssl
RUN npm install -g pnpm
WORKDIR /app
COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile
COPY . .
# Updated 2026-04-01: Fixed Instagram Business Account ID for conversations
RUN pnpm prisma:generate
RUN pnpm build
EXPOSE 3004
CMD ["node", "dist/main"]
```

**Changes**:
1. Line 2: `RUN apk add --no-cache openssl` → `RUN apk add --no-cache openssl netcat-openbsd`
2. After line 8 (COPY . .), add 2 new lines:
   ```dockerfile
   # Copy entrypoint script from root
   COPY ../entrypoint.sh /usr/local/bin/entrypoint.sh
   RUN chmod +x /usr/local/bin/entrypoint.sh
   ```
3. Line 12: Replace `CMD ["node", "dist/main"]` with:
   ```dockerfile
   ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
   CMD ["node", "dist/main"]
   ```

**Result** (26 lines):
```dockerfile
FROM node:20-alpine

RUN apk add --no-cache openssl netcat-openbsd

RUN npm install -g pnpm

WORKDIR /app

COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile

COPY . .

# Copy entrypoint script from root
COPY ../entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Updated 2026-04-01: Fixed Instagram Business Account ID for conversations
# Prisma generation and build happen in entrypoint
# RUN pnpm prisma:generate
RUN pnpm build

EXPOSE 3004

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["node", "dist/main"]
```

---

## 7. tiktok/Dockerfile

**Current** (11 lines):
```dockerfile
FROM node:20-alpine
RUN apk add --no-cache openssl
RUN npm install -g pnpm
WORKDIR /app
COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm prisma:generate
RUN pnpm build
EXPOSE 3005
CMD ["node", "dist/main"]
```

**Changes**:
1. Line 2: `RUN apk add --no-cache openssl` → `RUN apk add --no-cache openssl netcat-openbsd`
2. After line 7 (COPY . .), add 2 new lines:
   ```dockerfile
   # Copy entrypoint script from root
   COPY ../entrypoint.sh /usr/local/bin/entrypoint.sh
   RUN chmod +x /usr/local/bin/entrypoint.sh
   ```
3. Line 11: Replace `CMD ["node", "dist/main"]` with:
   ```dockerfile
   ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
   CMD ["node", "dist/main"]
   ```

**Result** (26 lines):
```dockerfile
FROM node:20-alpine

RUN apk add --no-cache openssl netcat-openbsd

RUN npm install -g pnpm

WORKDIR /app

COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile

COPY . .

# Copy entrypoint script from root
COPY ../entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Prisma generation and build happen in entrypoint
# RUN pnpm prisma:generate
RUN pnpm build

EXPOSE 3005

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["node", "dist/main"]
```

---

## 8. facebook/Dockerfile

**Current** (11 lines):
```dockerfile
FROM node:20-alpine
RUN apk add --no-cache openssl
RUN npm install -g pnpm
WORKDIR /app
COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm prisma:generate
RUN pnpm build
EXPOSE 3006
CMD ["node", "dist/main"]
```

**Changes**:
1. Line 2: `RUN apk add --no-cache openssl` → `RUN apk add --no-cache openssl netcat-openbsd`
2. After line 7 (COPY . .), add 2 new lines:
   ```dockerfile
   # Copy entrypoint script from root
   COPY ../entrypoint.sh /usr/local/bin/entrypoint.sh
   RUN chmod +x /usr/local/bin/entrypoint.sh
   ```
3. Line 11: Replace `CMD ["node", "dist/main"]` with:
   ```dockerfile
   ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
   CMD ["node", "dist/main"]
   ```

**Result** (26 lines):
```dockerfile
FROM node:20-alpine

RUN apk add --no-cache openssl netcat-openbsd

RUN npm install -g pnpm

WORKDIR /app

COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile

COPY . .

# Copy entrypoint script from root
COPY ../entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Prisma generation and build happen in entrypoint
# RUN pnpm prisma:generate
RUN pnpm build

EXPOSE 3006

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["node", "dist/main"]
```

---

## 9. scrapping/Dockerfile - FULL REWRITE ⭐

**Current** (32 lines):
```dockerfile
FROM node:20

WORKDIR /app

# Install dependencies for Chromium
RUN apt-get update && apt-get install -y \
  chromium \
  fonts-noto-cjk \
  ca-certificates \
  --no-install-recommends \
  && rm -rf /var/lib/apt/lists/*

# Copy only package files
COPY package.json ./

# Install pnpm and dependencies
RUN npm install -g pnpm@10.18.0 && \
  PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true pnpm install

# Copy the rest of the application
COPY . .

# Build the application
RUN pnpm run build

# Set Puppeteer to use system Chromium
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true

EXPOSE 3008

CMD ["pnpm", "start"]
```

**Action**: Delete entire file and replace with new version

**New** (70 lines):
```dockerfile
# ═══════════════════════════════════════════════════════════════════════════
# Build Stage
# ═══════════════════════════════════════════════════════════════════════════
FROM node:20-alpine AS builder

WORKDIR /app

# Install pnpm
RUN npm install -g pnpm

# Copy package files
COPY package.json pnpm-lock.yaml* ./

# Install all dependencies (including dev)
RUN pnpm install --frozen-lockfile

# Copy source and prisma schema
COPY prisma ./prisma
COPY src ./src
COPY tsconfig.json nest-cli.json .*.config.* ./

# Generate Prisma client and build
RUN pnpm prisma:generate
RUN pnpm run build

# ═══════════════════════════════════════════════════════════════════════════
# Runtime Stage (Alpine with Chromium)
# ═══════════════════════════════════════════════════════════════════════════
FROM node:20-alpine

# Install Chromium, fonts, and dependencies from Alpine repos
# Alpine chromium is significantly smaller than Debian version
RUN apk add --no-cache \
  chromium \
  chromium-swiftshader \
  fonts-noto-cjk \
  ca-certificates \
  netcat-openbsd \
  && apk cache purge

WORKDIR /app

# Install pnpm
RUN npm install -g pnpm

# Copy package files and install production dependencies only
COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --prod --frozen-lockfile

# Copy prisma schema
COPY prisma ./prisma

# Copy built application from builder stage
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules/.pnpm /app/node_modules/.pnpm

# Copy entrypoint script from root context
COPY ../entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Set Puppeteer to use system Chromium
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
ENV PUPPETEER_ARGS=--no-sandbox,--disable-setuid-sandbox,--disable-dev-shm-usage

EXPOSE 3008

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["pnpm", "start"]
```

---

## Quick Edits by Service

### Standard Services (8 copies)
For: gateway, identity, whatsapp, slack, notion, instagram, tiktok, facebook

```diff
- RUN apk add --no-cache openssl
+ RUN apk add --no-cache openssl netcat-openbsd

+ # Copy entrypoint script from root
+ COPY ../entrypoint.sh /usr/local/bin/entrypoint.sh
+ RUN chmod +x /usr/local/bin/entrypoint.sh
+
- CMD ["node", "dist/main"]
+ ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
+ CMD ["node", "dist/main"]
```

### Multi-stage (identity)
Add `netcat-openbsd` to the second stage RUN apk line, then add entrypoint copy and ENTRYPOINT before CMD

### Scrapping (Full rewrite)
Replace entire file with new multi-stage Alpine version

---

## Testing Dockerfile Changes

After each edit, test syntax:

```bash
# Test individual Dockerfile syntax
docker build --dry-run -f gateway/Dockerfile .

# Or just check for parse errors
docker run --rm -i hadolint/hadolint < gateway/Dockerfile
```

For all at once:
```bash
for file in gateway identity whatsapp slack notion instagram tiktok facebook scrapping; do
  echo "Testing $file/Dockerfile..."
  docker build --dry-run -f $file/Dockerfile . && echo "✓" || echo "✗"
done
```

---

## Line-by-Line Edit Example

### For gateway/Dockerfile:

Using VS Code or vim:

**Step 1**: Open gateway/Dockerfile  
**Step 2**: Go to Line 3, column 30 (end of "openssl")  
**Step 3**: Add ` netcat-openbsd`  
**Step 4**: Go to Line 12 (after `COPY . .`)  
**Step 5**: Press Enter to create new line  
**Step 6**: Add:
```
# Copy entrypoint script from root
COPY ../entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
```
**Step 7**: Go to Line 18 (CMD line)  
**Step 8**: Delete `CMD ["node", "dist/main"]`  
**Step 9**: Add:
```
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["node", "dist/main"]
```
**Step 10**: Save file  
**Step 11**: Verify: 26 lines total

---

## Verification Checklist Per File

After editing each Dockerfile:

- [ ] File saved with Unix line endings (LF)
- [ ] No trailing whitespace
- [ ] Proper indentation (no tabs, only spaces)
- [ ] EXPOSE port is correct for service
- [ ] ENTRYPOINT + CMD on separate lines
- [ ] entrypoint.sh path is correct: `/usr/local/bin/entrypoint.sh`
- [ ] `netcat-openbsd` is in apk install
- [ ] Total lines match expected
- [ ] No duplicate commands

---

**Total Dockerfiles to edit**: 9  
**Average lines changed per file**: 7-12 lines  
**Total lines to add across all**: ~60 lines  
**Estimated time**: 30-45 minutes  
**Difficulty**: 2/10 (straightforward find-and-replace)
