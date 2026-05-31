# Card Flight Transitions — Design

**Status:** Approved design, ready for implementation planning.

## Goal

Make card movement between zones legible and juicy. Today every zone boundary
is a visual discontinuity: a drawn card pops into existence at the scene origin
and slides to the hand; a dying minion dissolves in place; mill and reshuffle
just change a counter. Cards never visibly *travel* between piles, so the player
can't follow what happened.

We want Slay-the-Spire-style **visible card travel** between pools and hand, but
with **Balatro-grade polish** (arcs, overshoot-and-settle, dealt-card stagger) —
not StS's dead-straight, stiff slides. We also want the existing in-hand card
selection ("fly to middle") to ride on the *same* juicy motion so the whole game
feels consistent.

## Scope

The flight system animates these six transitions, all of which are the same
`from_anchor -> to_anchor` flight differing only in face state and stagger:

| Transition | Path | Event source |
|---|---|---|
| Draw | deck -> hand | `CARD_DRAWN` |
| Rummage | discard -> hand | `CARD_RUMMAGED` |
| Mill | deck -> discard | `CARD_DISCARDED` (from deck) |
| Discard from hand | hand -> discard | `CARD_DISCARDED` (from hand) |
| Death | board -> discard | `UNIT_DIED` |
| Reshuffle | discard -> deck | `DECK_RESHUFFLED` |

Out of scope: any engine/game-logic change. The engine and its event stream are
unchanged; this is purely a presentation layer.

## Key decisions (locked during brainstorming)

1. **Architecture: per-zone ownership + small flight pieces (Approach A).** Zones
   keep owning their `CardView` nodes as they do today. We do *not* introduce a
   persistent one-node-per-card registry (Approach B) nor a pure per-frame
   spring-chase. The reasoning: a per-frame chase smooths *motion* but does not
   solve *identity/lifecycle* (birth at a source, death after landing) — those
   only vanish under full persistent identity (B), which is a large refactor.
   Approach A keeps the blast radius small and stays fully testable.

2. **The "manager" is small, stateless pieces — not a god-object.** A pure diff
   (`TransitionPlan`), a pure anchor lookup (`FlightAnchors`), a tween library
   (`CardFlight`), and a dumb container (`CardFlightLayer`). The orchestration is
   a `plan` parameter threaded through the existing zone renders.

3. **Source of truth for a card's source is a zone snapshot diff, not events.**
   `CARD_DISCARDED` is overloaded (mill, discard-to-limit, effect-discard), so
   the event alone can't tell us where a card came from. Instead we snapshot
   every card's zone before the action and after, and diff.

4. **Timing: staggered, non-blocking.** Game state updates immediately; flights
   are pure visual polish layered on top and never lock player input. A fast
   player may act "ahead" of an in-flight animation — that is acceptable and
   handled (see Edge cases).

5. **Flip: scale-x squash (Approach B for the flip), not a perspective turn.**
   See "Flip animation" below.

## Architecture & data flow

```
apply_action(action):
    before := snapshot_zones(state)        # { instance_id -> {zone, player} }, all zones
    engine.apply(action)                   # state mutates; events logged (unchanged)
    after  := snapshot_zones(state)
    plan   := TransitionPlan.compute(before, after)   # pure, ordered zone-change list
    render_all(plan)                       # zones reconcile, now plan-aware
    drive_pile_travelers(plan, events)     # mill/reshuffle travelers (no zone owns these)
    _post_action()
```

`TransitionPlan.compute(before, after)` returns an ordered list of
`{ instance_id, from_zone, to_zone, player }` for every card whose zone changed.
From a transition's zones we derive screen **anchors** via `FlightAnchors`:

- `HAND` / `BOARD` -> the card's computed `BoardLayout.slot(...)` position
- `DECK` / `DISCARD` -> that player's pile node global position

This single uniform pipeline handles all six transitions plus any future one;
there is no per-event special-casing for source.

`events` is a *secondary* signal only: it drives the reshuffle burst (a count
change, not per-card movement — capped, see below) and can refine stagger
ordering.

## Components

1. **`TransitionPlan`** — pure `RefCounted`, unit-tested like `StagedSelection`.
   `compute(before, after) -> Array`. No scene dependencies.

2. **`FlightAnchors`** — static helper. `of(zone, player, match_node) -> Vector2`.
   The single place mapping a logical zone to a screen point.

