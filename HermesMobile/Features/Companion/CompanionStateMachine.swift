/// What Mikan is reacting to.
enum CompanionState: Equatable, Sendable {
    case idle, thinking, working, happy, sad, annoyed
}

/// Maps chat state onto Mikan's reaction.
/// Priority: annoyed (being poked) > error > just completed > working > streaming > idle.
enum CompanionStateMachine {
    /// - Parameters:
    ///   - hasError: a current send or load error.
    ///   - lastRunFailed: the latest finished run failed. Only shows while idle, so a
    ///     new reply is not drawn sad because of the previous one.
    ///   - isWorking: a tool has run or answer text has started in this reply.
    static func state(
        isActiveStream: Bool,
        hasError: Bool,
        justCompletedResponse: Bool,
        lastRunFailed: Bool = false,
        isWorking: Bool = false,
        isAnnoyed: Bool = false
    ) -> CompanionState {
        if isAnnoyed { return .annoyed }
        if hasError || (lastRunFailed && !isActiveStream) { return .sad }
        if justCompletedResponse { return .happy }
        if isActiveStream && isWorking { return .working }
        if isActiveStream { return .thinking }
        return .idle
    }
}
