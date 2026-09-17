import SwiftUI
import WidgetKit

struct RecentChatsTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: RecentChatsSnapshot?
}

/// One snapshot per timeline: the widget never calls the server, so there is
/// nothing to predict ahead — the system re-reads the app-group file on the
/// 15-minute policy refresh and whenever the app reloads the kind after
/// writing a changed snapshot.
struct RecentChatsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentChatsTimelineEntry {
        RecentChatsTimelineEntry(date: .now, snapshot: Self.placeholderSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentChatsTimelineEntry) -> Void) {
        completion(RecentChatsTimelineEntry(date: .now, snapshot: RecentChatsSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentChatsTimelineEntry>) -> Void) {
        let entry = RecentChatsTimelineEntry(date: .now, snapshot: RecentChatsSnapshotStore.load())
        let refresh = Date.now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    /// Gallery and transient placeholder only. Real entries come from the
    /// app-group file; the gallery cannot wait for the app to write one.
    private var placeholderSnapshot: RecentChatsSnapshot {
        RecentChatsSnapshot(
            version: 1,
            serverURL: nil,
            generatedAt: .now,
            sessions: [
                RecentChatsSnapshot.Entry(sessionId: "placeholder-refactor", title: String(localized: "Refactor the auth flow"), updatedAt: .now),
                RecentChatsSnapshot.Entry(sessionId: "placeholder-tests", title: String(localized: "Fix flaky streaming tests"), updatedAt: .now.addingTimeInterval(-1_200)),
                RecentChatsSnapshot.Entry(sessionId: "placeholder-release", title: String(localized: "Prepare the release notes"), updatedAt: .now.addingTimeInterval(-4_800))
            ]
        )
    }
}

struct RecentChatsWidgetEntryView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    let entry: RecentChatsTimelineEntry

    var body: some View {
        RecentChatsWidgetContentView(
            snapshot: entry.snapshot,
            displayLimit: widgetFamily == .systemLarge ? 10 : 4
        )
    }
}

struct RecentChatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RecentChatsSnapshotStore.widgetKind, provider: RecentChatsTimelineProvider()) { entry in
            RecentChatsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Recent Chats"))
        .description(String(localized: "Jump straight back into a recent chat."))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
