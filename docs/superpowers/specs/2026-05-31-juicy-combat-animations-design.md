# Juicy Combat Animations — Design

**Date:** 2026-05-31
**Branch:** feat/ui-fix
**Status:** Approved design, pending implementation plan

## Goal

Give card actions a clear, readable, cartoony representation that matches the
rest of the game's bouncy/juicy feel. Today combat resolves instantly and the
only feedback is a flat floating damage number plus a tiny shake; the attacker
never visibly acts. This pass makes attacks, deaths, and damage *legible* through
choreographed motion.

## Scope

In scope:

- **Attacks** (unit-vs-unit and unit-vs-deck): attacker physically acts on its
  target, then returns to its slot.
- **Deaths / destruction**: a juicy pop before the unit is swept to the discard.
- **Damage reactions**: stronger recoil / squash on the unit taking damage.
- **Damage-number particles**: Slay-the-Spire-2 style numbers that pop out and
  fall away under gravity, replacing the current flat floating number.

Out of scope (this pass): spell and trap effect telegraphs. The damage-number
particle helper is built to be reused by those later.

## Motion brief (decisions)

- **Attack on a unit:** *wind-up → lunge → recoil.* Anticipation pull-back, then
  a snap forward that overshoots into the defender, then a bouncy spring home.
- **Attack on the deck:** full fly-over to the deck pile and back (the literal
  example: "fly to my deck a sec and then return"), since there is no card to
  overlap.
- **Pacing:** choreographed and **blocking** — each attack plays its full
  sequence and the next action waits — but with a **Balatro-style speed ramp**:
  as attacks chain back-to-back the playback gets progressively faster, then
  relaxes when the table goes quiet.

## Architecture (Approach A: async choreography director)

The central problem: `apply_action` is synchronous and instant. `engine.apply`
resolves combat in one pass and `render_all()` immediately reconciles the board
to its final state — dead units are already gone before any flourish runs. To
choreograph a blocking sequence we insert an async director **between**
engine-resolve and reconcile. Because the director runs before `render_all`, the
attacker and the dying defender's `CardView`s still exist on the board, so the
director can lunge/hit/pop them in place; only afterward does `render_all` send
the dead one flying to the discard. This avoids fighting the existing reconcile.

### New units

Each is small and focused, matching the existing `CardFlight` / `FlightAnchors`
style.

| File | Role |
|---|---|
| `src/ui/match/combat_director.gd` | Async "brain." Given an action's event list, detects an attack cluster and `await`s a choreographed recipe. Owns the `anim_speed` ramp. |
| `src/ui/match/card_juice.gd` | Static cartoony primitives: `windup`, `lunge`, `recoil`, `squash`, `pop`. Sibling to `CardFlight`; reuses `CardView.base_scale`. |
| `src/ui/match/damage_number.gd` | Slay-the-Spire-2 falling-number particle. Reusable by anyone dealing damage. |

### Changed flow in `match.gd::apply_action` (becomes a coroutine)

```
apply_action(action):
    before  = snapshot_zones()
    engine.apply(action)               # resolves instantly, as today
    events  = log.slice(from)
    plan    = enrich(compute(before, snapshot_after))
    if _director.has_attack(events):
        _anim_busy = true
        await _director.play(events, self)   # animates the STILL-PRESENT CardViews
        _anim_busy = false
    render_all(plan)                   # NOW reconcile: dead units fly to discard
    spawn_pile_travelers(plan)
    play_flourishes(events)            # keeps non-combat fx (e.g. DECK mill label)
    post_action()
```

Non-attack actions (draws, plays, mills) skip the director entirely and behave
exactly as they do today.

### Input gating

An `_anim_busy` flag on `match.gd`. While a sequence plays, the human input
handlers (drag-release, unit-click, end-turn) early-return. The AI turn loop
already `await`s, so chained AI attacks queue naturally one after another.

## Choreography (the beats)

All durations below are the relaxed, single-attack timings; each is multiplied by
`1/anim_speed`. Values are starting points to be tuned in-engine.

### Attack vs. an enemy unit

1. **Wind-up (~0.12s)** — attacker eases *away* from the target (anticipation),
   scales up ~8%, tilts slightly toward it. `TRANS_BACK / EASE_OUT`.
2. **Lunge (~0.14s)** — snaps forward, overshooting *into* the defender.
   `TRANS_BACK / EASE_IN`. Attacker is z-bumped above the defender during impact.
