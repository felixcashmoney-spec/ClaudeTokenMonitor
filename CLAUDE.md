<!-- GSD:project-start source:PROJECT.md -->
## Project

**Claude Token Monitor**

Eine native macOS App im Apple Liquid Glass Design, die den Token-Verbrauch von Claude Code in Echtzeit trackt. Die App läuft im Hintergrund, beobachtet Claude Code Sessions, zählt Tokens mit und zeigt ein Dashboard mit Verbrauchsstatistiken, Trends und Warnungen.

**Core Value:** Der Nutzer hat jederzeit volle Transparenz über seinen Claude Code Token-Verbrauch und wird gewarnt, bevor er seine selbst gesetzten Limits erreicht.

### Constraints

- **Platform**: macOS only — native App mit SwiftUI und Liquid Glass
- **OS Version**: macOS 26+ (Tahoe) für Liquid Glass Support
- **Datenquelle**: Claude Code Session-Daten, kein offizieller API-Endpoint
- **Limit-Definition**: Nutzer setzt manuell, da kein exaktes Pro Plan Token-Limit bekannt
<!-- GSD:project-end -->

<!-- GSD:stack-start source:STACK.md -->
## Technology Stack

Technology stack not yet documented. Will populate after codebase mapping or first phase.
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
