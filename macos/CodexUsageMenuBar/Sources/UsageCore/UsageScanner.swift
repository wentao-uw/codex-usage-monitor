import Foundation

public struct TokenUsageSnapshot: Equatable, Sendable {
    public let inputTokens: Int64
    public let cachedInputTokens: Int64
    public let outputTokens: Int64
    public let reasoningOutputTokens: Int64
    public let totalTokens: Int64

    public init(
        inputTokens: Int64 = 0,
        cachedInputTokens: Int64 = 0,
        outputTokens: Int64 = 0,
        reasoningOutputTokens: Int64 = 0,
        totalTokens: Int64 = 0
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }

    public var cacheHitPercent: Double? {
        guard inputTokens > 0 else { return nil }
        return Double(cachedInputTokens) / Double(inputTokens) * 100
    }
}

public struct ModelUsageSnapshot: Equatable, Sendable {
    public let modelID: String
    public let usage: TokenUsageSnapshot
    public let apiEquivalentUSD: Double?
    public let costIsComplete: Bool
}

public struct UsageLimitSnapshot: Equatable, Sendable {
    public let label: String
    public let usedPercent: Double
    public let windowMinutes: Int
    public let startsAt: Date
    public let resetsAt: Date
}

public struct UsageSnapshot: Equatable, Sendable {
    public let historicalUsage: TokenUsageSnapshot
    public let currentCycleUsage: TokenUsageSnapshot
    public let historicalApiEquivalentUSD: Double?
    public let historicalCostIsComplete: Bool
    public let currentCycleApiEquivalentUSD: Double?
    public let currentCycleCostIsComplete: Bool
    public let currentCycle: UsageLimitSnapshot?
    public let rateLimits: [UsageLimitSnapshot]
    public let historicalModels: [ModelUsageSnapshot]
    public let currentCycleModels: [ModelUsageSnapshot]
    public let latestModel: String?
    public let latestReasoningEffort: String?
    public let latestContextUsedPercent: Double?
    public let sessionCount: Int
    public let latestActivityAt: Date?
    public let updatedAt: Date

    public var totalTokens: Int64 { historicalUsage.totalTokens }
    public var apiEquivalentUSD: Double? { historicalApiEquivalentUSD }
    public var costIsComplete: Bool { historicalCostIsComplete }
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
            .appendingPathComponent(".codex", isDirectory: true),
        now: Date = Date()
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

        var historicalUsage = TokenUsage.zero
        var historicalModelUsage: [String: TokenUsage] = [:]
        var allEvents: [UsageEvent] = []
        var latestUpdate = Date.distantPast
        var latestDetail: SessionDetail?
        var latestLimitRecord: LimitRecord?

        for session in sessionsByID.values {
            historicalUsage.add(session.totalUsage)
            latestUpdate = max(latestUpdate, session.latestAt ?? session.modifiedAt)
            allEvents.append(contentsOf: session.events)
            for event in session.events {
                historicalModelUsage[event.model, default: .zero].add(event.usage)
            }
            if let detail = session.latestDetail,
               latestDetail == nil || detail.timestamp > latestDetail!.timestamp {
                latestDetail = detail
            }
            if let record = session.latestLimitRecord,
               latestLimitRecord == nil || record.timestamp > latestLimitRecord!.timestamp {
                latestLimitRecord = record
            }
        }

        let effectiveLimits = (latestLimitRecord?.limits ?? [])
            .map { effectiveLimit($0, now: now) }
            .sorted { $0.windowMinutes < $1.windowMinutes }
        let currentCycle = effectiveLimits.max { $0.windowMinutes < $1.windowMinutes }

        var currentCycleUsage = TokenUsage.zero
        var currentCycleModelUsage: [String: TokenUsage] = [:]
        if let currentCycle {
            for event in allEvents where event.timestamp >= currentCycle.startsAt && event.timestamp < currentCycle.resetsAt {
                currentCycleUsage.add(event.usage)
                currentCycleModelUsage[event.model, default: .zero].add(event.usage)
            }
        }

        let historicalCost = apiEquivalentCost(for: historicalModelUsage)
        let currentCycleCost = apiEquivalentCost(for: currentCycleModelUsage)
        let historicalModels = modelSnapshots(for: historicalModelUsage)
        let currentCycleModels = modelSnapshots(for: currentCycleModelUsage)
        let contextPercent: Double?
        if let detail = latestDetail, detail.contextWindow > 0 {
            contextPercent = Double(detail.latestUsage.inputTokens) / Double(detail.contextWindow) * 100
        } else {
            contextPercent = nil
        }

