import Foundation
import SwiftUI
import WidgetKit

/// Snapshot of the active server's scheduled tasks, handed to the Home Screen
/// widget through the app group. The widget renders this file as-is with no
/// network access; the app rewrites it whenever the task list refreshes (see
/// `TasksViewModel.updateScheduledTasksSnapshot`).
///
/// Every field is optional so older or newer writers never crash the reader
/// (same tolerance contract as `RecentChatsSnapshot`).
struct ScheduledTasksSnapshot: Codable, Equatable {
    struct Entry: Codable, Equatable, Identifiable {
        let jobId: String?
        let name: String?
        /// Human schedule from the server, e.g. "Every day at 6:00 PM".
        let scheduleDisplay: String?
        /// Absolute next run; the widget renders relative text from it.
        let nextRunAt: Date?
        /// `"ok"`, `"error"`, `"running"`, or nil.
        let lastStatus: String?
        let enabled: Bool?

        var id: String { jobId ?? name ?? UUID().uuidString }

        enum CodingKeys: String, CodingKey {
            case jobId
            case name
            case scheduleDisplay
            case nextRunAt
            case lastStatus
            case enabled
        }

        init(
            jobId: String?,
            name: String?,
            scheduleDisplay: String?,
            nextRunAt: Date?,
            lastStatus: String?,
            enabled: Bool?
        ) {
            self.jobId = jobId
            self.name = name
            self.scheduleDisplay = scheduleDisplay
            self.nextRunAt = nextRunAt
            self.lastStatus = lastStatus
            self.enabled = enabled
        }

        init(from decoder: Decoder) throws {
            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                jobId = nil
                name = nil
                scheduleDisplay = nil
                nextRunAt = nil
                lastStatus = nil
                enabled = nil
                return
            }

            jobId = container.scheduledTasksLossyStringIfPresent(forKey: .jobId)
            name = container.scheduledTasksLossyStringIfPresent(forKey: .name)
            scheduleDisplay = container.scheduledTasksLossyStringIfPresent(forKey: .scheduleDisplay)
            nextRunAt = container.scheduledTasksLossyDateIfPresent(forKey: .nextRunAt)
            lastStatus = container.scheduledTasksLossyStringIfPresent(forKey: .lastStatus)
            enabled = container.scheduledTasksLossyBoolIfPresent(forKey: .enabled)
        }
    }

    let version: Int?
    let serverURL: String?
    let generatedAt: Date?
    let tasks: [Entry]?

    enum CodingKeys: String, CodingKey {
        case version
        case serverURL
        case generatedAt
        case tasks
    }

    init(version: Int?, serverURL: String?, generatedAt: Date?, tasks: [Entry]?) {
        self.version = version
        self.serverURL = serverURL
        self.generatedAt = generatedAt
        self.tasks = tasks
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            version = nil
            serverURL = nil
            generatedAt = nil
            tasks = nil
            return
        }

        version = container.scheduledTasksLossyIntIfPresent(forKey: .version)
        serverURL = container.scheduledTasksLossyStringIfPresent(forKey: .serverURL)
        generatedAt = container.scheduledTasksLossyDateIfPresent(forKey: .generatedAt)
        tasks = (try? container.decodeIfPresent([Entry].self, forKey: .tasks)) ?? nil
    }
}

/// Reads and writes `ScheduledTasksSnapshot` in the shared app-group container.
/// Compiled into both the app (writer) and the widget (reader), so it must not
/// reference app-only types like `CronJob`.
enum ScheduledTasksSnapshotStore {
    static let widgetKind = "ScheduledTasksWidget"
    static let maximumTaskCount = 12

    static var appGroupIdentifier: String {
        RecentChatsSnapshotStore.appGroupIdentifier
    }

