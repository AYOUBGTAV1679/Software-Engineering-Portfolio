# RP Respond AI — Threaded Chat API Integration

## Overview

RP Respond AI connects a Lua client script to a remote language-model API and presents generated responses through a chat-oriented interface. Its central engineering constraint is that the host script loop is cooperative: waiting for a network response in that loop would delay UI and runtime updates.

The script moves HTTP work into a worker created through the `lanes` threading library. Results are returned through a thread-safe Linda channel and polled by the main script, which handles the UI update after the response is ready.

## Request flow

1. The main script builds a prompt from the current interaction, character settings, and recent context.
2. It serializes the request using the fields required by the configured provider API.
3. A worker thread performs the HTTP request outside the main loop.
4. The worker sends the response or an error through a Linda channel.
5. The main script polls for completion and parses the response before updating the interface.

## Implemented features

- Background HTTP requests so network waits do not run directly in the main script loop.
- Character/context configuration and a bounded conversation context.
- Local history, saved replies, and reusable knowledge-base entries.
- A bounded response cache for repeated prompts, scoped by provider and model so results from different backends are not mixed.
- Manual provider selection between Groq and OpenRouter.
- Model rotation within the selected provider after recognized rate-limit or model-availability errors.
- UI windows and commands for chat, character settings, knowledge bases, saved replies, and history.
- A focused JSON response extractor for the response fields consumed by this script.

Provider selection is manual; the implementation does not automatically fail over from one provider to the other. Model rotation is limited to the model list for the provider currently selected. Each request retains the provider and model it started with; a late error only rotates the model when that same selection is still active, so switching providers while a request is pending cannot redirect its endpoint/key or mutate the newly selected provider's model.

## Provider configuration

The provider keys are constants near the top of `threaded_ai_chat_api.lua`:

```lua
local API_KEY = "YOUR_GROQ_KEY_HERE"
local API_KEY_OR = ""
```

Replace the placeholders in a local working copy only. Do not commit real API keys or publish a populated copy of the script. The default provider is Groq. If `USE_OR` is enabled directly in the configuration, the initial model is selected from the OpenRouter model list; otherwise the initial model comes from Groq. At runtime, use `/jrpor or` to select OpenRouter after configuring its key, or `/jrpor groq` to return to Groq.

The script requires a valid key for the selected provider, the selected model to remain available, and network access to the service.

## Commands

| Command | Purpose |
|---|---|
| `/jrp` | Open the main interface |
| `/jrpset` | Open settings |
| `/jrplast` | Reuse or view the last response |
| `/jrpchar` | Manage character information |
| `/jrpbase` | Open knowledge-base controls |
| `/jrphistory` | Open response history |
| `/jrpsave` | Save a response |
| `/jrpsaved` | View saved responses |
| `/jrpauto` | Toggle automatic response behavior |
| `/jrphelp` | Show help |
| `/jrpor groq` or `/jrpor or` | Select the provider |

## Bugs Fixed & Engineering Challenges

The response extractor handles escaped quotes, newline escapes, and backslash sequences while scanning the response content. A past defect involved a response ending with a literal backslash: a redundant look-behind check could treat the actual closing quote as escaped and continue reading into the next JSON field. The current source removes that redundant check and consumes escape pairs in one pass.

The extractor is intentionally narrow and is not a general-purpose JSON parser. Provider error payloads are classified separately before the script reports a parse failure, so recognized rate-limit and unavailable-model responses can trigger model rotation. Provider response changes or unexpected JSON layouts may still require an update.

## Tech Stack

- Lua in a MoonLoader-based scripting host
- Lua Lanes for background HTTP workers
- The `requests` HTTP module for provider requests
- ImGui for chat, settings, and history interfaces
- Groq or OpenRouter-compatible chat-completion APIs
- Pure-Lua helpers for error classification and asynchronous callback epochs

## How to Use / Installation

- A compatible MoonLoader scripting host and its ImGui integration
- SAMPFUNCS and the event hooks used by the script
- The `lanes` multi-state/threading library
- The `requests` HTTP module
- A valid API key for the selected provider
- Network access to that provider

Install the dependencies, copy `threaded_ai_chat_api.lua` into the host's MoonLoader scripts directory, and copy both `provider_error_classifier.lua` and `prefetch_epoch.lua` into `moonloader/lib` so the script can resolve its pure-Lua helpers. Set the desired provider key in a private local copy, then test with a short request before enabling automatic-response behavior.

## Provider error regression tests

Run the standalone classifier tests from this project directory with Lua 5.4:

```sh
lua5.4 tests/test_provider_error_classifier.lua
```

The cases cover common rate-limit and unavailable-model phrases/codes plus an unrelated authentication error. They test classification only; live provider responses still need validation with the selected service and model.

## Practical limits

The worker model prevents a normal request wait from blocking the main script loop, but it does not remove network latency, provider rate limits, service outages, model changes, or dependency compatibility issues. Request deadlines use the host's elapsed-time game timer rather than Lua's process-CPU clock. The same timer is used for the short response-correlation window. The polling coroutine also checks the worker status and reports lane errors/cancellation instead of waiting for the full deadline. When the deadline expires, the script retains the Lua Lanes worker handle and issues a hard cancellation request. Lanes cancellation is cooperative: a worker blocked inside a native/network call may not process cancellation until that call returns. The implementation deliberately avoids force-killing the worker because doing so can leave native resources or locks in an unsafe state.


## Prefetch concurrency regression tests

Both interactive responses and prefetch results use separate generation tokens. Resetting the current chat context invalidates stale callbacks and releases the loading state so a new message can be requested. Switching providers, or rotating the model after a recognized availability error, also invalidates old prefetch work; this prevents a result produced for the previous provider/model from being displayed or cached under the new selection. The epoch helper is tested without a live provider request:

```sh
lua5.4 tests/test_prefetch_epoch.lua
```

The helper suite checks callback freshness bookkeeping, including independent tokens for interactive responses and prefetch work. It does not simulate the MoonLoader event loop or prove live HTTP timing behavior.

## License

No project-specific license file is currently included for this project. Review the source and any upstream notices before redistributing or reusing it; publication in this portfolio does not by itself grant additional redistribution rights.
