# Action Feedback for Every Card Action — Design

Date: 2026-06-01
Branch: `feat/play-card-feedback`

## Goal

Today only attacks have clear visual feedback (`CombatDirector`). Every other
card action — play a minion, cast a spell, deploy a trap, a trap firing/being
revealed, a request/condition being met, harmonize, rummage, trash — resolves
silently or with only incidental movement. The player cannot reliably tell what
just happened, especially on the opponent's turn.

This work gives **every action a clear, readable feedback beat**, and adds a
**trap pile** so deployed traps are visible on the board (face-up for you,
face-down for the opponent).

## Decisions (resolved during brainstorming)

- **Style: hybrid.** A unified cue covers most events; trap deploy and trap
  fired/revealed get richer bespoke treatment.
- **Bespoke moments:** spell cast, trap deployed, trap fired/revealed.
  Everything else uses the unified cue.
- **Trap pile count:** visible for both players (number of set traps is public);
  contents face-down for the opponent.
- **Readability hold:** every feedback beat holds **2.0s** for readability
  (shared `HOLD_TIME` constant).
- **Sequencing:** when one action produces multiple cues, they play
  **sequentially** (one 2s beat each) — but **ramp gradually faster** across the
  chain, reusing `CombatDirector`'s speed-ramp logic. Input is locked
  (`_anim_busy`) until the chain finishes.
- **Spell cast motion:** Balatro joker-trigger feel — the spell flies to **screen
  center**, scales up, does a snappy **spring-rotation wiggle** within the 2.0s
  hold, then flies a short path to the caster's **discard pile**.
- **Trap deploy motion:** Slay-the-Spire "power card" feel — the trap features at
  **screen center**, scaled up, holds 2.0s, then sweeps along a **curved arc**
  into the trap pile in a short time, flipping face-down, ending with a pile thunk.
- **Audience:** cues fire for **both** players' actions.

## Approach

Extend existing seams rather than build parallel systems:

- `match.gd` already calls `_play_flourishes(events)` after **every** action —
  the natural dispatch point for the unified cue.
- `PileView` + `PileOverlay` already implement a clickable, counted pile with a
  fly-out viewer that supports face-down cards — the trap pile is nearly free.
- `CombatDirector` shows the pattern: a **pure static function** that turns
  events into a descriptor, plus a thin instance that animates it, with a
  speed-ramp (`next_speed`, `RAMP_STEP`, `MAX_SPEED`, `CHAIN_GAP`). The new cue
  system mirrors this split so logic is testable without rendering, and reuses
  the same ramp so chained cues accelerate like chained attacks.

Rejected alternatives: a fully reactive event-bus subscription model and bespoke
animations for every event — both are more code and fight the current structure.

## Components

### 1. Unified action cue — `ActionCue` (`src/ui/match/action_cue.gd`)

Mirrors the `CombatDirector` split:

- `ActionCue.descriptors(events, lookup) -> Array` — **pure**. Maps each
  qualifying event to `{ at_pos: Vector2, label: String, color: Color,
  target_id: int }`. `lookup` resolves an instance id to a board `CardView`
  center (or a pile anchor). Unit-testable.
- An `ActionCue` instance with `play(match, events) -> void` (async). It builds
  descriptors, then for each one in order: plays the in-place beat below, holds
  for `HOLD_TIME / speed`, then advances. Speed starts at 1.0 and ramps via the
  shared ramp helper across the chain.

#### What the common cue looks like (in-place — no trip to center)

1. **Pop** — the target card does a quick squash-stretch **scale-punch** (pops to
   ~1.15× and springs back, `TRANS_ELASTIC`/`BACK`), snapping the eye to it.
2. **Label** — a short word springs up just above the target and drifts slightly
   upward while held, reusing the `DamageNumber` / `FxLayer` float pattern.
