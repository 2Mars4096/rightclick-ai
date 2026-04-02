# 2-3: Action Bundle Contract And Loader

**Parent:** [2-mvp-roadmap.md](2-mvp-roadmap.md)
**Status:** proposed
**Goal:** Define the file-based action format and load actions from disk.

## Context

This is the core extensibility mechanism for the open-source product.

The app should not need an internal feature builder just to let contributors add capabilities.

## Tasks

### 1. Manifest Contract

- [ ] 1-1. Define `action.yaml`
- [ ] 1-2. Define allowed `inputKinds`
- [ ] 1-3. Define `responseMode`, `review`, and `postAction` contracts
- [ ] 1-4. Define manifest versioning

### 2. Prompt And Schema Files

- [ ] 2-1. Support external prompt files
- [ ] 2-2. Support optional JSON Schema output validation
- [ ] 2-3. Define template variables available to prompts

### 3. Loader

- [ ] 3-1. Load built-in actions from a stable directory
- [ ] 3-2. Load user/community actions from a user-writable directory
- [ ] 3-3. Handle invalid bundles with clear error reporting

### 4. Contributor Tooling

- [ ] 4-1. Add action validation tooling
- [ ] 4-2. Add action scaffolding tooling
- [ ] 4-3. Add fixture support for action tests

## Deliverables

- manifest spec
- action loader
- validation tooling
- starter action bundle examples

## Decisions

- Action bundles are files first, not database records.
- Prompts should remain editable without recompiling the app.

## Risks

- overcomplicating the first manifest version
- coupling action format too tightly to one host UI

## Success Criteria

- contributors can add or change an action with normal file edits and validation tooling
