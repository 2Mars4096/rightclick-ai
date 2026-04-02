# 2-4: Native Host And Selected-Text Service

**Parent:** [2-mvp-roadmap.md](2-mvp-roadmap.md)
**Status:** in progress
**Goal:** Ship one native host app that owns selected-text invocation and feels invisible in daily use.

## Context

The product promise depends on not making users manually manage Quick Actions or Services.

## Tasks

### 1. App Shell

- [x] 1-1. Create the native macOS app target
- [x] 1-2. Add a small settings surface
- [x] 1-3. Add a lightweight action picker surface

### 2. Invocation

- [x] 2-1. Register one selected-text service entry point
- [x] 2-2. Pass selected text into the runtime
- [ ] 2-3. Add a stronger fallback invocation path

Current fallback:

- the native review window can import plain text from the clipboard when the Services menu is unavailable
- a true global hotkey path is still open work

### 3. Native Integration

- [ ] 3-1. Handle macOS permission prompts cleanly
- [ ] 3-2. Define logging and crash-reporting strategy for local debugging
- [ ] 3-3. Keep the app mostly invisible outside settings and review flows

### 4. Packaging

- [x] 4-1. Define app install/update path
- [x] 4-2. Plan signing and notarization
- [x] 4-3. Remove dependence on users editing native automation tools by hand

## Deliverables

- native host app
- selected-text entry point
- fallback hotkey path
- packaging plan

## Decisions

- One installed entry point is preferable to many visible menu items.
- The host should stay thin and delegate action logic to the runtime.

## Risks

- macOS Services behavior varies by app
- native integration details can expand scope quickly

## Success Criteria

- a normal user can install once and invoke selected-text actions without terminal setup
