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
    /// Height the row reserves in the composer accessory stack.
    static let rowHeight: CGFloat = 36
}

/// Mikan's row in the composer accessory stack. Inputs are plain values so the
/// row only re-renders when what Mikan reacts to changes. Double-tap walks
/// Mikan to the other side; a completed response shows `.happy` for 1.2s.
@MainActor
struct MikanCompanionView: View {
    let isActiveStream: Bool
    let hasError: Bool
    /// Identifies the latest completed response; each new value triggers a short celebration.
    let completedResponseID: Date?

    @AppStorage(CompanionSettings.sideKey) private var sideRawValue = CompanionSide.right.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var walkingTo: CompanionSide?
    @State private var celebration = 0
    @State private var isCelebrating = false

    private static let walkDuration = 0.6

    var body: some View {
        MikanView(state: state, walking: walkingTo?.walkDirection)
            .frame(width: 32, height: CompanionSettings.rowHeight)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: switchSides)
            .frame(maxWidth: .infinity, alignment: alignment(for: walkingTo ?? storedSide))
            .onChange(of: completedResponseID) { _, newValue in
                if newValue != nil { celebration += 1 }
            }
            .task(id: celebration) { await celebrate() }
    }

    private var state: CompanionState {
        CompanionStateMachine.state(
            isActiveStream: isActiveStream,
            hasError: hasError,
            justCompletedResponse: isCelebrating
        )
    }

    private var storedSide: CompanionSide {
        CompanionSide(rawValue: sideRawValue) ?? .right
    }

    private func alignment(for side: CompanionSide) -> Alignment {
        let isRight = side == .right
        return isRight == (layoutDirection == .leftToRight) ? .trailing : .leading
    }

    private func switchSides() {
        guard walkingTo == nil else { return }
        let target = storedSide.opposite
        guard !reduceMotion else {
            sideRawValue = target.rawValue
            return
        }
        withAnimation(.easeInOut(duration: Self.walkDuration)) {
            walkingTo = target
        } completion: {
            sideRawValue = target.rawValue
            walkingTo = nil
        }
    }

    private func celebrate() async {
        guard celebration > 0 else { return }
        isCelebrating = true
        try? await Task.sleep(for: .milliseconds(1200))
        // A newer celebration cancels this one and owns the flag.
        if !Task.isCancelled {
            isCelebrating = false
        }
    }
}