3. **Tint** — a brief color flash on the card during the hold, keyed to meaning
   (the descriptor's `color`; e.g. gold for request met, green for played).
4. **Hold** — the label stays readable for `HOLD_TIME` (ramped faster across a
   chain), then fades.
5. **No-single-card events** — `HARMONIZE` pops the whole board row with the label
   at board center; `RUMMAGE` pops the discard pile with the label at that pile.

Shared constants: `HOLD_TIME := 2.0`. To avoid duplication, the ramp helper
(`next_speed`) and the pile-bump helper (`_bump_pile`), plus the ramp constants
(`RAMP_STEP`, `MAX_SPEED`, `CHAIN_GAP`), are **extracted into a new
`FeedbackFx` helper** (`src/ui/match/feedback_fx.gd`). `CombatDirector` is
updated to call `FeedbackFx` for these so both it and `ActionCue` share one
implementation.

#### Event → cue mapping

Fires for both players. Skipped during attack clusters (the
`CombatDirector.has_attack(events)` guard already gates `Flourishes`; the same
guard gates `ActionCue` so attack damage isn't double-reported).

| Event | Cue |
|---|---|
| `CARD_PLAYED`, `card_type == MINION` | "PLAYED" pulse on the new board card |
| `CARD_PLAYED`, `card_type == SPELL` | handled by §3a (bespoke center feature) |
| `CARD_PLAYED`, `card_type == TRAP` | handled by §3 (no generic cue) |
| `REQUEST_MET` | "REQUEST MET" pulse on the card (`instance`) |
| `HARMONIZE` | "HARMONIZE" ripple/pulse across that player's board (payload has only `player`, no instance) |
| `UNIT_TRASHED` | "TRASHED" on the unit (`instance`) before it leaves |
| `RUMMAGE_PERFORMED` | "RUMMAGE ×{count}" near that player's discard pile |
| `CARD_RUMMAGED` / `CARD_DRAWN` / `CARD_DISCARDED` | no new cue — already animated by flight travelers; avoids double feedback |

Dispatch: `match.gd`'s `_play_flourishes` calls the new `ActionCue.play`
alongside the existing `Flourishes.play`. `ActionCue` and `Flourishes` stay
separate classes; existing damage-number / mill flourishes are unchanged.

### 2. Trap pile UI

- Add `PlayerTrap` and `OppTrap` `PileView` instances to the Table scene
  (`match.tscn`), positioned within the existing pile stations
  (`PlayerPileStation` / `OppPileStation`).
- `render_all()` sets their counts from `PlayerState.set_traps` for each player —
  **count visible for both**.
- Wire `clicked` signals (like deck/discard) to a handler that opens the pile
  overlay on the owner's `set_traps`.
- `PileOverlay.open(...)` gains a `face_down: bool = false` parameter:
  - Your traps: open face-down then flip face-up (existing behavior).
  - Opponent's traps: open and **stay face-down** (skip the flip schedule).
- Titles: "Your Traps" / "Opponent's Traps".
- Add a `Zone.TRAP_SET` case to `FlightAnchors.of` / `_pile_for` so the pile's
  screen anchor is available to both the overlay fly-out and the deploy flight.

### 3. Bespoke center-feature beats (spell cast, trap deployed)

Spell cast and trap deploy share a structure: the played card flies to **screen
center**, scales up, holds for `HOLD_TIME` (ramped if part of a chain), then
flies to its destination. They differ only in the per-type flourish during the
hold and the destination. A shared helper provides the lift-to-center and the
return flight; each type supplies its own hold-flourish and end zone.

#### 3a. Spell cast (Balatro joker-trigger feel)

On `CARD_PLAYED` with `card_type == SPELL`:

1. **Lift & center** — the spell flies from the hand to **screen center**, scaled
   up to a readable size.
2. **Spring trigger** — within the `HOLD_TIME` hold, a snappy **spring-rotation
   wiggle**: tilts a few degrees and elastically springs back to upright (a quick
   damped oscillation, `TRANS_ELASTIC`/`BACK`), signalling the effect resolving.
3. **Hold** — stays centered and readable for the full `HOLD_TIME`; the wiggle
   plays inside that window.
4. **Fly home** — a short flight to the caster's **discard pile**, shrinking as it
   goes (reuse `CardFlight.fly_out`).

New flight primitive `CardFlight.spring_wiggle(cv, degrees, ...) -> Tween` for the
trigger oscillation.

#### 3b. Trap deployed (Slay-the-Spire power-card feel)

On `CARD_PLAYED` with `card_type == TRAP`:

1. **Lift & center** — the trap card lifts to **screen center**, scaled up, held
   for `HOLD_TIME` (ramped if part of a chain) so the player can read it.
2. **Curved sweep** — a short flight along a **curved arc** into the owner's trap
   pile, rotating slightly and flipping to **face-down** en route.
3. **Land** — pile "thunk" (the shared `_bump_pile` scale-punch).

New flight primitive `CardFlight.flourish_arc(cv, to_pos, control_offset, ...)
-> Tween`: samples a quadratic/cubic Bézier across several segments so the path
reads as a circular/looping sweep (the existing `fly_in` only does a single
midpoint hop). Kept structured so waypoints are unit-testable.

### 4. Bespoke: trap fired / revealed

- Keep the existing `TrapRevealOverlay` as the decision/reveal beat. Read-only
  intercept hold goes from 0.8s → `HOLD_TIME` (2.0s) for consistency.
- On `TRAP_FIRED` (`{player, instance}`): the owner's trap pile **flashes +
  bumps**, the fired trap flips face-up and flies trap-pile → discard, with a
  "TRAP SPRUNG" cue — making clear which pile reacted.

### 5. Timing & sequencing

- `apply_action` (and AI turns) already lock input via `_anim_busy` during the
  attack director. The cue chain extends that: set `_anim_busy` for the whole
  `ActionCue.play` / bespoke sequence, clear it after.
- Within one action's event batch, cues + bespoke beats play **sequentially**.
  First beat holds full 2.0s; each subsequent beat's hold is `HOLD_TIME / speed`
  where `speed` ramps (`next_speed`) up to `MAX_SPEED`, gap-resetting like
  attacks. Net: long actions accelerate instead of dragging linearly.
- Order within a batch follows event order, consistent with `CombatDirector`.

## Testing (gdUnit4, matching repo conventions)

- `test_action_cue.gd` — `ActionCue.descriptors` mapping: correct label / color /
  target per event type; minion `CARD_PLAYED` produces a "PLAYED" cue, while
  spell and trap `CARD_PLAYED` produce **no** generic cue (routed to bespoke
  §3a/§3b); rummage/draw/discard produce none.
- `CardFlight.spring_wiggle` — oscillation returns to upright (final rotation 0).
- Spell-cast routing: `CARD_PLAYED` spell drives the lift-to-center → wiggle →
  fly-to-discard path.
- Ramp: `next_speed` chaining behaves (reuse/extend existing combat-director ramp
  coverage).
- `test_pile_view` / `test_pile_overlay` extensions — trap pile renders
  `set_traps` count; click opens overlay; `face_down = true` keeps opponent traps
  face-down (no flip scheduled).
- `FlightAnchors` resolves `Zone.TRAP_SET` for both players.
- `CardFlight.flourish_arc` waypoint sampling (endpoints + curvature).
- Trap-deploy routing: `CARD_PLAYED` trap drives the feature→sweep path to the
  `TRAP_SET` anchor.

Animation timing/visual polish is verified by running the app, not asserted in
unit tests.

## Out of scope

- No changes to game rules / engine logic; this is presentation only. New event
  payload fields are not required (existing payloads suffice).
- No rework of the existing attack `CombatDirector` beyond extracting shared
  helpers (ramp, pile-bump) for reuse.
- No new sound design (visual feedback only).
