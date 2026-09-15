import XCTest
import AVFoundation
import ImageIO
import SwiftData
import UIKit
import UniformTypeIdentifiers
@testable import HermesMobile

final class APIClientSkillEndpointTests: APIClientTestCase {
    func testSkillsBuildsExpectedPathAndDecodesResponse() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.url?.path, "/api/skills")
            XCTAssertEqual(request.httpMethod, "GET")

            return apiTestJSONResponse("""
            {
              "skills": [
                {"name": "swift-refactor", "category": "coding", "description": "Refactors Swift code", "path": "/skills/coding/swift-refactor", "disabled": true, "tags": ["swift", "refactor"], "related_skills": ["test-driven-development"]},
                {"name": "doc-search", "category": "research", "description": "Searches docs"}
              ]
            }
            """, for: request)
        }

        let response = try await client.skills()
        XCTAssertEqual(response.skills?.count, 2)
        XCTAssertEqual(response.skills?[0].name, "swift-refactor")
        XCTAssertEqual(response.skills?[0].category, "coding")
        XCTAssertEqual(response.skills?[0].description, "Refactors Swift code")
        XCTAssertEqual(response.skills?[0].disabled, true)
        XCTAssertEqual(response.skills?[0].tags, ["swift", "refactor"])
        XCTAssertEqual(response.skills?[0].relatedSkills, ["test-driven-development"])
        XCTAssertEqual(response.skills?[1].name, "doc-search")
        XCTAssertEqual(response.skills?[1].category, "research")
    }

    func testSkillsToleratesMissingFields() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.url?.path, "/api/skills")
            return apiTestJSONResponse("""
            {"skills": [{"name": "minimal-skill"}]}
            """, for: request)
        }

        let response = try await client.skills()
        XCTAssertEqual(response.skills?.count, 1)
        XCTAssertEqual(response.skills?[0].name, "minimal-skill")
        XCTAssertNil(response.skills?[0].category)
        XCTAssertNil(response.skills?[0].description)
        XCTAssertNil(response.skills?[0].disabled)
        XCTAssertNil(response.skills?[0].tags)
        XCTAssertNil(response.skills?[0].relatedSkills)
    }

    func testToggleSkillPostsExpectedBodyAndDecodesResponse() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.url?.path, "/api/skills/toggle")
            XCTAssertEqual(request.httpMethod, "POST")

            let body = try apiTestJSONBody(from: request)
            XCTAssertEqual(body["name"] as? String, "swift-refactor")
            XCTAssertEqual(body["enabled"] as? Bool, false)

            return apiTestJSONResponse("""
            {"ok": true, "name": "swift-refactor", "enabled": false}
            """, for: request)
        }

        let response = try await client.toggleSkill(name: "swift-refactor", enabled: false)
        XCTAssertEqual(response.ok, true)
        XCTAssertEqual(response.name, "swift-refactor")
        XCTAssertEqual(response.enabled, false)
    }

    func testSkillContentBuildsExpectedQueryAndDecodesResponse() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.url?.path, "/api/skills/content")
            let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value) })
            XCTAssertEqual(query["name"], "swift-refactor")
            XCTAssertNil(query["file"])
            XCTAssertEqual(request.httpMethod, "GET")

            return apiTestJSONResponse("""
            {"name": "swift-refactor", "content": "# Swift Refactor\\n\\nRefactors Swift code.", "linked_files": {"README.md": "Read me", "config.json": "Config"}}
            """, for: request)
        }

        let response = try await client.skillContent(name: "swift-refactor")
        XCTAssertEqual(response.name, "swift-refactor")
        XCTAssertEqual(response.content, "# Swift Refactor\n\nRefactors Swift code.")
        XCTAssertEqual(response.linkedFiles, ["README.md", "config.json"])
    }

    func testSkillContentDecodesGroupedLinkedFiles() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.url?.path, "/api/skills/content")

            return apiTestJSONResponse("""
            {
              "name": "google-workspace",
              "content": "# Google Workspace",
              "linked_files": {
                "references": ["references/auth.md"],
                "scripts": ["scripts/setup.py", "scripts/google_api.py"],
                "assets": []
              }
            }
            """, for: request)
        }

        let response = try await client.skillContent(name: "google-workspace")

        XCTAssertEqual(response.linkedFiles, [
            "references/auth.md",
            "scripts/google_api.py",
            "scripts/setup.py"
        ])
    }

    func testSkillLinkedFileBuildsExpectedQueryAndDecodesResponse() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.url?.path, "/api/skills/content")
            let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value) })
            XCTAssertEqual(query["name"], "swift-refactor")
            XCTAssertEqual(query["file"], "README.md")
            XCTAssertEqual(request.httpMethod, "GET")

            return apiTestJSONResponse("""
            {"content": "# README\\n\\nDetails here.", "path": "README.md"}
            """, for: request)
        }

        let response = try await client.skillContent(name: "swift-refactor", file: "README.md")
        XCTAssertEqual(response.content, "# README\n\nDetails here.")
    }

    // MARK: - SkillLinkedFileViewModel

    @MainActor
    func testLinkedFileLoadBuildsExpectedRequestAndPopulatesContent() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.url?.path, "/api/skills/content")
            let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value) })
            XCTAssertEqual(query["name"], "swift-refactor")
            XCTAssertEqual(query["file"], "README.md")

            return apiTestJSONResponse("""
            {"content": "# README\\n\\nDetails here."}
            """, for: request)
        }
        let model = SkillLinkedFileViewModel(
            server: URL(string: "https://example.test")!,
            skillName: "swift-refactor",
            apiClient: client
        )

        await model.load(named: "README.md")

        XCTAssertEqual(model.fileContent, "# README\n\nDetails here.")
        XCTAssertFalse(model.isLoadingFile)
    }

    @MainActor
    func testLinkedFileLoadFailureShowsErrorInContent() async {
        let client = makeClient { request in
            (HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!, Data())
        }
        let model = SkillLinkedFileViewModel(
            server: URL(string: "https://example.test")!,
            skillName: "swift-refactor",
            apiClient: client
        )

        await model.load(named: "README.md")

        XCTAssertEqual(model.fileContent?.hasPrefix("Could not load file"), true)
        XCTAssertFalse(model.isLoadingFile)
    }

    /// The linked-file sheet can be dismissed and reopened for another file
    /// while a fetch is still in flight. When two loads race and the older
    /// response lands while the newer request is still pending, it must be
    /// discarded: no content overwrite, and the newer load keeps its spinner.
    @MainActor
    func testStaleLinkedFileLoadDoesNotOverwriteNewerPendingLoad() async throws {
        let firstRequestArrived = expectation(description: "stale file request arrived")
        let secondRequestArrived = expectation(description: "fresh file request arrived")
        let requests = DeferredSkillFileRequests()

        DeferredSkillFileMockURLProtocol.onRequest = { pendingRequest in
            switch requests.append(pendingRequest) {
            case 1: firstRequestArrived.fulfill()
            case 2: secondRequestArrived.fulfill()
            default: XCTFail("unexpected extra linked-file request")
            }
        }
        defer { DeferredSkillFileMockURLProtocol.onRequest = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeferredSkillFileMockURLProtocol.self]
        let client = APIClient(
            baseURL: URL(string: "https://example.test")!,
            session: URLSession(configuration: configuration)
        )
        let model = SkillLinkedFileViewModel(
            server: URL(string: "https://example.test")!,
            skillName: "swift-refactor",
            apiClient: client
        )

        let staleLoad = Task { await model.load(named: "README.md") }
        await fulfillment(of: [firstRequestArrived], timeout: 5)
        XCTAssertTrue(model.isLoadingFile)

        // A newer load starts while the first request is still in flight …
        let freshLoad = Task { await model.load(named: "CONFIG.md") }
        await fulfillment(of: [secondRequestArrived], timeout: 5)

        // … and the stale response lands first: it must not touch the newer
        // load's content or clear its loading state.
        requests.request(at: 0).complete(withJSON: """
        {"content": "# Stale README"}
        """)
        await staleLoad.value
        XCTAssertNil(model.fileContent, "a stale response must not become visible content")
        XCTAssertTrue(model.isLoadingFile, "the still-pending newer load owns the loading state")

        // The fresh response lands afterwards and wins.
        requests.request(at: 1).complete(withJSON: """
        {"content": "# Fresh CONFIG"}
        """)
        await freshLoad.value
        XCTAssertEqual(model.fileContent, "# Fresh CONFIG")
        XCTAssertFalse(model.isLoadingFile)
    }

    /// The inverse ordering: the newer load completes first, then the stale
    /// response lands late — it must not overwrite the newer file's content.
    @MainActor
    func testLateStaleLinkedFileSuccessDoesNotOverwriteNewerResponse() async throws {
        let firstRequestArrived = expectation(description: "stale file request arrived")
        let secondRequestArrived = expectation(description: "fresh file request arrived")
        let requests = DeferredSkillFileRequests()

        DeferredSkillFileMockURLProtocol.onRequest = { pendingRequest in
            switch requests.append(pendingRequest) {
            case 1: firstRequestArrived.fulfill()
            case 2: secondRequestArrived.fulfill()
            default: XCTFail("unexpected extra linked-file request")
            }
        }
        defer { DeferredSkillFileMockURLProtocol.onRequest = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeferredSkillFileMockURLProtocol.self]
        let client = APIClient(
            baseURL: URL(string: "https://example.test")!,
            session: URLSession(configuration: configuration)
        )
        let model = SkillLinkedFileViewModel(
            server: URL(string: "https://example.test")!,
            skillName: "swift-refactor",
            apiClient: client
        )

        let staleLoad = Task { await model.load(named: "README.md") }
        await fulfillment(of: [firstRequestArrived], timeout: 5)

        let freshLoad = Task { await model.load(named: "CONFIG.md") }
        await fulfillment(of: [secondRequestArrived], timeout: 5)

        // The newer response lands first and is displayed.
        requests.request(at: 1).complete(withJSON: """
        {"content": "# Fresh CONFIG"}
        """)
        await freshLoad.value
        XCTAssertEqual(model.fileContent, "# Fresh CONFIG")
        XCTAssertFalse(model.isLoadingFile)

        // The stale response lands afterwards — it must be discarded.
        requests.request(at: 0).complete(withJSON: """
        {"content": "# Stale README"}
        """)
        await staleLoad.value
        XCTAssertEqual(model.fileContent, "# Fresh CONFIG", "a stale late success must not overwrite newer data")
        XCTAssertFalse(model.isLoadingFile)
    }

    /// A stale load that *fails* late must be discarded too — an older error
    /// response may not clobber the newer file's content or its loading state.
    @MainActor
    func testLateStaleLinkedFileFailureDoesNotOverwriteNewerResponse() async throws {
        let firstRequestArrived = expectation(description: "stale file request arrived")
        let secondRequestArrived = expectation(description: "fresh file request arrived")
        let requests = DeferredSkillFileRequests()

        DeferredSkillFileMockURLProtocol.onRequest = { pendingRequest in
            switch requests.append(pendingRequest) {
            case 1: firstRequestArrived.fulfill()
            case 2: secondRequestArrived.fulfill()
            default: XCTFail("unexpected extra linked-file request")
            }
        }
        defer { DeferredSkillFileMockURLProtocol.onRequest = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeferredSkillFileMockURLProtocol.self]
        let client = APIClient(
            baseURL: URL(string: "https://example.test")!,
            session: URLSession(configuration: configuration)
        )
        let model = SkillLinkedFileViewModel(
            server: URL(string: "https://example.test")!,
            skillName: "swift-refactor",
            apiClient: client
        )

        let staleLoad = Task { await model.load(named: "README.md") }
        await fulfillment(of: [firstRequestArrived], timeout: 5)

        let freshLoad = Task { await model.load(named: "CONFIG.md") }
        await fulfillment(of: [secondRequestArrived], timeout: 5)

        requests.request(at: 1).complete(withJSON: """
        {"content": "# Fresh CONFIG"}
        """)
        await freshLoad.value
        XCTAssertEqual(model.fileContent, "# Fresh CONFIG")

        requests.request(at: 0).complete(withJSON: """
        {"message": "gone"}
        """, status: 500)
        await staleLoad.value
        XCTAssertEqual(model.fileContent, "# Fresh CONFIG", "a stale failure must not overwrite newer data")
        XCTAssertFalse(model.isLoadingFile)
    }
}

/// URLProtocol whose responses are completed manually by the test, so two
/// in-flight linked-file requests can be answered out of order (the shared
/// `MockURLProtocol` answers synchronously inside `startLoading`, which
/// serializes responses in request order).
private final class DeferredSkillFileMockURLProtocol: URLProtocol {
    /// Called (on a URLSession worker thread) whenever a request starts loading.
    static var onRequest: ((DeferredSkillFileMockURLProtocol) -> Void)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let onRequest = Self.onRequest else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        onRequest(self)
    }

    override func stopLoading() {}

    func complete(withJSON json: String, status: Int = 200) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Thread-safe collector for the deferred requests above (`onRequest` fires on
/// URLSession worker threads).
private final class DeferredSkillFileRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [DeferredSkillFileMockURLProtocol] = []

    /// Appends the request and returns its 1-based arrival order.
    func append(_ request: DeferredSkillFileMockURLProtocol) -> Int {
        lock.lock()
        defer { lock.unlock() }
        pending.append(request)
        return pending.count
    }

    func request(at index: Int) -> DeferredSkillFileMockURLProtocol {
        lock.lock()
        defer { lock.unlock() }
        return pending[index]
    }
}
