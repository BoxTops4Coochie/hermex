# Companion (Mikan) — agent notes

Mikan is an orange tabby cat that sits just above the chat composer and reacts
to what the agent is doing. It is app-target only: the widget and share
extension do not include it. This file holds the decisions and constraints that
are not obvious from the code.

## Files

All in `HermesMobile/Features/Companion/`:

| File | Owns |
|---|---|
| `CompanionStateMachine.swift` | `CompanionState` and the pure mapping from chat state to a state. |
| `MikanView.swift` | The public view: state → pose, idle fidgets, walk loop, previews. |
| `MikanRig.swift` | `MikanRig`, every pose value in one `VectorArithmetic` vector, plus the per-state poses and `MikanGeometry`. |
| `MikanPainter.swift` | `MikanFigure` (`Animatable` + `Canvas`) and the painter that draws a rig. |
| `MikanCompanionView.swift` | The composer-accessory row: side, double-tap walk, completion celebration, `CompanionSettings` keys. |
| `CompanionSettingsSection.swift` | Settings > Appearance: on/off toggle and Left/Right picker. |

Tests: `HermesMobileTests/CompanionStateMachineTests.swift` (contains
`CompanionStateMachineTests`, `CompanionTapTrackerTests`, and `MikanRigTests`).

## States

`CompanionStateMachine.state(isActiveStream:hasError:justCompletedResponse:lastRunFailed:isWorking:isAnnoyed:)`
is pure. Priority: **annoyed > error > just completed > working > streaming
(`.thinking`) > idle**. A failed last run counts as an error only while no new
reply is streaming (`latestRunOutcome` is never cleared when a run starts, so a
new reply must not be drawn sad because of the previous one). `.working` also
requires an active stream, so the laptop never outlives a cancelled run.

| `MikanCompanionView` input (from `ChatView`) | Source |
|---|---|
| `streamID` | `viewModel.activeStreamID` |
| `hasError` | `sendErrorMessage != nil \|\| errorMessage != nil` |
| `lastRunFailed` | `latestRunOutcome?.ending == .failed` |
| `isRunningTool` | `viewModel.liveToolCalls.contains { !$0.isCompleted }` (ChatView already reads `liveToolCalls`, so no new invalidation) |
| `hasAnswerText` | `viewModel.hasLiveAnswerText`: set on the turn's first answer-text flush (live or replayed after a reattach), reset wherever the TTFT stopwatch resets. Reasoning does not set it. |
| `completedResponseID` | `latestRunOutcome.endedAt` when `ending == .completed` |
| `newestMessageSide` | from `chatLayoutDirection` (the transcript's own direction, which can differ from the app's): assistant replies sit on its leading edge |

`.working` shows Mikan standing at a cardboard box with a laptop on it (lid
back toward the viewer, a mikan sticker, a line of screen light), both paws on
the keyboard and eyes on the screen. Every reply goes thinking → laptop:
working is `hasAnswerText` or "a tool has run in this stream". The tool latch
stores the stream ID (`toolUsedInStream`), so it can never carry into the next
reply. Mikan stays at the laptop through later reasoning instead of flipping
back to `.thinking`. Do not use `liveTurnTTFT` or the streaming haptic pulse
for this: TTFT also fires on reasoning, and the pulse is throttled and skips
replayed text.

`.happy` is a pointing pose: Mikan leans and points up toward the newest
message, toward `newestMessageSide` (mirrored with `MikanRig.mirror()` when it
is `.right`; the tail is not mirrored because the painter anchors it behind the
right hip). The 2s hold lives in `MikanCompanionView`, not the view model. It
triggers on `onChange` of the completed-response ID, so reopening a chat whose
last run completed does not celebrate again. Cancelled and failed runs never
celebrate.

## Rendering: vector, not sprites

Mikan is drawn on a `Canvas`, not from PNG sprite sheets. Procedural raster
sprites were tried first and rejected: they looked like programmer art at 32pt
and could only step between fixed frames. The vector rig is sharp at any size,
needs no assets, and picks the outline color from the color scheme.

- Everything is drawn in a **100×110 unit space with the feet on y = 106**,
  then scaled to fit. Keep new geometry in those units.
- A pose is a `MikanRig`. `MikanFigure.animatableData` is the whole rig, so
  any state change springs every value (ears, arms, tail curve, lids) at once.
  To add an animatable value, add a `Slot` case and set it in `pose(for:)`. The
  vector is `SIMD64`, so there is plenty of room.
- The desk (`laptop` slot) is drawn last so the lid sits in front of the paws.
  It slides up 12 units and fades in as `laptop` goes from 0 to 1.
