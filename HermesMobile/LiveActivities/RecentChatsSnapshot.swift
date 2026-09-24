import Foundation
import SwiftUI
import WidgetKit

/// Snapshot of the active server's recent session list, handed to the Home
/// Screen widget through the app group. The widget renders this file as-is
/// with no network access; the app rewrites it whenever the session list
/// refreshes (see `SessionListViewModel.updateRecentChatsSnapshot`).
///
/// Every field is optional so older or newer writers never crash the reader
/// (same tolerance contract as `SharedDraftPayload`).
struct RecentChatsSnapshot: Codable, Equatable {
    struct Entry: Codable, Equatable, Identifiable {
        let sessionId: String?
        let title: String?
        let updatedAt: Date?

        var id: String {
            sessionId ?? title ?? ""
        }
    }

    let version: Int?
    /// Absolute URL string of the server the rows came from. Set only when
    /// more than one server is configured, so the widget can say where its
    /// rows live (single-server installs are unambiguous).
    let serverURL: String?
    let generatedAt: Date?
    let sessions: [Entry]?
}

/// Reads and writes `RecentChatsSnapshot` in the shared app-group container.
/// Compiled into both the app (writer) and the widget (reader), so it must not
/// reference app-only types like `SessionSummary`.
enum RecentChatsSnapshotStore {
    static let widgetKind = "RecentChatsWidget"
    static let maximumSessionCount = 12

    static var appGroupIdentifier: String {
        let hinted = Bundle.main.object(forInfoDictionaryKey: "HermesAppGroupIdentifier") as? String
        if let hinted,
           FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: hinted) != nil {
            return hinted
        }
        // SideStore's signing flow re-creates the APP_GROUPS capability on every
        // sign, and Apple compounds the implicit group name once per recreation
        // (group.<bundle-id>.<team>, then .<team> again, ...). The hardcoded hint
        // therefore lags the profile by one generation after each re-sign. Scan
        // the embedded provisioning profile for every granted group and return
        // the first one iOS will actually open a container for.
        for granted in provisionedAppGroups {
            if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: granted) != nil {
                return granted
            }
        }
        return hinted ?? "group.com.uzairansar.hermesmobile"
    }

    /// App group names granted by the provisioning profile embedded in this
    /// binary (embedded.mobileprovision), extracted from its plist XML payload.
    static var provisionedAppGroups: [String] {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let xmlStart = data.range(of: Data("<?xml".utf8)),
              let xmlEnd = data.range(of: Data("</plist>".utf8))
        else { return [] }
        let xml = data.subdata(in: xmlStart.lowerBound..<xmlEnd.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return [] }
        return groups
    }

    /// Caps and stamps a mapped session list. Callers sort their entries by
    /// recency; the snapshot keeps the first `maximumSessionCount`.
    static func makeSnapshot(
        from entries: [RecentChatsSnapshot.Entry],
        serverURL: String?
    ) -> RecentChatsSnapshot {
        RecentChatsSnapshot(
            version: 1,
            serverURL: serverURL,
            generatedAt: Date(),
            sessions: Array(entries.prefix(maximumSessionCount))
        )
    }

    /// Writes the snapshot atomically. Returns true when the file's content
    /// actually changed, so callers can skip the WidgetKit timeline reload
    /// when a refresh carried the same sessions as before.
    @discardableResult
    static func write(_ snapshot: RecentChatsSnapshot, to fileURL: URL? = nil) -> Bool {
        guard let fileURL = fileURL ?? defaultFileURL else { return false }

        if let existing = load(from: fileURL),
           existing.sessions == snapshot.sessions,
           existing.serverURL == snapshot.serverURL {
            return false
        }

        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    /// nil when nothing was written yet (fresh install) or the file is
    /// unreadable/malformed — the widget then shows its empty state.
    static func load(from fileURL: URL? = nil) -> RecentChatsSnapshot? {
        guard let fileURL = fileURL ?? defaultFileURL else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(RecentChatsSnapshot.self, from: data)
    }

    static var defaultFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("recent-chats-snapshot.json", isDirectory: false)
    }
}

/// The widget's content for both supported families. Lives beside the snapshot
/// model so the app's test target can render it with `ImageRenderer` without
/// importing the widget extension.
struct RecentChatsWidgetContentView: View {
    let snapshot: RecentChatsSnapshot?
    let displayLimit: Int

    var body: some View {
        rowsOrEmptyState
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) {
                RecentChatsWidgetTheme.background.ignoresSafeArea()
            }
    }

    private var rowsOrEmptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            let sessions = (snapshot?.sessions ?? []).prefix(displayLimit)
            if sessions.isEmpty {
                emptyState
            } else {
                ForEach(Array(sessions)) { entry in
                    RecentChatsWidgetRowView(entry: entry)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption2.weight(.bold))
                .foregroundStyle(RecentChatsWidgetTheme.secondaryText)

            Text(String(localized: "Recent Chats"))
                .font(.caption2.weight(.bold))
                .foregroundStyle(RecentChatsWidgetTheme.secondaryText)
                .textCase(.uppercase)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let serverHost = serverHostLabel {
                Text(serverHost)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(RecentChatsWidgetTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.bottom, 2)
    }

    /// Shown only for multi-server setups (the snapshot omits the server for
    /// single-server installs), so rows always say where they came from.
    private var serverHostLabel: String? {
        guard let serverURL = snapshot?.serverURL else { return nil }
        return URL(string: serverURL)?.host
    }

    private var emptyState: some View {
        Text(String(localized: "Open Hermex to load chats"))
            .font(.footnote.weight(.medium))
            .foregroundStyle(RecentChatsWidgetTheme.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct RecentChatsWidgetRowView: View {
    let entry: RecentChatsSnapshot.Entry

    var body: some View {
        // WidgetKit's multi-destination tap target: each row carries its own
        // session deep link (`Link`, not `widgetURL`, which is one-per-widget).
        // A row that somehow decodes without a usable session id still renders,
        // just without a tap destination.
        if let linkURL = HermesDeepLink.sessionURL(sessionID: entry.sessionId ?? "") {
            Link(destination: linkURL) {
                rowContent
            }
            .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(displayTitle)
                .font(.footnote.weight(.medium))
                .foregroundStyle(RecentChatsWidgetTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            if let updatedAt = entry.updatedAt {
                Text(updatedAt, style: .relative)
                    .font(.caption2.weight(.regular))
                    .foregroundStyle(RecentChatsWidgetTheme.secondaryText)
                    .lineLimit(1)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RecentChatsWidgetTheme.rowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var displayTitle: String {
        let title = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty else {
            return String(localized: "Untitled Session")
        }
        return title
    }
}

private enum RecentChatsWidgetTheme {
    static let background = Color(red: 0.025, green: 0.028, blue: 0.038)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.68)
    static let rowBackground = Color.white.opacity(0.08)
}
