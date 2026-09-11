import AppKit
import Combine
import Foundation
import ServiceManagement
import UserNotifications
import UsageCore

enum UsageSnapshotCache {
    private static let fileManager = FileManager.default

    private static var fileURL: URL? {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        return applicationSupport
            .appendingPathComponent("Codex Usage Monitor", isDirectory: true)
            .appendingPathComponent("usage-snapshot.json")
    }

    static func load() -> UsageSnapshot? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    static func save(_ snapshot: UsageSnapshot) {
        guard let fileURL,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }
}

enum NotificationThreshold: Int, CaseIterable, Identifiable {
    case off = 0
    case fifty = 50
    case seventyFive = 75
    case ninety = 90

    var id: Int { rawValue }
}

enum LaunchAtLoginService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum UsageNotificationService {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func evaluate(
        snapshot: UsageSnapshot,
        threshold: Int,
        isChinese: Bool
    ) async {
        guard threshold > 0 else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        for limit in snapshot.rateLimits where limit.usedPercent >= Double(threshold) {
            let alertID = "\(limit.windowMinutes)-\(Int(limit.resetsAt.timeIntervalSince1970))-\(threshold)"
            let defaultsKey = "usageNotification.last.\(limit.windowMinutes)"
            guard UserDefaults.standard.string(forKey: defaultsKey) != alertID else { continue }

            let content = UNMutableNotificationContent()
            content.title = isChinese ? "Codex 用量提醒" : "Codex usage alert"
            let percent = String(format: "%.0f%%", limit.usedPercent)
            content.body = isChinese
                ? "\(limit.label) 周期已使用 \(percent)，点击菜单栏查看详情。"
                : "The \(limit.label) window is \(percent) used. Open the menu bar app for details."
            content.sound = .default

            do {
                try await center.add(UNNotificationRequest(identifier: alertID, content: content, trigger: nil))
                UserDefaults.standard.set(alertID, forKey: defaultsKey)
            } catch {
                continue
            }
        }
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case current
        case noRelease
        case available(version: String, url: URL)
        case failed
    }

    @Published private(set) var state: State = .idle

    func performAction() {
        if case .available(_, let url) = state {
            NSWorkspace.shared.open(url)
        } else {
            check()
        }
    }

    func check() {
        guard state != .checking else { return }
        state = .checking

        Task {
            do {
                let endpoint = URL(string: "https://api.github.com/repos/wentao-uw/codex-usage-monitor/releases/latest")!
                var request = URLRequest(url: endpoint)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 10
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    state = .failed
                    return
                }
                if http.statusCode == 404 {
                    state = .noRelease
                    return
                }
                guard (200..<300).contains(http.statusCode) else {
                    state = .failed
                    return
                }

                struct Release: Decodable {
                    let tagName: String
                    let htmlURL: URL

                    enum CodingKeys: String, CodingKey {
                        case tagName = "tag_name"
                        case htmlURL = "html_url"
                    }
                }

                let release = try JSONDecoder().decode(Release.self, from: data)
                guard release.htmlURL.host == "github.com" else {
                    state = .failed
                    return
                }
                let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
                state = isNewer(latest, than: current)
                    ? .available(version: release.tagName, url: release.htmlURL)
                    : .current
            } catch {
                state = .failed
            }
        }
    }

    private func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateParts = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let currentParts = current.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(candidateParts.count, currentParts.count)
        for index in 0..<count {
            let left = index < candidateParts.count ? candidateParts[index] : 0
            let right = index < currentParts.count ? currentParts[index] : 0
            if left != right { return left > right }
        }
        return false
    }
}
