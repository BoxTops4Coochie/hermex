import XCTest
@testable import HermesMobile

final class CompanionStateMachineTests: XCTestCase {
    func testAllInputCombinationsFollowPriorityOrder() {
        let flags = [false, true]
        for isActiveStream in flags {
            for hasError in flags {
                for justCompleted in flags {
                    for lastRunFailed in flags {
                        for isWorking in flags {
                            for isAnnoyed in flags {
                                let expected: CompanionState
                                if isAnnoyed {
                                    expected = .annoyed
                                } else if hasError || (lastRunFailed && !isActiveStream) {
                                    expected = .sad
                                } else if justCompleted {
                                    expected = .happy
                                } else if isActiveStream && isWorking {
                                    expected = .working
                                } else if isActiveStream {
                                    expected = .thinking
                                } else {
                                    expected = .idle
                                }
                                XCTAssertEqual(
                                    CompanionStateMachine.state(
                                        isActiveStream: isActiveStream,
                                        hasError: hasError,
                                        justCompletedResponse: justCompleted,
                                        lastRunFailed: lastRunFailed,
                                        isWorking: isWorking,
                                        isAnnoyed: isAnnoyed
                                    ),
                                    expected,
                                    "stream=\(isActiveStream) error=\(hasError) completed=\(justCompleted) "
                                        + "failed=\(lastRunFailed) working=\(isWorking) annoyed=\(isAnnoyed)"
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    func testAnnoyedBeatsEverything() {
        XCTAssertEqual(
            CompanionStateMachine.state(isActiveStream: true, hasError: true, justCompletedResponse: true,
                                        lastRunFailed: true, isWorking: true, isAnnoyed: true),
            .annoyed
        )
    }

    func testFailedRunIsSadOnlyUntilTheNextReplyStarts() {
        XCTAssertEqual(CompanionStateMachine.state(isActiveStream: false, hasError: false, justCompletedResponse: false, lastRunFailed: true), .sad)
        XCTAssertEqual(CompanionStateMachine.state(isActiveStream: true, hasError: false, justCompletedResponse: false, lastRunFailed: true), .thinking)
    }

    func testWorkingOnlyWhileStreaming() {
        XCTAssertEqual(CompanionStateMachine.state(isActiveStream: true, hasError: false, justCompletedResponse: false, isWorking: true), .working)
        XCTAssertEqual(CompanionStateMachine.state(isActiveStream: false, hasError: false, justCompletedResponse: false, isWorking: true), .idle)
        XCTAssertEqual(CompanionStateMachine.state(isActiveStream: true, hasError: false, justCompletedResponse: true, isWorking: true), .happy)
    }

    func testCurrentErrorBeatsCelebrationAndStreaming() {
        XCTAssertEqual(CompanionStateMachine.state(isActiveStream: true, hasError: true, justCompletedResponse: true), .sad)
    }

    func testStreamingIsThinkingAndRestIsIdle() {
        XCTAssertEqual(CompanionStateMachine.state(isActiveStream: true, hasError: false, justCompletedResponse: false), .thinking)
        XCTAssertEqual(CompanionStateMachine.state(isActiveStream: false, hasError: false, justCompletedResponse: false), .idle)
    }
}

final class CompanionTapTrackerTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testQuickPairIsADoubleTap() {
        var taps = CompanionTapTracker()
        XCTAssertEqual(taps.register(at: at(0)), .none)
        XCTAssertEqual(taps.register(at: at(0.2)), .doubleTap)
    }

    func testSlowPairIsNotADoubleTap() {
        var taps = CompanionTapTracker()
        XCTAssertEqual(taps.register(at: at(0)), .none)
        XCTAssertEqual(taps.register(at: at(0.5)), .none)
    }

    func testThirdQuickTapStartsANewPairInsteadOfWalkingAgain() {
        var taps = CompanionTapTracker()
        XCTAssertEqual(taps.register(at: at(0)), .none)
        XCTAssertEqual(taps.register(at: at(0.2)), .doubleTap)
        XCTAssertEqual(taps.register(at: at(0.4)), .none)
        XCTAssertEqual(taps.register(at: at(0.6)), .doubleTap)
    }

    func testFiveTapsInTheWindowAnnoyOnceThenStayAnnoyed() {
        var taps = CompanionTapTracker()
        let outcomes = [0.0, 0.5, 1.0, 1.5, 2.0, 2.2].map { taps.register(at: at($0)) }
        XCTAssertEqual(outcomes, [.none, .none, .none, .none, .becameAnnoyed, .stillAnnoyed])
        XCTAssertTrue(taps.isAnnoyed)
    }

    func testTapsSpreadOutDoNotAnnoy() {
        var taps = CompanionTapTracker()
        for second in stride(from: 0.0, to: 10, by: 1) {
            XCTAssertEqual(taps.register(at: at(second)), .none)
        }
        XCTAssertFalse(taps.isAnnoyed)
    }

    func testCalmDownResetsEverything() {
        var taps = CompanionTapTracker()
        for second in [0.0, 0.5, 1.0, 1.5, 2.0] { _ = taps.register(at: at(second)) }
        taps.calmDown()
        XCTAssertFalse(taps.isAnnoyed)
        XCTAssertEqual(taps.register(at: at(10)), .none)
    }
}

final class MikanRigTests: XCTestCase {
    private let states: [CompanionState] = [.idle, .thinking, .working, .happy, .sad, .annoyed]

    func testEveryStateHasADistinctPose() {
        for (i, a) in states.enumerated() {
            for b in states[(i + 1)...] {
                XCTAssertNotEqual(MikanRig.pose(for: a), MikanRig.pose(for: b), "\(a) and \(b) share a pose")
            }
        }
    }

    func testEveryPoseHasEyesOpenAtRest() {
        for state in states {
            XCTAssertEqual(MikanRig.pose(for: state)[.eyeOpen], 1, "\(state)")
        }
    }

    func testWalkingFacesTheWalkDirection() {
        let idle = MikanRig.pose(for: .idle)
        XCTAssertGreaterThan(idle.walking(toward: .right, stride: true)[.faceDX], 0)
        XCTAssertLessThan(idle.walking(toward: .left, stride: true)[.faceDX], 0)
    }

    func testWalkingKeepsTheExpression() {
        let walk = MikanRig.pose(for: .annoyed).walking(toward: .left, stride: true)
        XCTAssertEqual(walk[.browAngry], 1)
        XCTAssertEqual(walk[.angryLid], 1)
        XCTAssertEqual(walk[.leftArmOver], 0)
        XCTAssertEqual(walk[.rightArmOver], 0)
    }

    func testOnlyWorkingShowsTheLaptop() {
        for state in states {
            XCTAssertEqual(MikanRig.pose(for: state)[.laptop], state == .working ? 1 : 0, "\(state)")
        }
        XCTAssertGreaterThan(MikanRig.pose(for: .working)[.lookY], 0, "eyes on the screen")
    }

    func testWalkingPutsTheLaptopAway() {
        let walk = MikanRig.pose(for: .working).walking(toward: .right, stride: false)
        XCTAssertEqual(walk[.laptop], 0)
        XCTAssertEqual(walk[.lookY], 0)
    }

    func testHappyPointsTowardTheNewestMessage() {
        let left = MikanRig.pose(for: .happy, pointing: .left)
        let right = MikanRig.pose(for: .happy, pointing: .right)
        XCTAssertLessThan(left[.lHandX], 30, "left paw reaches out to the left")
        XCTAssertLessThan(left[.faceDX], 0)
        XCTAssertGreaterThan(right[.rHandX], 70, "mirrored: right paw reaches out to the right")
        XCTAssertGreaterThan(right[.faceDX], 0)
        XCTAssertEqual(left[.lHandY], right[.rHandY], accuracy: 1e-9)
    }

    func testWalkingStridesAlternateFeet() {
        let idle = MikanRig.pose(for: .idle)
        let a = idle.walking(toward: .right, stride: true)
        let b = idle.walking(toward: .right, stride: false)
        XCTAssertGreaterThan(a[.leftLift], 0)
        XCTAssertEqual(a[.rightLift], 0)
        XCTAssertGreaterThan(b[.rightLift], 0)
        XCTAssertEqual(b[.leftLift], 0)
    }

    func testRigInterpolatesLinearly() {
        let idle = MikanRig.pose(for: .idle)
        let sad = MikanRig.pose(for: .sad)
        var half = sad - idle
        half.scale(by: 0.5)
        let mid = idle + half
        XCTAssertEqual(mid[.earDroop], (idle[.earDroop] + sad[.earDroop]) / 2, accuracy: 1e-9)
        XCTAssertEqual((sad - sad).magnitudeSquared, 0)
        XCTAssertEqual(MikanRig.zero.magnitudeSquared, 0)
    }
}
