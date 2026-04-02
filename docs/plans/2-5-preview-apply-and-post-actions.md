# 2-5: Preview, Apply, And Post-Actions

**Parent:** [2-mvp-roadmap.md](2-mvp-roadmap.md)
**Status:** proposed
**Goal:** Make action results safe, reviewable, and understandable before apply.

## Context

The app will often use LLM output to suggest changes or trigger side effects. The default posture must be reviewable, not blind.

## Tasks

### 1. Review Models

- [ ] 1-1. Define review modes for text preview, text diff, and structured forms
- [ ] 1-2. Map review modes from action manifests
- [ ] 1-3. Handle parse failures and partial outputs clearly

### 2. Apply Models

- [ ] 2-1. Implement clipboard copy
- [ ] 2-2. Implement replace-selection behavior where feasible
- [ ] 2-3. Implement calendar creation through a post-action adapter

### 3. Safety Rules

- [ ] 3-1. Require review for destructive or side-effecting actions
- [ ] 3-2. Define which simple actions may allow one-click apply
- [ ] 3-3. Keep logs or error surfaces clear enough for support and debugging

### 4. UX Quality

- [ ] 4-1. Keep review surfaces compact and native
- [ ] 4-2. Avoid exposing raw model payloads unless debugging
- [ ] 4-3. Preserve user trust with predictable apply behavior

## Deliverables

- review UI contract
- apply adapters
- safety rules for side effects

## Decisions

- Structured actions should render native forms, not raw JSON.
- Safety and clarity matter more than shaving one extra click from the flow.

## Risks

- replace-selection support may vary by source app
- review surfaces can become too generic or too special-cased

## Success Criteria

- users can understand what will happen before results are applied
