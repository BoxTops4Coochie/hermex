import SwiftUI

/// Temporary diagnostics row for the recent-chats widget plumbing.
/// Shows the app-group id the app resolves, whether the shared container
/// is reachable, and whether a snapshot file exists in it.
struct WidgetDiagnosticsSection: View {
    @State private var info: (groupID: String, container: Bool, snapshot: String) =
        ("…", false, "…")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Widget Diagnostics")
                .font(.headline)
            Text("App group: \(info.groupID)\nContainer reachable: \(info.container ? "YES" : "NO")\nSnapshot: \(info.snapshot)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear(perform: measure)
    }

    private func measure() {
        let groupID = RecentChatsSnapshotStore.appGroupIdentifier
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID)
        let snapshotURL = RecentChatsSnapshotStore.defaultFileURL
        var snapshotState = "none"
        if let url = snapshotURL,
           FileManager.default.fileExists(atPath: url.path) {
            snapshotState = "present (\(url.lastPathComponent))"
        } else if let url = snapshotURL {
            snapshotState = "missing (\(url.path))"
        } else {
            snapshotState = "no container URL"
        }
        info = (groupID, container != nil, snapshotState)
    }
}
