import Foundation

public struct UsageSnapshot: Equatable, Sendable {
    public let totalTokens: Int64
    public let apiEquivalentUSD: Double?
    public let costIsComplete: Bool
    public let sessionCount: Int
    public let updatedAt: Date

    public init(
        totalTokens: Int64,
        apiEquivalentUSD: Double?,
        costIsComplete: Bool,
        sessionCount: Int,
        updatedAt: Date
    ) {
        self.totalTokens = totalTokens
        self.apiEquivalentUSD = apiEquivalentUSD
        self.costIsComplete = costIsComplete
        self.sessionCount = sessionCount
        self.updatedAt = updatedAt
    }
}

public enum UsageScannerError: LocalizedError {
    case noCodexDirectory(URL)

    public var errorDescription: String? {
        switch self {
        case .noCodexDirectory(let url):
            return "Codex data directory was not found at \(url.path)."
        }
    }
}

public enum UsageScanner {
    private static let maximumTranscriptBytes: Int64 = 50 * 1024 * 1024

    public static func scan(
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    ) throws -> UsageSnapshot {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: codexHome.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw UsageScannerError.noCodexDirectory(codexHome)
        }

        let roots = ["sessions", "archived_sessions"]
            .map { codexHome.appendingPathComponent($0, isDirectory: true) }
            .filter { fileManager.fileExists(atPath: $0.path) }

        var sessionsByID: [String: SessionUsage] = [:]
        for root in roots {
            for file in jsonlFiles(below: root, fileManager: fileManager) {
                guard let session = parseSession(file, fileManager: fileManager) else { continue }
                let key = session.id ?? file.standardizedFileURL.path
                if let existing = sessionsByID[key], existing.modifiedAt >= session.modifiedAt {
                    continue
                }
                sessionsByID[key] = session
            }
        }

        var totalTokens: Int64 = 0
        var modelUsage: [String: TokenUsage] = [:]
        var latestUpdate = Date.distantPast

        for session in sessionsByID.values {
            totalTokens += session.totalTokens
            latestUpdate = max(latestUpdate, session.modifiedAt)
            for (model, usage) in session.modelUsage {
                modelUsage[model, default: .zero].add(usage)
            }
        }

