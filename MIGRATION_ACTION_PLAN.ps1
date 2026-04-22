# Database Migration Action Plan (PowerShell)
# Execute these commands in order of priority

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         DATABASE SCHEMA AUDIT - MIGRATION ACTION PLAN                         ║" -ForegroundColor Cyan
Write-Host "║                   Generated: 2026-04-22                                       ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ──────────────────────────────────────────────────────────────────────────────────
# 🔴 CRITICAL PRIORITY - EXECUTE IMMEDIATELY
# ──────────────────────────────────────────────────────────────────────────────────

Write-Host "🔴 CRITICAL PRIORITY - Execute Immediately" -ForegroundColor Red
Write-Host "─────────────────────────────────────────────────────────────────────────────────" -ForegroundColor Red
Write-Host ""

Write-Host "📌 STEP 1: Notion Service" -ForegroundColor Yellow
Write-Host "   Status: CRITICAL EMPTY (0/4 tables)" -ForegroundColor Red
Write-Host "   Commands:" -ForegroundColor Gray
Write-Host "   ┌─ cd notion"
Write-Host "   ├─ npm run prisma:generate"
Write-Host "   ├─ npm run prisma:migrate"
Write-Host "   ├─ npm run prisma:studio  # Verify tables created"
Write-Host "   └─ cd .."
Write-Host ""
Write-Host "   Tables that will be created:" -ForegroundColor Gray
Write-Host "      • days_off (legacy reference)"
Write-Host "      • inventory (legacy reference)"
Write-Host "      • n8n_vectors (legacy reference)"
Write-Host "      • NotionOperation (service-specific)"
Write-Host ""

Write-Host "📌 STEP 2: Slack Service" -ForegroundColor Yellow
Write-Host "   Status: CRITICAL EMPTY (0/4 tables)" -ForegroundColor Red
Write-Host "   Commands:" -ForegroundColor Gray
Write-Host "   ┌─ cd slack"
Write-Host "   ├─ npm run prisma:generate"
Write-Host "   ├─ npm run prisma:migrate"
Write-Host "   ├─ npm run prisma:studio  # Verify tables created"
Write-Host "   └─ cd .."
Write-Host ""
Write-Host "   Tables that will be created:" -ForegroundColor Gray
Write-Host "      • days_off (legacy reference)"
Write-Host "      • inventory (legacy reference)"
Write-Host "      • n8n_vectors (legacy reference)"
Write-Host "      • SlackMessage (service-specific)"
Write-Host ""

Write-Host "📌 STEP 3: Scraping Service" -ForegroundColor Yellow
Write-Host "   Status: NO SCHEMA FILE - Cannot proceed without clarification" -ForegroundColor Red
Write-Host "   Investigation Steps:" -ForegroundColor Gray
Write-Host "   ┌─ cd scrapping"
Write-Host "   ├─ Get-ChildItem                # Check directory structure"
Write-Host "   ├─ Select-String -Path 'package.json' -Pattern 'prisma|typeorm|mikro'"
Write-Host "   └─ Test-Path 'prisma/' && Get-ChildItem prisma/ || Write-Host 'No prisma directory'"
Write-Host ""
Write-Host "   If using Prisma:" -ForegroundColor Gray
Write-Host "      • Initialize Prisma: npx prisma init"
Write-Host "      • Create schema.prisma with appropriate models"
Write-Host "      • Run: npm run prisma:migrate"
Write-Host ""
Write-Host "   If using different ORM:" -ForegroundColor Gray
Write-Host "      • Document the ORM used"
Write-Host "      • Ensure database is initialized"
Write-Host "      • Update architecture documentation"
Write-Host ""

# ──────────────────────────────────────────────────────────────────────────────────
# 🟠 HIGH PRIORITY - THIS WEEK
# ──────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "🟠 HIGH PRIORITY - This Week" -ForegroundColor DarkYellow
Write-Host "─────────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkYellow
Write-Host ""

