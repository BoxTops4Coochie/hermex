import SwiftUI

/// Screen direction Mikan walks in. Physical, not leading/trailing: the drawing never mirrors.
enum MikanWalkDirection: Equatable, Sendable {
    case left, right
}

/// Mikan, the vector companion cat. Drawn on a `Canvas` in a 100×110 unit space
/// (feet on y = 106) and scaled to fit. State changes spring between poses; idle
/// fidgets (blink, ear twitch, tail flick) fire every few seconds and then rest,
/// so nothing repaints continuously. Reduce Motion snaps between poses and
/// disables fidgets and the walk cycle.
@MainActor
struct MikanView: View {
    var state: CompanionState
    /// Non-nil while walking.
    var walking: MikanWalkDirection? = nil
    /// Which way `.happy` points (toward the newest message).
    var pointing: MikanWalkDirection = .left

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var blink = false
    @State private var fidget = false
    @State private var stride = false

    var body: some View {
        MikanFigure(rig: rig, ink: colorScheme == .dark ? MikanPalette.inkDark : MikanPalette.inkLight)
            .aspectRatio(100.0 / 110.0, contentMode: .fit)
            .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.35), value: state)
            .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.35), value: walking)
            .task(id: state) { await fidgetLoop() }
            .task(id: walking) { await walkLoop() }
            .accessibilityHidden(true)
    }

    private var rig: MikanRig {
        var r = MikanRig.pose(for: state, pointing: pointing)
        if let walking {
            r = r.walking(toward: walking, stride: stride)
        } else if fidget {
            r.applyFidget(for: state)
        }
        if blink { r[.eyeOpen] = 0 }
        return r
    }

    private func fidgetLoop() async {
        blink = false
        fidget = false
        guard !reduceMotion, state != .happy else { return }
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(Double.random(in: 2.5...5)))
                withAnimation(.easeIn(duration: 0.07)) { blink = true }
                try await Task.sleep(for: .milliseconds(130))
                withAnimation(.easeOut(duration: 0.1)) { blink = false }
                if Bool.random() {
                    withAnimation(.spring(duration: 0.45, bounce: 0.45)) { fidget.toggle() }
                }
            } catch {
                return
            }
        }
    }

    private func walkLoop() async {
        guard walking != nil, !reduceMotion else { return }
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: 0.3)) { stride.toggle() }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        }
    }
}

// MARK: - Previews

#Preview("All states") {
    HStack(spacing: 16) {
        ForEach([CompanionState.idle, .thinking, .happy, .sad, .annoyed], id: \.self) { state in
            MikanView(state: state).frame(width: 64, height: 70)
        }
        MikanView(state: .idle, walking: .right).frame(width: 64, height: 70)
    }
    .padding()
}

#Preview("Interactive") {
    @Previewable @State var state = CompanionState.idle
    @Previewable @State var walking: MikanWalkDirection?
    VStack(spacing: 24) {
        MikanView(state: state, walking: walking).frame(width: 120, height: 132)
        Picker("State", selection: $state) {
            Text("Idle").tag(CompanionState.idle)
            Text("Thinking").tag(CompanionState.thinking)
            Text("Happy").tag(CompanionState.happy)
            Text("Sad").tag(CompanionState.sad)
            Text("Annoyed").tag(CompanionState.annoyed)
        }
        .pickerStyle(.segmented)
        Button("Walk") {
            walking = .right
            Task {
                try? await Task.sleep(for: .milliseconds(3000))
                walking = nil
            }
        }
        // Real in-app size
        MikanView(state: state, walking: walking).frame(width: 60, height: 66)
    }
    .padding()
}
