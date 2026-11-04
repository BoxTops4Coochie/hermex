import SwiftUI
import WidgetKit
import XCTest
@testable import HermesMobile

@MainActor
final class ScheduledTasksSnapshotTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("scheduled-tasks-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        fileURL = temporaryDirectory.appendingPathComponent("scheduled-tasks-snapshot.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    private func makeSnapshot(
        tasks: [ScheduledTasksSnapshot.Entry],
        serverURL: String? = "https://hermes.example.com"
    ) -> ScheduledTasksSnapshot {
        ScheduledTasksSnapshot(
            version: 1,
            serverURL: serverURL,
            generatedAt: Date(),
            tasks: tasks
        )
    }

    // MARK: - Round trip

    func testWriteThenLoadPreservesTasks() throws {
        let snapshot = makeSnapshot(tasks: [
            ScheduledTasksSnapshot.Entry(
                jobId: "job-1",
                name: "Daily backup",
                scheduleDisplay: "Every day at 6:00 PM",
                nextRunAt: Date(timeIntervalSince1970: 1_700),
                lastStatus: "ok",
                enabled: true
            ),
            ScheduledTasksSnapshot.Entry(
                jobId: "job-2",
                name: "Weekly report",
                scheduleDisplay: nil,
                nextRunAt: Date(timeIntervalSince1970: 1_600),
                lastStatus: "error",
                enabled: false
            )
        ])

        XCTAssertTrue(ScheduledTasksSnapshotStore.write(snapshot, to: fileURL))

        let loaded = try XCTUnwrap(ScheduledTasksSnapshotStore.load(from: fileURL))
        XCTAssertEqual(loaded.tasks, snapshot.tasks)
        XCTAssertEqual(loaded.serverURL, "https://hermes.example.com")
        XCTAssertEqual(loaded.version, 1)
    }

    func testLoadFromMissingFileIsNil() {
        XCTAssertNil(ScheduledTasksSnapshotStore.load(from: fileURL))
    }

    // MARK: - Decode tolerance

    func testDecodeToleratesMissingUnknownAndWrongTypedFields() throws {
        let json = """
        {
            "version": "1",
            "serverURL": "https://hermes.example.com",
            "tasks": [
                {
                    "jobId": 123,
                    "name": true,
                    "scheduleDisplay": 6,
                    "nextRunAt": "not-a-date",
                    "lastStatus": 7,
                    "enabled": "maybe",
                    "futureField": {"a": 1}
                },
                {"jobId": "job-2"},
                {}
            ],
            "futureTopLevel": true
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let snapshot = try XCTUnwrap(try? JSONDecoder().decode(ScheduledTasksSnapshot.self, from: data))

        XCTAssertEqual(snapshot.version, 1)
        XCTAssertEqual(snapshot.serverURL, "https://hermes.example.com")

        let tasks = try XCTUnwrap(snapshot.tasks)
        XCTAssertEqual(tasks.count, 3)
        // Wrong types degrade to strings rather than failing the whole decode.
        XCTAssertEqual(tasks[0].jobId, "123")
        XCTAssertEqual(tasks[0].name, "true")
        XCTAssertEqual(tasks[0].scheduleDisplay, "6")
        XCTAssertEqual(tasks[0].lastStatus, "7")
        XCTAssertNil(tasks[0].nextRunAt)
        XCTAssertNil(tasks[0].enabled)

        XCTAssertEqual(tasks[1].jobId, "job-2")
        XCTAssertNil(tasks[1].name)
        XCTAssertNil(tasks[1].nextRunAt)

        XCTAssertNil(tasks[2].jobId)
        XCTAssertNil(tasks[2].name)
    }

    func testDecodeOfEmptyObjectYieldsAllNils() throws {
        let data = try XCTUnwrap("{}".data(using: .utf8))
        let snapshot = try XCTUnwrap(try? JSONDecoder().decode(ScheduledTasksSnapshot.self, from: data))

        XCTAssertNil(snapshot.tasks)
        XCTAssertNil(snapshot.serverURL)
        XCTAssertNil(snapshot.version)
        XCTAssertNil(snapshot.generatedAt)
    }

    func testDecodeOfMalformedDataIsNil() throws {
        try Data("not json".utf8).write(to: fileURL)
        XCTAssertNil(ScheduledTasksSnapshotStore.load(from: fileURL))
    }

    // MARK: - Change detection (gates the WidgetKit timeline reload)

    func testWriteReportsChangeOnlyWhenContentChanged() throws {
        let first = makeSnapshot(tasks: [
            ScheduledTasksSnapshot.Entry(
                jobId: "job-1",
                name: "Daily backup",
                scheduleDisplay: nil,
                nextRunAt: nil,
                lastStatus: "ok",
                enabled: true
            )
        ])
        XCTAssertTrue(ScheduledTasksSnapshotStore.write(first, to: fileURL))

        // Same tasks/server, new generatedAt: no content change, no reload.
        let unchanged = makeSnapshot(tasks: try XCTUnwrap(first.tasks))
        XCTAssertFalse(ScheduledTasksSnapshotStore.write(unchanged, to: fileURL))

        let changed = makeSnapshot(tasks: [
            ScheduledTasksSnapshot.Entry(
                jobId: "job-1",
                name: "Daily backup",
                scheduleDisplay: nil,
                nextRunAt: nil,
                lastStatus: "error",
                enabled: true
            )
        ])
        XCTAssertTrue(ScheduledTasksSnapshotStore.write(changed, to: fileURL))
    }

    // MARK: - Eviction

    func testWriteCapsAtTwelveTasks() throws {
        let entries = (0..<15).map { index in
            ScheduledTasksSnapshot.Entry(
                jobId: "job-\(index)",
                name: "Task \(index)",
                scheduleDisplay: nil,
                nextRunAt: Date(timeIntervalSince1970: TimeInterval(1_000 + index)),
                lastStatus: "ok",
                enabled: true
            )
        }

        XCTAssertTrue(ScheduledTasksSnapshotStore.write(makeSnapshot(tasks: entries), to: fileURL))

        let loaded = try XCTUnwrap(ScheduledTasksSnapshotStore.load(from: fileURL))
        XCTAssertEqual(ScheduledTasksSnapshotStore.maximumTaskCount, 12)
        XCTAssertEqual(loaded.tasks?.count, 12)
        XCTAssertEqual(loaded.tasks?.first?.jobId, "job-0")
        XCTAssertEqual(loaded.tasks?.last?.jobId, "job-11")
    }

    // MARK: - Clear

    func testClearDeletesSnapshotFile() throws {
        let snapshot = makeSnapshot(tasks: [
            ScheduledTasksSnapshot.Entry(
                jobId: "job-1",
                name: "Daily backup",
                scheduleDisplay: nil,
                nextRunAt: nil,
                lastStatus: "ok",
                enabled: true
            )
        ])
        XCTAssertTrue(ScheduledTasksSnapshotStore.write(snapshot, to: fileURL))
        XCTAssertNotNil(ScheduledTasksSnapshotStore.load(from: fileURL))

        ScheduledTasksSnapshotStore.clear(fileURL: fileURL)

        XCTAssertNil(ScheduledTasksSnapshotStore.load(from: fileURL))
    }

    func testClearOfMissingFileIsNoOp() {
        ScheduledTasksSnapshotStore.clear(fileURL: fileURL)

        XCTAssertNil(ScheduledTasksSnapshotStore.load(from: fileURL))
    }

    // MARK: - Presentation policy

    func testRowCountMatchesFamilyLimits() {
        XCTAssertEqual(ScheduledTasksWidgetPresentation.rowCount(family: .systemSmall, taskCount: 10), 2)
        XCTAssertEqual(ScheduledTasksWidgetPresentation.rowCount(family: .systemMedium, taskCount: 10), 4)
        XCTAssertEqual(ScheduledTasksWidgetPresentation.rowCount(family: .systemLarge, taskCount: 10), 8)
        XCTAssertEqual(ScheduledTasksWidgetPresentation.rowCount(family: .systemSmall, taskCount: 1), 1)
        XCTAssertEqual(ScheduledTasksWidgetPresentation.rowCount(family: .systemSmall, taskCount: 0), 0)
    }

    func testStatusMapsServerValuesAndDisabling() {
        XCTAssertEqual(ScheduledTasksWidgetStatus.status(lastStatus: "running", enabled: true), .running)
        XCTAssertEqual(ScheduledTasksWidgetStatus.status(lastStatus: "error", enabled: true), .error)
        XCTAssertEqual(ScheduledTasksWidgetStatus.status(lastStatus: "ok", enabled: true), .active)
        XCTAssertEqual(ScheduledTasksWidgetStatus.status(lastStatus: nil, enabled: true), .active)
        // A disabled job is dimmed regardless of what it last reported.
        XCTAssertEqual(ScheduledTasksWidgetStatus.status(lastStatus: "running", enabled: false), .disabled)
    }
}