Write-Host "📌 STEP 4: Gateway Service" -ForegroundColor Yellow
Write-Host "   Status: INCOMPLETE (2/10 tables)" -ForegroundColor Red
Write-Host "   Missing: Conversation system (8 tables)" -ForegroundColor Red
Write-Host "   Commands:" -ForegroundColor Gray
Write-Host "   ┌─ cd gateway"
Write-Host "   ├─ npm run prisma:generate"
Write-Host "   ├─ npm run prisma:migrate"
Write-Host "   ├─ npm run prisma:studio  # Verify all 10 tables created"
Write-Host "   └─ cd .."
Write-Host ""
Write-Host "   Tables that will be created:" -ForegroundColor Gray
Write-Host "      • Conversation"
Write-Host "      • ConversationMessage"
Write-Host "      • ConversationAIResponse"
Write-Host "      • User"
Write-Host "      • UserIdentity"
Write-Host "      • AIResponse"
Write-Host "      • AIResponseChunk"
Write-Host "      • N8NRateLimit"
Write-Host ""

Write-Host "📌 STEP 5: Identity Service - SCHEMA REVIEW FIRST" -ForegroundColor Yellow
Write-Host "   Status: INCOMPLETE (4/18 tables, 0/12 enums)" -ForegroundColor Red
Write-Host "   ⚠️  ISSUE: Schema contains models from OTHER services" -ForegroundColor Magenta
Write-Host "   Action: REVIEW BEFORE MIGRATION" -ForegroundColor Magenta
Write-Host ""
Write-Host "   Current situation:" -ForegroundColor Gray
Write-Host "      • 4 core identity tables present in DB ✓"
Write-Host "      • 14 foreign service models in schema (should NOT be here)"
Write-Host "      • 0 foreign tables in DB ✗"
Write-Host ""
Write-Host "   Recommendation:" -ForegroundColor Gray
Write-Host "      1. Review identity_db schema"
Write-Host "      2. Remove all foreign models (AIResponse, Message, etc.)"
Write-Host "      3. Keep only these 4 core tables:"
Write-Host "         - User"
Write-Host "         - UserIdentity"
Write-Host "         - UserContact"
Write-Host "         - NameHistory"
Write-Host ""
Write-Host "   After fixing schema:" -ForegroundColor Gray
Write-Host "   ┌─ cd identity"
Write-Host "   ├─ npm run prisma:generate"
Write-Host "   ├─ npm run prisma:migrate"
Write-Host "   ├─ npm run prisma:studio  # Verify 4 core tables"
Write-Host "   └─ cd .."
Write-Host ""

# ──────────────────────────────────────────────────────────────────────────────────
# 🟡 MEDIUM PRIORITY - NEXT WEEK
# ──────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "🟡 MEDIUM PRIORITY - Next Week" -ForegroundColor DarkGreen
Write-Host "─────────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGreen
Write-Host ""

Write-Host "📌 STEP 6: Facebook Service" -ForegroundColor Yellow
Write-Host "   Status: INCOMPLETE (1/4 tables)" -ForegroundColor Yellow
Write-Host "   Missing: 3 legacy reference tables" -ForegroundColor Yellow
Write-Host "   Commands:" -ForegroundColor Gray
Write-Host "   ┌─ cd facebook"
Write-Host "   ├─ npm run prisma:generate"
Write-Host "   ├─ npm run prisma:migrate"
Write-Host "   ├─ npm run prisma:studio  # Verify all 4 tables created"
Write-Host "   └─ cd .."
Write-Host ""
Write-Host "   Tables that will be created:" -ForegroundColor Gray
Write-Host "      • days_off (legacy reference)"
Write-Host "      • inventory (legacy reference)"
Write-Host "      • n8n_vectors (legacy reference)"
Write-Host "      [FbMessage already exists]"
Write-Host ""

Write-Host "📌 STEP 7: TikTok Service" -ForegroundColor Yellow
Write-Host "   Status: INCOMPLETE (1/4 tables)" -ForegroundColor Yellow
Write-Host "   Missing: 3 legacy reference tables" -ForegroundColor Yellow
Write-Host "   Commands:" -ForegroundColor Gray
Write-Host "   ┌─ cd tiktok"
Write-Host "   ├─ npm run prisma:generate"
Write-Host "   ├─ npm run prisma:migrate"
Write-Host "   ├─ npm run prisma:studio  # Verify all 4 tables created"
Write-Host "   └─ cd .."
Write-Host ""
Write-Host "   Tables that will be created:" -ForegroundColor Gray
Write-Host "      • days_off (legacy reference)"
Write-Host "      • inventory (legacy reference)"
Write-Host "      • n8n_vectors (legacy reference)"
Write-Host "      [TikTokPost already exists]"
Write-Host ""

