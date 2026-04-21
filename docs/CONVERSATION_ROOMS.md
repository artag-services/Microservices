# Conversation Rooms Implementation Guide

## 📋 Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Data Model](#data-model)
4. [Communication Flow](#communication-flow)
5. [Implementation Guide](#implementation-guide)
6. [RabbitMQ Contracts](#rabbitmq-contracts)
7. [API Endpoints](#api-endpoints)
8. [Topic Detection](#topic-detection)
9. [Rate Limiting](#rate-limiting)
10. [Future Services](#future-services)

---

## Overview

**Conversation Rooms** is a scalable, distributed system for grouping user messages by conversation across multiple channels (WhatsApp, Instagram, Slack, TikTok, Facebook).

### Key Features

- ✅ Automatic conversation creation on first message
- ✅ Topic detection (Billing, Support, Product, Order, General)
- ✅ Per-conversation AI enable/disable (not global user setting)
- ✅ Multi-agent support (assign humans to conversations)
- ✅ Rate limiting (20 AI calls/day per user per service)
- ✅ Distributed data ownership (each service owns its conversations)
- ✅ Cross-channel discovery (query all user's channels via Identity)

### Architecture Philosophy

```
Each service = sovereign kingdom
├─ Owns its conversations
├─ Owns its messages
├─ Owns its AI responses
├─ Listens to RabbitMQ events
└─ Publishes events when things change

Gateway = Coordinator
├─ Entry point for webhooks
├─ Publishes conversation lifecycle events
├─ Exposes REST endpoints (read-only queries)
└─ Tracks rate limits per service

Identity Service = User Linker
├─ Links users across channels
├─ Resolves channelUserId → userId
└─ Enables cross-channel discovery
```

---

## Architecture

### High-Level Diagram

```
┌────────────────────────────────────────────────────────────────┐
│                    META WEBHOOKS / EVENTS                    │
└───────────────────────────┬────────────────────────────────────┘
                            │
                            ↓
┌────────────────────────────────────────────────────────────────┐
│                    GATEWAY (port 3000)                         │
├────────────────────────────────────────────────────────────────┤
│ • POST /webhooks/whatsapp → parse → channels.conversation.in  │
│ • GET  /conversations → list all                              │
│ • PATCH /conversations/:id → toggle AI, assign agent          │
│ • Track rate limits: N8NRateLimit                             │
└────────────────────────────┬────────────────────────────────────┘
                │            │            │
                ↓            ↓            ↓
    ┌─────────────────┐ ┌──────────┐ ┌──────────┐
    │  WHATSAPP SVC   │ │IDENTITY  │ │INSTAGRAM │
    │   (port 3001)   │ │(port 3010)
│ (port 3004)   │
    ├─────────────────┤ ├──────────┤ ├──────────┤
    │ Listens to:     │ │ Listens: │ │ Listens: │
    │ • channels.     │ │ • identity│ │ • channels
│ •channels. │
    │   conversation. │ │   .resolve│ │   insta  │
    │   incoming      │ │ • identity│ │   gram.  │
    │                 │ │   .request│ │   events │
    │ Persists:       │ │          │ │          │
    │ • whatsapp_db:  │ │ Persists:│ │ Persists:│
    │   Conversation  │ │ • User   │ │ • Conver-│
    │   ConvMessage   │ │ • UserID │ │   sation │
    │   AIResponse    │ │ • Contact│ │ • ConvMsg│
    │                 │ │          │ │          │
    │ Detects topic   │ │ Resolves:│ │ Same as  │
    │ via keywords    │ │ senderId │ │ WhatsApp │
    │                 │ │ → userId │ │          │
    │ Tracks AI calls │ │          │ │ Tracks   │
    │ per service     │ │Publishes:│ │AI calls  │
    │                 │ │ • identity│ │per svcs  │
    │ Publishes:      │ │   .response│ │          │
    │ • channels.     │ └──────────┘ │ Publishes│
    │   whatsapp.msg  │               │ • channels
│
    │ • channels.     │               │   .insta │
    │   conversation. │               │   gram.  │
    │   created       │               │   msg    │
    └─────────────────┘               └──────────┘
```

### Data Ownership

```
GATEWAY DB (gateway_db)
├─ Message (existing - outgoing messages)
├─ Conversation* (NEW - conversation metadata)
│  └─ {id, channel, channelUserId, topic, aiEnabled, agentAssigned, status}
└─ N8NRateLimit* (NEW - track 20 calls/day per user per service)
   └─ {id, userId, service, date, callCount}

WHATSAPP DB (whatsapp_db)
├─ WaMessage (existing - individual WhatsApp messages)
├─ Conversation* (NEW - conversation aggregate owned by WhatsApp)
│  └─ {id, userId, channelUserId, channel, topic, aiEnabled, agentAssigned, status, ...}
├─ ConversationMessage* (NEW - individual messages in conversation)
│  └─ {conversationId, sender, content, mediaUrl, aiGenerated, externalId, createdAt}
└─ AIResponse (existing, possibly renamed to ConversationAIResponse)
   └─ {conversationId, userMessage, aiResponse, model, confidence, ...}

INSTAGRAM DB (instagram_db) - Similar structure to WhatsApp
├─ IgMessage (existing)
├─ Conversation* (NEW)
├─ ConversationMessage* (NEW)
└─ ConversationAIResponse* (NEW)

IDENTITY DB (identity_db)
├─ User (existing)
├─ UserIdentity (existing - links channelUserId to userId)
├─ UserContact (existing)
└─ No new tables needed - queries existing data
```

---

## Data Model

### 1. Gateway DB: Conversation (Metadata Only)

```prisma
model Conversation {
  id              String   @id @default(uuid())
  
  // Channel & User identification
  channel         String   // "whatsapp", "instagram", "slack", etc
  channelUserId   String   // senderId from Meta (or equivalent)
  userId          String?  // FK → Identity.User (NULL until resolved)
  
  // Topic & Classification
  topic           String?  // "Billing", "Support", "Product", "Order", "General"
  detectionMethod String   // "KEYWORDS", "AI", "MANUAL"
  keywords        String[] // e.g., ["factura", "pago"] for detection
  
  // Control
  aiEnabled       Boolean  @default(true)
  agentAssigned   String?  // username or agent ID
  status          ConvStatus @default(ACTIVE)
  
  // Metadata
  messageCount    Int      @default(0)
  aiCallCount     Int      @default(0)
  createdAt       DateTime @default(now())
  updatedAt       DateTime @updatedAt
  lastMessageAt   DateTime?
  archivedAt      DateTime?
  
  @@unique([channelUserId, channel, status])
  @@index([userId])
  @@index([channel])
  @@index([status])
  @@index([lastMessageAt])
}

enum ConvStatus {
  ACTIVE
  WAITING_AGENT
  WITH_AGENT
  ARCHIVED
  CLOSED
}
```

### 2. Gateway DB: N8NRateLimit

```prisma
model N8NRateLimit {
  id              String   @id @default(uuid())
  userId          String   // From Identity.User
  service         String   // "whatsapp", "instagram", etc
  date            DateTime @default(now()) // Daily bucket
  callCount       Int      @default(0)
  maxCalls        Int      @default(20)
  
  @@unique([userId, service, date])
  @@index([userId])
  @@index([date])
}
```

**Logic:**
- Before each AI call: Check if `callCount < maxCalls` for (userId, service, today)
- If yes: Increment callCount, proceed
- If no: Return error "Rate limit exceeded for today"

### 3. WhatsApp DB: Conversation (Service-Owned)

```prisma
model Conversation {
  id              String   @id @default(uuid())
  
  // User & Channel
  userId          String?  // May be null initially, updated async from Identity
  channelUserId   String   // WhatsApp senderId
  channel         String   @default("whatsapp")
  
  // Topic & Detection
  topic           String?
  detectionMethod String   // "KEYWORDS", "AI", "MANUAL"
  keywords        String[]
  
  // Control
  aiEnabled       Boolean  @default(true)
  agentAssigned   String?
  status          ConvStatus @default(ACTIVE)
  
  // Counters
  messageCount    Int      @default(0)
  aiMessageCount  Int      @default(0)
  
  // Timestamps
  createdAt       DateTime @default(now())
  updatedAt       DateTime @updatedAt
  lastMessageAt   DateTime?
  archivedAt      DateTime?
  
  // Relations
  messages        ConversationMessage[]
  aiResponses     ConversationAIResponse[]
  
  @@unique([channelUserId, channel, status])
  @@index([userId])
  @@index([status, lastMessageAt])
}

enum ConvStatus {
  ACTIVE
  WAITING_AGENT
  WITH_AGENT
  ARCHIVED
  CLOSED
}
```

### 4. WhatsApp DB: ConversationMessage

```prisma
model ConversationMessage {
  id              String   @id @default(uuid())
  conversationId  String
  
  // Message content
  sender          MessageSender // USER | BOT | AGENT | SYSTEM
  content         String   @db.Text
  mediaUrl        String?
  
  // Metadata
  aiGenerated     Boolean  @default(false)
  externalId      String?  // WhatsApp message ID
  metadata        Json?
  
  createdAt       DateTime @default(now())
  
  conversation    Conversation @relation(fields: [conversationId], references: [id], onDelete: Cascade)
  
  @@index([conversationId, createdAt])
  @@index([sender])
}

enum MessageSender {
  USER
  BOT
  AGENT
  SYSTEM
}
```

### 5. WhatsApp DB: ConversationAIResponse

```prisma
model ConversationAIResponse {
  id              String   @id @default(uuid())
  conversationId  String
  
  // Messages
  userMessage     String   @db.Text
  aiResponse      String   @db.Text
  
  // Model info
  model           String?  // "gpt-4", "claude", etc
  confidence      Float?
  processingTime  Int?    // milliseconds
  
  // Status
  status          AIResponseStatus @default(PENDING)
  chunks          Int      @default(0)
  failureReason   String?
  
  createdAt       DateTime @default(now())
  updatedAt       DateTime @updatedAt
  
  conversation    Conversation @relation(fields: [conversationId], references: [id], onDelete: Cascade)
  
  @@index([conversationId, createdAt])
  @@index([status])
}

enum AIResponseStatus {
  PENDING
  SENT
  PARTIAL
  FAILED
}
```

---

## Communication Flow

### Scenario: User sends first message via WhatsApp

```
┌─ STEP 1: Meta sends webhook to Gateway
│
├─ Gateway WhatsappWebhookController receives POST /webhooks/whatsapp
│  └─ Parses: {from: "+573205711428", body: "Tengo problemas con mi factura"}
│
├─ STEP 2: Gateway publishes events (parallelized)
│  ├─ channels.whatsapp.events.message
│  │  Payload: {senderId, senderName, messageText, messageId, timestamp}
│  │
│  └─ channels.conversation.incoming (NEW)
│     Payload: {
│       channel: "whatsapp",
│       channelUserId: "+573205711428",
│       messageText: "Tengo problemas con mi factura",
│       messageId: "wamid_...",
│       timestamp: "2026-04-21T10:30:00Z"
│     }
│
├─ STEP 3: WhatsApp Service receives channels.conversation.incoming
│  ├─ Detects topic: "factura" → topic = "Billing"
│  ├─ Generates conversationId = "conv_abc123"
│  ├─ Creates Conversation in whatsapp_db
│  │  INSERT {
│  │    id: "conv_abc123",
│  │    userId: null,
│  │    channelUserId: "+573205711428",
│  │    channel: "whatsapp",
│  │    topic: "Billing",
│  │    detectionMethod: "KEYWORDS",
│  │    keywords: ["factura"],
│  │    aiEnabled: true,
│  │    status: "ACTIVE"
│  │  }
│  ├─ Stores in memory cache:
│  │  cache["+573205711428"] = {
│  │    id: "conv_abc123",
│  │    channelUserId: "+573205711428",
│  │    topic: "Billing",
│  │    aiEnabled: true,
│  │    userId: null
│  │  }
│  └─ Publishes channels.conversation.created
│     Payload: {
│       conversationId: "conv_abc123",
│       channel: "whatsapp",
│       channelUserId: "+573205711428",
│       topic: "Billing",
│       aiEnabled: true,
│       createdAt: "2026-04-21T10:30:00Z"
│     }
│
├─ STEP 4: WhatsApp Service receives channels.whatsapp.events.message
│  ├─ Calls Gateway: GET /identity/resolve?channel=whatsapp&channelUserId=+573205711428
│  ├─ Identity responds: {userId: "user_xyz", name: "Juan"}
│  ├─ Updates cache with userId
│  ├─ Updates Conversation.userId in DB
│  └─ Stores ConversationMessage:
│     INSERT {
│       conversationId: "conv_abc123",
│       sender: "USER",
│       content: "Tengo problemas con mi factura",
│       aiGenerated: false,
│       externalId: "wamid_..."
│     }
│
├─ STEP 5: WhatsApp Service receives channels.conversation.created
│  └─ Validates conversation was created (double-check)
│
├─ STEP 6: WhatsApp Service processes AI (if conversation.aiEnabled = true)
│  ├─ Checks N8NRateLimit for (userId: "user_xyz", service: "whatsapp", today)
│  ├─ If callCount < 20:
│  │  ├─ Calls N8N webhook with message
│  │  ├─ Receives: aiResponse = "Te ayudaremos con la factura..."
│  │  ├─ Creates ConversationAIResponse
│  │  ├─ Creates ConversationMessage with sender: "BOT"
│  │  ├─ Updates N8NRateLimit.callCount++
│  │  └─ Sends response to Meta API (chunks)
│  └─ Else:
│     └─ Logs: "⚠️ Rate limit reached for user user_xyz today"
│
└─ DONE: User receives AI response via WhatsApp
```

---

## Implementation Guide

### Phase 1: Database Schema

#### 1.1 Gateway Service

File: `gateway/prisma/schema.prisma`

Add:
```prisma
model Conversation {
  // (see Data Model section above)
}

model N8NRateLimit {
  // (see Data Model section above)
}

enum ConvStatus {
  ACTIVE
  WAITING_AGENT
  WITH_AGENT
  ARCHIVED
  CLOSED
}
```

Run migration:
```bash
cd gateway
npm run prisma:migrate -- --name add_conversation_tables
```

#### 1.2 WhatsApp Service

File: `whatsapp/prisma/schema.prisma`

Add:
```prisma
model Conversation {
  // (see Data Model section above)
}

model ConversationMessage {
  // (see Data Model section above)
}

model ConversationAIResponse {
  // (see Data Model section above)
}

enum ConvStatus {
  ACTIVE
  WAITING_AGENT
  WITH_AGENT
  ARCHIVED
  CLOSED
}

enum MessageSender {
  USER
  BOT
  AGENT
  SYSTEM
}

enum AIResponseStatus {
  PENDING
  SENT
  PARTIAL
  FAILED
}
```

Run migration:
```bash
cd whatsapp
npm run prisma:migrate -- --name add_conversation_tables
```

---

### Phase 2: RabbitMQ Routing Keys

File: `gateway/src/rabbitmq/constants/queues.ts`

Add:
```typescript
export const ROUTING_KEYS = {
  // Existing
  WHATSAPP_SEND: 'channels.whatsapp.send',
  WHATSAPP_MESSAGE_RECEIVED: 'channels.whatsapp.events.message',
  WHATSAPP_AI_RESPONSE: 'channels.whatsapp.ai-response',
  
  // NEW - Conversation lifecycle
  CONVERSATION_INCOMING: 'channels.conversation.incoming',
  CONVERSATION_CREATED: 'channels.conversation.created',
  CONVERSATION_UPDATED: 'channels.conversation.updated',
  CONVERSATION_AI_TOGGLE: 'channels.conversation.ai-toggle',
  CONVERSATION_AGENT_ASSIGN: 'channels.conversation.agent-assign',
};

export const QUEUES = {
  // Existing
  WHATSAPP_SEND: 'whatsapp.send',
  WHATSAPP_EVENTS_MESSAGE: 'whatsapp.events.message',
  WHATSAPP_AI_RESPONSE: 'whatsapp.ai-response',
  
  // NEW
  CONVERSATION_INCOMING: 'conversation.incoming',
  CONVERSATION_CREATED: 'conversation.created',
  CONVERSATION_UPDATED: 'conversation.updated',
  CONVERSATION_AI_TOGGLE: 'conversation.ai-toggle',
  CONVERSATION_AGENT_ASSIGN: 'conversation.agent-assign',
};
```

---

### Phase 3: Gateway Webhook Controller

File: `gateway/src/webhooks/whatsapp.webhook.controller.ts`

Modify to publish both events:

```typescript
@Post('/whatsapp')
async handleWhatsappWebhook(@Body() payload: WhatsappWebhookPayload) {
  const {from, body, messageId} = parseWhatsappPayload(payload);
  
  // Existing: publish message received
  await this.rabbitMQ.publish(
    'channels',
    'channels.whatsapp.events.message',
    {senderId: from, messageText: body, messageId, timestamp: new Date()}
  );
  
  // NEW: publish conversation incoming
  await this.rabbitMQ.publish(
    'channels',
    'channels.conversation.incoming',
    {
      channel: 'whatsapp',
      channelUserId: from,
      messageText: body,
      messageId,
      timestamp: new Date()
    }
  );
  
  return {status: 'ok'};
}
```

---

### Phase 4: WhatsApp Conversation Listener

File: `whatsapp/src/conversations/conversation.listener.ts` (NEW)

```typescript
import {Injectable, Logger} from '@nestjs/common';
import {RabbitSubscribe} from '@golevelup/nestjs-rabbitmq';
import {PrismaService} from '../prisma/prisma.service';
import {TopicDetectionService} from './topic-detection.service';
import {ConversationCacheService} from './conversation-cache.service';

interface ConversationIncomingPayload {
  channel: string;
  channelUserId: string;
  messageText: string;
  messageId: string;
  timestamp: Date;
}

@Injectable()
export class ConversationListener {
  private readonly logger = new Logger(ConversationListener.name);
  
  constructor(
    private prisma: PrismaService,
    private topicDetection: TopicDetectionService,
    private cache: ConversationCacheService,
    private rabbitMQ: AmqpConnection, // Inject RabbitMQ
  ) {}
  
  @RabbitSubscribe({
    exchange: 'channels',
    routingKey: 'channels.conversation.incoming',
    queue: 'whatsapp.conversation.incoming',
  })
  async handleConversationIncoming(payload: ConversationIncomingPayload) {
    this.logger.log(`Processing conversation incoming: ${payload.channelUserId}`);
    
    try {
      const {channel, channelUserId, messageText, messageId} = payload;
      
      // Only process WhatsApp messages
      if (channel !== 'whatsapp') return;
      
      // 1. Detect topic
      const topic = this.topicDetection.detectTopic(messageText);
      const keywords = this.topicDetection.extractKeywords(messageText, topic);
      
      // 2. Create conversation in database
      const conversation = await this.prisma.conversation.create({
        data: {
          userId: null, // Will be updated when Identity resolves
          channelUserId,
          channel: 'whatsapp',
          topic,
          detectionMethod: 'KEYWORDS',
          keywords,
          aiEnabled: true,
          status: 'ACTIVE',
          messageCount: 0,
          aiMessageCount: 0,
        },
      });
      
      // 3. Update cache
      this.cache.set(channelUserId, {
        id: conversation.id,
        channelUserId,
        topic,
        aiEnabled: true,
        userId: null,
      });
      
      // 4. Publish conversation created event
      await this.rabbitMQ.publish(
        'channels',
        'channels.conversation.created',
        {
          conversationId: conversation.id,
          channel: 'whatsapp',
          channelUserId,
          topic,
          aiEnabled: true,
          createdAt: new Date(),
        }
      );
      
      this.logger.log(
        `✅ Conversation created: ${conversation.id} | Topic: ${topic}`
      );
    } catch (error) {
      this.logger.error('Error handling conversation incoming:', error);
      throw error;
    }
  }
}
```

---

### Phase 5: Topic Detection Service

File: `whatsapp/src/conversations/topic-detection.service.ts` (NEW)

```typescript
import {Injectable} from '@nestjs/common';

@Injectable()
export class TopicDetectionService {
  private readonly keywordMap = {
    billing: [
      'factura', 'invoice', 'pago', 'payment', 'precio', 'price',
      'costo', 'cost', 'dinero', 'money', 'tarjeta', 'card',
      'transacción', 'transaction', 'cobro', 'charge'
    ],
    support: [
      'error', 'problema', 'problem', 'bug', 'no funciona', 'not working',
      'ayuda', 'help', 'soporte', 'support', 'falla', 'broken',
      'crash', 'issue', 'no me', 'cannot', 'no puedo'
    ],
    product: [
      'producto', 'product', 'catálogo', 'catalog', 'item',
      'feature', 'característica', 'descripción', 'description',
      'disponible', 'available', 'modelo', 'model'
    ],
    order: [
      'pedido', 'order', 'compra', 'purchase', 'envío', 'shipping',
      'delivery', 'entrega', 'seguimiento', 'tracking', 'recibir', 'receive'
    ],
  };
  
  detectTopic(text: string): string {
    const lowerText = text.toLowerCase();
    
    for (const [topic, keywords] of Object.entries(this.keywordMap)) {
      if (keywords.some(kw => lowerText.includes(kw))) {
        return topic.charAt(0).toUpperCase() + topic.slice(1);
      }
    }
    
    return 'General';
  }
  
  extractKeywords(text: string, topic: string): string[] {
    const lowerText = text.toLowerCase();
    const keywords = this.keywordMap[topic.toLowerCase()] || [];
    
    return keywords.filter(kw => lowerText.includes(kw));
  }
}
```

---

### Phase 6: Conversation Cache Service

File: `whatsapp/src/conversations/conversation-cache.service.ts` (NEW)

```typescript
import {Injectable} from '@nestjs/common';

interface CachedConversation {
  id: string;
  channelUserId: string;
  topic: string;
  aiEnabled: boolean;
  userId: string | null;
}

@Injectable()
export class ConversationCacheService {
  private cache = new Map<string, CachedConversation>();
  
  set(channelUserId: string, data: CachedConversation): void {
    this.cache.set(channelUserId, data);
  }
  
  get(channelUserId: string): CachedConversation | undefined {
    return this.cache.get(channelUserId);
  }
  
  update(channelUserId: string, updates: Partial<CachedConversation>): void {
    const existing = this.cache.get(channelUserId);
    if (existing) {
      this.cache.set(channelUserId, {...existing, ...updates});
    }
  }
  
  delete(channelUserId: string): void {
    this.cache.delete(channelUserId);
  }
  
  getAll(): CachedConversation[] {
    return Array.from(this.cache.values());
  }
  
  clear(): void {
    this.cache.clear();
  }
}
```

---

### Phase 7: Update AI Response Handler

File: `whatsapp/src/whatsapp/services/ai-response.service.ts` (MODIFY)

```typescript
// Existing code... ADD the following:

async processAIResponse(
  conversationId: string,
  messageText: string,
  userId: string
): Promise<string> {
  // 1. Check if AI is enabled for this conversation
  const conversation = await this.prisma.conversation.findUnique({
    where: {id: conversationId},
  });
  
  if (!conversation || !conversation.aiEnabled) {
    this.logger.log(
      `AI disabled for conversation ${conversationId} or agent assigned`
    );
    return null; // Return early, no AI response
  }
  
  // 2. Check rate limit for this user/service
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  
  const rateLimit = await this.prisma.n8NRateLimit.findUnique({
    where: {
      userId_service_date: {
        userId,
        service: 'whatsapp',
        date: today,
      },
    },
  });
  
  if (rateLimit && rateLimit.callCount >= 20) {
    this.logger.warn(
      `Rate limit exceeded for user ${userId} (WhatsApp): ${rateLimit.callCount}/20`
    );
    return null; // No AI response
  }
  
  // 3. Call N8N (existing logic)
  const aiResponse = await this.callN8N(messageText);
  
  // 4. Increment rate limit counter
  if (rateLimit) {
    await this.prisma.n8NRateLimit.update({
      where: {id: rateLimit.id},
      data: {callCount: rateLimit.callCount + 1},
    });
  } else {
    await this.prisma.n8NRateLimit.create({
      data: {userId, service: 'whatsapp', date: today, callCount: 1},
    });
  }
  
  // 5. Save AI response to ConversationAIResponse
  const convAIResponse = await this.prisma.conversationAIResponse.create({
    data: {
      conversationId,
      userMessage: messageText,
      aiResponse: aiResponse.text,
      model: aiResponse.model,
      confidence: aiResponse.confidence,
      status: 'SENT',
    },
  });
  
  // 6. Create ConversationMessage for bot response
  await this.prisma.conversationMessage.create({
    data: {
      conversationId,
      sender: 'BOT',
      content: aiResponse.text,
      aiGenerated: true,
    },
  });
  
  // 7. Update conversation counters
  await this.prisma.conversation.update({
    where: {id: conversationId},
    data: {
      aiMessageCount: {increment: 1},
      messageCount: {increment: 1},
    },
  });
  
  return aiResponse.text;
}
```

---

### Phase 8: Gateway Conversation Endpoints

File: `gateway/src/v1/conversations/conversations.controller.ts` (NEW)

```typescript
import {Controller, Get, Post, Patch, Body, Param, Query, UseGuards} from '@nestjs/common';
import {ConversationsService} from './conversations.service';
import {JwtAuthGuard} from 'src/auth/guards/jwt-auth.guard';
import {CurrentUser} from 'src/auth/decorators/current-user.decorator';

@Controller('api/v1/conversations')
@UseGuards(JwtAuthGuard)
export class ConversationsController {
  constructor(private conversationsService: ConversationsService) {}
  
  /**
   * GET /conversations
   * List all conversations for authenticated user
   */
  @Get()
  async listConversations(
    @CurrentUser('id') userId: string,
    @Query('channel') channel?: string,
    @Query('status') status?: string,
    @Query('limit') limit = '50',
    @Query('offset') offset = '0',
  ) {
    return this.conversationsService.listByUserId(userId, {
      channel,
      status,
      limit: parseInt(limit),
      offset: parseInt(offset),
    });
  }
  
  /**
   * GET /conversations/:id
   * Get conversation details
   */
  @Get(':conversationId')
  async getConversation(
    @CurrentUser('id') userId: string,
    @Param('conversationId') conversationId: string,
  ) {
    return this.conversationsService.getById(conversationId, userId);
  }
  
  /**
   * GET /conversations/:id/messages
   * Get messages in conversation (queries appropriate service DB)
   */
  @Get(':conversationId/messages')
  async getMessages(
    @CurrentUser('id') userId: string,
    @Param('conversationId') conversationId: string,
    @Query('limit') limit = '50',
    @Query('offset') offset = '0',
  ) {
    return this.conversationsService.getMessages(
      conversationId,
      userId,
      {limit: parseInt(limit), offset: parseInt(offset)}
    );
  }
  
  /**
   * PATCH /conversations/:id
   * Update conversation: aiEnabled, agentAssigned, status
   */
  @Patch(':conversationId')
  async updateConversation(
    @CurrentUser('id') userId: string,
    @Param('conversationId') conversationId: string,
    @Body() updates: {aiEnabled?: boolean; agentAssigned?: string; status?: string},
  ) {
    return this.conversationsService.update(conversationId, userId, updates);
  }
  
  /**
   * POST /conversations
   * Manually create conversation
   */
  @Post()
  async createConversation(
    @CurrentUser('id') userId: string,
    @Body() data: {channel: string; topic?: string; aiEnabled?: boolean},
  ) {
    return this.conversationsService.create(userId, data);
  }
}
```

File: `gateway/src/v1/conversations/conversations.service.ts` (NEW)

```typescript
import {Injectable, NotFoundException, ForbiddenException} from '@nestjs/common';
import {PrismaService} from 'src/prisma/prisma.service';
import {AmqpConnection} from '@golevelup/nestjs-rabbitmq';

@Injectable()
export class ConversationsService {
  constructor(
    private prisma: PrismaService,
    private rabbitMQ: AmqpConnection,
  ) {}
  
  async listByUserId(
    userId: string,
    filters: {channel?: string; status?: string; limit: number; offset: number},
  ) {
    const where: any = {userId};
    if (filters.channel) where.channel = filters.channel;
    if (filters.status) where.status = filters.status;
    
    const conversations = await this.prisma.conversation.findMany({
      where,
      take: filters.limit,
      skip: filters.offset,
      orderBy: {lastMessageAt: 'desc'},
    });
    
    return conversations;
  }
  
  async getById(conversationId: string, userId: string) {
    const conversation = await this.prisma.conversation.findUnique({
      where: {id: conversationId},
    });
    
    if (!conversation) {
      throw new NotFoundException('Conversation not found');
    }
    
    if (conversation.userId !== userId) {
      throw new ForbiddenException('Access denied');
    }
    
    return conversation;
  }
  
  async getMessages(
    conversationId: string,
    userId: string,
    pagination: {limit: number; offset: number},
  ) {
    // Verify conversation ownership
    const conversation = await this.getById(conversationId, userId);
    
    // Query appropriate service DB based on channel
    // This would call the service-specific endpoint or database
    // For now, return placeholder
    return {
      conversationId,
      channel: conversation.channel,
      messages: [], // TODO: Query service DB
    };
  }
  
  async update(
    conversationId: string,
    userId: string,
    updates: {aiEnabled?: boolean; agentAssigned?: string; status?: string},
  ) {
    // Verify ownership
    await this.getById(conversationId, userId);
    
    const updated = await this.prisma.conversation.update({
      where: {id: conversationId},
      data: {
        aiEnabled: updates.aiEnabled,
        agentAssigned: updates.agentAssigned,
        status: updates.status,
        updatedAt: new Date(),
      },
    });
    
    // Publish event for the service to react
    if (updates.aiEnabled !== undefined) {
      await this.rabbitMQ.publish(
        'channels',
        'channels.conversation.ai-toggle',
        {conversationId, aiEnabled: updates.aiEnabled}
      );
    }
    
    if (updates.agentAssigned !== undefined) {
      await this.rabbitMQ.publish(
        'channels',
        'channels.conversation.agent-assign',
        {conversationId, agentAssigned: updates.agentAssigned}
      );
    }
    
    return updated;
  }
  
  async create(
    userId: string,
    data: {channel: string; topic?: string; aiEnabled?: boolean},
  ) {
    const conversation = await this.prisma.conversation.create({
      data: {
        userId,
        channel: data.channel,
        topic: data.topic || 'General',
        detectionMethod: 'MANUAL',
        aiEnabled: data.aiEnabled ?? true,
        status: 'ACTIVE',
      },
    });
    
    return {
      conversationId: conversation.id,
      created: true,
    };
  }
}
```

---

## RabbitMQ Contracts

### 1. `channels.conversation.incoming`

**Published by:** Gateway (WhatsappWebhookController)

**Consumed by:** WhatsApp Service (ConversationListener)

**Payload:**
```json
{
  "channel": "whatsapp",
  "channelUserId": "+573205711428",
  "messageText": "Tengo problemas con mi factura",
  "messageId": "wamid_ABC123",
  "timestamp": "2026-04-21T10:30:00Z"
}
```

---

### 2. `channels.conversation.created`

**Published by:** WhatsApp Service (ConversationListener)

**Consumed by:** WhatsApp Service (ConversationCreatedListener) for validation

**Payload:**
```json
{
  "conversationId": "conv_abc123",
  "channel": "whatsapp",
  "channelUserId": "+573205711428",
  "topic": "Billing",
  "aiEnabled": true,
  "createdAt": "2026-04-21T10:30:00Z"
}
```

---

### 3. `channels.conversation.ai-toggle`

**Published by:** Gateway (ConversationsController - PATCH)

**Consumed by:** WhatsApp Service

**Payload:**
```json
{
  "conversationId": "conv_abc123",
  "aiEnabled": false
}
```

**Action:** Update Conversation.aiEnabled in service DB

---

### 4. `channels.conversation.agent-assign`

**Published by:** Gateway (ConversationsController - PATCH)

**Consumed by:** WhatsApp Service

**Payload:**
```json
{
  "conversationId": "conv_abc123",
  "agentAssigned": "juan@company.com"
}
```

**Action:** Update Conversation.agentAssigned, set aiEnabled=false

---

## API Endpoints

### 1. List All Conversations

```
GET /api/v1/conversations?channel=whatsapp&status=ACTIVE&limit=50&offset=0

Auth: Bearer token

Response:
{
  "data": [
    {
      "id": "conv_abc123",
      "channel": "whatsapp",
      "channelUserId": "+573205711428",
      "userId": "user_xyz",
      "topic": "Billing",
      "aiEnabled": true,
      "agentAssigned": null,
      "status": "ACTIVE",
      "messageCount": 5,
      "aiMessageCount": 2,
      "createdAt": "2026-04-21T10:30:00Z",
      "lastMessageAt": "2026-04-21T11:45:00Z"
    }
  ],
  "total": 1
}
```

---

### 2. Get Conversation Details

```
GET /api/v1/conversations/conv_abc123

Auth: Bearer token

Response:
{
  "id": "conv_abc123",
  "channel": "whatsapp",
  "channelUserId": "+573205711428",
  "userId": "user_xyz",
  "topic": "Billing",
  "aiEnabled": true,
  "agentAssigned": null,
  "status": "ACTIVE",
  "messageCount": 5,
  "aiMessageCount": 2,
  "createdAt": "2026-04-21T10:30:00Z",
  "lastMessageAt": "2026-04-21T11:45:00Z"
}
```

---

### 3. Get Conversation Messages

```
GET /api/v1/conversations/conv_abc123/messages?limit=50&offset=0

Auth: Bearer token

Response:
{
  "conversationId": "conv_abc123",
  "channel": "whatsapp",
  "messages": [
    {
      "id": "msg_1",
      "sender": "USER",
      "content": "Tengo problemas con mi factura",
      "aiGenerated": false,
      "createdAt": "2026-04-21T10:30:00Z"
    },
    {
      "id": "msg_2",
      "sender": "BOT",
      "content": "Te ayudaremos con tu factura...",
      "aiGenerated": true,
      "createdAt": "2026-04-21T10:31:00Z"
    }
  ]
}
```

---

### 4. Update Conversation (AI Toggle / Agent Assign)

```
PATCH /api/v1/conversations/conv_abc123

Auth: Bearer token

Body:
{
  "aiEnabled": false,
  "agentAssigned": "juan@company.com",
  "status": "WITH_AGENT"
}

Response:
{
  "id": "conv_abc123",
  "aiEnabled": false,
  "agentAssigned": "juan@company.com",
  "status": "WITH_AGENT",
  "updatedAt": "2026-04-21T12:00:00Z"
}
```

---

### 5. Manually Create Conversation

```
POST /api/v1/conversations

Auth: Bearer token

Body:
{
  "channel": "whatsapp",
  "topic": "Support",
  "aiEnabled": true
}

Response:
{
  "conversationId": "conv_new123",
  "created": true
}
```

---

### 6. Get All User's Channels (Cross-Channel Discovery)

```
GET /api/v1/identity/users/:userId/all-channels

Auth: Bearer token

Response:
{
  "userId": "user_xyz",
  "channels": [
    {
      "channel": "whatsapp",
      "channelUserId": "+573205711428",
      "conversationCount": 5,
      "activeConversations": 2
    },
    {
      "channel": "instagram",
      "channelUserId": "instagram_user_123",
      "conversationCount": 2,
      "activeConversations": 1
    }
  ]
}
```

---

## Topic Detection

### Method: KEYWORDS (Current Implementation)

**Keywords mapping:**

```typescript
{
  billing: ['factura', 'invoice', 'pago', 'payment', 'precio', 'price', 'costo', 'cost'],
  support: ['error', 'problema', 'problem', 'bug', 'ayuda', 'help', 'soporte', 'support'],
  product: ['producto', 'product', 'catálogo', 'catalog', 'feature', 'característica'],
  order: ['pedido', 'order', 'compra', 'purchase', 'envío', 'shipping', 'entrega', 'delivery'],
  general: [default fallback]
}
```

**Logic:**
1. Convert messageText to lowercase
2. Check if any keyword matches
3. Return first matching topic
4. If no match: return "General"

**Example:**
```
Input: "Tengo problemas con mi factura"
Detected: "billing" (matches "factura")
```

---

## Rate Limiting

### Implementation

```
Service: WhatsApp (or any channel)
User: user_xyz
Limit: 20 AI calls per day

Daily Bucket Logic:
- Today = 2026-04-21 (00:00:00)
- SELECT * FROM N8NRateLimit 
  WHERE userId = 'user_xyz' 
    AND service = 'whatsapp' 
    AND date = 2026-04-21

Before each AI call:
1. Query N8NRateLimit for (userId, service, today)
2. If callCount < 20:
   - Proceed with N8N call
   - Increment callCount
3. Else:
   - Return error "Rate limit exceeded for today"
   - Log warning
```

---

## Future Services

This same pattern applies to **Instagram**, **Slack**, **TikTok**, **Facebook**.

### Instagram Service Example

File: `instagram/src/conversations/conversation.listener.ts`

```typescript
// Same structure as WhatsApp, just replace channel check
@RabbitSubscribe({
  exchange: 'channels',
  routingKey: 'channels.conversation.incoming',
  queue: 'instagram.conversation.incoming',
})
async handleConversationIncoming(payload: ConversationIncomingPayload) {
  if (payload.channel !== 'instagram') return; // ← Only process Instagram
  
  // Rest of logic identical to WhatsApp
}
```

**Schema:** `instagram/prisma/schema.prisma`
```prisma
model Conversation {
  // Same model as WhatsApp
}

model ConversationMessage {
  // Same model as WhatsApp
}

model ConversationAIResponse {
  // Same model as WhatsApp
}
```

### Slack Service Example

Similar structure, but consider:
- Slack uses **threads**: Map Slack threadId → conversationId
- Slack channels are public: May have multiple "conversations" per channel

### Implementation Checklist for New Service

1. ✅ Add Conversation/ConversationMessage/ConversationAIResponse tables
2. ✅ Create TopicDetectionService (customize keywords for channel)
3. ✅ Create ConversationCacheService
4. ✅ Create ConversationListener for `channels.conversation.incoming`
5. ✅ Update MessageListener to respect conversation.aiEnabled
6. ✅ Update AI response handler to check rate limits
7. ✅ Create listener for `channels.conversation.ai-toggle` and `channels.conversation.agent-assign`

---

## Summary

This design provides:

- **Scalability**: Each service owns its data
- **Loose coupling**: Services communicate via RabbitMQ events
- **Simple**: In-memory caching, keyword-based topic detection
- **Extensible**: Easy to add new services following same pattern
- **User-centric**: Can query all channels via Identity linking

Start with **Phase 1** (Database schema) and work through each phase sequentially.

