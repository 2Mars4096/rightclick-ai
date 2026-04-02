# 1: Native Right-Click AI Foundation

**Status:** proposed
**Goal:** Replace the current one-off `Add to Calendar` Service installer with a reusable native macOS shell and runtime foundation for selected-text LLM actions.

## Context

The current repo proves the core value:

- selected text can be passed from macOS into a local runner
- provider calls can be abstracted behind a small adapter layer
- model output can be normalized and applied to a concrete side effect

But the current shape does not scale:

- one generated Automator workflow
- file-edited settings
- one purpose-built action path

This plan creates the foundation for a general native product.

## Tasks

### 1. Extract The Runtime Boundary

- [ ] 1-1. Separate provider logic, prompt rendering, normalization, and side-effect application into a reusable runtime module instead of keeping everything inside `install.sh`
- [ ] 1-2. Preserve a CLI entry point for local testing and smoke tests
- [ ] 1-3. Keep the existing `Add to Calendar` behavior working through the new runtime boundary

### 2. Introduce A Native Host App

- [ ] 2-1. Create a signed macOS app target that installs once and owns the selected-text service entry point
- [ ] 2-2. Replace the generated Automator workflow path with a native invocation path where possible
- [ ] 2-3. Add a fallback invocation path for apps where Services support is weak

### 3. Build The Provider Center

- [ ] 3-1. Define provider-profile storage for non-secret settings
- [ ] 3-2. Move API credentials into Keychain
- [ ] 3-3. Support at least these provider families:
  - [ ] OpenAI-compatible
  - [ ] Anthropic
  - [ ] Gemini
  - [ ] custom command
- [ ] 3-4. Define default provider and default model behavior

### 4. Define The Action-Bundle Contract

- [ ] 4-1. Create `action.yaml` manifest schema
- [ ] 4-2. Support prompt files and optional JSON Schema output validation
- [ ] 4-3. Load action bundles from a stable on-disk folder
- [ ] 4-4. Add validation/reload tooling for contributors

### 5. Add Native Review UX

- [ ] 5-1. Text preview for simple text actions
- [ ] 5-2. Diff preview for rewrite actions
- [ ] 5-3. Structured form review for calendar/event extraction
- [ ] 5-4. Clear approval step before destructive post-actions

### 6. Ship The First Generalized Action Set

- [ ] 6-1. `add-to-calendar`
- [ ] 6-2. `summarize`
- [ ] 6-3. `rewrite-friendly`
- [ ] 6-4. `extract-action-items`

### 7. Migration And Verification

- [ ] 7-1. Keep a migration path from the current shell-script prototype
- [ ] 7-2. Add smoke tests for provider resolution and action validation
- [ ] 7-3. Add end-to-end tests for selected-text invocation where feasible

## Priority And Sequencing

Recommended order:

1. runtime extraction
2. provider center
3. action-bundle contract
4. native host shell
5. review UX
6. broader starter actions

This order keeps the extensibility model stable before the native shell hardens around it.

## Decisions

- One installed entry point is the product surface. Actions are internal bundles, not separate Services.
- The app should not depend on an internal feature-builder UI for extensibility.
- `custom_command` remains first-class to support local and experimental adapters.
- Calendar stays the first built-in action, but not the product boundary.

## Notes

- The current `install.sh` remains useful as a behavioral reference and migration artifact even if it is not the final packaging story.
- The architecture should optimize for contributors who will edit prompts/manifests with normal tools and AI coding assistants.
- Native macOS feel matters more than maximizing the number of visible menu items.
