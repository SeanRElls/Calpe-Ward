# REPOSITORY STRUCTURE REPORT
**Generated:** January 20, 2026  
**Purpose:** Complete inventory of HTML pages, script loading, and code duplications

---

## 📄 HTML PAGES INVENTORY

### Active Production Pages (5)

#### 1. **login.html** (484 lines)
**Purpose:** Login page with username + PIN authentication  
**Script Loading Order:**
```html
1. @supabase/supabase-js@2 (CDN)
2. js/config.js
3. (inline script)
```
**Supabase Client:** Creates inline via `window.supabase.createClient(window.SUPABASE_URL, window.SUPABASE_ANON)`  
**Session Management:** Sets sessionStorage tokens, validates via RPC

---

#### 2. **index.html** (8435 lines) ⚠️ MASSIVE FILE
**Purpose:** Landing/redirect page (also contains full app inline)  
**Script Loading Order:**
```html
1. js/config.js ⚠️ LOADS BEFORE SUPABASE LIBRARY
2. (inline script at line 2730+)
   - Redefines SUPABASE_URL/ANON inline 🔴 DUPLICATE
   - Creates supabaseClient inline
   - Contains entire app logic embedded
```
**Issues:**
- 🔴 **CRITICAL:** config.js loads BEFORE Supabase CDN library
- 🔴 Massive duplication - entire app is inline (8435 lines)
- 🔴 Duplicate SUPABASE_URL and ANON definitions

---

#### 3. **requests.html** (8270 lines)
**Purpose:** Off-duty requests management page  
**Script Loading Order:**
```html
1. @supabase/supabase-js@2 (CDN) ✅
2. js/config.js ✅
3. js/session-validator.js ✅
4. js/view-as.js?v=8
5. quill.js (rich text editor)
6. js/shift-functions.js (defer)
7. js/notifications-shared.js (defer)
8. (inline script - 8200+ lines)
```
**Supabase Client:** Uses `window.supabaseClient` from config.js, also creates local `supaClient` ⚠️  
**Duplication:** Renamed supabaseClient to supaClient to avoid conflict

---

#### 4. **rota.html** (2925 lines)
**Purpose:** Rota viewing and shift management  
**Script Loading Order:**
```html
1. @supabase/supabase-js@2 (CDN) ✅
2. js/config.js ✅
3. js/session-validator.js ✅
4. js/permissions.js ✅
5. js/view-as.js?v=8
6. js/swap-functions.js (defer)
7. js/notifications-shared.js (defer)
8. js/shift-functions.js (defer)
9. js/shift-editor.js (defer)
10. (inline script)
```
**Supabase Client:** Uses `window.supabaseClient` from config.js ✅  
**Status:** ✅ Proper loading order

---

#### 5. **admin.html** (1197 lines)
**Purpose:** Admin control panel  
**Script Loading Order:**
```html
1. @supabase/supabase-js@2 (CDN) ✅
2. js/config.js ⚠️ LOADED TWICE (line 9 AND line 1154)
3. js/session-validator.js
4. (inline script)
```
**Issues:**
- 🔴 **js/config.js included TWICE** (duplicate script tag)
- ⚠️ Should load view-as.js for "View As" feature

---

### Archived/Old Pages (4)

#### 6. **index - Copy.html** (8517 lines)
**Status:** DUPLICATE of requests page with old routing  
**Contains:** Old Supabase credentials embedded inline  
**Recommendation:** Archive or delete

#### 7. **Old/index.broken.html**
**Status:** Broken version with old credentials  
**Contains:** `tbclufdtyefexwwitfsz.supabase.co` (OLD PROJECT)  
**Recommendation:** Delete

#### 8. **Old/index copy fixed.html**
**Status:** Old fixed version  
**Contains:** Old credentials  
**Recommendation:** Delete

#### 9. **Old/index - Copy.html**
**Status:** Another old copy  
**Contains:** Old credentials  
**Recommendation:** Delete

---

## 🔧 JAVASCRIPT FILES INVENTORY

### Configuration & Core

#### **js/config.js** (103 lines)
**Purpose:** Central configuration file  
**Exports:**
```javascript
const SUPABASE_URL = "https://pxpjxyfcydiasrycpbfp.supabase.co";
const SUPABASE_ANON = "eyJ...";
window.SUPABASE_URL = SUPABASE_URL;
window.SUPABASE_ANON = SUPABASE_ANON;
window.supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON);
```
**Issues:** ⚠️ Attempts to create client immediately - will fail if loaded before Supabase library

---

#### **js/app.js** (5624 lines)
**Purpose:** Legacy app file (not referenced by any HTML)  
**Contains:** 🔴 **DUPLICATE** SUPABASE_URL and ANON definitions (lines 4-5)  
**Creates:** Own supabaseClient instance  
**Status:** ⚠️ Appears unused - not loaded by any current HTML page  
**Recommendation:** Archive or delete

---

#### **js/session-validator.js**
**Purpose:** Session token validation  
**Exports:**
```javascript
getActiveSessionToken() // Returns impersonation token or normal token
validateSessionOnLoad() // Redirects if not logged in
```
**Supabase Usage:** References `window.supabase` and `window.supabaseClient`

---

#### **js/permissions.js**
**Purpose:** Load user permissions and profile  
**Exports:**
```javascript
loadCurrentUserPermissions() // Checks impersonation, loads user data
```
**Supabase Usage:** Uses `window.supabaseClient`  
**Impersonation Support:** ✅ Checks sessionStorage for viewAsUser

