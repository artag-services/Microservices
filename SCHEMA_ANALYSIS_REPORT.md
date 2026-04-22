# SCHEMA MIGRATION ANALYSIS REPORT
# Generated: 2026-04-22 11:49:58

## EXECUTIVE SUMMARY

All 8 services have Prisma schemas with database migrations. The initial migration (0_init) has been created for each service, but the analysis reveals several critical schema inconsistencies that need attention.

**Key Findings:**
- ✅ All services have 1 migration (0_init) created
- ❌ Schema.prisma files in different services define different structures for the same models
- ❌ Gateway service is missing ConversationMessage and ConversationAIResponse models
- ⚠️ Identity service has different User model definition than other services
- ⚠️ N8NRateLimit model structure differs across services

---

## SERVICE-BY-SERVICE ANALYSIS

