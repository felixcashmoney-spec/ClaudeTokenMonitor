# Phase 1: App Foundation - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-03-26
**Phase:** 01-App Foundation
**Mode:** assumptions
**Areas analyzed:** App Architecture, Data Layer, Login Item, Project Setup

## Assumptions Presented

### App Architecture
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| SwiftUI App Lifecycle with menubar-only presence | Confident | PROJECT.md: native macOS, SwiftUI; ROADMAP.md: no Dock icon |
| NSPopover for menubar interaction | Likely | Standard macOS menubar pattern; ROADMAP.md allows popover or window |

### Data Layer
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| SwiftData for local persistence | Likely | macOS 26+ target; simpler than Core Data |
| Set up container in Phase 1 | Likely | Avoids retrofit in Phase 2 |

### Login Item
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| SMAppService for auto-start | Confident | Modern API, App Store compatible |

### Project Setup
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Xcode project, deployment target macOS 26.0 | Confident | Liquid Glass requires macOS 26 |

## Corrections Made

No corrections — all assumptions confirmed (auto mode).

## Auto-Resolved

No Unclear assumptions — all Confident or Likely, no resolution needed.
