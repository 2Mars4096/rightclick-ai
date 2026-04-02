# LLM API Guide

## Goal

LLM access should feel like shared app infrastructure, not feature-specific plumbing.

Users should set up providers once. Actions should consume provider profiles, not raw API keys.

## Provider Model

Each provider profile should include:

- `id`
- `type`
- `displayName`
- `baseURL` when applicable
- `authScheme`
- `defaultModel`
- `timeoutSeconds`
- `capabilities`

Supported provider types:

- `openai_compatible`
- `anthropic`
- `gemini`
- `ollama`
- `custom_command`

## Credential Management

Credentials should be stored centrally and securely:

- non-secret provider metadata in app config
- secrets in macOS Keychain

Actions should reference:

- `provider: default`
- or `provider: <provider-profile-id>`

They should never embed:

- raw API keys
- copied endpoints per action
- per-feature auth logic

## Request Contract

Every runtime request should normalize into a shared shape even if providers differ underneath.

Example logical request fields:

```yaml
provider: default
model: gpt-4.1-mini
input:
  kind: selected_text
  text: "Dinner with Alex tomorrow at 7pm at IFC Mall."
context:
  sourceApp: com.apple.mail
  locale: en-US
  timezone: Asia/Hong_Kong
action:
  id: add-to-calendar
  promptTemplate: prompt.md
  responseMode: structured_json
```

## Response Modes

The runtime should support a small number of normalized response modes.

### `text`

Use for:

- rewrite
- summarize
- translate
- explain

### `structured_json`

Use for:

- event extraction
- task extraction
- field mapping
- any action that needs a native review form

### `tool_result`

Use for:

- actions that call a local post-processor or side-effect adapter after model output normalization

## Reliability

The provider layer should own:

- request timeouts
- retries
- transient error classification
- fallback model policy
- response extraction across vendor formats

This is especially important because action bundles should not have to know the differences between:

- OpenAI chat-style payloads
- Anthropic message payloads
- Gemini content payloads
- custom local command wrappers

## Output Normalization

Actions should be able to require one of:

- plain text
- schema-validated JSON

For schema-validated actions:

- the runtime should validate the model response
- surface clear errors
- optionally retry with stronger formatting instructions

## Current Prototype Mapping

The current prototype already has the rough shape of a provider layer:

- OpenAI-compatible request builder
- Anthropic request builder
- Gemini request builder
- custom command hook
- mock provider for local smoke tests

The gaps are structural, not conceptual:

- settings still live in editable files
- the runtime still loads plain config from `settings.env` for non-secret values
- the native app now stores provider API keys centrally in Keychain
- provider hooks now serve a general action runtime rather than only the calendar flow

## Suggested Defaults

Recommended initial defaults:

- one user-selected `default` provider profile
- one lightweight default model for everyday text actions
- one stronger model override for extraction-heavy actions
- explicit capability flags for:
  - `supports_json`
  - `supports_vision`
  - `supports_tools`

## Local And Open-Source Friendly Adapters

`custom_command` should remain a first-class provider type.

That gives contributors a clean way to integrate:

- local proxies
- experimental wrappers
- private gateways
- offline models

without changing core runtime code for every variation.
