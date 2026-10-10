import XCTest
@testable import HermesMobile

final class CompanionStateMachineTests: XCTestCase {
    func testAllInputCombinationsFollowPriorityOrder() {
        for isActiveStream in [false, true] {
            for hasError in [false, true] {
                for justCompleted in [false, true] {
                  for isAnnoyed in [false, true] {
                    let expected: CompanionState
                    if isAnnoyed {
                        expected = .annoyed
                    } else if hasError {
                        expected = .sad
                    } else if justCompleted {
                        expected = .happy
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
                            isAnnoyed: isAnnoyed
                        ),
                        expected,
                        "stream=\(isActiveStream) error=\(hasError) completed=\(justCompleted) annoyed=\(isAnnoyed)"
                    )
                  }
                }
            }
        }
    }

    func testAnnoyedBeatsEverything() {
        XCTAssertEqual(
            CompanionStateMachine.state(isActiveStream: true, hasError: true, justCompletedResponse: true, isAnnoyed: true),
            .annoyed
        )
    }

    func testErrorBeatsCelebrationAndStreaming() {
        XCTAssertEqual(CompanionStateMachine.state(isActiveStream: true, hasError: true, justCompletedResponse: true), .sad)
    }

    func testCelebrationBeatsStreaming() {
        XCTAssertEqual(CompanionStateMachine.state(isActiveStream: true, hasError: false, justCompletedResponse: true), .happy)
    }

    func testStreamingIsThinkingAndRestIsIdle() {
        XCTAssertEqual(CompanionStateMachine.state(isActiveStream: true, hasError: false, justCompletedResponse: false), .thinking)
        XCTAssertEqual(CompanionStateMachine.state(isActiveStream: false, hasError: false, justCompletedResponse: false), .idle)
    }

    func testSameInputAlwaysYieldsSameState() {
        for _ in 0..<10 {
            XCTAssertEqual(CompanionStateMachine.state(isActiveStream: true, hasError: false, justCompletedResponse: false), .thinking)
        }
    }
}

final class MikanRigTests: XCTestCase {
    private let states: [CompanionState] = [.idle, .thinking, .happy, .sad, .annoyed]

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