3. **`CardFlight`** — static tween builders; the one shared juicy mover. Also
   used directly by the in-hand selection overlay.
   - `fly_in(cv, from_pos, to_rot, delay)` — place card at `from_pos`, tween to
     its already-set rest slot with arc + overshoot-settle + landing scale-pop,
     offset by `delay` (the stagger).
   - `fly_out(cv, to_pos, delay) -> Tween` — tween to a pile anchor with a slight
     shrink/fade; returns the tween so the caller frees the node on `finished`.

4. **`CardFlightLayer`** — `Node2D` container on top of `Table`. Owns nodes no
   zone owns while airborne: reparented *leavers* (death/discard) and spawned
   *pile->pile travelers* (mill/reshuffle). Frees each on landing. The only
   stateful new node, and it is just a parent.

**Zone-view integration seam:** `render(cards, player)` gains a `plan` argument.
- **Entering card** (new node; plan says it came from zone Z): start it at
  `FlightAnchors.of(Z)` and call `CardFlight.fly_in` instead of the current
  origin-tween. Covers draw, rummage, board<->hand bounce.
- **Leaving card** (gone from the list; plan says it went to a pile): instead of
  `queue_free()`, hand the node to `CardFlightLayer` + `fly_out` to that pile.
  Covers death, hand-discard.

**`match.gd`:** does the before/after snapshot + `TransitionPlan.compute`, passes
the plan into `render_all` -> zone renders, and drives **pile->pile travelers**
(mill, reshuffle) by asking `CardFlightLayer` to spawn capped face-down travelers
— the only transitions no zone owns.

## Per-transition behavior & feel

All flights are the same `from_anchor -> to_anchor` motion; defaults (tunable):

| Transition | Face | Stagger | Notes |
|---|---|---|---|
| Draw | face-down, flip to face-up ~60% through flight | ~0.06s/card | Headline juice: arc up out of deck, overshoot-settle into the fan, scale-pop on land |
| Rummage | face-up the whole way | ~0.06s/card | Same landing juice, no flip |
| Mill | face-down, flip to face-up on landing | ~0.05s/card | Capped travelers on big bursts |
| Death | face-up | none (usually 1) | Reparented real node; small shrink dropping into discard |
| Discard from hand | face-up | ~0.05s | Reparented real node |
| Reshuffle | face-down | burst | Capped at ~5 representative travelers + deck shimmer, not one-per-card; `returns_on_reshuffle()` cards appear in the plan as discard->hand and fly rummage-style |

**Motion character (Balatro, not StS):**
- **Arc, not straight line** — flights lift along a slight vertical arc.
- **Overshoot-and-settle** on arrival (elastic/back tail) + a brief **scale pop**,
  reusing the elastic feel already in `card_view`'s hover/release tweens so it is
  consistent with the rest of the game.
- **Stagger** makes multi-card draws read as *dealt*, not teleported.
- Durations ~0.30-0.40s, in the same family as the existing 0.25s render tweens.

## Flip animation (the hard part)

The cards are "fake 3D": `CardSurface` is a single `SubViewportContainer` driven
by the `fake_3D` shader (real perspective with `cull_back` + backface discard).
Because it shows **one** texture (whatever the viewport renders — back *or*
front), any two-sided flip *must* swap content at the edge-on midpoint
(`set_face_down(false)` at the sliver), regardless of how the quad turns.

**Decision: scale-x squash flip (not the perspective turn).** Tween
`CardSurface.scale.x` 1 -> 0 (card squashes to a vertical sliver), swap face at
0, then 0 -> 1. Rationale:
- No shader cull/mirror choreography. The perspective alternative would require
  toggling `cull_back=false` past 90 degrees *and* horizontally mirroring the
  front content so it isn't reversed — fiddly, stateful, and visual-only (hard to
  test). That is exactly the corner-case complexity we want to avoid.
- Lives on the **inner** `CardSurface` node, so it never fights the root
  `CardView`'s scale (used by `base_scale`, hover, drag, layout). Fully isolated.
- Matches the Balatro reference — their flips are essentially squash flips with
  good timing. On a small in-flight card over ~0.18s it is indistinguishable from
  a true 3D turn.

The flip is only exercised by **two** transitions (draw, mill). It triggers via a
`tween_callback` at ~60% of the draw flight, or on-landing for mill. A subtle
shader `y_rot` tilt could be layered on later for flavor without changing the
mechanism.

## Folding in the in-hand selection plan