    static var defaultFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("scheduled-tasks-snapshot.json", isDirectory: false)
    }

    /// Writes the snapshot atomically with full at-rest file protection. The
    /// list is capped so the widget file stays small (2 small, 4 medium, 8
    /// large rows plus headroom). Returns true when the file's content actually
    /// changed, so callers can skip the WidgetKit timeline reload when a
    /// refresh carried the same tasks as before.
    @discardableResult
    static func write(_ snapshot: ScheduledTasksSnapshot, to fileURL: URL? = nil) -> Bool {
        guard let fileURL = fileURL ?? defaultFileURL else { return false }

        let capped = cappedSnapshot(snapshot)

        if let existing = load(from: fileURL),
           existing.tasks == capped.tasks,
           existing.serverURL == capped.serverURL {
            return false
        }

        do {
            let data = try JSONEncoder().encode(capped)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            return false
        }
    }

    static func cappedSnapshot(_ snapshot: ScheduledTasksSnapshot) -> ScheduledTasksSnapshot {
        guard let tasks = snapshot.tasks, tasks.count > maximumTaskCount else { return snapshot }
        return ScheduledTasksSnapshot(
            version: snapshot.version,
            serverURL: snapshot.serverURL,
            generatedAt: snapshot.generatedAt,
            tasks: Array(tasks.prefix(maximumTaskCount))
        )
    }

    /// Deletes the snapshot file and reloads the widget, so tasks rendered for
    /// a previous server (or a signed-out state) never linger.
    static func clear(fileURL: URL? = nil) {
        guard let fileURL = fileURL ?? defaultFileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    /// nil when nothing was written yet (fresh install) or the file is
    /// unreadable/malformed — the widget then shows its empty state.
    static func load(from fileURL: URL? = nil) -> ScheduledTasksSnapshot? {
        guard let fileURL = fileURL ?? defaultFileURL else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(ScheduledTasksSnapshot.self, from: data)
    }
}

/// Pure presentation policy, kept beside the snapshot so the app's test target
/// can exercise it without importing the widget extension.
enum ScheduledTasksWidgetPresentation {
    /// Rows a family can show: small 2, medium 4, large 8.
    static func rowCount(family: WidgetFamily, taskCount: Int) -> Int {
        let limit: Int
        switch family {
        case .systemSmall:
            limit = 2
        case .systemMedium:
            limit = 4
        case .systemLarge:
            limit = 8
        default:
            limit = 2
        }
        return min(max(taskCount, 0), limit)
    }
}

enum ScheduledTasksWidgetStatus: Equatable {
    case running
    case error
    case active
    case disabled

    static func status(lastStatus: String?, enabled: Bool?) -> ScheduledTasksWidgetStatus {
        if enabled == false { return .disabled }

        switch lastStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "running":
            return .running
        case "error", "failed":
            return .error
        default:
            return .active
        }
    }
}

private extension KeyedDecodingContainer {
    func scheduledTasksLossyStringIfPresent(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }

        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return "\(value)"
        }

        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return "\(value)"
        }

        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }

        return nil
    }

    func scheduledTasksLossyIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }

        if let value = try? decodeIfPresent(Double.self, forKey: key),
           value.isFinite {
            return Int(exactly: value.rounded(.towardZero))
        }

        guard let stringValue = try? decodeIfPresent(String.self, forKey: key) else {
            return nil
        }

        let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Int(trimmed) {
            return value
        }

        guard let value = Double(trimmed), value.isFinite else { return nil }
        return Int(exactly: value.rounded(.towardZero))
    }

    func scheduledTasksLossyBoolIfPresent(forKey key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value
        }

        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            switch value {
            case 0:
                return false
            case 1:
                return true
            default:
                return nil
            }
        }

        guard let stringValue = try? decodeIfPresent(String.self, forKey: key) else {
            return nil
        }

        switch stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1":
            return true
        case "false", "0":
            return false
        default:
            return nil
        }
    }

    func scheduledTasksLossyDateIfPresent(forKey key: Key) -> Date? {
        if let value = try? decodeIfPresent(Date.self, forKey: key) {
            return value
        }

        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: value)
        }

        guard let stringValue = try? decodeIfPresent(String.self, forKey: key) else {
            return nil
        }

        let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(trimmed) {
            return Date(timeIntervalSince1970: value)
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let value = isoFormatter.date(from: trimmed) {
            return value
        }

        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return isoFormatter.date(from: trimmed)
    }
}
