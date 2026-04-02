# Architecture

## Overview

Right Click should become a thin native macOS shell around a reusable local action runtime.

The shell is responsible for invocation, permissions, native UI, and central settings.
The runtime is responsible for action loading, provider calls, validation, preview, and post-actions.

The key design choice is:

- install one native entry point
- load many actions from files
- manage provider credentials once

Not:

- one Automator workflow per feature
- one API key per action
- one hidden script per use case

## Product Shape

Primary flow:

1. User selects text in any app that supports macOS Services.
2. User right-clicks and chooses `RightClick AI`.
3. The native host passes the selected text into the local runtime.
4. The runtime loads the chosen action bundle.
5. The runtime resolves the configured provider profile and calls the model.
6. The app shows a native review step if the action requires it.
7. The app applies the result by copying, replacing text, creating a calendar event, or another side effect.

## Core Components

### 1. Native Host

Responsibilities:

- install once as a signed and notarized macOS app
- expose one selected-text service entry point
- optionally expose a fallback global hotkey
- show native picker, preview, and settings windows
- request macOS permissions only when needed

Likely implementation:

- Swift app
- AppKit for Services integration
- SwiftUI for settings and preview surfaces

### 2. Local Runtime

Responsibilities:

- accept normalized input from the host
- load action bundles from disk
- render prompts
- call provider adapters
- validate model output
- return structured preview/apply payloads to the host

The runtime should be usable both from the app and from a CLI for testing.

### 3. Provider Layer

Responsibilities:

- central provider registry
- shared auth and endpoint config
- request normalization across providers
- capability detection: text, JSON, vision, tool use
- retries, timeouts, and fallback model policy

Target provider families:

- OpenAI-compatible
- Anthropic
- Gemini
- local runtimes such as Ollama
- custom command adapters

### 4. Action Bundle Registry

Responsibilities:

- load actions from a known folder
- validate manifests
- expose built-in and user-contributed actions
- separate prompt/config metadata from runtime code

This is the main extensibility point for open-source contributors.

### 5. Preview And Apply Layer

Responsibilities:

- present text diffs and structured forms before apply
- prevent silent destructive side effects
- standardize post-actions such as copy, replace, calendar create, file write

The review model should be generic enough to support:

- text rewrite
- structured extraction
- side-effect confirmation

## Data Flow

### Selected Text Action

1. Host captures selected text.
2. Host sends:
   - input payload
   - action ID
   - current app context when available
3. Runtime loads action manifest and prompt template.
4. Runtime resolves provider profile.
5. Runtime executes provider request.
6. Runtime normalizes output into one of:
   - plain text result
   - structured JSON result
   - side-effect command payload
7. Host renders review UI.
8. Host applies the approved result.

## Design Principles

- Native first: macOS should feel like the host, not a wrapper around Automator editing.
- Invisible by default: install once, then reuse.
- One control plane for LLM settings: credentials and provider defaults live in one place.
- File-based extensibility: features are bundles on disk, not rows hidden in app state.
- Open-source friendly: contributors should be able to improve actions with normal file edits and Codex/Cursor.
- Safe by default: no side effects without validation and, when appropriate, preview.

## Current Prototype Mapping

The current repo already contains useful pieces of the future runtime:

- `install.sh` installs a selected-text Service.
- `scripts/install-native-app.sh` installs the native app plus shared runtime from a built app bundle.
- provider adapters exist for OpenAI-compatible, Anthropic, Gemini, mock, and custom-command backends
- prompt rendering and output normalization already exist
- Apple Calendar write-back exists for one specific action
- a native macOS host app exists under `app/`
- provider settings can be edited natively and secrets are persisted in Keychain
- built-in non-calendar actions already run through the shared runtime

What is still missing:

- signed native host app
- release-grade packaging and updater flow
- richer preview/apply surfaces such as diff and structured editors
- broader action coverage beyond the initial built-ins

## Proposed Future Repo Shape

One possible target layout:

```text
RightClick/
  README.md
  docs/
  app/
    RightClickApp/
  runtime/
    rightclick-runtime/
  actions/
    summarize/
    rewrite-friendly/
    add-to-calendar/
  tools/
    validate-action
    scaffold-action
```

This repo does not need to move there immediately, but the docs assume that direction.
