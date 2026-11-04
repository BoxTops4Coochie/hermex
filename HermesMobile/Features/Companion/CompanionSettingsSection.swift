import SwiftUI

/// Settings > Appearance: turn Mikan on or off and pick a side. The side picker
/// is the VoiceOver-reachable way to move Mikan (the chat double-tap is not).
struct CompanionSettingsSection: View {
    @AppStorage(CompanionSettings.isEnabledKey) private var isEnabled = true
    @AppStorage(CompanionSettings.sideKey) private var sideRawValue = CompanionSide.right.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $isEnabled) {
                HStack(spacing: 12) {
                    MikanView(state: .idle)
                        .frame(width: 36, height: 40)

                    Text("Companion")
                        .font(AppFont.body(weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .toggleStyle(.switch)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

            if isEnabled {
                Picker("Position", selection: $sideRawValue) {
                    ForEach(CompanionSide.allCases) { side in
                        Text(side.title).tag(side.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Text("Mikan sits above the composer and reacts while Hermes works. Double-tap Mikan to switch sides.")
                .font(AppFont.caption())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
