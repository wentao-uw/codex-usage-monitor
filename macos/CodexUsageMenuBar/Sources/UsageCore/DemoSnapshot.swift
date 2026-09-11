import Foundation

public extension UsageSnapshot {
    static func demo(now: Date = Date()) -> UsageSnapshot {
        let sevenDays: TimeInterval = 7 * 24 * 60 * 60
        let fiveHours: TimeInterval = 5 * 60 * 60
        let weeklyReset = now.addingTimeInterval(5 * 24 * 60 * 60)
        let shortReset = now.addingTimeInterval(3 * 60 * 60)

        let historicalUsage = TokenUsageSnapshot(
            inputTokens: 119_980_000,
            cachedInputTokens: 97_340_000,
            outputTokens: 8_470_320,
            reasoningOutputTokens: 3_120_400,
            totalTokens: 128_450_320
        )
        let currentUsage = TokenUsageSnapshot(
            inputTokens: 3_610_910,
            cachedInputTokens: 3_021_000,
            outputTokens: 232_000,
            reasoningOutputTokens: 91_400,
            totalTokens: 3_842_910
        )

        let weeklyLimit = UsageLimitSnapshot(
            label: "7d",
            usedPercent: 62,
            windowMinutes: 10_080,
            startsAt: weeklyReset.addingTimeInterval(-sevenDays),
            resetsAt: weeklyReset
        )
        let shortLimit = UsageLimitSnapshot(
            label: "5h",
            usedPercent: 38,
            windowMinutes: 300,
            startsAt: shortReset.addingTimeInterval(-fiveHours),
            resetsAt: shortReset
        )

        return UsageSnapshot(
            historicalUsage: historicalUsage,
            currentCycleUsage: currentUsage,
            historicalApiEquivalentUSD: 74.28,
            historicalCostIsComplete: true,
            currentCycleApiEquivalentUSD: 2.14,
            currentCycleCostIsComplete: true,
            currentCycle: weeklyLimit,
            rateLimits: [shortLimit, weeklyLimit],
            historicalModels: [
                ModelUsageSnapshot(
                    modelID: "gpt-5.6-sol",
                    usage: TokenUsageSnapshot(
                        inputTokens: 88_120_000,
                        cachedInputTokens: 72_400_000,
                        outputTokens: 6_940_000,
                        reasoningOutputTokens: 2_640_000,
                        totalTokens: 95_060_000
                    ),
                    apiEquivalentUSD: 55.16,
                    costIsComplete: true
                ),
                ModelUsageSnapshot(
                    modelID: "gpt-5.6-luna",
                    usage: TokenUsageSnapshot(
                        inputTokens: 31_860_000,
                        cachedInputTokens: 24_940_000,
                        outputTokens: 1_530_320,
                        reasoningOutputTokens: 480_400,
                        totalTokens: 33_390_320
                    ),
                    apiEquivalentUSD: 19.12,
                    costIsComplete: true
                ),
            ],
            currentCycleModels: [
                ModelUsageSnapshot(
                    modelID: "gpt-5.6-sol",
                    usage: TokenUsageSnapshot(
                        inputTokens: 2_740_000,
                        cachedInputTokens: 2_311_000,
                        outputTokens: 188_000,
                        reasoningOutputTokens: 72_000,
                        totalTokens: 2_928_000
                    ),
                    apiEquivalentUSD: 1.68,
                    costIsComplete: true
                ),
                ModelUsageSnapshot(
                    modelID: "gpt-5.6-luna",
                    usage: TokenUsageSnapshot(
                        inputTokens: 870_910,
                        cachedInputTokens: 710_000,
                        outputTokens: 44_000,
                        reasoningOutputTokens: 19_400,
                        totalTokens: 914_910
                    ),
                    apiEquivalentUSD: 0.46,
                    costIsComplete: true
                ),
            ],
            latestModel: "gpt-5.6-sol",
            latestReasoningEffort: "high",
            latestContextUsedPercent: 17.1,
            sessionCount: 214,
            latestActivityAt: now.addingTimeInterval(-120),
            updatedAt: now
        )
    }
}
