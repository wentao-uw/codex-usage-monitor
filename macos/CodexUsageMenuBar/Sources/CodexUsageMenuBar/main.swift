import AppKit
import Combine
import SwiftUI
import UsageCore

private enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese
    case english

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }
}

private struct Copy {
    let language: AppLanguage

    var title: String { language == .chinese ? "Codex 总用量" : "Codex Total Usage" }
    var totalTokens: String { language == .chinese ? "总 Token 数量" : "Total Tokens" }
    var apiCost: String { language == .chinese ? "API 等价费用" : "API-equivalent Cost" }
    var refresh: String { language == .chinese ? "手动刷新" : "Refresh" }
    var refreshing: String { language == .chinese ? "正在刷新…" : "Refreshing…" }
    var autoRefresh: String { language == .chinese ? "每 10 分钟自动刷新" : "Refreshes every 10 minutes" }
    var unavailable: String { language == .chinese ? "暂不可用" : "Unavailable" }
    var quit: String { language == .chinese ? "退出" : "Quit" }
    var approximate: String { language == .chinese ? "按 API 价格估算" : "Estimated at API prices" }

    func updated(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .chinese ? "zh_Hans_CN" : "en_US")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let time = formatter.string(from: date)
        return language == .chinese ? "更新于 \(time)" : "Updated at \(time)"
    }

    func error(_ message: String) -> String {
        language == .chinese ? "读取失败：\(message)" : "Could not read usage: \(message)"
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
                let next = try await Task.detached(priority: .utility) {
                    try UsageScanner.scan()
                }.value
                snapshot = next
            } catch {
                errorMessage = error.localizedDescription
            }
            isRefreshing = false
        }
    }

    @objc private func scheduledRefresh() {
        refresh()
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let footnote: String?
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct UsageMenuView: View {
    @EnvironmentObject private var store: UsageStore
    @AppStorage("language") private var languageRaw = AppLanguage.chinese.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .chinese
    }

    private var copy: Copy { Copy(language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text(copy.title)
                    .font(.headline)
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
                MetricCard(
                    title: copy.totalTokens,
                    value: formatTokens(snapshot.totalTokens),
                    footnote: nil,
                    systemImage: "number"
                )
                MetricCard(
                    title: copy.apiCost,
                    value: formatCost(snapshot.apiEquivalentUSD, complete: snapshot.costIsComplete),
                    footnote: copy.approximate,
                    systemImage: "dollarsign.circle"
                )
            } else if store.isRefreshing {
                HStack {
                    Spacer()
                    ProgressView(copy.refreshing)
                    Spacer()
                }
                .frame(height: 116)
            }

            if let error = store.errorMessage {
                Label(copy.error(error), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.snapshot.map { copy.updated($0.updatedAt) } ?? copy.autoRefresh)
                    Text(copy.autoRefresh)
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

            Divider()

            Button(copy.quit) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(16)
        .frame(width: 330)
        .task { store.start() }
    }

    private func formatTokens(_ value: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: language == .chinese ? "zh_Hans_CN" : "en_US")
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func formatCost(_ value: Double?, complete: Bool) -> String {
        guard let value else { return copy.unavailable }
        let digits = value < 0.01 ? 4 : 2
        let prefix = complete ? "≈" : "≥"
        return String(format: "%@$%.*f", prefix, digits, value)
    }
}

@main
private struct CodexUsageMenuBarApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            UsageMenuView()
                .environmentObject(store)
        } label: {
            Image(systemName: "chart.bar.xaxis")
                .accessibilityLabel("Codex Usage Monitor")
        }
        .menuBarExtraStyle(.window)
    }
}
