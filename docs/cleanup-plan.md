# REPOSITORY CLEANUP PLAN
**Generated:** January 20, 2026  
**Purpose:** Reorganize 41 markdown files and 62 SQL files into logical structure

---

## 🎯 PROPOSED FOLDER STRUCTURE

```
Calpe-Ward/
├── docs/                          # All documentation
│   ├── architecture/              # System design & diagrams
│   ├── security/                  # Security audits & reports
│   ├── migration/                 # Migration documentation
│   ├── deployment/                # Deployment guides
│   ├── features/                  # Feature specifications
│   └── legacy/                    # Historical documentation
│
├── sql/
│   ├── deploy/                    # Production deployment scripts
│   ├── migrations/                # Schema migration scripts
│   ├── fixes/                     # Hotfixes and patches
│   ├── tables/                    # Table creation scripts
│   ├── functions/                 # Function definitions
│   ├── diagnostics/               # Check and diagnostic scripts
│   └── archive/                   # Old/superseded SQL files
│
├── archive/                       # Old HTML files and backups
│   └── html/                      # Old HTML versions
│
├── js/                            # JavaScript modules (no change)
├── css/                           # CSS files (no change)
├── icons/                         # Icon assets (no change)
│
└── [root HTML files]              # Active pages stay in root
    ├── index.html
    ├── login.html
    ├── rota.html
    ├── requests.html
    ├── admin.html
    └── README.md                  # Main readme stays in root
```

---

## 📋 MARKDOWN FILES - MOVE PLAN

### Architecture Documentation → docs/architecture/ (2 files)
```
ARCHITECTURE_DIAGRAMS.md                    → docs/architecture/diagrams.md
OVERRIDE_SYSTEM.md                          → docs/architecture/override-system.md
```

### Security Documentation → docs/security/ (7 files)
```
SECURITY_AUDIT_REPORT.md                    → docs/security/audit-report-current.md
SECURITY_AUDIT_REPORT_OLD.md                → docs/security/audit-report-old.md
SECURITY_AUDIT_VISUAL_SUMMARY.md            → docs/security/visual-summary.md
SECURITY_AUDIT_COMPREHENSIVE.md             → docs/security/comprehensive-audit.md
SECURITY_EXECUTIVE_SUMMARY.md               → docs/security/executive-summary.md
SECURITY_PATCH_PLAN_IMPLEMENTATION.md       → docs/security/patch-plan.md
CRITICAL_SECURITY_ISSUE_REPORT.md           → docs/security/critical-issues.md
```

### Migration Documentation → docs/migration/ (13 files)
```
MIGRATION_SUMMARY.md                        → docs/migration/summary.md
MIGRATION_STATUS_REPORT.md                  → docs/migration/status-report.md
MIGRATION_REVIEW_CHECKLIST.md               → docs/migration/review-checklist.md
MIGRATION_COMPLETE.md                       → docs/migration/completion-report.md
TOKEN_ONLY_MIGRATION_SUMMARY.md             → docs/migration/token-only-summary.md
LEGACY_VS_TOKEN_COMPARISON.md               → docs/migration/legacy-vs-token.md
CLEAN_RPC_INVENTORY.md                      → docs/migration/rpc-inventory.md
FUNCTION_INVENTORY.md                       → docs/migration/function-inventory.md
FUNCTION_RECREATION_ANALYSIS.md             → docs/migration/function-recreation.md
FUNCTION_SIGNATURES.md                      → docs/migration/function-signatures.md
LEGACY_AUDIT_INDEX.md                       → docs/migration/legacy-audit-index.md
LEGACY_FUNCTIONS_INVENTORY.md               → docs/migration/legacy-functions.md
SUMMARY_LEGACY_AUTH_FUNCTIONS.md            → docs/migration/legacy-auth-summary.md
```

