# Changelog

## Unreleased

- Add a local MCP server with a `show_usage` tool.
- Add a responsive Codex Desktop usage card with in-place refresh.
- Add a native macOS menu bar app that separates all-time local usage from usage accumulated in the current longest rolling-limit cycle.
- Show current-cycle input, cached input, output, reasoning, cache hit, latest context fill, rolling-limit progress, reset time, and API-equivalent cost.
- Add per-model current-cycle and historical token breakdowns with API-equivalent cost.
- Make the displayed update time reflect completion of each automatic or manual scan.
- Cache parsed macOS session data and incrementally read appended JSONL records, making warm refreshes near-instant even with large histories.
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
