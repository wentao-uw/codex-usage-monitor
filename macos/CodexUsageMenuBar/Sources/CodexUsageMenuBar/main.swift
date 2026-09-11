import AppKit
import Combine
import SwiftUI
import UsageCore

private enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese
    case english

    var id: String { rawValue }
    var displayName: String { self == .chinese ? "中文" : "English" }
}

private struct Copy {
    let language: AppLanguage

    private func text(_ chinese: String, _ english: String) -> String {
        language == .chinese ? chinese : english
    }

    var title: String { text("Codex 用量", "Codex Usage") }
    var historical: String { text("历史累计", "All-time local") }
    var currentCycle: String { text("当前周期", "Current cycle") }
    var totalTokens: String { text("Token 总量", "Total tokens") }
    var apiCost: String { text("API 等价费用", "API-equivalent cost") }
    var input: String { text("输入", "Input") }
    var cachedInput: String { text("缓存输入", "Cached input") }
    var output: String { text("输出", "Output") }
    var reasoning: String { text("推理", "Reasoning") }
    var cacheHit: String { text("缓存命中", "Cache hit") }
    var context: String { text("当前上下文", "Current context") }
    var rollingLimits: String { text("滚动限制", "Rolling limits") }
    var used: String { text("已使用", "used") }
    var resets: String { text("重置于", "resets") }
    var cycleRange: String { text("本地日志累计周期", "Local-log cycle") }
    var refresh: String { text("手动刷新", "Refresh") }
    var refreshing: String { text("正在刷新…", "Refreshing…") }
    var autoRefresh: String { text("每 10 分钟自动刷新", "Refreshes every 10 minutes") }
    var unavailable: String { text("暂不可用", "Unavailable") }
    var quit: String { text("退出", "Quit") }
    var approximate: String { text("按 API 价格估算", "Estimated at API prices") }
    var localOnly: String { text("仅统计本地 Codex 日志", "Local Codex logs only") }
    var sessions: String { text("个会话", "sessions") }
    var noCycle: String { text("尚未找到周期信息", "No cycle information found") }

    func updated(_ date: Date) -> String {
        text("更新于 \(time(date))", "Updated at \(time(date))")
    }

    func error(_ message: String) -> String {
        text("读取失败：\(message)", "Could not read usage: \(message)")
    }

    func period(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMM d HH:mm")
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    func resetTime(_ date: Date) -> String {
        "\(resets) \(dateTime(date))"
    }

    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var locale: Locale {
        Locale(identifier: language == .chinese ? "zh_Hans_CN" : "en_US")
    }
}

@MainActor
private final class UsageStore: NSObject, ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var isRefreshing = false
    @Published var errorMessage: String?

    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer(
            timeInterval: 10 * 60,
            target: self,
            selector: #selector(scheduledRefresh),
            userInfo: nil,
            repeats: true
        )
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil

        Task {
            do {
                snapshot = try await Task.detached(priority: .utility) {
                    try UsageScanner.scan()
                }.value
            } catch {
                errorMessage = error.localizedDescription
            }
            isRefreshing = false
        }
    }

    @objc private func scheduledRefresh() { refresh() }
}

private struct SummaryCard: View {
    let eyebrow: String
    let title: String
    let tokens: String
    let costTitle: String
    let cost: String
    let footnote: String?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(tokens)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Text(costTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(cost)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            }
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct SmallMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct LimitRow: View {
    let limit: UsageLimitSnapshot
    let usedText: String
    let resetText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.label)
                    .font(.body.weight(.semibold))
                Spacer()
                Text("\(formatPercent(limit.usedPercent)) \(usedText)")
                    .font(.caption.weight(.semibold))
                Text(resetText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(LinearGradient(colors: [.indigo, .mint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * min(max(limit.usedPercent / 100, 0), 1))
                }
            }
            .frame(height: 7)
        }
        .padding(11)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func formatPercent(_ value: Double) -> String {
        value.rounded() == value ? String(format: "%.0f%%", value) : String(format: "%.1f%%", value)
    }
}

