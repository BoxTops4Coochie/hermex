import XCTest
import UIKit
@testable import HermesMobile

final class AttachmentImageCacheTests: XCTestCase {
    // MARK: - Fixtures

    /// Counts loader invocations and can hold the first call behind a gate so
    /// a test can keep one request in flight deterministically. Call 1 returns
    /// `firstCallData`, later calls `laterCallData`; distinct pixel sizes make
    /// the resulting images distinguishable.
    private final class AttachmentLoaderSpy: @unchecked Sendable {
        private let lock = NSLock()
        private let firstCallData: Data
        private let laterCallData: Data
        private let holdsFirstCall: Bool
        private var callCount = 0
        private var gateIsOpen = false
        private var callStartWaiters: [CheckedContinuation<Void, Never>] = []
        private var gateWaiters: [CheckedContinuation<Void, Never>] = []

        init(
            firstCallData: Data,
            laterCallData: Data,
            holdsFirstCall: Bool = false
        ) {
            self.firstCallData = firstCallData
            self.laterCallData = laterCallData
            self.holdsFirstCall = holdsFirstCall
        }

        func load() async -> Data? {
            lock.lock()
            callCount += 1
            let callNumber = callCount
            let waiters = callStartWaiters
            callStartWaiters.removeAll()
            let shouldHold = holdsFirstCall && callNumber == 1 && !gateIsOpen
            lock.unlock()
            waiters.forEach { $0.resume() }

            if shouldHold {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    lock.lock()
                    if gateIsOpen {
                        lock.unlock()
                        continuation.resume()
                        return
                    }
                    gateWaiters.append(continuation)
                    lock.unlock()
                }
            }

            return callNumber == 1 ? firstCallData : laterCallData
        }

        var calls: Int {
            lock.lock()
            defer { lock.unlock() }
            return callCount
        }

        /// Resumes once the loader has been entered `count` times — no sleeps,
        /// no polling.
        func waitForCallCount(_ count: Int) async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if callCount >= count {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                callStartWaiters.append(continuation)
                lock.unlock()
            }
        }

        func openGate() {
            lock.lock()
            gateIsOpen = true
            let waiters = gateWaiters
            gateWaiters.removeAll()
            lock.unlock()
            waiters.forEach { $0.resume() }
        }
    }

    /// A tiny solid-color PNG at a fixed pixel size (scale forced to 1 so the
    /// encoded pixel dimensions do not depend on the simulator's screen
    /// scale). The cache passes data this small through the downsampler
    /// untouched, so the decoded `UIImage.size` equals these pixel dimensions.
    private static func solidColorImageData(
        width: Int,
        height: Int,
        color: UIColor
    ) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.pngData() ?? Data()
    }

    private static let smallImageData = solidColorImageData(width: 4, height: 4, color: .systemRed)
    private static let largeImageData = solidColorImageData(width: 8, height: 8, color: .systemBlue)

    private static let serverASessionA = "https://one.example.test|session-a"
    private static let serverASessionB = "https://one.example.test|session-b"

    // MARK: - Key builder

    func testKeyJoinsNamespaceAndPath() {
        XCTAssertEqual(
            AttachmentImageCacheKey.make(namespace: Self.serverASessionA, path: "report.png"),
            "https://one.example.test|session-a|report.png"
        )
    }

    func testKeyFallsBackToBarePathWithoutNamespace() {
        XCTAssertEqual(
            AttachmentImageCacheKey.make(namespace: "", path: "report.png"),
            "report.png"
        )
    }

    // MARK: - Namespacing

    /// Same attachment path, different namespaces: two separate entries, the
    /// loader runs for each, and each context gets its own image — never the
    /// other server's or session's.
    func testSamePathDifferentNamespacesLoadSeparately() async throws {
        let cache = AttachmentImageCache()
        let spy = AttachmentLoaderSpy(
            firstCallData: Self.smallImageData,
            laterCallData: Self.largeImageData
        )
        let loader: @Sendable (String) async -> Data? = { _ in await spy.load() }

        let first = try XCTUnwrap(
            await cache.image(for: "report.png", cacheNamespace: Self.serverASessionA, loadAttachmentImage: loader)
        )
        let second = try XCTUnwrap(
            await cache.image(for: "report.png", cacheNamespace: Self.serverASessionB, loadAttachmentImage: loader)
        )

        XCTAssertEqual(spy.calls, 2)
        XCTAssertEqual(first.size.width, 4)
        XCTAssertEqual(second.size.width, 8)

        // A repeat inside the same namespace is a cache hit: no new load.
        let repeated = try XCTUnwrap(
            await cache.image(for: "report.png", cacheNamespace: Self.serverASessionA, loadAttachmentImage: loader)
        )
        XCTAssertEqual(spy.calls, 2)
        XCTAssertEqual(repeated.size.width, 4)
    }

    /// Same namespace and path: concurrent requests deduplicate onto one load.
    func testSameNamespaceSamePathDeduplicatesConcurrentRequests() async throws {
        let cache = AttachmentImageCache()
        let spy = AttachmentLoaderSpy(
            firstCallData: Self.smallImageData,
            laterCallData: Self.largeImageData
        )
        let loader: @Sendable (String) async -> Data? = { _ in await spy.load() }

        async let first = cache.image(
            for: "report.png",
            cacheNamespace: Self.serverASessionA,
            loadAttachmentImage: loader
        )
        async let second = cache.image(
            for: "report.png",
            cacheNamespace: Self.serverASessionA,
            loadAttachmentImage: loader
        )

        let firstImage = try XCTUnwrap(await first)
        let secondImage = try XCTUnwrap(await second)

        // Both requests resolved from a single load, whichever entered the
        // actor first.
        XCTAssertEqual(spy.calls, 1)
        XCTAssertEqual(firstImage.size.width, 4)
        XCTAssertEqual(secondImage.size.width, 4)
    }

    /// A held in-flight request must never satisfy a second request from a
    /// different namespace: the second loads on its own while the first is
    /// still waiting.
    func testInFlightRequestDoesNotSatisfyDifferentNamespace() async throws {
        let cache = AttachmentImageCache()
        let spy = AttachmentLoaderSpy(
            firstCallData: Self.smallImageData,
            laterCallData: Self.largeImageData,
            holdsFirstCall: true
        )
        let loader: @Sendable (String) async -> Data? = { _ in await spy.load() }

        let heldTask = Task {
            await cache.image(
                for: "report.png",
                cacheNamespace: Self.serverASessionA,
                loadAttachmentImage: loader
            )
        }

        // Deterministic: wait until the first loader call has actually begun
        // (and is now held by the gate) before starting the second request.
        await spy.waitForCallCount(1)

        let otherNamespace = try XCTUnwrap(
            await cache.image(
                for: "report.png",
                cacheNamespace: Self.serverASessionB,
                loadAttachmentImage: loader
            )
        )

        // The second request completed on its own loader while the first was
        // still held, and got its own image.
        XCTAssertEqual(spy.calls, 2)
        XCTAssertEqual(otherNamespace.size.width, 8)

        spy.openGate()
        let heldNamespace = try XCTUnwrap(await heldTask.value)
        XCTAssertEqual(heldNamespace.size.width, 4)
        XCTAssertEqual(spy.calls, 2)
    }
}
