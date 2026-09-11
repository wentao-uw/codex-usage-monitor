import Foundation
import UsageCore

if CommandLine.arguments.contains("--live") {
    let snapshot = try UsageScanner.scan()
    let cost = snapshot.apiEquivalentUSD.map { String(format: "%.6f", $0) } ?? "unavailable"
    print("Live scan passed: \(snapshot.totalTokens) tokens, API≈$\(cost), \(snapshot.sessionCount) sessions")
    exit(EXIT_SUCCESS)
}

let fileManager = FileManager.default
let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
let sessions = root.appendingPathComponent("sessions/2026/09/11", isDirectory: true)
defer { try? fileManager.removeItem(at: root) }

try fileManager.createDirectory(at: sessions, withIntermediateDirectories: true)

let first = """
{"type":"session_meta","payload":{"id":"first"}}
{"type":"turn_context","payload":{"model":"gpt-5.5"}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":100,"total_tokens":1100},"last_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":100,"total_tokens":1100}}}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1500,"cached_input_tokens":300,"output_tokens":150,"total_tokens":1650},"last_token_usage":{"input_tokens":500,"cached_input_tokens":100,"output_tokens":50,"total_tokens":550}}}}
"""

let second = """
{"type":"session_meta","payload":{"id":"second"}}
{"type":"turn_context","payload":{"model":"gpt-5.4-mini"}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500,"cached_input_tokens":100,"output_tokens":50,"total_tokens":550},"last_token_usage":{"input_tokens":500,"cached_input_tokens":100,"output_tokens":50,"total_tokens":550}}}}
"""

try first.write(to: sessions.appendingPathComponent("first.jsonl"), atomically: true, encoding: .utf8)
try second.write(to: sessions.appendingPathComponent("second.jsonl"), atomically: true, encoding: .utf8)

let snapshot = try UsageScanner.scan(codexHome: root)
precondition(snapshot.totalTokens == 2_200, "expected 2,200 tokens, got \(snapshot.totalTokens)")
precondition(snapshot.sessionCount == 2, "expected two sessions")
precondition(snapshot.costIsComplete, "expected complete pricing")
precondition((snapshot.apiEquivalentUSD ?? 0) > 0, "expected a positive cost")

print("UsageCoreCheck passed: \(snapshot.totalTokens) tokens across \(snapshot.sessionCount) sessions")
