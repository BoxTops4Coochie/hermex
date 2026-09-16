import AVFoundation
import XCTest
@testable import HermesMobile

final class ComposerVoiceNoteRecorderTests: XCTestCase {
    // MARK: - Filename

    func testGenerateFilenameIsM4AVoiceNote() {
        let uuid = UUID(uuidString: "ABCDEF01-2345-6789-ABCD-EF0123456789")!
        let name = VoiceNoteFilename.generate(uuid: uuid)

        XCTAssertTrue(name.hasPrefix("voice-note-"))
        XCTAssertTrue(name.hasSuffix(".m4a"))
        XCTAssertEqual(name, "voice-note-abcdef01.m4a")
        XCTAssertTrue(VoiceNoteFilename.isVoiceNote(name))
    }

    func testTwoGeneratedFilenamesDiffer() {
        XCTAssertNotEqual(VoiceNoteFilename.generate(), VoiceNoteFilename.generate())
    }

    func testIsVoiceNoteRejectsOtherFiles() {
        XCTAssertFalse(VoiceNoteFilename.isVoiceNote("photo.jpg"))
        XCTAssertFalse(VoiceNoteFilename.isVoiceNote("voice-note-123.wav"))
        XCTAssertFalse(VoiceNoteFilename.isVoiceNote("note.m4a"))
    }

    // MARK: - Gesture

    func testCancelArmsOnlyWhenSlidUpPastThreshold() {
        let threshold = ComposerVoiceNoteGesture.cancelTranslationThreshold

        XCTAssertFalse(ComposerVoiceNoteGesture.isCancelArmed(dragTranslationHeight: 0))
        XCTAssertFalse(ComposerVoiceNoteGesture.isCancelArmed(dragTranslationHeight: -10))
        // Sliding down (positive height) never cancels.
        XCTAssertFalse(ComposerVoiceNoteGesture.isCancelArmed(dragTranslationHeight: 200))
        XCTAssertTrue(ComposerVoiceNoteGesture.isCancelArmed(dragTranslationHeight: -threshold))
        XCTAssertTrue(ComposerVoiceNoteGesture.isCancelArmed(dragTranslationHeight: -200))
    }

    func testScheduledRecordingStartIsAbandonedOnceTheTouchIsUp() {
        // A system-cancelled touch never calls onEnded, so the @GestureState
        // reset to not-touching is the only end signal; a clean lift resets
        // too, but onEnded owns that path and the cancel is idempotent.
        XCTAssertFalse(ComposerVoiceNoteGesture.shouldCancelScheduledRecordingStart(isTouchDown: true))
        XCTAssertTrue(ComposerVoiceNoteGesture.shouldCancelScheduledRecordingStart(isTouchDown: false))
    }

    // MARK: - Interruption

    /// Recorder double: the real `AVAudioRecorder` stops reporting
    /// `isRecording` when the system tears the capture down mid-recording.
    private final class FakeVoiceNoteRecording: VoiceNoteRecording {
        var isRecording = true
        var currentTime: TimeInterval = 0
        private(set) var didStop = false

        func prepareToRecord() -> Bool { true }
        func record() -> Bool { true }

        func stop() {
            didStop = true
            isRecording = false
        }
    }

    /// Audio-session double so tests never drive the live shared session.
    private final class SpyVoiceNoteAudioSession {
        private(set) var activationCount = 0
        private(set) var deactivationCount = 0

        func activate() { activationCount += 1 }
        func deactivate() { deactivationCount += 1 }
    }

    @MainActor
    private func makeRecordingRecorder(
        _ fake: FakeVoiceNoteRecording,
        session: SpyVoiceNoteAudioSession
    ) -> ComposerVoiceNoteRecorder {
        ComposerVoiceNoteRecorder(
            recorderFactory: { _ in fake },
            permissionRequester: { true },
            activateAudioSession: { session.activate() },
            deactivateAudioSession: { session.deactivate() }
        )
    }

    @MainActor
    func testInterruptionDetectedOnlyWhenRecordingStateLostItsRecorderActivity() {
        XCTAssertTrue(ComposerVoiceNoteRecorder.interruptionDetected(currentState: .recording, isRecording: false))
        XCTAssertFalse(ComposerVoiceNoteRecorder.interruptionDetected(currentState: .recording, isRecording: true))
        // Non-recording states never count as an interruption.
        XCTAssertFalse(ComposerVoiceNoteRecorder.interruptionDetected(currentState: .idle, isRecording: false))
        XCTAssertFalse(ComposerVoiceNoteRecorder.interruptionDetected(currentState: .requestingPermission, isRecording: false))
    }

    @MainActor
    func testInterruptionMidRecordingFinishesStateAndStopsTicker() async {
        let fake = FakeVoiceNoteRecording()
        let session = SpyVoiceNoteAudioSession()
        let recorder = makeRecordingRecorder(fake, session: session)

        await recorder.begin()

        XCTAssertEqual(recorder.state, .recording)
        XCTAssertTrue(recorder.isTickerActive)
        XCTAssertTrue(ComposerAudioCaptureState.shared.isCapturing)

        // Audio-session interruption: the recorder object stays but reports
        // it is no longer recording. The next tick finalizes through the
        // normal teardown path instead of freezing in `.recording`.
        fake.isRecording = false
        recorder.tick()

        XCTAssertEqual(recorder.state, .idle)
        XCTAssertEqual(recorder.elapsed, 0)
        XCTAssertFalse(recorder.isTickerActive)
        XCTAssertEqual(session.deactivationCount, 1)
        XCTAssertFalse(ComposerAudioCaptureState.shared.isCapturing)
        // An already-interrupted recorder is not stopped a second time.
        XCTAssertFalse(fake.didStop)

        // Later ticks (the timer is gone) cannot resurrect state or move elapsed.
        fake.isRecording = true
        fake.currentTime = 42
        recorder.tick()

        XCTAssertEqual(recorder.state, .idle)
        XCTAssertEqual(recorder.elapsed, 0)
    }

    @MainActor
    func testTickAdvancesElapsedOnlyWhileRecording() async {
        let fake = FakeVoiceNoteRecording()
        fake.currentTime = 3.5
        let session = SpyVoiceNoteAudioSession()
        let recorder = makeRecordingRecorder(fake, session: session)

        await recorder.begin()
        recorder.tick()

        XCTAssertEqual(recorder.elapsed, 3.5)
        XCTAssertEqual(recorder.state, .recording)
        XCTAssertEqual(session.deactivationCount, 0)
    }

    // MARK: - Policy

    func testMaximumDurationStaysWellUnderUploadCap() {
        XCTAssertEqual(ComposerVoiceNoteRecorder.maximumDuration, 300)
        XCTAssertLessThan(ComposerVoiceNoteRecorder.minimumDuration, 1)

        // AAC mono at ~32 kbps over 5 minutes is roughly 1.2 MB — far below the
        // 20 MB attachment ceiling, so the duration cap (not size) bounds the UX.
        let approxBytesAt32kbps = 32_000 / 8 * Int(ComposerVoiceNoteRecorder.maximumDuration)
        XCTAssertLessThan(approxBytesAt32kbps, PendingAttachment.maximumUploadBytes)
    }

    func testRecordingSettingsAreMonoAAC() {
        let settings = ComposerVoiceNoteRecorder.recordingSettings
        XCTAssertEqual(settings[AVFormatIDKey] as? Int, Int(kAudioFormatMPEG4AAC))
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 1)
    }
}