- Discrete features (happy `^ ^` eyes, open mouth, arm layering) switch when the
  interpolated value crosses 0.5.
- Lids are one shape for both moods: `sadLid` slants down at the outer corner,
  `angryLid` at the inner corner.
- Walk direction is **physical** (`MikanWalkDirection.left/.right`) because a
  `Canvas` drawing never mirrors for RTL. `CompanionSide` is physical too, and
  `MikanCompanionView` converts it to a leading/trailing alignment per layout
  direction.

## Taps

Taps are classified by `CompanionTapTracker`, a pure value type with unit
tests. It counts every tap itself (`onTapGesture` without a count), so there is
no single-tap delay:

- Two taps within 0.35s walk Mikan to the other side over 3s. A pair is used up
  once it walks, so a third quick tap starts a new pair rather than walking (or,
  under Reduce Motion, swapping) again.
- Five taps within 2.5s make Mikan `.annoyed` (ears pinned, arms crossed,
  angry lids and brows, a red anger mark) with one medium haptic
  (`ChatHaptics.companionAnnoyed`, honoring the haptics setting). Every
  further tap restarts a 3s calm-down timer.
- Mikan ignores touches while walking: SwiftUI hit-tests the destination
  layout, not the animated position, so the transcript keeps those touches.
- The tap area is a capsule over the cat's body (55% × 92% of the frame), not
  the whole frame, so the transcript under the rest of the frame stays
  scrollable and tappable.

## Motion rules

These follow the "no continuous repaint" and Reduce Motion rules in `AGENTS.md`.

- `MikanView`'s fidget, typing, and walk loops are keyed on Reduce Motion as
  well as their state, so turning Reduce Motion on mid-chat stops them at once.
- Nothing loops while Mikan is at rest. Idle fidgets (a blink, sometimes an ear
  twitch or tail flick) fire every 2.5–5s through a `.task(id: state)` sleep
  loop, then hold still. There are no fidgets in `.happy`.
- A walk keeps the current expression (`MikanRig.walking(toward:stride:)` is
  applied on top of the state's pose) and puts the laptop away.
- The walk loop runs only while `walking` is non-nil (about 3s, a step every 0.3s).
- `.working` types in bursts instead of fidgeting: 4–7 alternating keystrokes
  110ms apart, then a 1.2–2.6s pause. Keystrokes lift a paw 2.4 units on top of
  the pose; they are not rig slots.
- The walk pose (`walkingTo`) and the walk position (`walkPosition`) are separate
  state with separate animations. Do not add an implicit
  `.animation(_:value: walking)` inside `MikanView`: implicit animations also
  re-time the view's position change in the same transaction, so Mikan would
  jump across in 0.4s and then walk in place. (That was a real bug.)
- Reduce Motion: pose changes snap, fidgets and the walk cycle are off, and a
  double-tap swaps sides instantly.

## Placement

Mikan is the **first** row of `ChatView.composerAccessoryStack`, so it rides the
keyboard and sits on top of any pinned notices and run-status bars.

- Mikan renders at `CompanionSettings.width` × `rowHeight` (70×77pt).
- It deliberately **reserves no transcript space**. It is not counted in
  `composerAccessoryVisibleItemCount` or `composerAccessorySpacerHeight`, so it
  may overlap the bottom of the newest message. Being first in the stack keeps
  it from ever covering a notice or the run-status bar, which keep their
  reserved slots directly above the composer. The stack renders when
  `isCompanionEnabled` even if no other item is visible.
- The scroll-to-bottom button is centered and Mikan rests at a side edge, so
  they only cross while Mikan walks across.
- The stack used to apply `.allowsHitTesting(false)` to the whole `VStack`. That
  modifier now sits on each existing item, so only Mikan's body capsule takes
  touches (see Taps). The rest of its row passes touches through to the transcript.
- It must never live inside the transcript `LazyVStack` or any scroll row.

## Settings

| Key | Default | Meaning |
|---|---|---|
| `companion.enabled` | `true` | Show Mikan in chat. |
| `companion.side` | `"right"` | `left` or `right` (physical). |

These are app-wide appearance preferences, not per-server state. The Left/Right
picker is the VoiceOver path to moving Mikan, because `MikanView` is
`accessibilityHidden` and the double-tap is not reachable from VoiceOver.

## Changing the art

Edit the geometry in `MikanPainter` and the poses in `MikanRig.pose(for:)`, then
check the `#Preview`s in `MikanView.swift`. The "Interactive" preview includes a
copy at the real in-app size (70×77pt). Light and dark outline colors are
`MikanPalette.inkLight` and `MikanPalette.inkDark`. The five user-facing strings
are in `Localizable.xcstrings` with all 17 shipped languages (`needs_review`).
