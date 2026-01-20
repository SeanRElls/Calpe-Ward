# SECURITY FINDINGS REPORT
**Generated:** January 20, 2026  
**Scope:** Full repository scan for sensitive data, credentials, and security issues

---

## 🔴 CRITICAL FINDINGS

### 1. Database Dump Contains Encrypted/Sensitive Data
**File:** `sql/full_dump.sql` Line 5  
**Issue:** Contains what appears to be encrypted data or key material:
```
\restrict mvnbWlmxjxMLfpvaS6h2ldya4HMdFk3lhXFmIP6Hvj3CMRA0hSrNSRFgww7Lwxg
```
**Risk Level:** HIGH - Unknown encryption key/data in SQL dump  
**Recommendation:** Review and sanitize full_dump.sql, remove sensitive material

---

## 🟡 MODERATE FINDINGS

### 2. Duplicate Supabase ANON Keys in Old Files
**Files:**
- `Old/index.broken.html` (line 2515)
- `Old/index copy fixed.html` (line 2534)
- `Old/index - Copy.html` (line 2515)

**Issue:** These files contain **OLD** Supabase credentials for `tbclufdtyefexwwitfsz.supabase.co`
```javascript
const SUPABASE_ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRiY2x1ZmR0eWVmZXh3d2l0ZnN6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcwODA4ODksImV4cCI6MjA4MjY1Njg4OX0.OYnj44QQCTD-5tqR2XSVt4oQso9Ol8ZLH2tLsRGIreA";
```
**Risk Level:** MODERATE - Old credentials in archived files  
**Recommendation:** If these credentials are revoked/unused, archive these files. If still active, revoke immediately.

---

## 🟢 INFORMATIONAL FINDINGS

### 3. Current Supabase ANON Key (Expected)
**Files:** Multiple active files use current production ANON key  
**Project:** `pxpjxyfcydiasrycpbfp.supabase.co`

**Files containing ANON key:**
- `js/config.js` (line 29) ✅ **Centralized - GOOD**
- `js/app.js` (line 5) ⚠️ **Duplicate**
- `index.html` (line 2741) ⚠️ **Duplicate**
- `login.html` (references via window.SUPABASE_ANON) ✅ **Good practice**

**Risk Level:** LOW - ANON keys are safe to expose in frontend  
**Note:** Per Supabase docs, ANON keys are meant for client-side use with RLS policies  
**Recommendation:** Consolidate to single source (js/config.js) and remove duplicates

### 4. Service Role Grants in SQL (Expected)
**Files:** Multiple SQL files contain `GRANT ... TO service_role`  
**Count:** 50+ instances

**Sample Files:**
- `sql/full_dump.sql` (lines 7118+)
- `sql/CREATE_REQUEST_LOCKS_AND_FUNCTIONS.sql`
- `sql/FIX_REQUEST_SYSTEM.sql`
- Many others

**Risk Level:** NONE - This is normal PostgreSQL permission management  
**Note:** These are database permission grants, not exposed keys  
**Status:** ✅ SAFE - Standard database security configuration

### 5. Password Field References (Expected)
**Files:** `login.html`, `js/admin.js`  
**Issue:** HTML input type="password" fields for PIN entry

**Risk Level:** NONE - Standard HTML form fields  
**Status:** ✅ SAFE - No actual credentials stored

---

## 📊 SUMMARY

| Finding | Severity | Count | Action Required |
|---------|----------|-------|----------------|
| Unknown encrypted data in SQL dump | HIGH | 1 | Review & sanitize |
| Old Supabase credentials in archived files | MODERATE | 3 files | Archive or delete |
| Duplicate ANON key declarations | LOW | 3 files | Code cleanup |
| Service role grants | NONE | 50+ | No action |
| Password input fields | NONE | 2 files | No action |

---

## ✅ RECOMMENDATIONS

### Immediate Actions:
1. **Review sql/full_dump.sql line 5** - Determine if `\restrict` command and following data should be removed
2. **Archive Old/ directory files** - Move to secure archive or delete if no longer needed
3. **Consolidate ANON key** - Remove duplicates from app.js and index.html, use config.js only

### Medium Priority:
4. **Add .gitignore rules** for future dumps and sensitive data:
   ```
   *.dump
   *full_dump*.sql
   service_role_key.txt
   .env.local
   ```

### Code Quality:
5. **Standardize config loading** - All pages should load config.js and reference window.SUPABASE_URL
6. **Document security model** - Create SECURITY.md explaining RLS, token auth, and why ANON key is safe

---

## 🔍 SCAN METHODOLOGY

**Search Patterns:**
- `password|service_role|eyJ[A-Za-z0-9_-]{20,}|postgres://|postgresql://|\restrict`
- JWT tokens (eyJ prefix indicates JWT)
- Connection strings with credentials
- PostgreSQL special commands

**Files Scanned:**
- All .sql files (62 total)
- All .js files
- All .html files
- All .py and .ps1 files

**No findings for:**
- PostgreSQL connection strings with embedded credentials
- Service role keys (none found in frontend code ✅)
- Private keys or certificates
- API keys other than Supabase ANON (which is safe)

---

**Report End**
