import SwiftUI
import XCTest
@testable import HermesMobile

@MainActor
final class RecentChatsSnapshotTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recent-chats-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        fileURL = temporaryDirectory.appendingPathComponent("snapshot.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    // MARK: - Round trip

    func testWriteThenLoadPreservesSessions() throws {
        let snapshot = RecentChatsSnapshotStore.makeSnapshot(
            from: [
                RecentChatsSnapshot.Entry(sessionId: "s-1", title: "Fix the build", updatedAt: Date(timeIntervalSince1970: 1_700)),
                RecentChatsSnapshot.Entry(sessionId: "s-2", title: "Review diff", updatedAt: Date(timeIntervalSince1970: 1_600))
            ],
            serverURL: "https://hermes.example.com"
        )

        XCTAssertTrue(RecentChatsSnapshotStore.write(snapshot, to: fileURL))

        let loaded = try XCTUnwrap(RecentChatsSnapshotStore.load(from: fileURL))
        XCTAssertEqual(loaded.sessions, snapshot.sessions)
        XCTAssertEqual(loaded.serverURL, "https://hermes.example.com")
    }

    func testLoadFromMissingFileIsNil() {
        XCTAssertNil(RecentChatsSnapshotStore.load(from: fileURL))
    }

    // MARK: - Eviction

    func testMakeSnapshotEvictsBeyondTwelve() {
        let entries = (0..<15).map { index in
            RecentChatsSnapshot.Entry(
                sessionId: "s-\(index)",
                title: "Session \(index)",
                updatedAt: Date(timeIntervalSince1970: TimeInterval(1_000 + index))
            )
        }

        let snapshot = RecentChatsSnapshotStore.makeSnapshot(from: entries, serverURL: nil)

        XCTAssertEqual(RecentChatsSnapshotStore.maximumSessionCount, 12)
        XCTAssertEqual(snapshot.sessions?.count, 12)
        // Newest-first input order survives: the newest 12 win.
        XCTAssertEqual(snapshot.sessions?.first?.sessionId, "s-0")
        XCTAssertEqual(snapshot.sessions?.last?.sessionId, "s-11")
    }

    // MARK: - Decode tolerance

    func testDecodeToleratesUnknownAndMissingFields() throws {
        let json = """
        {
            "version": 1,
            "serverURL": "https://hermes.example.com",
            "sessions": [
                {"sessionId": "s-1", "title": "Hello", "updatedAt": 750000000.0, "futureField": {"a": 1}},
                {"sessionId": "s-2"}
            ],
            "futureTopLevel": true
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let snapshot = try XCTUnwrap(try? JSONDecoder().decode(RecentChatsSnapshot.self, from: data))

        let sessions = try XCTUnwrap(snapshot.sessions)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].sessionId, "s-1")
        XCTAssertEqual(sessions[0].title, "Hello")
        XCTAssertEqual(sessions[0].updatedAt, Date(timeIntervalSinceReferenceDate: 750000000.0))
        XCTAssertNil(sessions[1].title)
        XCTAssertNil(sessions[1].updatedAt)
    }

    func testDecodeOfEmptyObjectYieldsAllNils() throws {
        let data = try XCTUnwrap("{}".data(using: .utf8))
        let snapshot = try XCTUnwrap(try? JSONDecoder().decode(RecentChatsSnapshot.self, from: data))

        XCTAssertNil(snapshot.sessions)
        XCTAssertNil(snapshot.serverURL)
        XCTAssertNil(snapshot.version)
    }

    func testDecodeOfMalformedDataIsNil() throws {
        try Data("not json".utf8).write(to: fileURL)
        XCTAssertNil(RecentChatsSnapshotStore.load(from: fileURL))
    }

    // MARK: - Change detection (gates the WidgetKit timeline reload)

    func testWriteReportsChangeOnlyWhenContentChanged() throws {
        let first = RecentChatsSnapshotStore.makeSnapshot(
            from: [RecentChatsSnapshot.Entry(sessionId: "s-1", title: "Fix the build", updatedAt: Date(timeIntervalSince1970: 1_700))],
            serverURL: nil
        )
        XCTAssertTrue(RecentChatsSnapshotStore.write(first, to: fileURL))

        // Same sessions/server, new generatedAt: no content change, no reload.
        XCTAssertFalse(RecentChatsSnapshotStore.write(first, to: fileURL))

        let changed = RecentChatsSnapshotStore.makeSnapshot(
            from: [RecentChatsSnapshot.Entry(sessionId: "s-2", title: "New chat", updatedAt: Date(timeIntervalSince1970: 1_800))],
            serverURL: nil
        )
        XCTAssertTrue(RecentChatsSnapshotStore.write(changed, to: fileURL))
    }

    // MARK: - Widget content rendering

    func testMediumContentViewRendersSampleRows() throws {
        let snapshot = RecentChatsSnapshotStore.makeSnapshot(
            from: [
                RecentChatsSnapshot.Entry(sessionId: "s-1", title: "Fix the build", updatedAt: Date()),
                RecentChatsSnapshot.Entry(sessionId: "s-2", title: "Review diff", updatedAt: Date().addingTimeInterval(-120))
            ],
            serverURL: nil
        )

        let renderedInk = Self.inkSum(
            of: RecentChatsWidgetContentView(snapshot: snapshot, displayLimit: 4)
                .frame(width: 329, height: 155)
        )
        let emptyInk = Self.inkSum(
            of: RecentChatsWidgetContentView(snapshot: nil, displayLimit: 4)
                .frame(width: 329, height: 155)
        )

        XCTAssertGreaterThan(renderedInk, 0, "medium widget with sample data must render visible rows")
        XCTAssertGreaterThan(emptyInk, 0, "empty state must render its 'Open Hermex to load chats' copy")
        XCTAssertGreaterThan(renderedInk, emptyInk, "sample rows must lay down more ink than the empty state")
    }

    /// Antialiasing-tolerant ink measure over a dark render: counts how far
    /// each pixel rises above the widget's near-black background.
    private static func inkSum(of view: some View) -> Int {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage else { return 0 }

        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return 0
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var sum = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let rgb = Int(pixels[index]) + Int(pixels[index + 1]) + Int(pixels[index + 2])
            sum += max(0, rgb - 90)
        }
        return sum
    }
}