3. **Hit-stop (~0.05s)** — brief freeze for an impact punch.
4. **Impact (parallel, ~0.18s)** — defender squashes + knocks back away from the
   attacker; attacker squashes; damage-number particles spawn on each unit that
   took damage; optional small shake on the struck card.
5. **Recoil home (~0.22s)** — attacker springs back to its slot, overshooting and
   settling. `TRANS_ELASTIC / EASE_OUT`.
6. **Death pop** — see below.

### Attack vs. the deck (`target_unit == -1`)

- Wind-up, then the attacker **flies the whole way** to the opponent's deck pile
  (`FlightAnchors.of(DECK, opponent)`), arcing slightly. On arrival the deck pile
  jiggles/squashes, damage particles burst at the pile, and the existing "MILL"
  feedback fires. Then the attacker **springs back** to its slot.

### Death / destruction pop (any `UNIT_DIED` in the cluster)

- Before reconcile, the dying card does a **squash-then-pop**: quick scale-up with
  a white flash, then a snappy scale-down/spin. When `render_all` runs immediately
  after, the existing leaver mechanism flies the shrunken husk to the discard, so
  it reads as "destroyed, swept away."
- If both attacker and defender die (a trade), both pop, staggered slightly.

### Event ordering

The recipe reads the cluster's events in order: `UNIT_ATTACKED` (attacker id +
target) drives the lunge target; the two `UNIT_DAMAGED` events drive the
particles/recoil; `UNIT_DIED` events drive the pops at the end.

## Damage-number particles (`damage_number.gd`)

- A bold `Label` spawned at the hit point on `FxLayer`. Pops in with an over-scale
  (~1.4× → 1.0×), then becomes a small physics object: initial upward + sideways
  velocity, gravity, a little spin, and a fade over ~0.6s before `queue_free`.
- Color/size scale with severity — bigger hits get a larger, punchier number with
  a slightly different tint, so a 5 reads heavier than a 1.
- One particle per `UNIT_DAMAGED` event, at that unit's card (or at the deck pile
  for deck damage). Replaces the current flat floating-number + shake in
  `Flourishes` for combat. Reusable later for spell damage.

## The Balatro speed ramp (on `CombatDirector`)

- A single `anim_speed` multiplier, baseline `1.0`, capped (~`2.5×`).
- On each `play()`, compare now vs. the previous sequence's end. If chaining
  quickly (gap below a threshold), bump `anim_speed` up a step; on a lull, decay
  it back toward `1.0`. Reset to `1.0` on `TURN_STARTED`.
- Every recipe duration is divided by `anim_speed`, so a long AI turn's attacks
  get progressively snappier and then the table relaxes. Sequences stay blocking
  throughout; they just get shorter.

## Error handling / edge cases

- Attacker or defender `CardView` already gone (e.g. killed by a trap before
  combat resolves) → skip that beat gracefully, no crash. Guard every lookup.
- Multiple deaths in one cluster → staggered pops.
- `GAME_OVER` mid-sequence → finish the current sequence, then show the game-over
  panel (`post_action` already runs after the sequence).
- Human input during a sequence → ignored via `_anim_busy`; AI loop `await`s so
  there is no overlap.

## Testing (GdUnit4)

Mirror existing patterns (`test_card_flight.gd`, `test_flight_anchors.gd`). Push
all *decisions* into pure, testable functions; keep the tween glue a thin shell.

- `CombatDirector.has_attack(events)` and the cluster parser (attacker id, target,
  damaged ids, died ids) — pure, fully unit-tested.
- `anim_speed` ramp math (timestamps → multiplier; bump, decay, cap, reset) —
  pure, unit-tested.
- `DamageNumber.spawn(...)` adds a node to a parent and self-frees — assert node
  creation.

## Files touched

New:

- `src/ui/match/combat_director.gd`
- `src/ui/match/card_juice.gd`
- `src/ui/match/damage_number.gd`
- `tests/test_combat_director.gd`
- `tests/test_card_juice.gd`
- `tests/test_damage_number.gd`

Modified:

- `src/ui/match/match.gd` — `apply_action` becomes a coroutine; add `_director`,
  `_anim_busy`, input gating; wire `TURN_STARTED` ramp reset.
- `src/ui/match/match.tscn` — add the `CombatDirector` node.
- `src/ui/match/flourishes.gd` — remove combat damage-number + shake (now owned by
  the director / `DamageNumber`); keep `DECK_DAMAGED` mill feedback.
```
