# Right Click Docs

This repo now contains both the original shell-based calendar prototype and a broader native macOS utility.

The product direction is now best described as:

- install once
- feel native on macOS
- make selected-text AI actions fast
- keep clipboard history local and reusable
- manage LLM providers and credentials centrally
- load file-based action bundles instead of making users edit Quick Actions by hand

## Doc Map

- [architecture.md](architecture.md)
  - Target system shape, component boundaries, and how the current prototype maps to the future app.
- [mvp-spec.md](mvp-spec.md)
  - The concrete MVP boundary: what ships, what is deferred, and what quality bar qualifies as "native enough".
- [development-plan.md](development-plan.md)
  - Product direction, design principles, build-vs-buy reasoning, and phased roadmap.
- [llm-api-guide.md](llm-api-guide.md)
  - Provider abstraction, credential management, request/response contracts, and future runtime behavior.
- [action-bundles.md](action-bundles.md)
  - File-based action format intended for open-source contribution and Codex/Cursor-assisted editing.
- [release.md](release.md)
  - Native app build, preflight, packaging, and the remaining signing/notarization boundary for MVP exit.
- [business/competitor-landscape.md](business/competitor-landscape.md)
  - The current market landscape for selected-text actions, right-click automation, and calendar extraction.
- [plans/1-native-right-click-ai-foundation.md](plans/1-native-right-click-ai-foundation.md)
  - First implementation plan for moving from the current shell-script prototype to a native reusable runtime.
- [plans/2-mvp-roadmap.md](plans/2-mvp-roadmap.md)
  - Parent roadmap for the first shippable selected-text MVP, with linked subplans.

## Working Style

- Keep stable product and architecture docs at the top level of `docs/`.
- Put concrete implementation slices in `docs/plans/`.
- Prefer file-based extension points over hidden settings or in-app builders.
- Optimize for contributors who may use Codex, Cursor, or direct edits to improve action bundles and runtime behavior.

## Current State

- `runtime/` contains the shared action runner used by both the shell prototype and the native app.
- `app/` contains the native selected-text macOS host and settings UI.
- the native app now includes local clipboard history plus a clipboard fallback path when Services are unavailable.
- provider settings can now be edited natively and API keys are stored in the macOS Keychain.
- `actions/` contains built-in file-based actions for summary, rewrite, draft-response, polish-draft, explanation, action-item extraction, and calendar creation.
- the current product hierarchy is intentional: `add-to-calendar`, `draft-response`, `polish-draft`, `explain`, and `summarize` are the core daily jobs, while `extract-action-items` and `rewrite-friendly` remain secondary utilities.
- the native installer currently exposes both the generic `RightClick AI` service and direct Services for the current built-in actions.
- live `Add to Calendar` runs now queue FIFO in the shared runtime so repeated invocations do not overlap.
- the clipboard workspace currently supports text, rich text, HTML, URLs, file references, images/screenshots, and colors for local preview/restore.
- `install.sh` still installs the legacy `Add to Calendar` workflow for shell/runtime validation.
- `scripts/build-native-app.sh` builds the native app bundle when full Xcode is available.
- `scripts/install-native-app.sh` installs the native app plus shared runtime without requiring manual Services setup.
- `scripts/release-preflight.sh` and `scripts/package-native-release.sh` validate and package the native app for handoff.
