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

`CompanionStateMachine.state(isActiveStream:hasError:justCompletedResponse:isAnnoyed:)`
is pure. Priority: **annoyed > error > just completed > streaming > idle**.

| Input (from `ChatView`) | Source |
|---|---|
| `isActiveStream` | `viewModel.activeStreamID != nil` |
| `hasError` | `sendErrorMessage`, `errorMessage`, or `latestRunOutcome?.ending == .failed` |
| completed response | `latestRunOutcome` with `ending == .completed`; its `endedAt` is the trigger |
| annoyed | local to `MikanCompanionView`: tapping Mikan too often (see Taps) |

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
  To add an animatable value, add a `Slot` case and set it in `pose(for:)`. All
  32 slots of the `SIMD32` are used, so widen it to `SIMD64` first.
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

- Two taps within 0.35s walk Mikan to the other side over 1.8s. More taps
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
- The walk loop runs only while `walking` is non-nil (about 1.8s, a step every 0.22s).
- Reduce Motion: pose changes snap, fidgets and the walk cycle are off, and a
  double-tap swaps sides instantly.

## Placement

Mikan is the last row of `ChatView.composerAccessoryStack`, so it rides the
keyboard and stacks with pinned notices and run-status bars.

- Mikan renders at `CompanionSettings.width` × `rowHeight` (40×44pt; the tap
  target meets the 44pt minimum).
- It counts in `composerAccessoryVisibleItemCount`, and its
  `CompanionSettings.rowHeight` counts in `composerAccessorySpacerHeight`.
  That reserves room in the transcript inset so Mikan never covers the last
  message.
- The stack used to apply `.allowsHitTesting(false)` to the whole `VStack`. That
  modifier now sits on each existing item, so only Mikan's 40pt hit area takes
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
copy at the real in-app size (40×44pt). Light and dark outline colors are
`MikanPalette.inkLight` and `MikanPalette.inkDark`. The five user-facing strings
are in `Localizable.xcstrings` with all 17 shipped languages (`needs_review`).