### Deployment Documentation → docs/deployment/ (7 files)
```
DEPLOYMENT_CHECKLIST.md                     → docs/deployment/checklist.md
DEPLOYMENT_INSTRUCTIONS.md                  → docs/deployment/instructions.md
DELIVERY_SUMMARY.md                         → docs/deployment/delivery-summary.md
PHASE_3_LOGIN_DEPLOYMENT.md                 → docs/deployment/phase-3-login.md
PHASE_4_SESSION_INTEGRATION.md              → docs/deployment/phase-4-session.md
deploy_schema.ps1                           → docs/deployment/deploy-schema.ps1
deploy_schema.py                            → docs/deployment/deploy-schema.py
```

### Feature Documentation → docs/features/ (4 files)
```
LOGIN_SYSTEM_SUMMARY.md                     → docs/features/login-system.md
REQUIRE_SESSION_PERMISSIONS_SPEC.md         → docs/features/session-permissions.md
STAFFING_REQUIREMENTS.md                    → docs/features/staffing-requirements.md
SETUP_STAFFING.md                           → docs/features/staffing-setup.md
```

### Fix/Patch Documentation → docs/legacy/ (7 files)
```
DROP_LEGACY_FUNCTIONS_QUICK_FIX.md          → docs/legacy/drop-legacy-functions.md
FIX_NOTIFICATIONS_NOTES.md                  → docs/legacy/fix-notifications.md
FIX_PLAN.md                                 → docs/legacy/fix-plan.md
FIX_SWAP_RPC_ERROR.md                       → docs/legacy/fix-swap-rpc.md
DOCUMENTATION_INDEX.md                      → docs/legacy/documentation-index.md
login.readme                                → docs/legacy/login-readme.txt
```

### Root (Stay in root) (1 file)
```
README.md                                   → (STAYS IN ROOT)
```

### New Files (Generated today) → docs/ (2 files)
```
SECURITY_FINDINGS.md                        → docs/security/findings-2026-01.md
STRUCTURE_REPORT.md                         → docs/structure-report.md
```

---

## 📋 SQL FILES - MOVE PLAN

### Deployment Scripts → sql/deploy/ (4 files)
```
sql/MASTER_DEPLOYMENT.sql                   → sql/deploy/master-deployment.sql
sql/COMPLETE_SECURITY_UPGRADE_MASTER.sql    → sql/deploy/complete-security-upgrade.sql
sql/DEPLOY_12_CRITICAL_FUNCTIONS.sql        → sql/deploy/12-critical-functions.sql
sql/DEPLOY_DATABASE_FIXES.sql               → sql/deploy/database-fixes.sql
```

### Migration Scripts → sql/migrations/ (1 file)
```
sql/migrate_to_token_only_rpcs.sql          → sql/migrations/token-only-rpcs.sql
```

### Fix Scripts → sql/fixes/ (15 files)
```
sql/FIX_LOGIN_SCHEMA.sql                    → sql/fixes/login-schema.sql
sql/FIX_REQUEST_SYSTEM.sql                  → sql/fixes/request-system.sql
sql/FIX_RLS_INFINITE_RECURSION.sql          → sql/fixes/rls-recursion.sql
sql/FIX_VERIFY_LOGIN.sql                    → sql/fixes/verify-login.sql
sql/FIX_VERIFY_LOGIN_AMBIGUITY.sql          → sql/fixes/verify-login-ambiguity.sql
sql/fix_admin_notifications_and_functions.sql → sql/fixes/admin-notifications.sql
sql/fix_period_id_to_uuid.sql               → sql/fixes/period-id-uuid.sql
sql/fix_swap_executions_period_nullable.sql → sql/fixes/swap-executions-nullable.sql
sql/fix_swap_functions.sql                  → sql/fixes/swap-functions.sql
sql/fix_swap_notification_handling.sql      → sql/fixes/swap-notifications.sql
sql/security_audit_and_cleanup.sql          → sql/fixes/security-audit-cleanup.sql
sql/SIMPLE_SCHEMA_FIX.sql                   → sql/fixes/simple-schema.sql
sql/FINAL_CLEANUP_RECURSIVE_POLICIES.sql    → sql/fixes/cleanup-recursive-policies.sql
sql/update_swap_functions.sql               → sql/fixes/update-swap-functions.sql
sql/UPDATE_SWAP_FUNCTIONS_WITH_HISTORY.sql  → sql/fixes/update-swap-with-history.sql
```

