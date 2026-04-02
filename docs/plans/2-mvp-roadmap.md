# 2: MVP Roadmap

**Status:** proposed
**Goal:** Ship the first real Right Click MVP for selected-text LLM actions on macOS.

## Context

The current repository already proves one wedge: selected text to calendar via a configurable LLM-backed Service.

The MVP needs to generalize that into a product:

- native host
- central provider management
- reusable action bundles
- safe preview/apply behavior

## MVP Boundary

See [../mvp-spec.md](../mvp-spec.md).

## Phase Structure

### Phase 1: Runtime Foundation

Plan: [2-1-runtime-and-cli-extraction.md](2-1-runtime-and-cli-extraction.md)

Objective:

- move core behavior out of the monolithic installer script
- preserve current calendar behavior through a reusable runtime and CLI

### Phase 2: Provider Center

Plan: [2-2-provider-center-and-secrets.md](2-2-provider-center-and-secrets.md)

Objective:

- centralize provider profiles and secrets
- stop treating credentials as action-local config

### Phase 3: Action Bundle System

Plan: [2-3-action-bundle-contract-and-loader.md](2-3-action-bundle-contract-and-loader.md)

Objective:

- define the action manifest contract
- make feature growth file-based and contributor-friendly

### Phase 4: Native Host And Invocation

Plan: [2-4-native-host-and-selected-text-service.md](2-4-native-host-and-selected-text-service.md)

Objective:

- replace manual workflow editing with one installed native entry point

### Phase 5: Review And Apply UX

Plan: [2-5-preview-apply-and-post-actions.md](2-5-preview-apply-and-post-actions.md)

Objective:

- make LLM actions safe and understandable for normal users

### Phase 6: Built-In Actions, Packaging, And MVP Exit

Plan: [2-6-built-in-actions-packaging-and-launch.md](2-6-built-in-actions-packaging-and-launch.md)

Objective:

- ship the built-in actions, installer, docs, and release-quality validation needed to call it an MVP

## Sequencing

Recommended order:

1. Phase 1
2. Phase 2
3. Phase 3
4. Phase 4
5. Phase 5
6. Phase 6

The host app should not harden around unstable bundle or provider contracts. That is why runtime, provider, and action contracts come first.

## Cross-Cutting Requirements

- preserve open-source friendliness
- support Codex/Cursor-assisted edits to action bundles
- keep the app mostly invisible during daily use
- keep side effects reviewable
- keep the current calendar prototype behavior mappable into the new architecture

## MVP Exit Criteria

- selected text works end to end through the native shell
- provider credentials are managed centrally
- action bundles are loaded from disk
- at least four actions ship through the same runtime
- preview/apply UX is in place for destructive or structured actions
- the product can be installed and used without manual Services editing
