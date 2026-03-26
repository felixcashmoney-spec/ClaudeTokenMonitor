# Requirements: Claude Token Monitor

**Defined:** 2026-03-26
**Core Value:** Der Nutzer hat jederzeit volle Transparenz über seinen Claude Code Token-Verbrauch und wird gewarnt, bevor er seine selbst gesetzten Limits erreicht.

## v1 Requirements

### Session Tracking

- [ ] **TRACK-01**: App erkennt laufende Claude Code Sessions automatisch
- [ ] **TRACK-02**: Input/Output Tokens werden pro Conversation mitgezählt
- [ ] **TRACK-03**: Rate-Limiting Events werden als "Limit erreicht" geloggt
- [ ] **TRACK-04**: Token-Verbrauch wird nach Projekt/Verzeichnis gruppiert

### Dashboard

- [ ] **DASH-01**: Echtzeit-Anzeige des aktuellen Token-Verbrauchs
- [ ] **DASH-02**: Verbrauchsansicht nach Tag/Woche/Monat filterbar
- [ ] **DASH-03**: Warnung wenn konfigurierbare Budget-Schwellenwerte erreicht werden

### Einstellungen

- [ ] **CONF-01**: Nutzer kann eigenes monatliches Token-Budget setzen
- [ ] **CONF-02**: Konfigurierbare Warnschwellen (z.B. 50%, 80%)
- [ ] **CONF-03**: App startet automatisch mit macOS (Login Item)
- [ ] **CONF-04**: Menubar-Icon mit Schnellzugriff auf Dashboard

### UI/Design

- [ ] **UI-01**: Native macOS App mit SwiftUI
- [ ] **UI-02**: Apple Liquid Glass Design (macOS 26+)

## v2 Requirements

### Analytics

- **ANLYT-01**: Trend-Grafiken über Zeit (Durchschnitt, Peaks)
- **ANLYT-02**: Durchschnittsverbrauch pro Conversation
- **ANLYT-03**: Export von Verbrauchsdaten (CSV)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Automatisches Blocking/Sperren | Nur Warnungen, kein Hard Stop — Nutzer will informiert werden, nicht eingeschränkt |
| Claude Web-App Tracking | Nur Claude Code (Terminal) |
| API-basierte Dollar-Abrechnung | Pro Plan hat keine Token-basierte Abrechnung |
| "Unnötiges Spending" erkennen | Zu vage, bewusst entfernt |
| Offizielles Anthropic API Limit-Abfrage | Existiert nicht für Pro Plan |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| TRACK-01 | TBD | Pending |
| TRACK-02 | TBD | Pending |
| TRACK-03 | TBD | Pending |
| TRACK-04 | TBD | Pending |
| DASH-01 | TBD | Pending |
| DASH-02 | TBD | Pending |
| DASH-03 | TBD | Pending |
| CONF-01 | TBD | Pending |
| CONF-02 | TBD | Pending |
| CONF-03 | TBD | Pending |
| CONF-04 | TBD | Pending |
| UI-01 | TBD | Pending |
| UI-02 | TBD | Pending |

**Coverage:**
- v1 requirements: 13 total
- Mapped to phases: 0
- Unmapped: 13 ⚠️

---
*Requirements defined: 2026-03-26*
*Last updated: 2026-03-26 after initial definition*
