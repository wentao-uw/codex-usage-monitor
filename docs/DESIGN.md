# Design

## Goals

1. Show Codex CLI usage in the terminal with the same practical density as
   `cc-usage-monitor`.
2. Read only local Codex files and hook input. No telemetry, analytics, or
   runtime network calls.
3. Stay zero-dependency and cross-platform.
4. Degrade gracefully when Codex changes a field or a model price is unknown.

## Surfaces

| Surface | File | Output |
| --- | --- | --- |
| CLI summary | `bin/codex-usage-monitor.js summary` | multi-line box on stdout |
| CLI statusline | `bin/codex-usage-monitor.js statusline` | compact one-line stdout |
| JSON | `bin/codex-usage-monitor.js json` | machine-readable summary |
| Watch | `bin/codex-usage-monitor.js watch` | periodically refreshed statusline |
| Stop hook | `bin/on-stop.js` | JSON to stdout, human box to stderr |

## Data Sources

Primary data comes from Codex session JSONL files under `~/.codex/sessions`.
The Stop hook receives a `transcript_path`, so it can read the exact session
file without scanning the directory tree.

Relevant record types:

- `session_meta`: session id, cwd, Codex CLI version.
- `turn_context`: active model, reasoning effort, context window.
- `event_msg` / `task_started`: turn id and context window snapshot.
- `event_msg` / `token_count`: total usage, latest-turn usage, rate limits.

The parser uses the latest `total_token_usage` snapshot as the session total.
It also sums each `last_token_usage` into a per-model bucket using the most
recent `turn_context.model`, which gives a useful cost breakdown when a session
switches models.

The macOS app has two scan paths. Its default fast path locates the latest
rolling window and parses only session files that can contribute to the current
cycle. All-time history is opt-in and runs at background priority. An
aggregate-only `UsageSnapshot` is stored under Application Support so the menu
can render before any due refresh; raw JSONL records are never copied there.

## Module Layout

```text
lib/pricing.js    Model registry and API-equivalent cost math.
lib/session.js    Codex JSONL walker and usage summarizer.
lib/format.js     Pure terminal formatting helpers.
bin/codex-usage-monitor.js  CLI command router.
bin/on-stop.js    Codex Stop hook entrypoint.
hooks/hooks.json  Plugin hook registration.
```

## Rendering Rules

Progress bars default to Unicode blocks and can switch to ASCII with
`--ascii` or `CODEX_USAGE_MONITOR_ASCII=1`.

Rate-limit and context colors:

| Usage | Color |
| --- | --- |
| `< 70%` | green |
| `70-89.9%` | yellow |
| `>= 90%` | red |

Cache-hit colors are inverted because higher is better:

| Cache hit | Color |
| --- | --- |
| `< 30%` | red |
| `30-69.9%` | yellow |
| `>= 70%` | green |

## Pricing

The pricing table is deliberately small and explicit. Unknown models make the
session cost incomplete instead of silently undercounting. `API≈` is an
estimate of pay-as-you-go API cost, not a Codex subscription charge.

## Failure Modes

- Missing session files return `null`.
- Oversized files are skipped. Default cap: 50 MB.
- Malformed JSON lines are counted and skipped.
- Unknown models keep token totals intact but mark cost incomplete.
- The Stop hook always emits `{"continue":true}` to stdout, even if parsing
  fails, so a monitor bug does not block Codex.

## Testing

Tests use Node's built-in `node:test` runner. Fixtures are synthetic Codex
JSONL records modeled after observed local session logs. The subprocess tests
verify that the CLI and hook behave like real commands rather than only pure
functions.