### Table Creation → sql/tables/ (8 files)
```
sql/create_assignment_comments.sql          → sql/tables/assignment-comments.sql
sql/create_assignment_overrides.sql         → sql/tables/assignment-overrides.sql
sql/create_shift_swaps.sql                  → sql/tables/shift-swaps.sql
sql/create_staffing_requirements.sql        → sql/tables/staffing-requirements.sql
sql/CREATE_ASSIGNMENT_HISTORY.sql           → sql/tables/assignment-history.sql
sql/add_notifications_table.sql             → sql/tables/notifications.sql
sql/add_comment_visibility.sql              → sql/tables/comment-visibility.sql
sql/add_override_comment_visibility.sql     → sql/tables/override-comment-visibility.sql
```

### Function Definitions → sql/functions/ (18 files)
```
sql/ADD_SESSION_FUNCTIONS.sql               → sql/functions/session-functions.sql
sql/CREATE_REMAINING_5_TOKEN_FUNCTIONS.sql  → sql/functions/remaining-5-token.sql
sql/CREATE_REQUEST_LOCKS_AND_FUNCTIONS.sql  → sql/functions/request-locks.sql
sql/CREATE_WEEK_COMMENTS_FUNCTIONS.sql      → sql/functions/week-comments.sql
sql/CREATE_NOTICES_FUNCTION_NO_PARAMS.sql   → sql/functions/notices-no-params.sql
sql/CREATE_ACK_NOTICE_NO_TOKEN.sql          → sql/functions/ack-notice-no-token.sql
sql/shift_swap_functions.sql                → sql/functions/shift-swap.sql
sql/shift_swap_functions_fixed.sql          → sql/functions/shift-swap-fixed.sql
sql/RECREATE_12_CRITICAL_FUNCTIONS.sql      → sql/functions/recreate-12-critical.sql
sql/RECREATE_NOTICES_FUNCTION.sql           → sql/functions/recreate-notices.sql
sql/ADMIN_SET_REQUEST_CELL.sql              → sql/functions/admin-set-request-cell.sql
sql/SET_REQUEST_CELL.sql                    → sql/functions/set-request-cell.sql
sql/GET_REQUESTS_FOR_PERIOD.sql             → sql/functions/get-requests-for-period.sql
sql/SESSION_PERMISSIONS_HELPER.sql          → sql/functions/session-permissions-helper.sql
sql/setup_rota_permissions.sql              → sql/functions/setup-rota-permissions.sql
sql/setup_rota_swap_permission.sql          → sql/functions/setup-rota-swap-permission.sql
sql/COMPLETE_FIX_ALL_25_FUNCTIONS.sql       → sql/functions/complete-fix-25.sql
sql/ADD_USERNAME_COLUMN.sql                 → sql/functions/add-username-column.sql
```

### Drop/Cleanup Scripts → sql/archive/ (4 files)
```
sql/drop_all_legacy_function_overloads.sql  → sql/archive/drop-legacy-overloads.sql
sql/DROP_LEGACY_ADMIN_FUNCTIONS.sql         → sql/archive/drop-legacy-admin.sql
sql/FINAL_DROP_ALL_LEGACY_FUNCTIONS.sql     → sql/archive/final-drop-legacy.sql
sql/IMPORT_REQUESTS_DATA.sql                → sql/archive/import-requests-data.sql
```

