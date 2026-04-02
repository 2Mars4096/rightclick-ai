# Action Bundles

## Purpose

Action bundles are the main extension surface for Right Click.

They exist so that:

- users do not have to hand-edit Quick Actions
- contributors can add features without touching native app code
- Codex and Cursor can safely scaffold and improve actions as files

## Design Rules

- Actions are folders on disk.
- Metadata lives in a manifest.
- Prompts live in files.
- Secrets never live in action bundles.
- Actions reference provider profiles by ID.

## Proposed Bundle Layout

```text
add-to-calendar/
  action.yaml
  prompt.md
  output.schema.json
  README.md
```

Optional extra files:

- `transform.js`
- `fixtures/`
- `icon.png`

## Manifest Shape

Example:

```yaml
id: add-to-calendar
title: Add to Calendar
description: Extract calendar events from selected text.
serviceName: Add to Calendar
serviceKind: calendar
inputKinds:
  - selected_text
provider: default
responseMode: structured_json
promptFile: prompt.md
outputSchema: output.schema.json
review:
  kind: event_form
postAction:
  kind: create_calendar_events
capabilities:
  destructive: true
  requiresReview: true
```

## Core Fields

- `id`
  - stable identifier
- `title`
  - user-facing name
- `description`
  - short summary
- `serviceName`
  - label for the direct macOS Service item when the action installs as a shortcut
- `serviceKind`
  - `calendar` for direct side effects like event creation, `clipboard` for actions that should copy text output immediately
- `inputKinds`
  - for example `selected_text`, later `image`, `file`, `url`
- `provider`
  - provider profile ID or `default`
- `responseMode`
  - `text` or `structured_json`
- `promptFile`
  - relative path to the prompt template
- `outputSchema`
  - JSON Schema file for structured outputs
- `review`
  - which native review UI to show
- `postAction`
  - what to do after approval

## Review Kinds

Likely first review kinds:

- `text_preview`
- `text_diff`
- `event_form`
- `generic_json_form`

## Post-Action Kinds

Likely first post-actions:

- `copy_to_clipboard`
- `replace_selection`
- `create_calendar_events`
- `save_file`

## Prompt Authoring

Prompt files should stay human-readable and easy to edit.

Inputs available to templates should be explicit, for example:

- selected text
- timezone
- locale
- source app when available
- user config relevant to the action

## Validation

The runtime or CLI should validate:

- required manifest fields
- unknown review/post-action kinds
- missing prompt/schema files
- schema compatibility with `responseMode`

Suggested future tooling:

- `rightclick validate`
- `rightclick scaffold-action`
- `rightclick reload-actions`

## Built-In Starter Actions

Recommended first built-ins:

- `add-to-calendar`
- `summarize`
- `rewrite-friendly`
- `extract-action-items`

## Why This Matters

This is the point where the product becomes open-source friendly.

Instead of asking users to:

- duplicate native services
- edit app internals
- add features in a custom in-app builder

we let them:

- open a folder
- edit a manifest and prompt
- reload

That is a better fit for contributors using normal tooling and AI coding assistants.
