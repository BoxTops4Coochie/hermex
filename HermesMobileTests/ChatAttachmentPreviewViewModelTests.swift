import XCTest
@testable import HermesMobile

/// Retry and dedupe semantics of `ChatAttachmentPreviewViewModel.load`.
/// The error-state "Try Again" button retries with `force: true`, so a failed
/// load must not poison the `didLoad` guard against a later refetch.
@MainActor
final class ChatAttachmentPreviewViewModelTests: APIClientTestCase {
    func testFailedLoadThenForcedRetryRefetchesAndClearsError() async throws {
        let calls = RequestCounter()
        let viewModel = makeViewModel { request in
            calls.increment()
            if calls.value == 1 {
                return apiTestJSONResponse("{}", for: request, status: 500)
            }
            return apiTestJSONResponse(#"{"path": "notes.txt", "content": "recovered"}"#, for: request)
        }

        await viewModel.load()
        XCTAssertEqual(calls.value, 1)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.preview)

        await viewModel.load(force: true)
        XCTAssertEqual(calls.value, 2, "A forced retry after a failed load must hit the server again")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.lastError)
        XCTAssertFalse(viewModel.isLoading)

        guard case let .text(file) = try XCTUnwrap(viewModel.preview) else {
            XCTFail("Expected a text preview, got \(String(describing: viewModel.preview))")
            return
        }
        XCTAssertEqual(file.content, "recovered")
    }

    func testNonForcedLoadAfterCompletedLoadDoesNotRefetch() async {
        let calls = RequestCounter()
        let viewModel = makeViewModel { request in
            calls.increment()
            return apiTestJSONResponse(#"{"path": "notes.txt", "content": "hello"}"#, for: request)
        }

        await viewModel.load()
        await viewModel.load()

        XCTAssertEqual(calls.value, 1, "A non-forced load after completion early-returns on didLoad")
        XCTAssertNotNil(viewModel.preview)
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Helpers

    private func makeViewModel(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> ChatAttachmentPreviewViewModel {
        let client = makeClient(handler: handler)
        let attachment = MessageAttachment(name: "notes.txt", path: "uploads/notes.txt")
        let item = ChatAttachmentPreviewItem(message: attachment, localData: nil)
        return ChatAttachmentPreviewViewModel(
            session: SessionSummary(sessionId: "session-abc"),
            server: URL(string: "https://example.test")!,
            item: item,
            apiClient: client
        )
    }
}

/// Thread-safe request counter: MockURLProtocol runs handlers off the caller's
/// thread, so the count cannot live in an unsynchronized capture.
private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() {
        lock.withLock { count += 1 }
    }
}
