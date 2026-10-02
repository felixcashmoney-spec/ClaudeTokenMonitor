---
phase: quick-260327-qfx
plan: 01
subsystem: services/api-client
tags: [api-client, cookies, crypto, live-data, billing]
dependency_graph:
  requires: [UsageWindowTracker, LogFileParser]
  provides: [ClaudeAPIClient, live-utilization, credit-balance, extra-usage-spending]
  affects: [DashboardView, UsageWindowTracker]
tech_stack:
  added: [CommonCrypto, Security framework, SQLite3, URLSession async/await]
  patterns: [Chromium Safe Storage decryption, PBKDF2+AES-128-CBC, cookie caching, 60s polling timer]
key_files:
  created:
    - ClaudeTokenMonitor/ClaudeTokenMonitor/Services/ClaudeAPIClient.swift
  modified:
    - ClaudeTokenMonitor/ClaudeTokenMonitor/Services/UsageWindowTracker.swift
    - ClaudeTokenMonitor/ClaudeTokenMonitor/Views/DashboardView.swift
    - ClaudeTokenMonitor/ClaudeTokenMonitor.xcodeproj/project.pbxproj
decisions:
  - "Cookie decryption uses Chromium Safe Storage format: PBKDF2-SHA1(keychain_password, saltysalt, 1003 iterations) + AES-128-CBC(IV=0x20*16)"
  - "API data freshness threshold is 120s — stale API data is discarded, log data used as fallback"
  - "ClaudeAPIClient owned by UsageWindowTracker (encapsulated, same pattern as LogFileParser)"
  - "lastActiveOrg cookie provides orgId — checked as plaintext first, then decrypted if empty"
metrics:
  duration: ~20 minutes
  completed: 2026-03-27
  tasks_completed: 2
  files_modified: 4
---

# Phase quick Plan 01: Add ClaudeAPIClient Service for Live Usage Summary

ClaudeAPIClient reads encrypted cookies from Claude Desktop's SQLite DB (Chromium Safe Storage: Keychain PBKDF2 + AES-128-CBC), calls three claude.ai API endpoints (usage, prepaid/credits, overage_spend_limit), and displays live EUR credit balance and extra usage spending in the dashboard.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create ClaudeAPIClient with cookie decryption and API calls | 69ba794 | ClaudeAPIClient.swift, project.pbxproj |
| 2 | Enhance UsageWindowTracker to consume API data and update DashboardView | d2ba403 | UsageWindowTracker.swift, DashboardView.swift |

## What Was Built

### ClaudeAPIClient.swift (new service, ~270 lines)

- Reads Claude Desktop's `~/Library/Application Support/Claude/Cookies` SQLite DB
- Keychain query for "Claude Safe Storage" password via `SecItemCopyMatching`
- PBKDF2-SHA1 key derivation (password from keychain, salt="saltysalt", 1003 iterations, 16 bytes)
- AES-128-CBC decryption with IV=0x20*16, strips "v10" prefix, PKCS7 padding via CCCrypt
- Extracts `sessionKey`, `cf_clearance`, `lastActiveOrg` cookies (plain value column checked first)
- Three API endpoints: `/usage`, `/prepaid/credits`, `/overage_spend_limit`
- Combined `fetchAll()` returning `ClaudeAPIData` with all three responses
- 5-minute cookie cache, graceful error handling via print() — never crashes

### UsageWindowTracker.swift (enhanced)

- `UsageWindow` struct gained six new API credit fields: `creditBalanceCents`, `creditCurrency`, `extraUsageSpentCents`, `extraUsageMonthlyLimitCents`, `extraUsageEnabled`, `apiDataFreshness`
- `ClaudeAPIClient` owned internally (same encapsulation pattern as LogFileParser)
- Separate 60-second API polling timer (independent of 10s log timer)
- When API data is fresh (<120s): API utilization and reset times override log-based values
- All three evaluation paths (log data, session rate limit, token fallback) populate new credit fields
- Fallback: when API unavailable, existing log/token evaluation unchanged

### DashboardView.swift (enhanced)

- New `creditSpendingBanner()` view builder in `PlanUsageBanner`
- Shows "Prepaid-Guthaben: X,XX EUR" in green
- Shows "Extra Usage ausgegeben: X,XX EUR" in orange (only when extra usage enabled)
- Shows monthly limit when set
- Shows "Aktualisiert: N Minuten zurueck" freshness indicator
- `formatEUR(cents:)` helper using NumberFormatter with de_DE locale for "8,15 EUR" format
- Section only renders when API data is available (no empty placeholder)

## Verification

- App compiles without errors: BUILD SUCCEEDED
- ClaudeAPIClient.swift exists with cookie decryption (CommonCrypto + Security framework)
- UsageWindow struct has `creditBalanceCents`, `extraUsageSpentCents` and other credit fields
- DashboardView shows EUR amounts with German locale formatting (de_DE)
- API polling runs on 60s interval (separate from 10s log polling)
- When API is unavailable: log-based data continues unchanged (graceful fallback)

## Deviations from Plan

### Auto-added enhancements

**1. [Rule 2 - Enhancement] ISO8601 parsing for API reset times**
- **Found during:** Task 2 integration
- **Issue:** Plan specified using API utilization values but not reset times from API
- **Fix:** Also parses `five_hour.resets_at` and `seven_day.resets_at` from API for more accurate reset display
- **Files modified:** UsageWindowTracker.swift

## Known Stubs

None — all API data flows directly from ClaudeAPIClient to UsageWindow to DashboardView. The credit display section is conditionally rendered only when API data is present (no stub/placeholder text shown when API is unavailable).

## Self-Check: PASSED
