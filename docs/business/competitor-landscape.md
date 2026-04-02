# Competitor Landscape — Right Click

**Last updated:** 2026-04-01

## Executive Summary

The generic idea already exists:

- selected text actions
- right-click text tools
- browser-based AI transformations

The sharper opportunity is narrower:

- native macOS
- install once
- selected text first
- LLM-provider-aware
- centrally managed credentials
- file-based open-source action extensibility

That exact combination still looks underbuilt.

## Category 1: Browser-First Selected-Text AI

Representative products:

- Prompt Selected
- Easy Add to Calendar
- highlight2calendar

What they prove:

- people want to act on selected text quickly
- calendar extraction is a real use case
- custom prompts on selected text are understandable to users

Where they stop short:

- browser-only or browser-first
- not a native macOS right-click platform
- limited reuse outside the browser
- weak fit for "install once and use across apps"

## Category 2: macOS Text-Action Frameworks

Representative products:

- PopClip
- Alfred Universal Actions
- Shortcuts / Services
- Raycast

What they prove:

- macOS users accept lightweight invocation from selected text
- packaging, settings, and extension models can be clean
- one host can support many actions

Where they stop short:

- they are platforms or power-user tools, not this product
- LLM provider management is not the center of the UX
- they do not give a native right-click-first open-source action runtime out of the box

## Category 3: Native Calendar Extraction Tools

Representative products:

- Text 2 Calendar
- browser extensions that extract events from highlighted text

What they prove:

- "text to event" is a good wedge
- preview before save matters
- structured extraction is easier to explain than generic AI tooling

Where they stop short:

- usually one-purpose
- not a broader selected-text action platform
- limited extensibility

## Build Vs Reuse Conclusion

The right position is:

- reuse macOS invocation primitives
- reuse proven ideas from PopClip, Raycast, and browser tools
- own the native shell, provider center, and action-bundle runtime

Do not depend on:

- manual Quick Action editing
- users stitching together third-party power-user tools
- a browser-only UX if the goal is native reuse

## Strategic Positioning

The product should be framed less as:

- a calendar extractor

and more as:

- native LLM actions for selected text on macOS

with calendar extraction as the first strong built-in action.

## Product Implications

- The app must install cleanly and disappear into normal workflows.
- Provider setup must happen once.
- Contributors should extend behavior via files, not hidden UI state.
- The first-party experience should feel native even if actions are open-source and editable.
