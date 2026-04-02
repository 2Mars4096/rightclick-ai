# Right Click Development Plan

## Vision

Build a native macOS utility that makes "select text, right-click, do something smart" feel built in.

The first serious use case is calendar extraction, but the product should not be limited to calendar actions. The platform should support selected-text LLM actions broadly, then expand to files, URLs, images, and other right-clickable objects.

## Product Principles

- Install once.
- Reuse everywhere.
- Feel native.
- Hide complexity from normal users.
- Keep extensibility in files, not in a complicated in-app feature builder.
- Treat LLM credentials as shared infrastructure, not per-feature setup.

## What We Are Building

We are building:

- one native right-click entry point
- one local runtime
- one provider settings surface
- many file-based action bundles

We are not building:

- a generic automation builder UI inside the app
- one Automator workflow per action
- a browser-only extension
- a power-user-only tool that requires manual Services editing

## Build Vs Buy

### Existing Tools Are Useful References

- PopClip proves that selected-text actions can feel lightweight and native.
- Raycast proves that central preferences, secrets, and extension packaging can feel clean.
- Shortcuts and Services prove that macOS already has the invocation surface.
- browser extensions such as Prompt Selected and calendar extractors prove the demand.

### Existing Tools Are Not The Product

They do not give the full package we want:

- native right-click-first flow
- one-time install for normal users
- central LLM provider center
- reusable open-source action bundles
- consistent preview/apply behavior across actions

So the right move is:

- reuse native macOS invocation primitives
- own the product shell and runtime

## Key Decisions

### 1. One Entry Point, Many Actions

Do not register one Quick Action per feature.

Instead:

- install one entry point such as `RightClick AI`
- let the app choose from actions internally

### 2. File-Based Action Bundles

Do not make action authoring depend on an internal visual builder.

Instead:

- store actions as folders on disk
- use manifests, prompt files, and optional schemas
- let Codex, Cursor, and contributors edit those files directly

### 3. Central Provider Management

Do not store credentials in each action.

Instead:

- define provider profiles once
- store secrets in Keychain
- let actions reference providers by ID

### 4. Preview Before Side Effects

LLM output should not directly mutate user data without review when the action is non-trivial.

Examples:

- text rewrite: show diff or replace/copy choice
- extraction: show editable form
- calendar: show event draft before create

## Roadmap

### Phase 0: Current Prototype

Current repo status:

- selected text Service via `install.sh`
- native app shell under `app/`
- shared runtime plus file-based actions
- provider scripts for multiple LLM vendors
- native provider settings surface with Keychain-backed secrets
- prompt rendering and event normalization

### Phase 1: Native Foundation

- replace generated Automator install flow with a signed native app
- expose one selected-text service entry point
- keep the runtime callable locally for tests
- preserve existing calendar prototype behavior through the new shell

### Phase 2: Provider Center

- build a native settings surface for provider profiles
- move secrets to Keychain
- support default provider/model selection
- keep the existing provider families working

### Phase 3: Action Bundle Runtime

- define the manifest schema
- load actions from disk
- add validation and reload tooling
- ship a few built-in actions beyond calendar:
  - summarize
  - rewrite
  - extract action items

### Phase 4: Generic Preview/Apply UX

- text diff preview
- structured form preview
- side-effect confirmation path

### Phase 5: Broader Input Types

- files
- URLs
- images/figures
- Finder items

## Open Questions

- How much should the right-click menu show directly versus opening a compact picker?
- Should the runtime live in-process with the app or as a local helper/daemon?
- How should signed built-in actions and unsigned community actions be distinguished?
- When app context is weak, what metadata should be passed into prompts by default?

## Immediate Next Step

The first implementation plan is in [plans/1-native-right-click-ai-foundation.md](plans/1-native-right-click-ai-foundation.md).
