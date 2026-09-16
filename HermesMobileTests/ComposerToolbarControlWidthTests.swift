import SwiftUI
import XCTest
@testable import HermesMobile

/// Layout probes for the composer toolbar row's width capping. The row's
/// scroller proposes no width to its content, so its text controls have to cap
/// themselves (`ComposerToolbarControlMetrics.textControlMaxWidth`) for
/// truncation to engage at all. A probe layout records the size a control
/// reports when it is laid out under a chosen proposal, mimicking the
/// width-less proposal the scroller hands its children.
final class ComposerToolbarControlWidthTests: XCTestCase {
    private let cap = ComposerToolbarControlMetrics.textControlMaxWidth

    // MARK: - Model + effort label

    @MainActor
    func testModelEffortLabelHugsShortTitle() throws {
        let size = try reportedSize(modelLabel(title: "gpt-4o", showsEffort: false), under: .unspecified)

        XCTAssertGreaterThan(size.width, 0)
        XCTAssertLessThan(size.width, cap, "short titles must keep their natural width, not stretch to the cap")
        XCTAssertEqual(size.height, ComposerInlineControlLabel.minimumHeight, accuracy: 0.5)
    }

    @MainActor
    func testModelEffortLabelCapsLongTitleUnderScrollerProposal() throws {
        // The title from the bug report: wide enough that its natural width
        // pushed every later control out of the scroller's viewport.
        let size = try reportedSize(modelLabel(title: "GLM-5.3-Flash-TP3", showsEffort: true), under: .unspecified)

        XCTAssertEqual(size.width, cap, accuracy: 0.5, "a long title must resolve to the cap, not its ideal width")
        XCTAssertEqual(size.height, ComposerInlineControlLabel.minimumHeight, accuracy: 0.5)
    }

    @MainActor
    func testModelEffortLabelCompressesUnderDefiniteProposal() throws {
        // Under a definite proposal the label must compress (and truncate);
        // `.fixedSize` would refuse and report the cap instead. This is the
        // regression guard for removing it.
        let size = try reportedSize(
            modelLabel(title: "GLM-5.3-Flash-TP3", showsEffort: true),
            under: ProposedViewSize(width: 80, height: nil)
        )

        XCTAssertLessThanOrEqual(size.width, 80.5, "the label refused to compress; fixedSize is back")
        XCTAssertEqual(size.height, ComposerInlineControlLabel.minimumHeight, accuracy: 0.5)
    }

    // MARK: - Inline control labels (workspace, profile)

    @MainActor
    func testInlineControlLabelHugsShortTitle() throws {
        let size = try reportedSize(inlineLabel(title: "Home"), under: .unspecified)

        XCTAssertLessThan(size.width, cap, "short titles must keep their natural width, not stretch to the cap")
        XCTAssertEqual(size.height, ComposerInlineControlLabel.minimumHeight, accuracy: 0.5)
    }

    @MainActor
    func testInlineControlLabelCapsLongTitle() throws {
        let size = try reportedSize(
            inlineLabel(title: "a-very-long-workspace-or-profile-title"),
            under: .unspecified
        )

        XCTAssertEqual(size.width, cap, accuracy: 0.5, "a long title must resolve to the cap, not its ideal width")
        XCTAssertEqual(size.height, ComposerInlineControlLabel.minimumHeight, accuracy: 0.5)
    }

    // MARK: - Git branch label

    @MainActor
    func testGitBranchPickerButtonCapsLongBranchName() throws {
        let button = GitBranchPickerButton(
            currentBranch: "fix/composer-toolbar-overflow-with-a-long-name",
            branches: nil,
            isLoading: false,
            isSwitching: false,
            isDisabled: false,
            onSelect: { _ in },
            onCreate: { _ in },
            onRefresh: {}
        )

        let size = try reportedSize(button, under: .unspecified)

        XCTAssertEqual(size.width, cap, accuracy: 0.5, "a long branch name must resolve to the cap")
        XCTAssertEqual(size.height, 44, accuracy: 0.5)
    }

    // MARK: - Cap sanity

    func testCapStaysAboveTheControlsFixedChrome() {
        // Below this, a control cannot show its icon, chevron, padding and an
        // ellipsis at once; the cap must never compress a control that far.
        XCTAssertGreaterThanOrEqual(cap, 64)
    }

    // MARK: - Probe plumbing

    /// Mutable receiver for the one measurement the probe layout takes. Only
    /// touched from the synchronous layout pass that renders the probe, so the
    /// unchecked sendability is sound.
    private final class MeasuredSizeBox: @unchecked Sendable {
        var size: CGSize?
    }

    /// Records the size its (single) child reports under a fixed proposal.
    /// `sizeThatFits` measures the child with `childProposal` no matter what
    /// the surrounding layout proposes, so the recording is deterministic.
    private struct SizeProbeLayout: Layout {
        let box: MeasuredSizeBox
        let childProposal: ProposedViewSize

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let size = subviews.first?.sizeThatFits(childProposal) ?? .zero
            box.size = size
            return size
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            guard let subview = subviews.first else { return }
            subview.place(
                at: CGPoint(x: bounds.minX, y: bounds.midY),
                anchor: .leading,
                proposal: childProposal
            )
        }
    }

    /// Runs one layout pass over the probe (ImageRenderer is the repo's
    /// established way to drive SwiftUI layout in tests) and returns the size
    /// the view reported.
    @MainActor
    private func reportedSize<V: View>(_ view: V, under proposal: ProposedViewSize) throws -> CGSize {
        let box = MeasuredSizeBox()
        let renderer = ImageRenderer(
            content: SizeProbeLayout(box: box, childProposal: proposal) {
                view
            }
        )
        renderer.scale = 1
        _ = try XCTUnwrap(renderer.cgImage, "probe produced no image; layout never ran")
        return try XCTUnwrap(box.size, "probe never measured its content")
    }

    private func modelLabel(title: String, showsEffort: Bool) -> some View {
        ComposerModelEffortMenuLabel(
            selection: ComposerModelEffortSelection(
                model: ModelCatalogOption(id: "test-model", displayName: title, providerID: "openai"),
                effort: "high",
                supportedEfforts: showsEffort ? ["low", "high"] : [],
                supportsEffort: showsEffort
            ),
            color: .secondary,
            controlFont: AppFont.subheadline(),
            chevronFont: AppFont.caption2()
        )
    }

    private func inlineLabel(title: String) -> some View {
        ComposerInlineControlLabel(
            title: title,
            systemImage: "folder",
            color: .secondary,
            controlFont: AppFont.subheadline(),
            chevronFont: AppFont.caption2()
        )
    }
}
