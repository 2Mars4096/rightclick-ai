# 2-2: Provider Center And Secrets

**Parent:** [2-mvp-roadmap.md](2-mvp-roadmap.md)
**Status:** proposed
**Goal:** Centralize provider profiles, defaults, and Keychain-backed credentials.

## Context

The product is LLM-adapted by design. That means provider setup is infrastructure, not a per-feature afterthought.

## Tasks

### 1. Provider Profile Model

- [ ] 1-1. Define provider profile fields for type, endpoint, model, timeout, and capabilities
- [ ] 1-2. Support profile IDs and one default profile
- [ ] 1-3. Define profile serialization for non-secret values

### 2. Secret Storage

- [ ] 2-1. Store secrets in macOS Keychain
- [ ] 2-2. Remove raw secrets from plain-text action config
- [ ] 2-3. Define secret update and rotation behavior

### 3. Provider Families

- [ ] 3-1. OpenAI-compatible
- [ ] 3-2. Anthropic
- [ ] 3-3. Gemini
- [ ] 3-4. custom command
- [ ] 3-5. keep room for local providers such as Ollama after MVP

### 4. Runtime Resolution

- [ ] 4-1. Let actions reference `default` or a named provider profile
- [ ] 4-2. Resolve provider capability mismatches early
- [ ] 4-3. Add timeout and retry defaults at the provider level

### 5. Settings UX

- [ ] 5-1. Add a simple native settings view for provider profiles
- [ ] 5-2. Add connection-test or validation feedback
- [ ] 5-3. Make it possible to finish setup without editing files by hand

## Deliverables

- provider profile model
- Keychain-backed secret storage
- native provider settings UI
- runtime provider resolution

## Decisions

- `custom_command` remains first-class for open-source and local experimentation.
- Actions must not own raw API credentials.

## Risks

- provider-specific behavior leaking back into action bundles
- underestimating the amount of UX needed for provider setup validation

## Success Criteria

- a user can configure a provider once and reuse it across all built-in actions
