-- ═══════════════════════════════════════════════════════════════════════════
-- PostgreSQL Initialization Script
-- Creates separate databases for each microservice
-- ═══════════════════════════════════════════════════════════════════════════

-- Gateway Service Database
CREATE DATABASE gateway_db;

-- Identity Service Database
CREATE DATABASE identity_db;

-- WhatsApp Service Database
CREATE DATABASE whatsapp_db;

-- Slack Service Database
CREATE DATABASE slack_db;

-- Notion Service Database
CREATE DATABASE notion_db;

-- Instagram Service Database
CREATE DATABASE instagram_db;

-- TikTok Service Database
CREATE DATABASE tiktok_db;

-- Facebook Service Database
CREATE DATABASE facebook_db;

-- Email Service Database
CREATE DATABASE email_db;

-- Scraping Service Database
CREATE DATABASE scraping_db;

-- ═══════════════════════════════════════════════════════════════════════════
-- All databases created successfully
-- Each microservice now has its own isolated PostgreSQL database
-- ═══════════════════════════════════════════════════════════════════════════
