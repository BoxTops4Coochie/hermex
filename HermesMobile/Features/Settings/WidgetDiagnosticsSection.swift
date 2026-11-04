import SwiftUI

/// Temporary diagnostics for the recent-chats widget plumbing.
/// Shows the app-group id the app resolves, whether the shared container
/// is reachable, whether a snapshot file exists, and — critically — what
/// the installed binary's embedded.mobileprovision actually grants.
struct WidgetDiagnosticsSection: View {
    struct DiagInfo {
        var requestedGroup: String = "…"
        var container: Bool = false
        var snapshot: String = "…"
        var profileName: String = "…"
        var profileAppID: String = "…"
        var profileGroups: String = "…"
        var profileExpires: String = "…"
    }

    @State private var info = DiagInfo()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Widget Diagnostics")
                .font(.headline)
            Text("Requested group: \(info.requestedGroup)\nProfile: \(info.profileName)\nProfile appID: \(info.profileAppID)\nProfile groups: \(info.profileGroups)\nProfile expires: \(info.profileExpires)\nContainer reachable: \(info.container ? "YES" : "NO")\nSnapshot: \(info.snapshot)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear(perform: measure)
    }

    private func measure() {
        var d = DiagInfo()
        d.requestedGroup = RecentChatsSnapshotStore.appGroupIdentifier

        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: d.requestedGroup)
        d.container = container != nil
        if let url = RecentChatsSnapshotStore.defaultFileURL,
           FileManager.default.fileExists(atPath: url.path) {
            d.snapshot = "present (\(url.lastPathComponent))"
        } else if let url = RecentChatsSnapshotStore.defaultFileURL {
            d.snapshot = "missing (\(url.path))"
        } else {
            d.snapshot = "no container URL"
        }

        if let profileURL = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
           let data = try? Data(contentsOf: profileURL),
           let str = String(data: data, encoding: .isoLatin1),
           let start = str.range(of: "<?xml"),
           let end = str.range(of: "</plist>") {
            let plistStr = String(str[start.lowerBound..<end.upperBound])
            if let plistData = plistStr.data(using: .isoLatin1),
               let plist = try? PropertyListSerialization.propertyList(
                   from: plistData, format: nil) as? [String: Any] {
                d.profileName = plist["Name"] as? String ?? "?"
                if let appID = plist["ApplicationIdentifier"] as? [String: String] {
                    d.profileAppID = appID.values.first ?? "?"
                }
                if let ents = plist["Entitlements"] as? [String: Any] {
                    if let groups = ents["com.apple.security.application-groups"] as? [String],
                       !groups.isEmpty {
                        d.profileGroups = groups.joined(separator: ", ")
                    } else {
                        d.profileGroups = "NONE GRANTED"
                    }
                }
                if let exp = plist["ExpirationDate"] as? Date {
                    let f = DateFormatter()
                    f.dateStyle = .short
                    d.profileExpires = f.string(from: exp)
                }
            }
        } else {
            d.profileName = "no embedded.mobileprovision"
        }
        info = d
    }
}
