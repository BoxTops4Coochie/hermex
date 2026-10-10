/// What Mikan is reacting to.
enum CompanionState: Equatable, Sendable {
    case idle, thinking, happy, sad, annoyed
}

/// Maps chat state onto Mikan's reaction.
/// Priority: annoyed (being poked) > error > just completed > streaming > idle.
enum CompanionStateMachine {
    static func state(
        isActiveStream: Bool,
        hasError: Bool,
        justCompletedResponse: Bool,
        isAnnoyed: Bool = false
    ) -> CompanionState {
        if isAnnoyed { return .annoyed }
        if hasError { return .sad }
        if justCompletedResponse { return .happy }
        if isActiveStream { return .thinking }
        return .idle
    }
}
