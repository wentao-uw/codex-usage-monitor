// Native menu bar interface and application entry point.
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

private enum ModelUsageScope: String, CaseIterable, Identifiable {
    case currentCycle
    case historical

    var id: String { rawValue }
}

private enum AutoRefreshInterval: Int, CaseIterable, Identifiable {
    case off = 0
    case oneMinute = 1
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60

    var id: Int { rawValue }
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
    var modelUsage: String { text("按模型统计", "Usage by model") }
    var tokens: String { text("Token", "tokens") }
    var noModelUsage: String { text("暂无模型用量", "No model usage") }
    var used: String { text("已使用", "used") }
    var resets: String { text("重置于", "resets") }
    var cycleRange: String { text("本地日志累计周期", "Local-log cycle") }
    var refresh: String { text("手动刷新", "Refresh") }
    var refreshing: String { text("正在刷新…", "Refreshing…") }
    var autoRefreshTitle: String { text("自动刷新", "Auto refresh") }
    var settings: String { text("设置", "Settings") }
    var historicalUsageSetting: String { text("统计历史累计", "Calculate all-time usage") }
    var refreshHistory: String { text("重新统计历史", "Recalculate history") }
    var calculatingHistory: String { text("正在后台统计历史…", "Calculating history in background…") }
    var historyDisabled: String { text("可在设置中开启历史累计", "Enable all-time usage in Settings") }
    var launchAtLogin: String { text("登录时启动", "Launch at login") }
    var notifications: String { text("用量提醒", "Usage alerts") }
    var demoMode: String { text("演示模式", "Demo mode") }
    var demoBanner: String { text("正在显示虚构演示数据", "Showing fictional demo data") }
    var checkUpdates: String { text("检查更新", "Check for updates") }
    var checkingUpdates: String { text("正在检查更新…", "Checking for updates…") }
    var latestVersion: String { text("已经是最新版本", "You are up to date") }
    var noRelease: String { text("尚无公开版本", "No public release yet") }
    var updateFailed: String { text("更新检查失败，请稍后重试", "Update check failed; try again") }
    var launchAtLoginFailed: String { text("无法修改登录项；请将应用移到“应用程序”后重试。", "Could not change the login item. Move the app to Applications and try again.") }
    var unavailable: String { text("暂不可用", "Unavailable") }
    var quit: String { text("退出", "Quit") }
    var approximate: String { text("按 API 价格估算", "Estimated at API prices") }
    var localOnly: String { text("仅统计本地 Codex 日志", "Local Codex logs only") }
    var sessions: String { text("个会话", "sessions") }
    var noCycle: String { text("尚未找到周期信息", "No cycle information found") }

    func scope(_ value: ModelUsageScope) -> String {
        switch value {
        case .currentCycle: return currentCycle
        case .historical: return historical
        }
    }

    func autoRefresh(minutes: Int) -> String {
        switch minutes {
        case 0:
            return text("自动刷新已关闭", "Auto refresh off")
        case 1:
            return text("每分钟自动刷新", "Refresh every minute")
        case 60:
            return text("每小时自动刷新", "Refresh every hour")
        default:
            return text("每 \(minutes) 分钟自动刷新", "Refresh every \(minutes) minutes")
        }
    }

    func autoRefreshOption(minutes: Int) -> String {
        switch minutes {
        case 0: return text("关闭", "Off")
        case 1: return text("1 分钟", "1 min")
        case 60: return text("1 小时", "1 hour")
        default: return text("\(minutes) 分钟", "\(minutes) min")
        }
    }

    func notificationOption(threshold: Int) -> String {
        threshold == 0
            ? text("关闭", "Off")
            : text("达到 \(threshold)% 时提醒", "Alert at \(threshold)%")
    }

    func updateAction(_ state: UpdateChecker.State) -> String {
        switch state {
        case .idle: return checkUpdates
        case .checking: return checkingUpdates
        case .current: return latestVersion
        case .noRelease: return noRelease
        case .available(let version, _): return text("下载 \(version)", "Download \(version)")
        case .failed: return updateFailed
        }
    }

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
    @Published var isLoadingHistory = false
    @Published var errorMessage: String?

    private var timer: Timer?
    private var hasStarted = false
    private var autoRefreshMinutes: Int?
    private var notificationThreshold = 0
    private var isChinese = true
    private var demoMode = false
    private var historicalUsageEnabled = false
    private var refreshGeneration = 0
    private var historyGeneration = 0

