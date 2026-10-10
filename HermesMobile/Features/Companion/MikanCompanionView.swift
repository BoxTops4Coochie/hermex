import SwiftUI

enum CompanionSettings {
    static let isEnabledKey = "companion.enabled"
    static let sideKey = "companion.side"
    /// Mikan's rendered size. The row reserves no transcript space (Mikan overlaps the chat).
    static let width: CGFloat = 70
    static let rowHeight: CGFloat = 77
}

/// Classifies taps on Mikan: a quick pair is a double-tap (walk), five taps within
/// 2.5s make Mikan annoyed. Counted per tap rather than with `onTapGesture(count: 2)`
/// so a double-tap walks immediately and rapid tapping can still build up annoyance.
struct CompanionTapTracker {
    enum Outcome: Equatable {
        case none, doubleTap, becameAnnoyed, stillAnnoyed
    }

    static let doubleTapInterval: TimeInterval = 0.35
    static let annoyingTapCount = 5
    static let annoyingTapWindow: TimeInterval = 2.5

    private var recentTaps: [Date] = []
    /// First tap of a potential double-tap; cleared once a pair is used so a third
    /// quick tap starts a new pair instead of walking again.
    private var pendingTap: Date?
    private(set) var isAnnoyed = false

    mutating func register(at now: Date) -> Outcome {
        recentTaps = recentTaps.filter { now.timeIntervalSince($0) < Self.annoyingTapWindow } + [now]
        if isAnnoyed || recentTaps.count >= Self.annoyingTapCount {
            let wasAnnoyed = isAnnoyed
            isAnnoyed = true
            pendingTap = nil
            return wasAnnoyed ? .stillAnnoyed : .becameAnnoyed
        }
        if let pendingTap, now.timeIntervalSince(pendingTap) < Self.doubleTapInterval {
            self.pendingTap = nil
            return .doubleTap
        }
        pendingTap = now
        return .none
    }

    mutating func calmDown() {
        isAnnoyed = false
        recentTaps.removeAll()
        pendingTap = nil
    }
}

/// Mikan's row in the composer accessory stack. Inputs are plain values so the
/// row only re-renders when what Mikan reacts to changes.
///
/// A double-tap walks Mikan to the other side; five quick taps make it annoyed
/// until 3s pass without a tap. A completed response shows `.happy` (pointing at
/// the new message) for 2s. Each reply starts with Mikan thinking; once a tool
/// runs or answer text arrives, Mikan works at a laptop until the reply ends.
@MainActor
struct MikanCompanionView: View {
    /// The active stream, or nil when no reply is streaming.
    let streamID: String?
    /// A current send or load error.
    let hasError: Bool
    /// The latest finished run failed.
    let lastRunFailed: Bool
    /// True while any live tool call is unfinished.
    let isRunningTool: Bool
    /// This reply's answer text has started arriving (`ChatViewModel.hasLiveAnswerText`).
    let hasAnswerText: Bool
    /// Identifies the latest completed response; each new value triggers a short celebration.
    let completedResponseID: Date?
    /// Where assistant messages sit in the transcript, so `.happy` points at the reply.
    let newestMessageSide: CompanionSide

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
    @State private var taps = CompanionTapTracker()
    @State private var annoyance = 0
    /// The stream in which a tool has run. Keyed by ID so it never carries into the next reply.
    @State private var toolUsedInStream: String?

    private static let walkDuration = 3.0
    private static let celebrationDuration: Duration = .seconds(2)
    private static let calmDownDelay: Duration = .seconds(3)

    var body: some View {
        MikanView(state: state, walking: walkingTo, pointing: newestMessageSide)
            .frame(width: CompanionSettings.width, height: CompanionSettings.rowHeight)
            // Just the cat's body, so the transcript under the rest of the frame stays
            // scrollable and tappable. Mikan ignores touches mid-walk (hit-testing uses
            // the destination, not the animated position).
            .contentShape(Capsule().scale(x: 0.55, y: 0.92, anchor: .bottom))
            .onTapGesture(perform: handleTap)
            .allowsHitTesting(walkingTo == nil && walkPosition == nil)
            .frame(maxWidth: .infinity, alignment: alignment(for: walkPosition ?? storedSide))
            .onChange(of: completedResponseID) { _, newValue in
                if newValue != nil { celebration += 1 }
            }
            .onChange(of: isRunningTool, initial: true) { _, running in
                if running, let streamID { toolUsedInStream = streamID }
            }
            .task(id: celebration) { await celebrate() }
            .task(id: annoyance) { await calmDown() }
    }

    private var state: CompanionState {
        let isActiveStream = streamID != nil
        return CompanionStateMachine.state(
            isActiveStream: isActiveStream,
            hasError: hasError,
            justCompletedResponse: isCelebrating,
            lastRunFailed: lastRunFailed,
            isWorking: hasAnswerText || (isActiveStream && toolUsedInStream == streamID),
            isAnnoyed: taps.isAnnoyed
        )
    }

    private var storedSide: CompanionSide {
        CompanionSide(rawValue: sideRawValue) ?? .right
    }

    private func alignment(for side: CompanionSide) -> Alignment {
        let isRight = side == .right
        return isRight == (layoutDirection == .leftToRight) ? .trailing : .leading
    }

    private func handleTap() {
        switch taps.register(at: Date()) {
        case .doubleTap:
            switchSides()
        case .becameAnnoyed:
            ChatHaptics.companionAnnoyed(isEnabled: isHapticsEnabled)
            annoyance += 1
        case .stillAnnoyed:
            annoyance += 1
        case .none:
            break
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
            taps.calmDown()
        }
    }
}
