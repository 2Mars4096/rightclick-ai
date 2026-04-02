# Right Click

Current state: shared runtime plus a native macOS app shell for selected-text actions.

The longer-term direction is broader: install once, expose one native macOS right-click entry point, manage LLM providers centrally, and load open-source action bundles for selected text first, then files/images later.

## Docs

- [Docs Index](docs/README.md)
- [Architecture](docs/architecture.md)
- [MVP Spec](docs/mvp-spec.md)
- [Development Plan](docs/development-plan.md)
- [LLM API Guide](docs/llm-api-guide.md)
- [Action Bundles](docs/action-bundles.md)
- [Competitor Landscape](docs/business/competitor-landscape.md)
- [Plan: Native Right-Click AI Foundation](docs/plans/1-native-right-click-ai-foundation.md)
- [Plan: MVP Roadmap](docs/plans/2-mvp-roadmap.md)

## Current State

What exists today:

- shared action runtime under `runtime/`
- file-based built-in actions under `actions/`
- native macOS app shell under `app/RightClickApp`
- native provider settings UI with Keychain-backed API secrets
- native app now behaves like a menu bar utility instead of forcing the review window on launch
- native settings now let the user enable or disable launch at login
- clipboard fallback in the native review window for apps where Services are weak
- direct `Add to Calendar` service backed by the same shared runtime
- FIFO queueing for repeated live calendar runs through `right-click-calendar`
- legacy Quick Action installer retained for runtime smoke coverage

## Install

Preferred native install path:

```bash
./scripts/build-native-app.sh
./scripts/install-native-app.sh
```

`build-native-app.sh` builds `RightClickApp.app` into `./build/RightClickApp.app` when full Xcode is available. `install-native-app.sh` uses that bundle automatically, or you can point it at another bundle with `RCA_APP_BUNDLE=/path/to/RightClickApp.app`.

Release helpers:

```bash
./scripts/release-preflight.sh
./scripts/package-native-release.sh
```

The native installer:

- installs the shared runtime into `~/Library/Application Support/RightClickAI`
- copies the app bundle into `~/Applications/RightClick AI.app`
- refreshes macOS Services so the `RightClick AI` and `Add to Calendar` menu items appear in text-selection context menus
- installs a direct `Add to Calendar` Quick Action backed by the same `RightClickAI` runtime
- opens in-app settings on first launch if provider setup is still incomplete
- keeps the app available from the menu bar after setup
- falls back to an existing `RightClickCalendar` runtime path in the native app so older prototype installs still open cleanly

Legacy runtime + Quick Action install:

```bash
./install.sh
```

That path is still useful for the calendar-only prototype and local shell smoke tests. It installs `Add to Calendar` into `~/Library/Services/Add to Calendar.workflow`.

## Configure

Preferred path: open the installed app and use its Settings window. Provider API keys are stored in the macOS Keychain when saved from the native UI.

After setup, close the windows and leave the app running. It stays in the menu bar and can be reopened there when needed. Settings now also include a native launch-at-login toggle for keeping the app available after reboot and login.

The shared runtime settings file still lives at:

```bash
~/Library/Application\ Support/RightClickAI/settings.env
```

Main knobs:

- `PROVIDER=openai_compatible|anthropic|gemini|custom_command`
- model and endpoint fields for the provider you use
- `CALENDAR_NAME=` to target a specific Calendar calendar
- `DEFAULT_EVENT_DURATION_MINUTES=` for missing end times
- `TIMEZONE=` to steer relative-date parsing in the prompt
- `REQUEST_TIMEOUT_SECONDS=` to allow slower providers and larger extraction batches

For Moonshot and similar slower OpenAI-compatible providers, the current default is `120`.

In the native `RightClick AI` app, non-calendar text actions can also take a short optional instruction such as `keep it warm`, `focus on risks`, or `explain for a beginner`.

You can also edit the calendar extraction prompt directly in:

`~/Library/Application Support/RightClickAI/actions/add-to-calendar/prompt.txt`

The direct `Add to Calendar` service is the fastest current path for calendar use. It sends selected text through the shared runtime and, for live runs, queues requests FIFO so repeated invocations do not overlap.

## Custom Provider

Set:

```bash
PROVIDER=custom_command
CUSTOM_PROVIDER_COMMAND=/path/to/your-script
```

Your command receives the rendered prompt on `stdin` and must print either:

- raw model text containing a JSON object with `events`
- or normalized JSON directly

Expected JSON shape:

```json
{
  "events": [
    {
      "title": "Dinner with Alex",
      "start": "2026-04-01T19:00:00+08:00",
      "end": "2026-04-01T20:00:00+08:00",
      "allDay": false,
      "location": "IFC Mall",
      "notes": "",
      "calendar": ""
    }
  ],
  "reason": ""
}
```

For all-day events, use `YYYY-MM-DD` and make `end` the exclusive end date.

## Smoke Test

The consolidated smoke path avoids network calls and covers:

- shared runtime install
- built-in actions
- Keychain secret resolution fallback
- native app install path with a fake `.app` bundle
- release preflight and zip packaging with a fake `.app` bundle

```bash
./tests/smoke-install-self-test.sh
```