### Diagnostics → sql/diagnostics/ (4 files)
```
sql/check_assignment_comments.sql           → sql/diagnostics/check-assignment-comments.sql
sql/check_periods_table.sql                 → sql/diagnostics/check-periods-table.sql
sql/check_rls_status.sql                    → sql/diagnostics/check-rls-status.sql
sql/check_swap_functions.sql                → sql/diagnostics/check-swap-functions.sql
```

### Phase Scripts → sql/migrations/ (2 files)
```
sql/PHASE_3_COMPLETE_LOGIN_SCHEMA.sql       → sql/migrations/phase-3-login-schema.sql
sql/PHASE_3_LOGIN_FUNCTIONS.sql             → sql/migrations/phase-3-login-functions.sql
```

### Full Dumps → sql/archive/ (2 files)
```
sql/full_dump.sql                           → sql/archive/full-dump-old.sql
sql/full_dump2.sql                          → sql/archive/full-dump-2.sql
```

### Guides → docs/deployment/ (2 files)
```
sql/FRONTEND_RPC_MIGRATION_GUIDE.md         → docs/deployment/frontend-rpc-migration.md
sql/HISTORY_IMPLEMENTATION_GUIDE.sql        → docs/deployment/history-implementation-guide.sql
```

### Root SQL Files (Move to deploy) (3 files)
```
RUN_THIS_IN_SUPABASE_SQL_EDITOR.sql         → sql/deploy/run-in-supabase-editor.sql
```

---

## 🗑️ FILES TO DELETE (Not Archive)

### HTML Files (0 files - recommend archive instead)
- None - all should be archived for reference

---

## 📦 FILES TO ARCHIVE

### HTML → archive/html/
```
index - Copy.html                           → archive/html/index-copy.html
index.html.backup                           → archive/html/index-backup.html
index.html.new                              → archive/html/index-new.html
Old/index.broken.html                       → archive/html/old-index-broken.html
Old/index copy fixed.html                   → archive/html/old-index-copy-fixed.html
Old/index - Copy.html                       → archive/html/old-index-copy.html
```

### JavaScript → archive/js/
```
js/app.js                                   → archive/js/app-legacy.js (unused, 5624 lines)
```

---

## 🔗 LINKS TO UPDATE

### After moving markdown files, update these internal references:

#### README.md likely references:
- Security audit files
- Migration documentation
- Deployment guides

#### Deployment scripts (deploy_schema.ps1, deploy_schema.py) may reference:
- SQL file paths in sql/ directory

#### Search and replace needed:
```powershell
# Example: Update references to moved SQL files
- Old: sql/MASTER_DEPLOYMENT.sql
- New: sql/deploy/master-deployment.sql
```

---

## 📊 SUMMARY STATISTICS

### Markdown Files:
- **Total:** 41 files
- **To docs/architecture/:** 2 files
- **To docs/security/:** 9 files (7 + 2 new)
- **To docs/migration/:** 13 files
- **To docs/deployment/:** 9 files (7 + 2 guides)
- **To docs/features/:** 4 files
- **To docs/legacy/:** 7 files
- **Stay in root:** 1 file (README.md)

### SQL Files:
- **Total:** 62 files
- **To sql/deploy/:** 5 files (4 + 1 from root)
- **To sql/migrations/:** 3 files
- **To sql/fixes/:** 15 files
- **To sql/tables/:** 8 files
- **To sql/functions/:** 18 files
- **To sql/archive/:** 6 files
- **To sql/diagnostics/:** 4 files
- **To docs/deployment/:** 2 files (guides)

### HTML Files:
- **To archive/html/:** 6 files
- **Stay in root:** 5 active files

### JavaScript Files:
- **To archive/js/:** 1 file (app.js)

---

## ✅ VALIDATION CHECKLIST

After file moves:
- [ ] All internal markdown links updated
- [ ] deploy_schema.ps1 updated with new paths
- [ ] deploy_schema.py updated with new paths
- [ ] README.md links verified
- [ ] No broken references in documentation
- [ ] Archive directory created and organized
- [ ] Old/ directory removed after archiving

---

**Report End**