        let cost = apiEquivalentCost(for: modelUsage)
        return UsageSnapshot(
            totalTokens: totalTokens,
            apiEquivalentUSD: cost.usd,
            costIsComplete: cost.complete,
            sessionCount: sessionsByID.count,
            updatedAt: latestUpdate == .distantPast ? Date() : latestUpdate
        )
    }

    private static func jsonlFiles(below root: URL, fileManager: FileManager) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true else { continue }
            files.append(url)
        }
        return files
    }

    private static func parseSession(_ file: URL, fileManager: FileManager) -> SessionUsage? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: file.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              size <= maximumTranscriptBytes,
              let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        let modifiedAt = (attributes[.modificationDate] as? Date) ?? Date.distantPast
        var id: String?
        var currentModel = "unknown"
        var latestTotalTokens: Int64 = 0
        var modelUsage: [String: TokenUsage] = [:]
        var sawUsage = false

        text.enumerateLines { line, _ in
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = record["type"] as? String,
                  let payload = record["payload"] as? [String: Any] else {
                return
            }

            if type == "session_meta" {
                id = nonemptyString(payload["session_id"]) ?? nonemptyString(payload["id"]) ?? id
                return
            }

            if type == "turn_context" {
                currentModel = nonemptyString(payload["model"])
                    ?? collaborationModel(payload)
                    ?? currentModel
                return
            }

            guard type == "event_msg",
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any] else {
                return
            }

            if let total = info["total_token_usage"] as? [String: Any] {
                latestTotalTokens = int64(total["total_tokens"])
            }
            if let latest = info["last_token_usage"] as? [String: Any] {
                modelUsage[currentModel, default: .zero].add(TokenUsage(dictionary: latest))
            }
            sawUsage = true
        }

        guard sawUsage else { return nil }
        return SessionUsage(
            id: id,
            modifiedAt: modifiedAt,
            totalTokens: latestTotalTokens,
            modelUsage: modelUsage
        )
    }

    private static func collaborationModel(_ payload: [String: Any]) -> String? {
        guard let mode = payload["collaboration_mode"] as? [String: Any],
              let settings = mode["settings"] as? [String: Any] else {
            return nil
        }
        return nonemptyString(settings["model"])
    }

    private static func apiEquivalentCost(for usageByModel: [String: TokenUsage]) -> (usd: Double?, complete: Bool) {
        var usd = 0.0
        var hasUsage = false
        var hasKnownPrice = false
        var complete = true

        for (modelID, usage) in usageByModel where usage.hasUsage {
            hasUsage = true
            guard let price = price(for: modelID) else {
                complete = false
                continue
            }
            hasKnownPrice = true
            let cached = min(usage.inputTokens, max(0, usage.cachedInputTokens))
            let uncached = max(0, usage.inputTokens - cached)
            let cachedRate = price.cachedInput ?? price.input
            usd += (
                Double(uncached) * price.input
                + Double(cached) * cachedRate
                + Double(usage.outputTokens) * price.output
            ) / 1_000_000
        }

        if !hasUsage { return (nil, true) }
        if !hasKnownPrice { return (nil, false) }
        return (usd, complete)
    }

    private static func price(for modelID: String) -> Price? {
        let normalized = modelID
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return prices.first { normalized.contains($0.key) }
    }

    private static let prices: [Price] = [
        Price(key: "gpt-6-astra", input: 10, cachedInput: 1, output: 50),
        Price(key: "gpt-5.6-luna", input: 0.2, cachedInput: 0.02, output: 1.2),
        Price(key: "gpt-5.6-terra", input: 2, cachedInput: 0.2, output: 12),
        Price(key: "gpt-5.6-sol", input: 4, cachedInput: 0.4, output: 20),
        Price(key: "gpt-5.6", input: 4, cachedInput: 0.4, output: 20),
        Price(key: "gpt-5.5-pro", input: 30, cachedInput: nil, output: 180),
        Price(key: "gpt-5.5", input: 5, cachedInput: 0.5, output: 30),
        Price(key: "gpt-5.4-mini", input: 0.75, cachedInput: 0.075, output: 4.5),
        Price(key: "gpt-5.4-nano", input: 0.2, cachedInput: 0.02, output: 1.25),
        Price(key: "gpt-5.4-pro", input: 30, cachedInput: nil, output: 180),
        Price(key: "gpt-5.4", input: 2.5, cachedInput: 0.25, output: 15),
        Price(key: "gpt-5.3", input: 1.75, cachedInput: 0.175, output: 14),
        Price(key: "gpt-5-mini", input: 0.25, cachedInput: 0.025, output: 2),
        Price(key: "gpt-5-nano", input: 0.05, cachedInput: 0.005, output: 0.4),
        Price(key: "gpt-5", input: 1.25, cachedInput: 0.125, output: 10),
        Price(key: "gpt-4.1-mini", input: 0.4, cachedInput: 0.1, output: 1.6),
        Price(key: "gpt-4.1-nano", input: 0.1, cachedInput: 0.025, output: 0.4),
        Price(key: "gpt-4.1", input: 2, cachedInput: 0.5, output: 8),
        Price(key: "o4-mini", input: 1.1, cachedInput: 0.275, output: 4.4),
        Price(key: "o3-pro", input: 20, cachedInput: nil, output: 80),
        Price(key: "o3-mini", input: 1.1, cachedInput: 0.55, output: 4.4),
        Price(key: "o3", input: 2, cachedInput: 0.5, output: 8),
    ]
}

private struct SessionUsage {
    let id: String?
    let modifiedAt: Date
    let totalTokens: Int64
    let modelUsage: [String: TokenUsage]
}

private struct TokenUsage {
    var inputTokens: Int64
    var cachedInputTokens: Int64
    var outputTokens: Int64

    static let zero = TokenUsage(inputTokens: 0, cachedInputTokens: 0, outputTokens: 0)

    init(inputTokens: Int64, cachedInputTokens: Int64, outputTokens: Int64) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
    }

    init(dictionary: [String: Any]) {
        inputTokens = int64(dictionary["input_tokens"])
        cachedInputTokens = int64(dictionary["cached_input_tokens"])
        outputTokens = int64(dictionary["output_tokens"])
    }

    var hasUsage: Bool {
        inputTokens > 0 || cachedInputTokens > 0 || outputTokens > 0
    }

    mutating func add(_ other: TokenUsage) {
        inputTokens += other.inputTokens
        cachedInputTokens += other.cachedInputTokens
        outputTokens += other.outputTokens
    }
}

private struct Price {
    let key: String
    let input: Double
    let cachedInput: Double?
    let output: Double
}

private func nonemptyString(_ value: Any?) -> String? {
    guard let string = value as? String, !string.isEmpty else { return nil }
    return string
}

private func int64(_ value: Any?) -> Int64 {
    if let number = value as? NSNumber { return number.int64Value }
    if let string = value as? String { return Int64(string) ?? 0 }
    return 0
}