`docs/superpowers/plans/2026-05-31-in-hand-card-selection.md` stays almost
entirely intact — its pure `StagedSelection` helper, the `HandChoice` controller,
the `match.gd` routing, and all its tests keep their structure. The selection's
"fly to middle" is a hand->center->hand move that lives *inside* the overlay, so
it does **not** go through `TransitionPlan`/zone-render (those are for real zone
changes). It calls **`CardFlight` directly** — the one shared mover. That is the
entire fold-in.

Two snippets in that plan change from hand-rolled tweens to `CardFlight`:
- **Task 2, `hand_view.set_choice_excluded`** — its inline 0.2s cubic reflow tween
  becomes a `CardFlight` reflow call.
- **Task 3, `HandChoice._restage`** — staged cards fly to the centered row via
  `CardFlight.fly_in`-style motion (arc + overshoot + landing pop) instead of a
  plain 0.2s tween.

Behavior, indices, routing, and the existing assertions (which check
`_rest_position` end-states, not mid-motion) are unchanged. The plan doc also
gets a dependency note at the top: it must be implemented **after** this shared
layer exists.

## Testing strategy

Mirrors the existing "assert end-state, not mid-motion" philosophy.

- **`TransitionPlan`** — pure unit tests: feed `before`/`after` zone dicts, assert
  the ordered transition list (draw, mill, death, discard, rummage, reshuffle with
  `returns_on_reshuffle`).
- **`FlightAnchors`** — assert `HAND`/`BOARD` map to `BoardLayout.slot` positions
  and `DECK`/`DISCARD` map to pile node positions (needs a spawned match).
- **`CardFlight`** — assert the contract, not the motion: `fly_in` leaves the
  card's `_rest_position` equal to its slot (set before the tween, so correct
  synchronously); `fly_out`'s tween frees the node on `finished`.
- **`card_view` flip** — assert `set_face_down(false)` swaps content and the
  squash returns `CardSurface.scale.x` to its resting value; flip is isolated on
  the inner node.
- **Zone render with plan** — apply a real draw, assert the new hand `CardView`'s
  *start* position is the deck anchor; apply a death, assert the leaving node is
  reparented into `CardFlightLayer` rather than freed in place.
- **Integration** — spawn a match, apply draw/mill/discard actions, assert final
  hand/board/discard state and that `CardFlightLayer` self-empties after the
  flight duration (await frames). Headless input isn't transported, so everything
  is driven by applying actions (matching `test_pending_choice_routing.gd`).

## Edge cases

- **Non-blocking re-render mid-flight** — `set_rest` stays authoritative, so a
  follow-up `render_all` re-tweens from the card's current position; no snap, no
  orphans.
- **Pile->pile with no node either end** (mill/reshuffle) — capped face-down
  travelers owned by `CardFlightLayer`, self-freeing.
- **Reshuffle burst** — capped at ~5 travelers + deck shimmer, never one-per-card;
  `returns_on_reshuffle()` cards fall out of the plan as normal discard->hand
  flights.
- **Bounce (board->hand)** — the new hand node starts at the board anchor and
  flies in; the old board node frees at the same spot (one-frame overlap,
  invisible).
- **Unknown/missing anchor or view** — `FlightAnchors` returns a sane default and
  the render skips gracefully rather than crashing.

## File structure

- **Create** `src/ui/match/transition_plan.gd` (pure) + `tests/test_transition_plan.gd`
- **Create** `src/ui/match/flight_anchors.gd` + `tests/test_flight_anchors.gd`
- **Create** `src/ui/card/card_flight.gd` (shared mover) + `tests/test_card_flight.gd`
- **Create** `src/ui/match/card_flight_layer.gd` (+ node in `match.tscn`)
- **Modify** `src/ui/card/card_view.gd` — squash-flip method + "start at position" support
- **Modify** `src/ui/table/hand_view.gd`, `src/ui/table/board_view.gd` — `render(cards, player, plan)` plan-aware entry/exit
- **Modify** `src/ui/match/match.gd` + `match.tscn` — before/after snapshot, `TransitionPlan.compute`, thread plan into `render_all`, drive pile->pile travelers, add `CardFlightLayer`
- **Modify** `docs/superpowers/plans/2026-05-31-in-hand-card-selection.md` — dependency note + the two `CardFlight` snippet swaps

## Test command (headless, one suite)

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/<suite>.gd
```

Exit code 0 = pass. Harmless headless noise to ignore: `ERROR: Required object
"rp_font" is null` and the "InputEvents not transported in headless" notice.
