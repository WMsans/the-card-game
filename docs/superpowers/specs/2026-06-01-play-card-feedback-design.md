# Card Play Feedback Improvements — Design

**Date:** 2026-06-01
**Branch:** feat/play-card-feedback

## Problem

When the player drags a card to play it, the intended "feature" animation (card
flies to screen-center, holds, then continues to its destination) does not run:
the card visibly **snaps back to its hand slot** instead. Spells and traps have a
center-feature beat in code (`_feature_spell` / `_feature_trap_deploy`) but it is
overridden at runtime. Minions never had a center beat — they squash in place on
the board.

Separately, the trap deployment flies a single gentle quadratic-bezier curve to
the trap pile. We want a dramatic full circular orbit around screen-center before
it darts into the pile, in the spirit of playing a "power" card in Slay the Spire.

## Root Cause of the Snap-Back

In `src/ui/card/card_view.gd`, the mouse-release branch of `_on_gui_input`
unconditionally starts `_tween_release`, animating `position` back to
`_rest_position` (the hand slot) over 0.25s:

```
drag_released.emit(self)          # line 295 — handler runs play synchronously
...                               # lines 296-304
_tween_release = create_tween()
_tween_release.parallel().tween_property(self, "position", _rest_position, 0.25)
```

The play flow is triggered from `drag_released.emit` (synchronously, up to the
first `await`): the handler calls `match.handle_drop` → `apply_action` →
`_run_bespoke` → `_feature_spell`, which creates the move-to-center tween and then
`await`s. Control then returns to line 296, where `_tween_release` is created
**after** the feature tween. Both tweens drive `position`; the later-created
release tween wins each frame and pulls the card back to the hand.

This is why unit tests pass (they call `_feature_spell` directly, with no drag, so
no release tween exists) while real play is broken.

## Goals

1. Played cards (minion, spell, trap) fly to screen-center and hold there.
2. Trap deployment performs a full 360° orbit around screen-center, then darts
   into the trap pile.
3. Cards flip face-down with a smooth animation that simultaneously scales the
   card slightly smaller; face-down cards in motion render at that smaller scale.

## Non-Goals

- No change to the underlying game engine, action resolution, or event model.
- No change to attack/combat animation paths (`CombatDirector` / `_director`).
- No change to the hover/grab tilt and wobble behavior beyond suppressing the
  snap-back for played cards.

## Components

### A. Suppress the snap-back for played cards (`CardView`)

- Add `var _consumed: bool = false`.
- Add `func mark_played() -> void: _consumed = true`.
- In the release branch of `_on_gui_input`, skip the `_tween_release`
  position/rotation snap-back when `_consumed` is true. (The grab-pop kill of
  competing tweens stays as-is.)
- Reset `_consumed = false` in `setup()` and on grab (the `pressed` branch), so a
  recycled or re-grabbed view behaves normally.

`match.handle_drop` calls `mark_played()` on the played card view **synchronously**
at each point it commits to a play — i.e. before `apply_action(...)` in the
by-discard, by-tickets, and leader-prompt branches. Because this runs inside the
synchronous portion of the `drag_released` handler (before the emit returns),
the flag is set before line 296 creates the release tween.

Helper: resolve the view via the existing `_find_card_view_any(instance_id)`.

### B. Unified move-to-center hold beat (`match.gd`)

Extract the common "reparent ownership + fly to center + hold" into a single
helper used by all three card types. The card being featured is the hand/opponent-
hand view found via `_find_card_view_any(iid)` (this runs inside `_run_bespoke`,
before `render_all`, so the source view still exists).

Shared beat:
1. `cv.z_index = 300` (render above board/piles during the feature).
2. Tween `global_position` to `FEATURE_CENTER - cv.size * FEATURE_SCALE * 0.5`
   and `scale` to `FEATURE_SCALE`, 0.25s, `TRANS_BACK`/`EASE_OUT`.
3. `CardJuice.spring_wiggle` for life (kept from current spell beat).
4. Hold `FeedbackFx.HOLD_TIME / spd`.

Per-type tail:
- **Spell:** `CardFlight.fly_out(cv, discard_pos)`; `cv.z_index = 0`. (unchanged)
- **Trap:** `cv.flip_to_face_down()` (component C) → `CardFlight.orbit_loop(...)`
  (component D) → `FeedbackFx.bump_pile(pile, spd)`; `cv.z_index = 0`.
- **Minion:** fly to the computed board slot, then let `render_all` swap in the
  real board view at the same position, plus a short landing squash.