# ──────────────────────────────────────────────────────────────────────────────────
# ✅ VERIFICATION (No Changes Needed)
# ──────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "✅ VERIFICATION - No Migration Needed (Already Synced)" -ForegroundColor Green
Write-Host "─────────────────────────────────────────────────────────────────────────────────" -ForegroundColor Green
Write-Host ""

Write-Host "📌 STEP 8: WhatsApp Service (Already Synced ✓)" -ForegroundColor Green
Write-Host "   Status: PRODUCTION READY (9/9 tables, 5/5 enums)" -ForegroundColor Green
Write-Host "   Action: Verify no migration needed" -ForegroundColor Gray
Write-Host "   Command: cd whatsapp && npm run prisma:studio"
Write-Host ""

Write-Host "📌 STEP 9: Instagram Service (Already Synced ✓)" -ForegroundColor Green
Write-Host "   Status: PRODUCTION READY (11/11 tables, 5/5 enums)" -ForegroundColor Green
Write-Host "   Action: Verify no migration needed" -ForegroundColor Gray
Write-Host "   Command: cd instagram && npm run prisma:studio"
Write-Host ""

# ──────────────────────────────────────────────────────────────────────────────────
# SUMMARY AND NEXT STEPS
# ──────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                          SUMMARY AND NEXT STEPS                                ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

Write-Host "📊 Current State:" -ForegroundColor Cyan
Write-Host "   • Total Services: 9"
Write-Host "   • Fully Synced: 2 (whatsapp, instagram)"
Write-Host "   • Needs Migration: 5 (gateway, notion, slack, facebook, tiktok)"
Write-Host "   • Requires Investigation: 1 (identity schema issue)"
Write-Host "   • Unknown: 1 (scraping - no schema)"
Write-Host ""

Write-Host "🎯 Migration Timeline:" -ForegroundColor Cyan
Write-Host ""
Write-Host "   Week 1 (CRITICAL):" -ForegroundColor Red
Write-Host "      ☐ Notion migration"
Write-Host "      ☐ Slack migration"
Write-Host "      ☐ Scraping investigation"
Write-Host ""
Write-Host "   Week 1-2 (HIGH):" -ForegroundColor DarkYellow
Write-Host "      ☐ Identity schema review"
Write-Host "      ☐ Identity migration"
Write-Host "      ☐ Gateway migration"
Write-Host ""
Write-Host "   Week 2-3 (MEDIUM):" -ForegroundColor Yellow
Write-Host "      ☐ Facebook migration"
Write-Host "      ☐ TikTok migration"
Write-Host ""
Write-Host "   Week 3 (VERIFICATION):" -ForegroundColor Green
Write-Host "      ☐ Test all services"
Write-Host "      ☐ Run integration tests"
Write-Host "      ☐ Verify data integrity"
Write-Host ""

Write-Host "⚠️  Important Notes:" -ForegroundColor Yellow
Write-Host "   1. Always backup database before running migrations"
Write-Host "   2. Run migrations in staging environment first"
Write-Host "   3. Verify each migration with 'npm run prisma:studio'"
Write-Host "   4. Check service logs after migration for any errors"
Write-Host "   5. Test service functionality thoroughly after migration"
Write-Host ""

Write-Host "📌 Rollback Instructions (if needed):" -ForegroundColor Yellow
Write-Host "   1. Most recent migration: npx prisma migrate resolve --rolled-back <migration_name>"
Write-Host "   2. Restore from backup if available"
Write-Host "   3. Document any data loss"
Write-Host ""

Write-Host "✅ Success Criteria:" -ForegroundColor Green
Write-Host "   • All services have their expected tables"
Write-Host "   • All enums properly created"
Write-Host "   • No NULL/missing constraints"
Write-Host "   • Services start without errors"
Write-Host "   • Integration tests pass"
Write-Host ""

Write-Host "╔════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Generated: 2026-04-22 | Status: Ready for Execution                          ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
