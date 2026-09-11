import Foundation
import UsageCore

if CommandLine.arguments.contains("--live") {
    let snapshot = try UsageScanner.scan()
    let cost = snapshot.apiEquivalentUSD.map { String(format: "%.6f", $0) } ?? "unavailable"
    let cycle = snapshot.currentCycle.map { "\($0.label): \(snapshot.currentCycleUsage.totalTokens) tokens" } ?? "cycle unavailable"
    print("Live scan passed: \(snapshot.totalTokens) historical tokens, \(cycle), API≈$\(cost), \(snapshot.sessionCount) sessions")
    exit(EXIT_SUCCESS)
}

let fileManager = FileManager.default
let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
let sessions = root.appendingPathComponent("sessions/2026/09/11", isDirectory: true)
defer { try? fileManager.removeItem(at: root) }

try fileManager.createDirectory(at: sessions, withIntermediateDirectories: true)

let first = """
{"timestamp":"2026-09-01T00:00:00.000Z","type":"session_meta","payload":{"id":"first"}}
{"timestamp":"2026-09-01T00:00:01.000Z","type":"turn_context","payload":{"model":"gpt-5.5","effort":"high","model_context_window":10000}}
{"timestamp":"2026-09-01T00:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":100,"reasoning_output_tokens":40,"total_tokens":1100},"last_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":100,"reasoning_output_tokens":40,"total_tokens":1100}}}}
{"timestamp":"2026-09-11T08:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1500,"cached_input_tokens":300,"output_tokens":150,"reasoning_output_tokens":60,"total_tokens":1650},"last_token_usage":{"input_tokens":500,"cached_input_tokens":100,"output_tokens":50,"reasoning_output_tokens":20,"total_tokens":550}},"rate_limits":{"primary":{"used_percent":25,"window_minutes":300,"resets_at":1789128000},"secondary":{"used_percent":6,"window_minutes":10080,"resets_at":1789142400}}}}
"""

let second = """
{"timestamp":"2026-09-11T09:00:00.000Z","type":"session_meta","payload":{"id":"second"}}
{"timestamp":"2026-09-11T09:00:01.000Z","type":"turn_context","payload":{"model":"gpt-5.4-mini","model_context_window":10000}}
{"timestamp":"2026-09-11T09:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500,"cached_input_tokens":100,"output_tokens":50,"reasoning_output_tokens":10,"total_tokens":550},"last_token_usage":{"input_tokens":500,"cached_input_tokens":100,"output_tokens":50,"reasoning_output_tokens":10,"total_tokens":550}},"rate_limits":{"primary":{"used_percent":25,"window_minutes":300,"resets_at":1789128000},"secondary":{"used_percent":6,"window_minutes":10080,"resets_at":1789142400}}}}
"""

try first.write(to: sessions.appendingPathComponent("first.jsonl"), atomically: true, encoding: .utf8)
try second.write(to: sessions.appendingPathComponent("second.jsonl"), atomically: true, encoding: .utf8)

let now = ISO8601DateFormatter().date(from: "2026-09-11T12:00:00Z")!
let snapshot = try UsageScanner.scan(codexHome: root, now: now)
precondition(snapshot.totalTokens == 2_200, "expected 2,200 tokens, got \(snapshot.totalTokens)")
precondition(snapshot.sessionCount == 2, "expected two sessions")
precondition(snapshot.costIsComplete, "expected complete pricing")
precondition((snapshot.apiEquivalentUSD ?? 0) > 0, "expected a positive cost")
precondition(snapshot.historicalUsage.inputTokens == 2_000, "expected complete historical input total")
precondition(snapshot.historicalUsage.reasoningOutputTokens == 70, "expected historical reasoning total")
precondition(snapshot.currentCycle?.label == "7d", "expected the longest rolling window as current cycle")
precondition(snapshot.currentCycleUsage.totalTokens == 1_100, "expected only events since cycle start")
precondition(snapshot.currentCycleUsage.cachedInputTokens == 200, "expected cycle cached input")
precondition(snapshot.currentCycleUsage.reasoningOutputTokens == 30, "expected cycle reasoning output")
precondition((snapshot.currentCycleApiEquivalentUSD ?? 0) > 0, "expected a positive cycle cost")
precondition(snapshot.rateLimits.map(\.label) == ["5h", "7d"], "expected both rolling limits")
precondition(snapshot.latestModel == "gpt-5.4-mini", "expected latest model")
precondition(snapshot.latestContextUsedPercent == 5, "expected latest context percent")

print("UsageCoreCheck passed: \(snapshot.totalTokens) historical, \(snapshot.currentCycleUsage.totalTokens) current-cycle tokens")