    private let historyRefreshInterval: TimeInterval = 24 * 60 * 60
    private let historyUpdatedDefaultsKey = "historicalUsage.lastCalculatedAt"

    func start(
        autoRefreshMinutes: Int,
        notificationThreshold: Int,
        isChinese: Bool,
        demoMode: Bool,
        historicalUsageEnabled: Bool
    ) {
        guard !hasStarted else { return }
        hasStarted = true
        self.isChinese = isChinese
        self.demoMode = demoMode
        self.historicalUsageEnabled = historicalUsageEnabled
        setAutoRefresh(minutes: autoRefreshMinutes)
        setNotificationThreshold(notificationThreshold)

        if demoMode {
            snapshot = .demo()
            return
        }

        snapshot = UsageSnapshotCache.load()
        if snapshot == nil {
            refresh()
        } else {
            refreshIfNeeded()
            if historicalUsageEnabled && historyNeedsRefresh {
                refreshHistory()
            }
        }
    }

    func setAutoRefresh(minutes: Int) {
        let normalizedMinutes = max(0, minutes)
        guard autoRefreshMinutes != normalizedMinutes else { return }

        autoRefreshMinutes = normalizedMinutes
        timer?.invalidate()
        timer = nil

        guard normalizedMinutes > 0 else { return }
        timer = Timer(
            timeInterval: TimeInterval(normalizedMinutes * 60),
            target: self,
            selector: #selector(scheduledRefresh),
            userInfo: nil,
            repeats: true
        )
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func refresh() {
        guard !isRefreshing else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        isRefreshing = true
        errorMessage = nil

        if demoMode {
            snapshot = .demo()
            isRefreshing = false
            return
        }

        Task {
            do {
                let currentSnapshot = try await Task.detached(priority: .userInitiated) {
                    try UsageScanner.scanCurrentCycle()
                }.value
                guard generation == refreshGeneration else { return }
                let refreshedSnapshot = currentSnapshot.preservingHistorical(from: snapshot)
                snapshot = refreshedSnapshot
                UsageSnapshotCache.save(refreshedSnapshot)
                let threshold = notificationThreshold
                let notificationLanguage = isChinese
                Task {
                    await UsageNotificationService.evaluate(
                        snapshot: refreshedSnapshot,
                        threshold: threshold,
                        isChinese: notificationLanguage
                    )
                }
            } catch {
                guard generation == refreshGeneration else { return }
                errorMessage = error.localizedDescription
            }
            isRefreshing = false
            if historicalUsageEnabled && (snapshot?.historicalIncluded != true || historyNeedsRefresh) {
                refreshHistory()
            }
        }
    }

    func refreshIfNeeded() {
        guard let autoRefreshMinutes, autoRefreshMinutes > 0 else { return }
        let maxAge = TimeInterval(autoRefreshMinutes * 60)
        guard let updatedAt = snapshot?.updatedAt else {
            refresh()
            return
        }
        if Date().timeIntervalSince(updatedAt) >= maxAge { refresh() }
    }

    func setHistoricalUsageEnabled(_ enabled: Bool) {
        guard historicalUsageEnabled != enabled else { return }
        historicalUsageEnabled = enabled
        if enabled {
            if snapshot?.historicalIncluded != true || historyNeedsRefresh {
                refreshHistory()
            }
        } else {
            historyGeneration += 1
            isLoadingHistory = false
        }
    }

    func refreshHistory(force: Bool = false) {
        guard historicalUsageEnabled, !demoMode, !isLoadingHistory else { return }
        if !force, snapshot?.historicalIncluded == true, !historyNeedsRefresh { return }

        historyGeneration += 1
        let generation = historyGeneration
        isLoadingHistory = true
        Task {
            do {
                let historicalSnapshot = try await Task.detached(priority: .background) {
                    try UsageScanner.scan()
                }.value
                guard generation == historyGeneration, historicalUsageEnabled, !demoMode else { return }
                let combinedSnapshot = snapshot?.applyingHistorical(from: historicalSnapshot) ?? historicalSnapshot
                snapshot = combinedSnapshot
                UsageSnapshotCache.save(combinedSnapshot)
                UserDefaults.standard.set(Date(), forKey: historyUpdatedDefaultsKey)
            } catch {
                guard generation == historyGeneration else { return }
                errorMessage = error.localizedDescription
            }
            guard generation == historyGeneration else { return }
            isLoadingHistory = false
        }
    }

    func setNotificationThreshold(_ threshold: Int) {
        notificationThreshold = max(0, threshold)
        guard notificationThreshold > 0 else { return }
        Task {
            guard await UsageNotificationService.requestAuthorization(),
                  let snapshot,
                  !demoMode else { return }
            await UsageNotificationService.evaluate(
                snapshot: snapshot,
                threshold: notificationThreshold,
                isChinese: isChinese
            )
        }
    }

    func setLanguage(isChinese: Bool) {
        self.isChinese = isChinese
    }

    func setDemoMode(_ enabled: Bool) {
        guard demoMode != enabled else { return }
        demoMode = enabled
        refreshGeneration += 1
        historyGeneration += 1
        isRefreshing = false
        isLoadingHistory = false
        errorMessage = nil
        if enabled {
            snapshot = .demo()
        } else {
            snapshot = UsageSnapshotCache.load()
            if snapshot == nil {
                refresh()
            } else {
                refreshIfNeeded()
                if historicalUsageEnabled && historyNeedsRefresh { refreshHistory() }
            }
        }
    }

    func reportError(_ message: String) {
        errorMessage = message
    }

    private var historyNeedsRefresh: Bool {
        guard let updatedAt = UserDefaults.standard.object(forKey: historyUpdatedDefaultsKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(updatedAt) >= historyRefreshInterval
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

private struct ModelUsageRow: View {
    let modelID: String
    let details: String
    let total: String
    let cost: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(modelID)
                    .font(.body.weight(.semibold))
                    .textSelection(.enabled)
                Text(details)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Text(total)
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text(cost)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(11)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct UsageMenuView: View {
    @EnvironmentObject private var store: UsageStore
    @AppStorage("language") private var languageRaw = AppLanguage.chinese.rawValue
    @AppStorage("autoRefreshMinutes") private var autoRefreshMinutes = AutoRefreshInterval.tenMinutes.rawValue
    @AppStorage("notificationThreshold") private var notificationThreshold = NotificationThreshold.off.rawValue
    @AppStorage("demoMode") private var demoMode = false
    @AppStorage("historicalUsageEnabled") private var historicalUsageEnabled = false
    @State private var modelScope = ModelUsageScope.currentCycle
    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    @StateObject private var updateChecker = UpdateChecker()

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
        .task {
            if AutoRefreshInterval(rawValue: autoRefreshMinutes) == nil {
                autoRefreshMinutes = AutoRefreshInterval.tenMinutes.rawValue
            }
            if NotificationThreshold(rawValue: notificationThreshold) == nil {
                notificationThreshold = NotificationThreshold.off.rawValue
            }
            launchAtLogin = LaunchAtLoginService.isEnabled
            store.start(
                autoRefreshMinutes: autoRefreshMinutes,
                notificationThreshold: notificationThreshold,
                isChinese: language == .chinese,
                demoMode: demoMode,
                historicalUsageEnabled: historicalUsageEnabled
            )
        }
        .onAppear { store.refreshIfNeeded() }
        .onChange(of: autoRefreshMinutes) { newValue in
            store.setAutoRefresh(minutes: newValue)
        }
        .onChange(of: notificationThreshold) { newValue in
            store.setNotificationThreshold(newValue)
        }
        .onChange(of: languageRaw) { newValue in
            store.setLanguage(isChinese: newValue == AppLanguage.chinese.rawValue)
        }
        .onChange(of: demoMode) { newValue in
            store.setDemoMode(newValue)
        }
        .onChange(of: historicalUsageEnabled) { newValue in
            if !newValue { modelScope = .currentCycle }
            store.setHistoricalUsageEnabled(newValue)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            store.refreshIfNeeded()
        }
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
            if demoMode {
                Label(copy.demoBanner, systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.purple.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(alignment: .top, spacing: 10) {
                if historicalUsageEnabled {
                    SummaryCard(
                        eyebrow: copy.historical,
                        title: copy.totalTokens,
                        tokens: snapshot.historicalIncluded
                            ? formatCompactTokens(snapshot.historicalUsage.totalTokens)
                            : "…",
                        costTitle: copy.apiCost,
                        cost: snapshot.historicalIncluded
                            ? formatCost(snapshot.historicalApiEquivalentUSD, complete: snapshot.historicalCostIsComplete)
                            : copy.unavailable,
                        footnote: store.isLoadingHistory
                            ? copy.calculatingHistory
                            : (snapshot.historicalIncluded ? "\(snapshot.sessionCount) \(copy.sessions)" : copy.historyDisabled),
                        tint: .blue
                    )
                }
                SummaryCard(
                    eyebrow: snapshot.currentCycle.map { "\(copy.currentCycle) · \($0.label)" } ?? copy.currentCycle,
                    title: copy.totalTokens,
                    tokens: formatCompactTokens(snapshot.currentCycleUsage.totalTokens),
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

            modelUsageSection(snapshot)

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

    @ViewBuilder
    private func modelUsageSection(_ snapshot: UsageSnapshot) -> some View {
        sectionHeader(copy.modelUsage, subtitle: nil)
        if historicalUsageEnabled {
            Picker("", selection: $modelScope) {
                ForEach(ModelUsageScope.allCases) { scope in
                    Text(copy.scope(scope)).tag(scope)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }

        let showHistory = historicalUsageEnabled && modelScope == .historical
        let models = showHistory ? snapshot.historicalModels : snapshot.currentCycleModels
        if models.isEmpty {
            Text(copy.noModelUsage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        } else {
            VStack(spacing: 8) {
                ForEach(models, id: \.modelID) { model in
                    ModelUsageRow(
                        modelID: model.modelID,
                        details: modelDetails(model.usage),
                        total: "\(formatCompactTokens(model.usage.totalTokens)) \(copy.tokens)",
                        cost: formatCost(model.apiEquivalentUSD, complete: model.costIsComplete)
                    )
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.snapshot.map { copy.updated($0.updatedAt) } ?? copy.autoRefresh(minutes: autoRefreshMinutes))
                    Text("\(copy.autoRefresh(minutes: autoRefreshMinutes)) · \(copy.localOnly)")
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
                Picker(copy.autoRefreshTitle, selection: $autoRefreshMinutes) {
                    ForEach(AutoRefreshInterval.allCases) { interval in
                        Text(copy.autoRefreshOption(minutes: interval.rawValue)).tag(interval.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                settingsMenu
            }
        }
    }

    private var settingsMenu: some View {
        Menu {
            Toggle(copy.launchAtLogin, isOn: Binding(
                get: { launchAtLogin },
                set: setLaunchAtLogin
            ))

            Toggle(copy.demoMode, isOn: $demoMode)

            Toggle(copy.historicalUsageSetting, isOn: $historicalUsageEnabled)
            if historicalUsageEnabled {
                Button {
                    store.refreshHistory(force: true)
                } label: {
                    Label(
                        store.isLoadingHistory ? copy.calculatingHistory : copy.refreshHistory,
                        systemImage: "clock.arrow.circlepath"
                    )
                }
                .disabled(store.isLoadingHistory || demoMode)
            }

            Picker(copy.notifications, selection: $notificationThreshold) {
                ForEach(NotificationThreshold.allCases) { threshold in
                    Text(copy.notificationOption(threshold: threshold.rawValue)).tag(threshold.rawValue)
                }
            }

            Divider()

            Button {
                updateChecker.performAction()
            } label: {
                Label(copy.updateAction(updateChecker.state), systemImage: updateIcon)
            }
            .disabled(updateChecker.state == .checking)
        } label: {
            Label(copy.settings, systemImage: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var updateIcon: String {
        switch updateChecker.state {
        case .available: return "arrow.down.circle"
        case .current: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        default: return "arrow.triangle.2.circlepath"
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(enabled)
            launchAtLogin = LaunchAtLoginService.isEnabled
            if launchAtLogin != enabled {
                store.reportError(copy.launchAtLoginFailed)
            }
        } catch {
            launchAtLogin = LaunchAtLoginService.isEnabled
            store.reportError(copy.launchAtLoginFailed)
        }
    }

    private func formatCompactTokens(_ value: Int64) -> String {
        TokenFormatter.compact(value)
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

    private func modelDetails(_ usage: TokenUsageSnapshot) -> String {
        [
            "\(copy.input) \(formatCompactTokens(usage.inputTokens))",
            "\(copy.cachedInput) \(formatCompactTokens(usage.cachedInputTokens))",
            "\(copy.output) \(formatCompactTokens(usage.outputTokens))",
            "\(copy.reasoning) \(formatCompactTokens(usage.reasoningOutputTokens))",
        ].joined(separator: " · ")
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
