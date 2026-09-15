import XCTest
@testable import HermesMobile

/// The lightbox's reset rule: the scroll view re-fits only when the media actually
/// changed. A re-render rebuilds the same `UIImage`, so the decision runs on the
/// caller's identity, not object identity.
final class ImageLightboxLayoutPolicyTests: XCTestCase {
    func testFirstImageAlwaysLaysOut() {
        XCTAssertTrue(
            ImageLightboxLayoutPolicy.shouldResetLayout(
                oldIdentity: nil,
                newIdentity: "workspace/shots/capture.png"
            )
        )
    }

    func testSameIdentityKeepsTheZoom() {
        XCTAssertFalse(
            ImageLightboxLayoutPolicy.shouldResetLayout(
                oldIdentity: "workspace/shots/capture.png",
                newIdentity: "workspace/shots/capture.png"
            )
        )
    }

    func testChangedIdentityReFits() {
        XCTAssertTrue(
            ImageLightboxLayoutPolicy.shouldResetLayout(
                oldIdentity: "workspace/shots/capture.png",
                newIdentity: "workspace/shots/capture-2.png"
            )
        )
    }
}