        return UsageSnapshot(
            historicalUsage: historicalUsage.snapshot,
            currentCycleUsage: currentCycleUsage.snapshot,
            historicalApiEquivalentUSD: historicalCost.usd,
            historicalCostIsComplete: historicalCost.complete,
            currentCycleApiEquivalentUSD: currentCycleCost.usd,
            currentCycleCostIsComplete: currentCycleCost.complete,
            currentCycle: currentCycle,
            rateLimits: effectiveLimits,
            historicalModels: historicalModels,
            currentCycleModels: currentCycleModels,
            latestModel: latestDetail?.model,
            latestReasoningEffort: latestDetail?.reasoningEffort,
            latestContextUsedPercent: contextPercent,
            sessionCount: sessionsByID.count,
            latestActivityAt: latestUpdate == .distantPast ? nil : latestUpdate,
            updatedAt: now
        )
    }

    private static func jsonlFiles(below root: URL, fileManager: FileManager) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

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
              let text = String(data: data, encoding: .utf8) else { return nil }

        let modifiedAt = (attributes[.modificationDate] as? Date) ?? Date.distantPast
        var id: String?
        var currentModel = "unknown"
        var currentEffort: String?
        var contextWindow: Int64 = 0
        var latestAt: Date?
        var totalUsage = TokenUsage.zero
        var events: [UsageEvent] = []
        var latestDetail: SessionDetail?
        var latestLimitRecord: LimitRecord?
        var sawUsage = false

        text.enumerateLines { line, _ in
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = record["type"] as? String,
                  let payload = record["payload"] as? [String: Any] else { return }

            let timestamp = parseTimestamp(record["timestamp"]) ?? modifiedAt
            latestAt = max(latestAt ?? .distantPast, timestamp)

            if type == "session_meta" {
                id = nonemptyString(payload["session_id"]) ?? nonemptyString(payload["id"]) ?? id
                return
            }

            if type == "turn_context" {
                currentModel = nonemptyString(payload["model"]) ?? collaborationModel(payload) ?? currentModel
                currentEffort = nonemptyString(payload["effort"]) ?? collaborationEffort(payload) ?? currentEffort
                let window = int64(payload["model_context_window"])
                if window > 0 { contextWindow = window }
                return
            }

            guard type == "event_msg",
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any] else { return }

            let window = int64(info["model_context_window"])
            if window > 0 { contextWindow = window }
            if let total = info["total_token_usage"] as? [String: Any] {
                totalUsage = TokenUsage(dictionary: total)
            }
            let latest = TokenUsage(dictionary: info["last_token_usage"] as? [String: Any] ?? [:])
            if latest.hasUsage {
                events.append(UsageEvent(timestamp: timestamp, model: currentModel, usage: latest))
            }
            latestDetail = SessionDetail(
                timestamp: timestamp,
                model: currentModel == "unknown" ? nil : currentModel,
                reasoningEffort: currentEffort,
                contextWindow: contextWindow,
                latestUsage: latest
            )
            if let rawLimits = payload["rate_limits"] as? [String: Any] {
                let limits = [rawLimits["primary"], rawLimits["secondary"]].compactMap { parseLimit($0) }
                if !limits.isEmpty { latestLimitRecord = LimitRecord(timestamp: timestamp, limits: limits) }
            }
            sawUsage = true
        }

        guard sawUsage else { return nil }
        return SessionUsage(
            id: id,
            modifiedAt: modifiedAt,
            latestAt: latestAt,
            totalUsage: totalUsage,
            events: events,
            latestDetail: latestDetail,
            latestLimitRecord: latestLimitRecord
        )
    }

    private static func collaborationModel(_ payload: [String: Any]) -> String? {
        guard let mode = payload["collaboration_mode"] as? [String: Any],
              let settings = mode["settings"] as? [String: Any] else { return nil }
        return nonemptyString(settings["model"])
    }

    private static func collaborationEffort(_ payload: [String: Any]) -> String? {
        guard let mode = payload["collaboration_mode"] as? [String: Any],
              let settings = mode["settings"] as? [String: Any] else { return nil }
        return nonemptyString(settings["reasoning_effort"])
    }

    private static func parseLimit(_ value: Any?) -> RawUsageLimit? {
        guard let raw = value as? [String: Any] else { return nil }
        let minutes = Int(int64(raw["window_minutes"]))
        let resetSeconds = double(raw["resets_at"])
        guard minutes > 0, resetSeconds > 0 else { return nil }
        return RawUsageLimit(
            usedPercent: max(0, min(100, double(raw["used_percent"]))),
            windowMinutes: minutes,
            resetsAt: Date(timeIntervalSince1970: resetSeconds)
        )
    }

    private static func effectiveLimit(_ raw: RawUsageLimit, now: Date) -> UsageLimitSnapshot {
        let duration = TimeInterval(raw.windowMinutes * 60)
        var resetsAt = raw.resetsAt
        var usedPercent = raw.usedPercent
        if resetsAt <= now {
            let elapsed = now.timeIntervalSince(resetsAt)
            resetsAt = resetsAt.addingTimeInterval((floor(elapsed / duration) + 1) * duration)
            usedPercent = 0
        }
        return UsageLimitSnapshot(
            label: label(for: raw.windowMinutes),
            usedPercent: usedPercent,
            windowMinutes: raw.windowMinutes,
            startsAt: resetsAt.addingTimeInterval(-duration),
            resetsAt: resetsAt
        )
    }

    private static func label(for minutes: Int) -> String {
        if minutes % 1_440 == 0 { return "\(minutes / 1_440)d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
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

    private static func modelSnapshots(for usageByModel: [String: TokenUsage]) -> [ModelUsageSnapshot] {
        usageByModel.compactMap { modelID, usage in
            guard usage.hasUsage else { return nil }
            let cost = apiEquivalentCost(for: [modelID: usage])
            return ModelUsageSnapshot(
                modelID: modelID,
                usage: usage.snapshot,
                apiEquivalentUSD: cost.usd,
                costIsComplete: cost.complete
            )
        }
        .sorted {
            if $0.usage.totalTokens == $1.usage.totalTokens {
                return $0.modelID.localizedCaseInsensitiveCompare($1.modelID) == .orderedAscending
            }
            return $0.usage.totalTokens > $1.usage.totalTokens
        }
    }

    private static func price(for modelID: String) -> Price? {
        let normalized = modelID.lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return prices.first { normalized.contains($0.key) }
    }

    private static func parseTimestamp(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
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
    let latestAt: Date?
    let totalUsage: TokenUsage
    let events: [UsageEvent]
    let latestDetail: SessionDetail?
    let latestLimitRecord: LimitRecord?
}

private struct UsageEvent {
    let timestamp: Date
    let model: String
    let usage: TokenUsage
}

private struct SessionDetail {
    let timestamp: Date
    let model: String?
    let reasoningEffort: String?
    let contextWindow: Int64
    let latestUsage: TokenUsage
}

private struct LimitRecord {
    let timestamp: Date
    let limits: [RawUsageLimit]
}

private struct RawUsageLimit {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: Date
}

private struct TokenUsage {
    var inputTokens: Int64
    var cachedInputTokens: Int64
    var outputTokens: Int64
    var reasoningOutputTokens: Int64
    var totalTokens: Int64

    static let zero = TokenUsage(inputTokens: 0, cachedInputTokens: 0, outputTokens: 0, reasoningOutputTokens: 0, totalTokens: 0)

    init(inputTokens: Int64, cachedInputTokens: Int64, outputTokens: Int64, reasoningOutputTokens: Int64, totalTokens: Int64) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }

    init(dictionary: [String: Any]) {
        inputTokens = int64(dictionary["input_tokens"])
        cachedInputTokens = int64(dictionary["cached_input_tokens"])
        outputTokens = int64(dictionary["output_tokens"])
        reasoningOutputTokens = int64(dictionary["reasoning_output_tokens"])
        let reportedTotal = int64(dictionary["total_tokens"])
        totalTokens = reportedTotal > 0 ? reportedTotal : inputTokens + outputTokens
    }

    var hasUsage: Bool {
        inputTokens > 0 || cachedInputTokens > 0 || outputTokens > 0 || totalTokens > 0
    }

    var snapshot: TokenUsageSnapshot {
        TokenUsageSnapshot(
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            reasoningOutputTokens: reasoningOutputTokens,
            totalTokens: totalTokens
        )
    }

    mutating func add(_ other: TokenUsage) {
        inputTokens += other.inputTokens
        cachedInputTokens += other.cachedInputTokens
        outputTokens += other.outputTokens
        reasoningOutputTokens += other.reasoningOutputTokens
        totalTokens += other.totalTokens
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

private func double(_ value: Any?) -> Double {
    if let number = value as? NSNumber { return number.doubleValue }
    if let string = value as? String { return Double(string) ?? 0 }
    return 0
}
