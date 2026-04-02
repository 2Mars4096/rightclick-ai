# 2-1: Runtime And CLI Extraction

**Parent:** [2-mvp-roadmap.md](2-mvp-roadmap.md)
**Status:** proposed
**Goal:** Extract a reusable runtime and CLI from the current `install.sh` prototype.

## Context

Today, the provider calls, prompt rendering, normalization, and calendar side effect are all embedded in one installer-generated shell path.

That is good enough for a prototype and wrong for an extensible product.

## Tasks

### 1. Define Runtime Responsibilities

- [ ] 1-1. Split installer concerns from execution concerns
- [ ] 1-2. Define a stable runtime input contract for selected text
- [ ] 1-3. Define normalized runtime output types for:
  - [ ] text
  - [ ] structured JSON
  - [ ] post-action payloads

### 2. Extract Shared Modules

- [ ] 2-1. Move provider request logic into reusable adapters
- [ ] 2-2. Move prompt rendering into a reusable renderer
- [ ] 2-3. Move normalization into reusable validators/parsers
- [ ] 2-4. Move calendar creation into a post-action adapter

### 3. Preserve A CLI Surface

- [ ] 3-1. Add a CLI entry point for local smoke tests
- [ ] 3-2. Support `--dry-run` style execution for safe local verification
- [ ] 3-3. Support fixture-driven tests without touching Calendar

### 4. Maintain Backward Behavior

- [ ] 4-1. Keep the current `Add to Calendar` flow working through the new runtime
- [ ] 4-2. Keep existing prompt behavior mappable into the new action format
- [ ] 4-3. Preserve the mock-provider path for tests

## Deliverables

- reusable runtime module
- CLI wrapper
- tests for provider resolution and normalization
- `add-to-calendar` implemented through the extracted runtime

## Decisions

- The runtime should be host-agnostic enough to be called by both the app and CLI.
- The runtime should produce structured outputs before any native UI chooses how to display them.

## Risks

- Prematurely overengineering the runtime before the action contract stabilizes
- Breaking the calendar prototype during extraction

## Success Criteria

- the current calendar flow still works
- a second action can run through the same runtime without special casing
