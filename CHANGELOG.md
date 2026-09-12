# Changelog

## 0.2.1 - 2026-09-12

- Make all-time history optional and disabled by default, while keeping current-cycle usage on the fast path.
- Calculate enabled history at background priority and reuse its cached aggregate across launches.
- Persist the last aggregate snapshot so the menu can render immediately instead of blocking on a new scan.
- Compact large summary totals automatically with K, M, and B suffixes.

## 0.2.0 - 2026-09-11

- Add a local MCP server with a `show_usage` tool.
- Add a responsive Codex Desktop usage card with in-place refresh.
- Add a native macOS menu bar app that separates all-time local usage from usage accumulated in the current longest rolling-limit cycle.
- Show current-cycle input, cached input, output, reasoning, cache hit, latest context fill, rolling-limit progress, reset time, and API-equivalent cost.
- Add per-model current-cycle and historical token breakdowns with API-equivalent cost.
- Make the displayed update time reflect completion of each automatic or manual scan.
- Cache parsed macOS session data and incrementally read appended JSONL records, making warm refreshes near-instant even with large histories.
- Add Chinese and English switching, persistent configurable auto-refresh (Off, 1, 5, 10, 15, 30, or 60 minutes), and manual refresh to the menu bar app.
- Add in-app launch-at-login control, refresh-on-open and refresh-on-wake behavior.
- Add optional rolling-limit notifications at 50%, 75%, or 90%, de-duplicated until the limit resets.
- Add a fictional-data demo mode for screenshots and safe product previews.
- Add an explicit, manual GitHub release update check; no background update traffic is generated.
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
