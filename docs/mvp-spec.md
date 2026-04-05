# MVP Spec

## Goal

Ship a native-feeling macOS app that lets a user install once, select text in normal apps, right-click, run LLM-backed actions quickly, and fall back to a built-in local clipboard workspace when needed.

The MVP is not "generic right click everything." It is "selected text done well enough to feel real."

## MVP User Promise

After one install, a user should be able to:

- select text in supported macOS apps
- right-click and invoke `RightClick AI`, with direct built-in shortcuts for common actions
- choose from a small built-in action set
- use a centrally configured LLM provider without per-action setup
- use fast direct actions for common jobs and the native review window for guided runs
- reuse recent clipboard items locally through the same app
- reuse the feature without touching Automator, Shortcuts, or config files by hand

## In Scope

### Invocation

- one native app install
- one selected-text service entry point plus direct built-in shortcuts for core actions
- one fallback invocation path such as a global hotkey

### Provider Management

- central provider settings
- Keychain-backed secrets
- support for:
  - OpenAI-compatible
  - Anthropic
  - Gemini
  - custom command

### Action System

- file-based action bundles
- built-in bundle validation
- runtime loading from disk

### Review And Apply

- text preview for simple actions
- diff preview for rewrites
- structured review for calendar extraction
- direct quick mode for actions that are safe to copy or create immediately

### Clipboard

- local clipboard history
- search and restore
- pin and favorite
- privacy defaults for sensitive sources and likely secrets
- initial non-text preview/restore support

### Built-In Actions

- core:
  - add-to-calendar
  - draft-response
  - polish-draft
  - explain
  - summarize
- secondary:
  - extract-action-items
  - rewrite-friendly

## Explicitly Out Of Scope For MVP

- multimodal AI actions for images and figures
- Finder-driven file and folder workflows
- in-app natural-language feature generation
- public plugin marketplace
- cloud sync
- advanced enterprise policy controls
- full "right click everything" object coverage

## Quality Bar

The MVP should feel:

- installable by a normal macOS user
- reusable without terminal work after setup
- safe enough that side effects are reviewable
- open-source friendly for contributors

## Suggested UX Flow

1. Install app.
2. Open settings once to configure provider credentials.
3. Select text in an app.
4. Right-click and choose `RightClick AI`, or use a direct pinned shortcut such as `Add to Calendar`.
5. Either:
   - run a direct shortcut and get the result immediately
   - or open the native review window and pick an action there.
6. Review output when the action needs guidance or confirmation.
7. Apply.

## Technical Bar

- no manual Quick Action editing
- no per-action credential duplication
- no action definitions hidden only in app state
- no mandatory internet dependency for action authoring
- local smoke-testable runtime

## MVP Success Criteria

- a new user can complete setup without touching `install.sh`
- at least four built-in actions work through the same runtime
- action bundles can be edited as files and reloaded
- provider settings are stored centrally and secrets stay out of plain config
- the calendar flow works through the generalized runtime rather than a one-off script path
- the clipboard fallback path is usable without separate tooling or a second app

## Current Delta To MVP

The repo is close, but the remaining gap is not feature breadth. It is release confidence:

- validate the signed/notarized distribution path on a machine with full Xcode and Apple release credentials
- tighten the non-Service fallback path beyond the current clipboard import flow
- finish broader real-app validation for selected-text invocation and review/apply behavior