---

### Feature Modules

#### **js/view-as.js** (v8)
**Purpose:** Admin impersonation feature  
**Key Functions:**
- `startViewingAs()` - Calls admin_impersonate_user RPC
- `stopViewingAs()` - Restores admin session
- `ensureViewAsBanner()` - Shows impersonation UI
**Supabase Usage:** References `window.supabaseClient` and local `supabaseClient` variable

---

#### **js/swap-functions.js**
**Purpose:** Shift swap functionality  
**Supabase Usage:** Unknown (deferred script)

---

#### **js/shift-functions.js**
**Purpose:** Shift manipulation  
**Supabase Usage:** Unknown (deferred script)

---

#### **js/shift-editor.js**
**Purpose:** Shift editing UI  
**Supabase Usage:** Unknown (deferred script)

---

#### **js/notifications-shared.js**
**Purpose:** Notification system  
**Supabase Usage:** Unknown (deferred script)

---

#### **js/staffing-requirements.js**
**Purpose:** Staffing requirements management  
**Supabase Usage:** Unknown

---

#### **js/admin.js**
**Purpose:** Admin panel logic  
**Supabase Usage:** Unknown

---

## 🔴 CRITICAL DUPLICATIONS

### 1. SUPABASE_URL and SUPABASE_ANON Definitions

| File | Lines | Type | Status |
|------|-------|------|--------|
| js/config.js | 28-29 | const | ✅ PRIMARY SOURCE |
| js/app.js | 4-5 | const | 🔴 DUPLICATE (unused file) |
| index.html | 2740-2741 | const inline | 🔴 DUPLICATE |
| login.html | - | Uses window.* | ✅ Correct |
| requests.html | - | Uses window.* | ✅ Correct |
| rota.html | - | Uses window.* | ✅ Correct |
| admin.html | - | Uses window.* | ✅ Correct |

**Recommendation:** Remove duplicates from app.js and index.html inline

---

### 2. Supabase Client Creation

| File | Variable Name | Scope | Issue |
|------|---------------|-------|-------|
| js/config.js | window.supabaseClient | Global | ✅ Primary |
| js/view-as.js | supabaseClient (local) | Function | ⚠️ Sometimes window, sometimes local |
| requests.html | supaClient | Inline script | ⚠️ Renamed to avoid conflict |
| index.html | supabaseClient | Inline script | 🔴 Duplicate creation |
| login.html | supabaseClient | Inline script | 🔴 Duplicate creation |
| js/app.js | supabaseClient | Global | 🔴 Unused file |

**Recommendation:** Standardize on window.supabaseClient from config.js everywhere

---

### 3. STORAGE_KEY Definitions

| File | Definition | Value |
|------|------------|-------|
| js/config.js | (none) | N/A |
| js/session-validator.js | const STORAGE_KEY | "calpeward.loggedInUserId" |
| index.html inline | const STORAGE_KEY | "calpeward.loggedInUserId" |
| js/app.js | const STORAGE_KEY | "calpeward.loggedInUserId" |

**Recommendation:** Define once in config.js and export to window

---

### 4. Session/CurrentUser Logic

**Scattered across:**
- js/session-validator.js (getActiveSessionToken)
- js/permissions.js (loadCurrentUserPermissions)
- Each HTML page has inline session check logic

**Issue:** No single source of truth for current user state  
**Recommendation:** Create centralized session module

---

## ⚠️ SCRIPT LOADING ORDER ISSUES

### 🔴 CRITICAL: index.html
```html
<script src="js/config.js"></script>  <!-- LOADS FIRST -->
<!-- Supabase CDN not loaded yet! -->
```
**Problem:** config.js tries to call `window.supabase.createClient()` but Supabase library hasn't loaded  
**Fix:** Add Supabase CDN script tag BEFORE config.js

### 🔴 CRITICAL: admin.html
```html
Line 9:   <script src="js/config.js"></script>
Line 1154: <script src="js/config.js"></script>  <!-- DUPLICATE -->
```
**Problem:** Config loaded twice  
**Fix:** Remove duplicate at line 1154

---

## 📊 STATISTICS

### HTML Files:
- **Active:** 5 files
- **Archived:** 4 files
- **Total lines (active):** 21,311 lines
- **Largest:** index.html (8435 lines)

### JavaScript Files:
- **Core modules:** 4 files (config, session-validator, permissions, view-as)
- **Feature modules:** 5 files (swap, shift, editor, notifications, staffing)
- **Admin:** 1 file (admin.js)
- **Legacy:** 1 file (app.js - unused)
- **Total:** ~11 JS files

### Supabase Client Instances:
- **Primary:** window.supabaseClient (config.js) ✅
- **Duplicates:** 5+ redundant creations 🔴

### Script Loading Issues:
- **Critical:** 2 issues (index.html order, admin.html duplicate)
- **Warnings:** 3 issues (redundant client creation)

---

## 🎯 CLEANUP PRIORITIES

### High Priority (Immediate):
1. Fix admin.html duplicate config.js include
2. Fix index.html script loading order
3. Remove duplicate SUPABASE definitions from index.html inline code

### Medium Priority:
4. Archive or delete Old/ directory files
5. Archive or delete app.js (appears unused)
6. Standardize on window.supabaseClient everywhere
7. Remove index - Copy.html (duplicate)

### Low Priority (Code Quality):
8. Consolidate STORAGE_KEY definition
9. Consolidate session management logic
10. Extract inline scripts to separate files (8000+ lines in index.html, requests.html)

---

**Report End**