Minion landing target: after `engine.apply`, the minion is in the player's board
model. Compute its slot with
`BoardLayout.slot(Enums.Zone.BOARD, index, count, player)` where `index` is the
minion's position in `state.players[player].board` and `count` is that board's
size. Convert to the view's coordinate space the same way other beats do, fly the
centered card there, then `cv.z_index = 0`. When `_run_bespoke` returns,
`apply_action` calls `render_all`: the hand render frees the now-empty hand view
and the board render instantiates the real board view at the same slot —
seamless because the positions match. The trailing `action_cue` landing squash
on the new board view provides the impact.

`action_cue.descriptors` drops its `CARD_PLAYED` → `MINION` branch so the bespoke
beat is the single owner of minion play feedback and there is no double hold.
`REQUEST_MET`, `UNIT_TRASHED`, `HARMONIZE`, and `RUMMAGE_PERFORMED` cues are
unchanged.

`FEATURE_CENTER` and `FEATURE_SCALE` constants are unchanged.

### C. Smooth flip-to-face-down + smaller face-down cards (`CardView`)

- Add `const FACE_DOWN_SCALE := 0.85` (multiplier applied to `base_scale` for a
  card that is face-down while in motion).
- Add `func flip_to_face_down() -> Tween` mirroring `flip_to_face_up()`:
  - `_surface.pivot_offset = _surface.size * 0.5`
  - `_surface.scale:x` → 0 (SINE/EASE_IN), `tween_callback(set_face_down(true))`,
    `_surface.scale:x` → 1 (SINE/EASE_OUT).
  - **In parallel**, smoothly tween the whole node `scale` from its current value
    to `base_scale * FACE_DOWN_SCALE` over the flip duration, so the card shrinks
    as it flips.
- `card_flight_layer.spawn_traveler` sets face-down travelers' base scale to the
  smaller face-down scale so all face-down cards in motion are consistently a
  little smaller.

### D. Trap 360° orbit (`CardFlight`)

Add `static func orbit_loop(cv, center, radius, to_pos, speed) -> Tween`:
- Compute the card's current angle relative to `center` from `cv.position`.
- Sample a **full 360°** circle of the given `radius` around `center`, starting at
  that angle, into N segment points (e.g. 16) so the path reads as a smooth large
  loop returning near the start.
- Tween `position` through the loop points (LINEAR per segment), total duration
  scaled by `speed`.
- After the loop, dart from the final loop point into `to_pos` while tweening
  `scale` down to a small landing size, matching the existing pile-landing feel.
- The card is already face-down (flipped in B/C) and stays face-down throughout.

A companion pure helper (e.g. `circle_points(center, radius, start_angle,
segments)`) generates the ring so it is unit-testable without a live node, mirror-
ing the existing `arc_points` pattern.

The trap beat replaces its `CardFlight.flourish_arc(cv, to_topleft,
Vector2(-220,-120), spd)` call with `orbit_loop`, using `FEATURE_CENTER` as the
orbit center and the trap-pile anchor as `to_pos`. `flourish_arc` / `arc_points`
remain for any other callers.

## Data Flow (trap example)

```
drag release ─► handle_drop ─► mark_played(cv)         (sync, suppresses snap-back)
            └─► apply_action ─► engine.apply (card → trap_set in model)
                            └─► _run_bespoke
                                  ├─ fly cv to center + hold        (B)
                                  ├─ cv.flip_to_face_down()         (C: flip + shrink)
                                  └─ CardFlight.orbit_loop(...)      (D: 360° + dart to pile)
                            └─► render_all  (trap now lives in pile; cv z reset)
```

## Testing

New tests:
- **Snap-back suppression:** a `CardView` with `mark_played()` set does not run the
  release position tween back to `_rest_position` on release; an unflagged view
  still does.
- **`orbit_loop` / `circle_points`:** sampled points all sit ≈`radius` from the
  center (full ring), and the flight ends at `to_pos`.
- **Minion feature:** the played minion's hand view moves toward center during the
  hold, then ends at its computed board slot.
- **`flip_to_face_down`:** after the flip the view is face-down and its node scale
  equals `base_scale * FACE_DOWN_SCALE`.

Existing tests that must stay green:
- `test_bespoke_beats.gd` — center-move and trap face-down assertions still hold.
- `test_card_flight.gd` — `arc_points` / `flourish_arc` / `fly_*` unchanged.
- `test_card_flip.gd` — `flip_to_face_up` unchanged.
- `action_cue` tests — minion removal from descriptors reflected; other cues intact.

## Risks / Notes

- **One-frame swap on minion landing:** the feature view is freed and the real
  board view instantiated in the same `render_all`. Positions match, so the swap
  should be visually seamless; verify in-app.
- **`action_cue` ramp / chain timing:** removing the minion branch changes which
  events drive the speed ramp; confirm chained plays still feel right.
- **Orbit radius vs. screen bounds:** ~280px keeps a 0.6-scaled card on-screen at
  1920×1080; tune during verification.
