# Phase 1: App Foundation - Context

**Gathered:** 2026-03-26 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

A running macOS app the user can open, that lives in the menubar and starts automatically with macOS. Delivers UI-01 (native SwiftUI), CONF-03 (autostart), CONF-04 (menubar icon). No tracking, no dashboard — just the shell.

</domain>

<decisions>
## Implementation Decisions

### App Architecture
- **D-01:** SwiftUI App Lifecycle — use `@main` App struct, not AppDelegate-based
- **D-02:** Menubar-only app — set LSUIElement = true (no Dock icon)
- **D-03:** NSPopover for menubar interaction — clicking the status item opens a popover, not a separate window

### Data Layer
- **D-04:** SwiftData for local persistence (macOS 26 native) — will store token sessions in later phases
- **D-05:** Set up SwiftData container in Phase 1 even though tracking comes in Phase 2 — avoids retrofit

### Login Item
- **D-06:** SMAppService (ServiceManagement framework) for auto-start registration
- **D-07:** Toggle in settings to enable/disable auto-start

### Project Setup
- **D-08:** Xcode project with Swift Package Manager, deployment target macOS 26.0
- **D-09:** App name: "Claude Token Monitor" with bundle ID com.felixleis.claude-token-monitor

### Claude's Discretion
- Exact popover dimensions and initial placeholder content
- App icon design (menubar status item icon)
- Internal folder/target structure within Xcode project

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

No external specs — requirements fully captured in decisions above.

Project-level references:
- `.planning/PROJECT.md` — Core value, constraints, key decisions
- `.planning/REQUIREMENTS.md` — UI-01, CONF-03, CONF-04 requirements
- `.planning/ROADMAP.md` §Phase 1 — Success criteria (4 items)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None — greenfield project, no existing code

### Established Patterns
- None yet — Phase 1 establishes the patterns

### Integration Points
- Phase 2 will integrate session tracking into the SwiftData container set up here
- Phase 3 will build dashboard views into the popover established here

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches.

</specifics>

<deferred>
## Deferred Ideas

None — analysis stayed within phase scope.

</deferred>

---

*Phase: 01-app-foundation*
*Context gathered: 2026-03-26*
