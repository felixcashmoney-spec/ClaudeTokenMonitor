# Roadmap: Claude Token Monitor

## Overview

The project builds a native macOS menubar app that watches Claude Code sessions, counts tokens, and alerts the user before self-set budget limits are hit. Work flows from app skeleton to data engine to dashboard to budget controls, finishing with the Liquid Glass polish layer that makes it feel native on macOS 26.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: App Foundation** - SwiftUI app shell, menubar icon, login item
- [ ] **Phase 2: Session Tracking Engine** - Detect Claude Code sessions, count tokens, group by project
- [ ] **Phase 3: Dashboard** - Realtime token display, day/week/month filters
- [ ] **Phase 4: Budget & Alerts** - User-defined budget, configurable thresholds, warnings
- [ ] **Phase 5: Liquid Glass Polish** - macOS 26 Liquid Glass design applied throughout

## Phase Details

### Phase 1: App Foundation
**Goal**: A running macOS app the user can open, that lives in the menubar and starts automatically with macOS
**Depends on**: Nothing (first phase)
**Requirements**: UI-01, CONF-03, CONF-04
**Success Criteria** (what must be TRUE):
  1. App launches without crashing on macOS 26
  2. A menubar icon is visible and clicking it opens a popover or window
  3. App is registered as a Login Item and relaunches automatically after reboot
  4. No Dock icon appears — app is menubar-only
**Plans**: 3 plans

Plans:
- [x] 01-01-PLAN.md — Xcode project scaffold, LSUIElement, NSStatusItem + NSPopover
- [ ] 01-02-PLAN.md — SwiftData ModelContainer, SMAppService Login Item, SettingsView
- [ ] 01-03-PLAN.md — Human verification of all Phase 1 success criteria

**UI hint**: yes

### Phase 2: Session Tracking Engine
**Goal**: The app silently watches Claude Code activity and accumulates accurate token counts per conversation and project
**Depends on**: Phase 1
**Requirements**: TRACK-01, TRACK-02, TRACK-03, TRACK-04
**Success Criteria** (what must be TRUE):
  1. A new Claude Code session is detected and recorded without any manual action from the user
  2. Input and output token counts for each conversation are stored persistently
  3. Token usage is grouped by project directory so different repos are tracked separately
  4. A rate-limit event during a Claude Code session is captured and logged as "Limit erreicht"
**Plans**: TBD

### Phase 3: Dashboard
**Goal**: The user can see their current and historical token usage at a glance from the menubar
**Depends on**: Phase 2
**Requirements**: DASH-01, DASH-02
**Success Criteria** (what must be TRUE):
  1. Opening the app shows the current total token count updated in realtime as a session runs
  2. User can switch the view between today, this week, and this month without restarting the app
  3. Usage is broken down visibly by project so the user can see which repo consumed the most tokens
**Plans**: TBD
**UI hint**: yes

### Phase 4: Budget & Alerts
**Goal**: The user can set a monthly token budget and receive warnings when approaching or hitting it
**Depends on**: Phase 3
**Requirements**: CONF-01, CONF-02, DASH-03
**Success Criteria** (what must be TRUE):
  1. User can enter a monthly token budget in settings and it persists across app restarts
  2. User can configure at least two warning thresholds (e.g. 50% and 80%) in settings
  3. A visible warning appears in the app when a threshold is crossed during an active session
  4. The menubar icon or badge reflects the alert state so the user notices without opening the app
**Plans**: TBD
**UI hint**: yes

### Phase 5: Liquid Glass Polish
**Goal**: The entire app looks and feels native on macOS 26 using Apple's Liquid Glass design language
**Depends on**: Phase 4
**Requirements**: UI-02
**Success Criteria** (what must be TRUE):
  1. All panels and popovers use Liquid Glass materials instead of plain system backgrounds
  2. The app passes visual inspection against macOS 26 native apps — no flat or inconsistent surfaces
  3. The app runs without deprecation warnings related to pre-26 APIs on a macOS 26 machine
**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. App Foundation | 0/3 | Not started | - |
| 2. Session Tracking Engine | 0/TBD | Not started | - |
| 3. Dashboard | 0/TBD | Not started | - |
| 4. Budget & Alerts | 0/TBD | Not started | - |
| 5. Liquid Glass Polish | 0/TBD | Not started | - |
