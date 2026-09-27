import XCTest
@testable import HermesMobile

/// Coverage for the shared markdown image fetch policy (sweep MED #2/#4).
///
/// Agent-emitted markdown is attacker-influenced input, so the allow/deny
/// decision is a pure function exercised here directly — the providers built on
/// it must never reach the network for a denied source, and no URLSession is
/// involved in deciding.
final class MarkdownImageFetchPolicyTests: XCTestCase {
    func testRemoteHTTPSourceIsDenied() throws {
        let url = try XCTUnwrap(URL(string: "https://evil.example/pixel.gif"))

        XCTAssertEqual(MarkdownImageFetchPolicy.decision(forURL: url), .placeholder)
    }

    func testPlainHTTPSourceIsDenied() throws {
        let url = try XCTUnwrap(URL(string: "http://tracker.example/1x1.png"))

        XCTAssertEqual(MarkdownImageFetchPolicy.decision(forURL: url), .placeholder)
    }

    func testSameOriginAPIMediaSourceIsDeniedToo() throws {
        // Even a server-shaped media URL is denied here: the bounded download
        // path lives in the transcript's MEDIA: pipeline, not in markdown
        // image providers, so markdown never fetches the network.
        let url = try XCTUnwrap(URL(string: "https://hermes.example.com/api/media/abc123"))

        XCTAssertEqual(MarkdownImageFetchPolicy.decision(forURL: url), .placeholder)
    }

    func testDataURLIsDenied() throws {
        let url = try XCTUnwrap(URL(string: "data:image/png;base64,iVBORw0KGgo="))

        XCTAssertEqual(MarkdownImageFetchPolicy.decision(forURL: url), .placeholder)
    }

    func testRelativeSourceResolvesToNonFileAndIsDenied() {
        // MarkdownUI resolves relative sources against a base URL; with none,
        // the result has no scheme and can never be a local file reference.
        let url = URL(string: "./notes/diagram.png")

        XCTAssertEqual(MarkdownImageFetchPolicy.decision(forURL: url), .placeholder)
    }

    func testMissingURLIsDenied() {
        XCTAssertEqual(MarkdownImageFetchPolicy.decision(forURL: nil), .placeholder)
    }

    func testFileURLIsAllowedWithItsPath() throws {
        let url = try XCTUnwrap(URL(string: "file:///tmp/preview/export.png"))

        XCTAssertEqual(
            MarkdownImageFetchPolicy.decision(forURL: url),
            .loadLocalFile(path: "/tmp/preview/export.png")
        )
    }

    func testHostFormFileURLWithEmptyPathIsDenied() throws {
        // `file://image.png` names a host, not a path — nothing to read.
        let url = try XCTUnwrap(URL(string: "file://image.png"))

        XCTAssertEqual(MarkdownImageFetchPolicy.decision(forURL: url), .placeholder)
    }

    // MARK: - Placeholder chip title

    func testDisplayNamePrefersFileName() throws {
        let url = try XCTUnwrap(URL(string: "https://evil.example/pixel.gif"))

        XCTAssertEqual(HermesMarkdownImageProvider.displayName(for: url), "pixel.gif")
    }

    func testDisplayNameFallsBackToHostThenGeneric() throws {
        let hostOnly = try XCTUnwrap(URL(string: "https://evil.example"))
        XCTAssertEqual(HermesMarkdownImageProvider.displayName(for: hostOnly), "evil.example")
        XCTAssertEqual(HermesMarkdownImageProvider.displayName(for: nil), "Image")
    }
}
