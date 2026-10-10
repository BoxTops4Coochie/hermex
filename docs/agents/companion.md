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

Tests: `HermesMobileTests/CompanionStateMachineTests.swift` (contains both
`CompanionStateMachineTests` and `MikanRigTests`).

## States

`CompanionStateMachine.state(isActiveStream:hasError:justCompletedResponse:isRunningTool:isAnnoyed:)`
is pure. Priority: **annoyed > error > just completed > running a tool
(`.working`) > streaming (`.thinking`) > idle**. `.working` also requires an
active stream, so the laptop never outlives a cancelled run.

| Input (from `ChatView`) | Source |
|---|---|
| `isActiveStream` | `viewModel.activeStreamID != nil` |
| `hasError` | `sendErrorMessage`, `errorMessage`, or `latestRunOutcome?.ending == .failed` |
| completed response | `latestRunOutcome` with `ending == .completed`; its `endedAt` is the trigger |
| `isRunningTool` | `viewModel.liveToolCalls.contains { !$0.isCompleted }` (ChatView already reads `liveToolCalls`, so no new invalidation) |
| annoyed | local to `MikanCompanionView`: tapping Mikan too often (see Taps) |

`.working` shows Mikan standing at a cardboard box with a laptop on it (lid
back toward the viewer, a mikan sticker, a line of screen light), both paws on
the keyboard and eyes on the screen. `MikanCompanionView` turns working on as
soon as a tool runs and off only after tools have been idle for 1.5s, so bursts
of short tool calls do not flicker the laptop in and out.

`.happy` is a pointing pose: Mikan leans and points up toward the newest
message, which sits on the leading side of the transcript (up-left in LTR,
mirrored with `MikanRig.mirror()` in RTL). The 2s hold lives in
`MikanCompanionView`, not the view model.
It triggers on `onChange` of the completed-response ID, so reopening a chat
whose last run completed does not celebrate again. Cancelled and failed runs
never celebrate.

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

`MikanCompanionView` counts every tap itself (`onTapGesture` without a count),
so there is no single-tap delay:

- Two taps within 0.35s walk Mikan to the other side over 3s. More taps
  while walking do not start another walk.
- Five taps within 2.5s make Mikan `.annoyed` (ears pinned, arms crossed,
  angry lids and brows, a red anger mark) with one medium haptic
  (`ChatHaptics.companionAnnoyed`, honoring the haptics setting). Every
  further tap restarts a 3s calm-down timer.
- A walk keeps the current expression (`MikanRig.walking(toward:stride:)` is
  applied on top of the state's pose), so tapping during the walk annoys Mikan
  mid-stride.

## Motion rules

These follow the "no continuous repaint" and Reduce Motion rules in `AGENTS.md`.

- Nothing loops while Mikan is at rest. Idle fidgets (a blink, sometimes an ear
  twitch or tail flick) fire every 2.5–5s through a `.task(id: state)` sleep
  loop, then hold still. There are no fidgets in `.happy`.
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
  modifier now sits on each existing item, so only Mikan's own frame takes
  touches. The rest of its row passes touches through to the transcript.
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
