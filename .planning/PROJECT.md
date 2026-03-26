# Claude Token Monitor

## What This Is

Eine native macOS App im Apple Liquid Glass Design, die den Token-Verbrauch von Claude Code in Echtzeit trackt. Die App läuft im Hintergrund, beobachtet Claude Code Sessions, zählt Tokens mit und zeigt ein Dashboard mit Verbrauchsstatistiken, Trends und Warnungen.

## Core Value

Der Nutzer hat jederzeit volle Transparenz über seinen Claude Code Token-Verbrauch und wird gewarnt, bevor er seine selbst gesetzten Limits erreicht.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] App läuft im Hintergrund und trackt Claude Code Sessions automatisch
- [ ] Echtzeit-Dashboard zeigt aktuellen Token-Verbrauch (Gesamt vs. Limit, Tag/Woche/Monat)
- [ ] Durchschnittsverbrauch pro Conversation, pro Tag, Trend über Zeit
- [ ] Warnungen wenn konfigurierbare Schwellenwerte erreicht werden (z.B. 80% des Monatslimits)
- [ ] Verbrauch gruppiert nach Projekt oder Aufgabentyp
- [ ] Nutzer kann eigenes monatliches Token-Budget setzen
- [ ] Rate-Limit-Erkennung wird geloggt als "Limit erreicht"
- [ ] Native macOS App im Apple Liquid Glass Design (macOS 26+)

### Out of Scope

- Automatisches Blocking/Sperren von Claude Code — nur Warnungen, kein Hard Stop
- "Unnötiges Spending" erkennen — zu vage, bewusst entfernt
- Tracking der Claude Web-App — nur Claude Code (Terminal)
- API-basierte Dollar-Abrechnung — Pro Plan hat keine Token-basierte Abrechnung
- Offizielles Anthropic API Limit-Abfrage — existiert nicht für Pro Plan

## Context

- Nutzer ist auf dem Claude Pro Plan
- Anthropic stellt keine offizielle API für Pro Plan Verbrauchsdaten bereit
- Token-Counts kommen aus Claude Code Session Logs / Conversation-Daten
- Die App muss Tokens selbst mitzählen, da keine externe Datenquelle verfügbar ist
- Rate-Limiting durch Anthropic kann als Proxy für "Limit erreicht" genutzt werden
- Liquid Glass Design erfordert macOS 26 (Tahoe) — neues Apple Design-System

## Constraints

- **Platform**: macOS only — native App mit SwiftUI und Liquid Glass
- **OS Version**: macOS 26+ (Tahoe) für Liquid Glass Support
- **Datenquelle**: Claude Code Session-Daten, kein offizieller API-Endpoint
- **Limit-Definition**: Nutzer setzt manuell, da kein exaktes Pro Plan Token-Limit bekannt

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Selbst mitzählen statt API | Kein offizieller Anthropic-Endpoint für Pro Plan Verbrauch | — Pending |
| Nur Warnungen, kein Blocking | Nutzer will informiert werden, nicht eingeschränkt | — Pending |
| Native macOS statt Web | Nutzer will eine "richtige" Mac App im Liquid Glass Design | — Pending |
| Manuelles Budget statt automatisch | Pro Plan hat kein festes Token-Limit, Nutzer setzt eigenes Ziel | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-03-26 after initialization*