private struct UsageMenuView: View {
    @EnvironmentObject private var store: UsageStore
    @AppStorage("language") private var languageRaw = AppLanguage.chinese.rawValue

    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .chinese }
    private var copy: Copy { Copy(language: language) }
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    content
                }
                .padding(16)
            }

            Divider()
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
        }
        .frame(width: 440, height: 650)
        .task { store.start() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text(copy.title)
                    .font(.title3.weight(.bold))
                Spacer()
                Picker("", selection: $languageRaw) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            if let snapshot = store.snapshot {
                let details = [snapshot.latestModel, snapshot.latestReasoningEffort.map { "think \($0)" }]
                    .compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = store.snapshot {
            HStack(alignment: .top, spacing: 10) {
                SummaryCard(
                    eyebrow: copy.historical,
                    title: copy.totalTokens,
                    tokens: formatFullTokens(snapshot.historicalUsage.totalTokens),
                    costTitle: copy.apiCost,
                    cost: formatCost(snapshot.historicalApiEquivalentUSD, complete: snapshot.historicalCostIsComplete),
                    footnote: "\(snapshot.sessionCount) \(copy.sessions)",
                    tint: .blue
                )
                SummaryCard(
                    eyebrow: snapshot.currentCycle.map { "\(copy.currentCycle) · \($0.label)" } ?? copy.currentCycle,
                    title: copy.totalTokens,
                    tokens: formatFullTokens(snapshot.currentCycleUsage.totalTokens),
                    costTitle: copy.apiCost,
                    cost: formatCost(snapshot.currentCycleApiEquivalentUSD, complete: snapshot.currentCycleCostIsComplete),
                    footnote: snapshot.currentCycle.map { copy.period($0.startsAt, $0.resetsAt) } ?? copy.noCycle,
                    tint: .indigo
                )
            }

            if let cycle = snapshot.currentCycle {
                sectionHeader("\(copy.currentCycle) · \(cycle.label)", subtitle: copy.cycleRange)
                LazyVGrid(columns: columns, spacing: 8) {
                    SmallMetric(title: copy.input, value: formatCompactTokens(snapshot.currentCycleUsage.inputTokens))
                    SmallMetric(title: copy.cachedInput, value: formatCompactTokens(snapshot.currentCycleUsage.cachedInputTokens))
                    SmallMetric(title: copy.output, value: formatCompactTokens(snapshot.currentCycleUsage.outputTokens))
                    SmallMetric(title: copy.reasoning, value: formatCompactTokens(snapshot.currentCycleUsage.reasoningOutputTokens))
                    SmallMetric(title: copy.cacheHit, value: formatPercent(snapshot.currentCycleUsage.cacheHitPercent))
                    SmallMetric(title: copy.context, value: formatPercent(snapshot.latestContextUsedPercent))
                }
            }

            if !snapshot.rateLimits.isEmpty {
                sectionHeader(copy.rollingLimits, subtitle: nil)
                VStack(spacing: 8) {
                    ForEach(snapshot.rateLimits, id: \.windowMinutes) { limit in
                        LimitRow(limit: limit, usedText: copy.used, resetText: copy.resetTime(limit.resetsAt))
                    }
                }
            }

            if let error = store.errorMessage {
                Label(copy.error(error), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } else if store.isRefreshing {
            HStack {
                Spacer()
                ProgressView(copy.refreshing)
                Spacer()
            }
            .frame(height: 180)
        }
    }

    private func sectionHeader(_ title: String, subtitle: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }

    private var footer: some View {
        VStack(spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.snapshot.map { copy.updated($0.updatedAt) } ?? copy.autoRefresh)
                    Text("\(copy.autoRefresh) · \(copy.localOnly)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Spacer()
                Button {
                    store.refresh()
                } label: {
                    Label(store.isRefreshing ? copy.refreshing : copy.refresh, systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshing)
            }

            HStack {
                Button(copy.quit) { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
                Spacer()
                Text(copy.approximate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func formatFullTokens(_ value: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: language == .chinese ? "zh_Hans_CN" : "en_US")
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func formatCompactTokens(_ value: Int64) -> String {
        let amount = Double(value)
        if value >= 1_000_000_000 { return compact(amount / 1_000_000_000, suffix: "B") }
        if value >= 1_000_000 { return compact(amount / 1_000_000, suffix: "M") }
        if value >= 1_000 { return compact(amount / 1_000, suffix: "K") }
        return String(value)
    }

    private func compact(_ value: Double, suffix: String) -> String {
        let digits = value >= 100 ? 0 : (value >= 10 ? 1 : 2)
        return String(format: "%.*f%@", digits, value, suffix)
    }

    private func formatPercent(_ value: Double?) -> String {
        guard let value else { return copy.unavailable }
        return value.rounded() == value ? String(format: "%.0f%%", value) : String(format: "%.1f%%", value)
    }

    private func formatCost(_ value: Double?, complete: Bool) -> String {
        guard let value else { return copy.unavailable }
        let digits = value < 0.01 ? 4 : 2
        return String(format: "%@$%.*f", complete ? "≈" : "≥", digits, value)
    }
}

@main
private struct CodexUsageMenuBarApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            UsageMenuView().environmentObject(store)
        } label: {
            Image(systemName: "chart.bar.xaxis")
                .accessibilityLabel("Codex Usage Monitor")
        }
        .menuBarExtraStyle(.window)
    }
}
