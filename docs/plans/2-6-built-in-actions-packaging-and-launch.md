# 2-6: Built-In Actions, Packaging, And Launch

**Parent:** [2-mvp-roadmap.md](2-mvp-roadmap.md)
**Status:** in progress
**Goal:** Ship the first coherent built-in action set with packaging, release docs, and MVP acceptance criteria.

## Context

The product is not ready when the architecture exists. It is ready when the same runtime can power a small but convincing action set through a clean install experience.

## Tasks

### 1. Built-In Actions

- [x] 1-1. `draft-response`
- [x] 1-2. `polish-draft`
- [x] 1-3. `explain`
- [x] 1-4. `summarize`
- [x] 1-5. `rewrite-friendly`
- [x] 1-6. `extract-action-items`
- [x] 1-7. `add-to-calendar`

### 2. Action Quality

- [x] 2-1. Write fixtures and smoke tests for each built-in action
- [ ] 2-2. Tune prompts and schemas for messy real-world text
- [x] 2-3. Verify all built-ins run through the same runtime path

### 3. Packaging And Distribution

- [x] 3-1. Define install flow
- [ ] 3-2. Define update path
- [x] 3-3. Add release-facing documentation

### 4. MVP Validation

- [ ] 4-1. Verify first-run setup from a clean machine
- [x] 4-2. Verify provider setup without file editing
- [ ] 4-3. Verify selected-text invocation in common apps
- [ ] 4-4. Verify review/apply flows for each built-in action

## Deliverables

- a coherent starter set of built-in actions across calendar, rewrite, response-drafting, explanation, and extraction
- release docs
- packaging/install story
- MVP validation checklist

## Decisions

- Calendar remains the wedge, but the MVP must clearly support more than one action class.
- All built-ins should demonstrate the platform pattern, not special cases.

## Risks

- shipping too many built-ins before the shared runtime is solid
- underestimating app-to-app variability for selected-text invocation

## Success Criteria

- the product can be honestly described as a selected-text native LLM action app, not a one-off calendar utility

## Current Remaining Gaps

- signed/notarized release validation on a machine with full Xcode and release credentials
- stronger fallback invocation than the current clipboard handoff
- broader manual validation across common macOS apps
