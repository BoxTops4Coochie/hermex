import SwiftUI

/// Which screen edge Mikan sits on. Physical left/right, so it stays put in RTL.
enum CompanionSide: String, CaseIterable, Identifiable, Sendable {
    case left, right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: String(localized: "Left")
        case .right: String(localized: "Right")
        }
    }

    var opposite: CompanionSide { self == .left ? .right : .left }

    var walkDirection: MikanWalkDirection { self == .left ? .left : .right }
}

enum CompanionSettings {
    static let isEnabledKey = "companion.enabled"
    static let sideKey = "companion.side"
    /// Mikan's rendered size; the height is also what the row reserves in the composer accessory stack.
    static let width: CGFloat = 70
    static let rowHeight: CGFloat = 77
}

/// Mikan's row in the composer accessory stack. Inputs are plain values so the
/// row only re-renders when what Mikan reacts to changes.
///
/// Taps: a double-tap walks Mikan to the other side; five taps within 2.5s make
/// Mikan annoyed until 3s pass without a tap. A completed response shows
/// `.happy` (pointing at the new message) for 2s. Once a tool runs during a reply,
/// Mikan works at a laptop until that reply's stream ends.
@MainActor
struct MikanCompanionView: View {
    let isActiveStream: Bool
    let hasError: Bool
    /// True while any live tool call is unfinished.
    let isRunningTool: Bool
    /// Identifies the latest completed response; each new value triggers a short celebration.
    let completedResponseID: Date?

    @AppStorage(CompanionSettings.sideKey) private var sideRawValue = CompanionSide.right.rawValue
    @AppStorage(AppHaptics.isEnabledKey) private var isHapticsEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    /// Drives the walk pose (legs, facing). Kept separate from `walkPosition` so the
    /// pose change gets a short animation and only the position gets the slow walk.
    @State private var walkingTo: CompanionSide?
    @State private var walkPosition: CompanionSide?
    @State private var celebration = 0
    @State private var isCelebrating = false
    @State private var recentTaps: [Date] = []
    @State private var annoyance = 0
    @State private var isAnnoyed = false
    @State private var isWorking = false

    private static let walkDuration = 3.0
    private static let celebrationDuration: Duration = .seconds(2)
    private static let doubleTapInterval: TimeInterval = 0.35
    private static let annoyingTapCount = 5
    private static let annoyingTapWindow: TimeInterval = 2.5
    private static let calmDownDelay: Duration = .seconds(3)

    var body: some View {
        MikanView(state: state, walking: walkingTo?.walkDirection, pointing: newestMessageDirection)
            .frame(width: CompanionSettings.width, height: CompanionSettings.rowHeight)
            .contentShape(Rectangle())
            .onTapGesture(perform: handleTap)
            .frame(maxWidth: .infinity, alignment: alignment(for: walkPosition ?? storedSide))
            .onChange(of: completedResponseID) { _, newValue in
                if newValue != nil { celebration += 1 }
            }
            .task(id: celebration) { await celebrate() }
            .task(id: annoyance) { await calmDown() }
            .onChange(of: isRunningTool, initial: true) { _, running in
                if running { isWorking = true }
            }
            .onChange(of: isActiveStream) { _, streaming in
                if !streaming { isWorking = false }
            }
    }

    private var state: CompanionState {
        CompanionStateMachine.state(
            isActiveStream: isActiveStream,
            hasError: hasError,
            justCompletedResponse: isCelebrating,
            isRunningTool: isWorking,
            isAnnoyed: isAnnoyed
        )
    }

    private var storedSide: CompanionSide {
        CompanionSide(rawValue: sideRawValue) ?? .right
    }

    /// Assistant messages sit on the leading side of the transcript.
    private var newestMessageDirection: MikanWalkDirection {
        layoutDirection == .leftToRight ? .left : .right
    }

    private func alignment(for side: CompanionSide) -> Alignment {
        let isRight = side == .right
        return isRight == (layoutDirection == .leftToRight) ? .trailing : .leading
    }

    /// Single taps are counted here rather than with `onTapGesture(count: 2)` so a
    /// double-tap walks immediately and rapid tapping can still build up annoyance.
    private func handleTap() {
        let now = Date()
        recentTaps = recentTaps.filter { now.timeIntervalSince($0) < Self.annoyingTapWindow } + [now]

        if isAnnoyed || recentTaps.count >= Self.annoyingTapCount {
            if !isAnnoyed {
                ChatHaptics.companionAnnoyed(isEnabled: isHapticsEnabled)
            }
            isAnnoyed = true
            annoyance += 1
            return
        }

        if recentTaps.count >= 2,
           now.timeIntervalSince(recentTaps[recentTaps.count - 2]) < Self.doubleTapInterval {
            switchSides()
        }
    }

    private func switchSides() {
        guard walkingTo == nil, walkPosition == nil else { return }
        let target = storedSide.opposite
        guard !reduceMotion else {
            sideRawValue = target.rawValue
            return
        }
        withAnimation(.easeOut(duration: 0.25)) {
            walkingTo = target
        }
        withAnimation(.easeInOut(duration: Self.walkDuration)) {
            walkPosition = target
        } completion: {
            sideRawValue = target.rawValue
            walkPosition = nil
            withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
                walkingTo = nil
            }
        }
    }

    private func celebrate() async {
        guard celebration > 0 else { return }
        isCelebrating = true
        try? await Task.sleep(for: Self.celebrationDuration)
        // A newer celebration cancels this one and owns the flag.
        if !Task.isCancelled {
            isCelebrating = false
        }
    }

    /// Each annoying tap restarts this; Mikan calms down once the taps stop.
    private func calmDown() async {
        guard annoyance > 0 else { return }
        try? await Task.sleep(for: Self.calmDownDelay)
        if !Task.isCancelled {
            isAnnoyed = false
            recentTaps.removeAll()
        }
    }
}
