CREATE TYPE "ConvStatus" AS ENUM ('ACTIVE', 'WAITING_AGENT', 'WITH_AGENT', 'ARCHIVED', 'CLOSED');
CREATE TYPE "MessageSender" AS ENUM ('USER', 'BOT', 'AGENT', 'SYSTEM');

CREATE TABLE "Conversation" (
    "id" TEXT NOT NULL,
    "userId" TEXT,
    "channelUserId" TEXT NOT NULL,
    "channel" TEXT NOT NULL DEFAULT 'whatsapp',
    "topic" TEXT,
    "detectionMethod" TEXT NOT NULL,
    "keywords" TEXT[],
    "aiEnabled" BOOLEAN NOT NULL DEFAULT true,
    "agentAssigned" TEXT,
    "status" "ConvStatus" NOT NULL DEFAULT 'ACTIVE',
    "messageCount" INTEGER NOT NULL DEFAULT 0,
    "aiMessageCount" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "lastMessageAt" TIMESTAMP(3),
    "archivedAt" TIMESTAMP(3),
    CONSTRAINT "Conversation_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ConversationMessage" (
    "id" TEXT NOT NULL,
    "conversationId" TEXT NOT NULL,
    "sender" "MessageSender" NOT NULL,
    "content" TEXT NOT NULL,
    "mediaUrl" TEXT,
    "aiGenerated" BOOLEAN NOT NULL DEFAULT false,
    "externalId" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "ConversationMessage_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ConversationAIResponse" (
    "id" TEXT NOT NULL,
    "conversationId" TEXT NOT NULL,
    "userMessage" TEXT NOT NULL,
    "aiResponse" TEXT NOT NULL,
    "model" TEXT,
    "confidence" DOUBLE PRECISION,
    "processingTime" INTEGER,
    "status" "AIResponseStatus" NOT NULL DEFAULT 'PENDING',
    "chunks" INTEGER NOT NULL DEFAULT 0,
    "failureReason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "ConversationAIResponse_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "Conversation_channelUserId_channel_status_key" ON "Conversation"("channelUserId", "channel", "status");
CREATE INDEX "Conversation_userId_idx" ON "Conversation"("userId");
CREATE INDEX "Conversation_status_lastMessageAt_idx" ON "Conversation"("status", "lastMessageAt");
CREATE INDEX "ConversationMessage_conversationId_createdAt_idx" ON "ConversationMessage"("conversationId", "createdAt");
CREATE INDEX "ConversationMessage_sender_idx" ON "ConversationMessage"("sender");
CREATE INDEX "ConversationAIResponse_conversationId_createdAt_idx" ON "ConversationAIResponse"("conversationId", "createdAt");
CREATE INDEX "ConversationAIResponse_status_idx" ON "ConversationAIResponse"("status");

ALTER TABLE "ConversationMessage" ADD CONSTRAINT "ConversationMessage_conversationId_fkey" FOREIGN KEY ("conversationId") REFERENCES "Conversation"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ConversationAIResponse" ADD CONSTRAINT "ConversationAIResponse_conversationId_fkey" FOREIGN KEY ("conversationId") REFERENCES "Conversation"("id") ON DELETE CASCADE ON UPDATE CASCADE;
