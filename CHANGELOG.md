# Changelog

## Unreleased

- Add a local MCP server with a `show_usage` tool.
- Add a responsive Codex Desktop usage card with in-place refresh.
- Add a native macOS menu bar app that aggregates total local tokens and API-equivalent cost across sessions.
- Add Chinese and English switching, 10-minute background refresh, and manual refresh to the menu bar app.
- Refresh bundled API-equivalent prices for the current GPT-5.4, GPT-5.5, GPT-5.6, and GPT-6 families.
- Preserve the existing terminal statusline and hook behavior.

## 0.1.0 - 2026-06-30

- Initial public release.
- Add Codex JSONL session parser.
- Add model, reasoning effort, token, context, cache, rate-limit, and cost
  summaries.
- Add `summary`, `statusline`, `json`, `watch`, and `doctor` CLI commands.
- Add Codex Stop hook entrypoint.
- Add zero-dependency Node test suite.
