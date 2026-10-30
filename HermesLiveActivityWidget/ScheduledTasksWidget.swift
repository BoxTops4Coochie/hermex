import SwiftUI
import WidgetKit

struct ScheduledTasksTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: ScheduledTasksSnapshot?
}

/// One snapshot per timeline: the widget never calls the server, so there is
/// nothing to predict ahead — the system re-reads the app-group file on the
/// 15-minute policy refresh and whenever the app reloads the kind after
/// writing a changed snapshot.
struct ScheduledTasksTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduledTasksTimelineEntry {
        ScheduledTasksTimelineEntry(date: .now, snapshot: Self.placeholderSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduledTasksTimelineEntry) -> Void) {
        completion(ScheduledTasksTimelineEntry(date: .now, snapshot: ScheduledTasksSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduledTasksTimelineEntry>) -> Void) {
        let entry = ScheduledTasksTimelineEntry(date: .now, snapshot: ScheduledTasksSnapshotStore.load())
        let refresh = Date.now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    /// Gallery and transient placeholder only. Real entries come from the
    /// app-group file; the gallery cannot wait for the app to write one.
    private static var placeholderSnapshot: ScheduledTasksSnapshot {
        let now = Date.now
        return ScheduledTasksSnapshot(
            version: 1,
            serverURL: nil,
            generatedAt: now,
            tasks: [
                ScheduledTasksSnapshot.Entry(
                    jobId: "placeholder-daily-backup",
                    name: String(localized: "Daily backup"),
                    scheduleDisplay: String(localized: "Every day at 6:00 PM"),
                    nextRunAt: now.addingTimeInterval(60 * 60),
                    lastStatus: "ok",
                    enabled: true
                ),
                ScheduledTasksSnapshot.Entry(
                    jobId: "placeholder-weekly-report",
                    name: String(localized: "Weekly report"),
                    scheduleDisplay: nil,
                    nextRunAt: now.addingTimeInterval(24 * 60 * 60),
                    lastStatus: "error",
                    enabled: true
                ),
                ScheduledTasksSnapshot.Entry(
                    jobId: "placeholder-morning-briefing",
                    name: String(localized: "Morning briefing"),
                    scheduleDisplay: nil,
                    nextRunAt: now.addingTimeInterval(2 * 24 * 60 * 60),
                    lastStatus: "running",
                    enabled: true
                )
            ]
        )
    }
}

struct ScheduledTasksWidgetView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    let snapshot: ScheduledTasksSnapshot?

    var body: some View {
        rowsOrEmptyState
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) {
                RecentChatsWidgetTheme.background.ignoresSafeArea()
            }
            .widgetURL(HermesDeepLink.tasksURL())
    }

    private var rowsOrEmptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            let tasks = visibleTasks
            if tasks.isEmpty {
                emptyState
            } else {
                ForEach(tasks) { entry in
                    ScheduledTasksWidgetRowView(
                        entry: entry,
                        showsSchedule: widgetFamily != .systemSmall
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var visibleTasks: [ScheduledTasksSnapshot.Entry] {
        let all = snapshot?.tasks ?? []
        return Array(all.prefix(ScheduledTasksWidgetPresentation.rowCount(family: widgetFamily, taskCount: all.count)))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "clock")
                .font(.caption2.weight(.bold))
                .foregroundStyle(RecentChatsWidgetTheme.secondaryText)

            Text(String(localized: "Scheduled Tasks"))
                .font(.caption2.weight(.bold))
                .foregroundStyle(RecentChatsWidgetTheme.secondaryText)
                .textCase(.uppercase)
                .lineLimit(1)

            Spacer(minLength: 8)
        }
        .padding(.bottom, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.title3.weight(.medium))
                .foregroundStyle(RecentChatsWidgetTheme.secondaryText)

            Text(String(localized: "No scheduled tasks"))
                .font(.footnote.weight(.medium))
                .foregroundStyle(RecentChatsWidgetTheme.primaryText)
                .lineLimit(1)

            Text(String(localized: "Open Hermex to load tasks"))
                .font(.caption2)
                .foregroundStyle(RecentChatsWidgetTheme.secondaryText)
                .lineLimit(1)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct ScheduledTasksWidgetRowView: View {
    let entry: ScheduledTasksSnapshot.Entry
    var showsSchedule = true

    private var status: ScheduledTasksWidgetStatus {
        ScheduledTasksWidgetStatus.status(lastStatus: entry.lastStatus, enabled: entry.enabled)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            statusDot

            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(displayNameColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if showsSchedule, let schedule = scheduleDisplay {
                    Text(schedule)
                        .font(.caption2)
                        .foregroundStyle(RecentChatsWidgetTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 6)

            if entry.enabled != false, let nextRunAt = entry.nextRunAt {
                Text(nextRunAt, format: .relative(presentation: .named))
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
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusDot: some View {
        if status == .disabled {
            Circle()
                .stroke(RecentChatsWidgetTheme.secondaryText.opacity(0.5), lineWidth: 1)
                .frame(width: 6, height: 6)
        } else {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
        }
    }

    private var displayNameColor: Color {
        status == .disabled ? RecentChatsWidgetTheme.secondaryText : RecentChatsWidgetTheme.primaryText
    }

    private var displayName: String {
        let name = entry.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else {
            return String(localized: "Untitled Task")
        }
        return name
    }

    private var scheduleDisplay: String? {
        let schedule = entry.scheduleDisplay?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let schedule, !schedule.isEmpty else { return nil }
        return schedule
    }
}

private extension ScheduledTasksWidgetStatus {
    var color: Color {
        switch self {
        case .running:
            return Color(red: 0.40, green: 0.70, blue: 1.0)
        case .error:
            return Color(red: 1.0, green: 0.36, blue: 0.36)
        case .active:
            return Color(red: 0.35, green: 0.90, blue: 0.55)
        case .disabled:
            return RecentChatsWidgetTheme.secondaryText
        }
    }
}

struct ScheduledTasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ScheduledTasksSnapshotStore.widgetKind, provider: ScheduledTasksTimelineProvider()) { entry in
            ScheduledTasksWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName(String(localized: "Scheduled Tasks"))
        .description(String(localized: "Your next scheduled tasks."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
