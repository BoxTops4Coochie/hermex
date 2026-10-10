/// What Mikan is reacting to.
enum CompanionState: Equatable, Sendable {
    case idle, thinking, happy, sad
}

/// Maps chat state onto Mikan's reaction. Priority: error > just completed > streaming > idle.
enum CompanionStateMachine {
    static func state(isActiveStream: Bool, hasError: Bool, justCompletedResponse: Bool) -> CompanionState {
        if hasError { return .sad }
        if justCompletedResponse { return .happy }
        if isActiveStream { return .thinking }
        return .idle
    }
}
