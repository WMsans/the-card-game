# VGDC: The Card Game — Card Abilities Foundation + Strike Deck Design

**Date:** 2026-05-30
**Status:** Approved (design); pending implementation plan
**Engine target:** Godot 4.6 (GL Compatibility)
**Test framework:** GdUnit4

## Context

The rules/combat engine (see `2026-05-29-rules-combat-engine-design.md`) plays a
full two-player game of **vanilla** cards: it has a turn/ticket/draw/reshuffle
loop, combat, an `EventBus`, a `PendingChoice` mechanism, and an `Action`/
`GameEngine` command model. But **no card ability logic runs at all** — `_play_card`
moves a card to a zone and fires `CARD_PLAYED`; keywords are extracted from the
CSV text as strings but unused; traps are explicitly stubbed
(`_trap_condition_met` always returns `false`).

The card data lives in `docs/design_docs/Card List/` (and is imported under
`src/data/decks/`): four decks — **Strike** (REQUEST), **Raccoon** (RUMMAGE),
**Audio** (HARMONIZE/CLEF), **Writing** (TRASH/ORANGE) — each ~21 rows but with
duplicate copies, so roughly **13–14 unique effects per deck (~52 total)**. Each
deck is built around one keyword engine the codebase does not yet have.

Implementing "all card logic" therefore means two things: (1) a **card-script
architecture** so each card is its own pure GDScript, and (2) the **engine-level
primitives** those scripts need. That is far too much for one spec/plan, and the
architecture is unproven until cards actually exercise it.

### Decisions already made (from brainstorming)

- **Scope of this spec:** *Foundation + one deck slice.* Build the full
  card-script architecture and the shared engine primitives, then prove it by
  fully implementing **one** deck end-to-end. The other three decks are
  follow-on specs that reuse the framework.
- **First deck:** **Strike (REQUEST)** — its conditions map closely onto the
  `turn_counters` the engine already tracks, so it is the lowest-friction deck
  that still exercises the full spread of hook types (on-cast effects, triggered
  abilities, static conditions, combat modifiers, activated abilities, traps).
- **Choice/targeting scope:** *Full engine + human UI targeting.* Build one
  generic choice-request system; wire the match UI so a human can pick
  targets/cards for every Strike effect.
- **Architecture:** Per-card GDScript subclass + engine facade + reactive
  dispatch (Approach A). Rejected: a data-driven effect DSL (increases coupling
  to a central interpreter, not "pure GDScript per card") and a component/mixin
  system (more machinery than the RefCounted data model warrants).
- **REQUEST-gating ruling:** A card's listed ability fires **unconditionally**.
  REQUEST's *only* automatic effect is the +2/+2-on-attack combat buff, plus a
  queryable boolean. The only cards that gate on REQUEST are the ones whose text
  literally says so (Request Board, Bjorn Hammer, Wrong Mascot, Strike Social).
- **Tests:** GdUnit4, run headless.

## Goals

- A `CardScript` architecture where **each card is one pure GDScript file**,
  self-contained, touching the engine only through a stable facade, so adding a
  card is "new file + one registry line" with **zero edits to the engine or
  sibling cards.**
- The shared engine primitives Strike needs: an in-engine effect/event queue,
  reactive trigger dispatch, a generic suspend/resume choice system, REQUEST
  evaluation + combat integration, and real trap firing.
- One reusable card-selection UI page (generalized from the discard panel) plus
  targeting-arrow and option-prompt paths, so card choices need no per-card UI.
- All 14 unique Strike cards implemented and unit-tested against shipping card
  data, with the existing engine + UI suites staying green.

## Non-goals (explicitly deferred to later specs)

- The Raccoon / Audio / Writing decks and their keyword engines (RUMMAGE,
  HARMONIZE/CLEF, TRASH/ORANGE/BOMB, Scrapped/Harmonize chaining).
- A full general-purpose replacement-effect system (only a minimal
  `immortal_this_turn` death-prevention hook is built now, as its seed).
- Trap "may reveal" opt-in (traps **auto-fire** when their condition is met for
  now).
- AI strategy beyond resolving choices legally (the existing greedy AI is kept).

## Architecture

### Layer 1 — Card scripts, registry, facade

**`CardScript`** (`src/cards/card_script.gd`, extends `RefCounted`) — one
**stateless** instance per *definition*, shared across copies. All hooks are
virtual no-ops so a card overrides only what it uses:

```gdscript
class_name CardScript
extends RefCounted

# Battlecry / on-play. Called after the card reaches its zone.
func on_cast(card: CardInstance, ctx: EffectContext) -> void: pass

# Triggered abilities. Engine calls this on each active card after every event.
func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void: pass

# Resume point after a requested choice is answered.
func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void: pass

# Keyword predicate (Strike REQUEST). Pure, side-effect free.
func condition_met(card: CardInstance, ctx: EffectContext) -> bool: return false
func has_request() -> bool: return false

# Transient stat/combat modifiers applied during a fight.
func combat_mods(card: CardInstance, ctx: EffectContext) -> Dictionary: return {}

# Activated abilities this card contributes to legal actions.
func activated_abilities(card: CardInstance, ctx: EffectContext) -> Array: return []
func activate(card: CardInstance, ability_id: String, ctx: EffectContext) -> void: pass

# Dispatch hints so the engine only visits relevant cards.
func reacts_to() -> Array: return []                       # event types
func active_zones() -> Array: return [Enums.Zone.BOARD, Enums.Zone.TRAP_SET]
```

**Per-instance mutable state** lives on `CardInstance` as a new
`vars: Dictionary` (once-per-turn flags, "used this turn", stolen-card tags).
Scripts hold no fields of their own, so a single shared script instance is safe
across multiple copies.

**`CardScriptRegistry`** (`src/cards/card_script_registry.gd`) maps
`(deck_color, card_id) -> CardScript`, one explicit `_register` line per card.
A `default` no-op script covers vanilla and not-yet-implemented cards, so the
engine never crashes on an unscripted card. `GameState.make_instance` resolves
and caches `CardInstance.script` at creation. Duplicate rows (e.g. two Gray
Aliens, both id 9) resolve to the same shared script.

**`EffectContext`** (`src/cards/effect_context.gd`) is the **only** surface
scripts touch — the decoupling boundary. It wraps the engine plus the acting
player and exposes verbs, never raw state mutation. Every verb routes through an
engine method; new verbs are added as small engine primitives:

```
draw(n)            mill(player, n)        discard_from_hand(card)
deal_deck_damage(player, n)               deal_damage(unit, n)   kill(unit)
search_deck(pred) -> card                 draw_specific(card)
summon_free(card)  put_on_deck_top(unit)  steal_top_discard(opp)
end_turn()         fire_trap(card)        set_unit_flag(unit, flag)
request_choice(spec, resume_tag)          request_met(card) -> bool
me() / opponent() / board(p) / hand(p) / discard(p) / counters(p)
emit(event)        # enqueues; never recurses
```

**File layout:**
```
src/cards/
  card_script.gd
  card_script_registry.gd
  effect_context.gd
  choice_spec.gd
  scripts/
    default_card.gd
    strike/
      battle_bjorn.gd  strike_request_form.gd  priority_raise.gd
      bounty_striker.gd  red_alien.gd  headphones_ghost.gd  gray_alien.gd
      cactus_guy.gd  request_slacker.gd  overstriker.gd  request_board.gd
      bjorn_hammer.gd  wrong_mascot.gd  strike_social.gd
```

### Layer 2 — Effect/event queue and trigger dispatch

Triggered abilities cause more events (a discard is itself a `CARD_DISCARDED`
other cards react to), so resolution must be serial and ordered, not recursive.
`GameEngine` gains an internal queue:

```gdscript
var _event_queue: Array[GameEvent] = []
var _resolving: bool = false
var _suspended: bool = false

func emit(event: GameEvent) -> void:
    _event_queue.append(event)
    if _resolving: return            # re-entrant: enqueue and unwind
    _resolving = true
    _drain()

func _drain() -> void:
    while not _event_queue.is_empty():
        if _suspended: return        # frozen mid-resolution awaiting a choice
        var e: GameEvent = _event_queue.pop_front()
        bus.publish(e)               # log + notify UI listeners (unchanged)
        _dispatch_triggers(e)
    _resolving = false
```

`_dispatch_triggers(event)` visits every card whose `active_zones()` and
`reacts_to()` make it eligible for this event type, in a **stable order**
(active player's cards first, then opponent's, each in board/play order), and
calls `card.script.react(card, event, ctx)`. The engine maintains an index from
event type → eligible scripts so dispatch does not walk every card. A reacting
script calls `ctx` verbs, which `emit` further events that drain **after** the
current event finishes — deterministic breadth-first ordering, no deep
recursion. The ordering rule is documented and tested.

**Migration:** every `state.bus.publish(...)` in `GameEngine` (`_draw`, `_mill`,
`_kill`, `_deck_damage`, `_play_card`, attack flow, turn flow) becomes
`emit(...)`. With no scripts reacting, behavior is identical and the existing
suite stays green. This is the riskiest edit and is isolated as build step 1
with the current engine tests as the regression guard.

New events added to `Enums.EventType`: `REQUEST_MET`, `TRAP_FIRED`.

### Layer 3 — Generic suspend/resume choice system

Some effects pause mid-resolution to ask a player — including **during a
triggered reaction** (Red Alien, Headphones Ghost) while the queue is draining.
Resolution must suspend and resume, and stay synchronous (deterministic seeded
engine; no coroutines). This generalizes the existing `PendingChoice` pattern.

**Suspend.** A script calls `ctx.request_choice(spec, resume_tag)`. The context
sets `state.pending_choice` carrying the `ChoiceSpec`, the asked player, and a
**resume descriptor** (requesting card's `instance_id` + `resume_tag`), sets
`engine._suspended = true`, and unwinds. `_drain()` checks `_suspended` after
each dispatch and returns **without discarding `_event_queue`** — the
half-finished resolution is frozen in place.

**Resume.** On `RESOLVE_CHOICE`, the engine finds the card by the resume
descriptor and calls `script.resume(card, resume_tag, result, ctx)`. The script
finishes (and may request another choice → a new tag, naturally nested). Then
the engine clears `_suspended` and re-enters `_drain()` where it left off.

```gdscript
# Gray Alien
func on_cast(card, ctx):
    ctx.request_choice(ChoiceSpec.select_cards(Enums.Zone.HAND, 0, 99), "discard")
func resume(card, tag, result, ctx):
    if tag == "discard":
        for c in result.cards: ctx.discard_from_hand(c)
        ctx.draw(result.cards.size() + 1)
```

Opponent-asked choices (Red Alien) set `pending_choice.player = opponent`; the
existing routing already sends non-human choices to the AI.

**`ChoiceSpec`** (`src/cards/choice_spec.gd`) is data, built by `EffectContext`
helpers (scripts never hand-assemble UI dicts). Three shapes cover every Strike
effect, each mapping to one existing/refactored overlay:

- `select_cards(zone, min, max)` → the refactored card-selection page (below).
- `select_target(candidate_ids, min, max)` → `targeting_arrow` + board click.
- `choose_option(labels)` → small button prompt (Red Alien: "Discard 1 from
  hand" vs "Mill 2"), styled like `leader_cost_prompt`.

`match.gd._route_pending_choice()` switches on a generic `pc.data.ui_shape`
instead of hardcoded `kind`s; `AiController.choice_action` gets one generic
resolver for the three shapes (first N legal / first option).

### Layer 3b — Reusable card-selection page (discard-panel refactor)

The current `src/ui/overlays/discard_panel.gd` is hardcoded to *exactly*
`count` cards, a baked-in "Select cards to discard" label, and emits raw hand
indices. It is generalized into a reusable **`card_select_panel`**:

- Selection rule changes from "exactly N" to **`min`/`max`** (`can_confirm()` →
  `min <= _selected.size() <= max`). Discard-to-limit is the `min == max == count`
  case.
- `show_selection(cards, min, max, title)` replaces `show_hand(hand, count)`;
  the title is set by the caller.
- **Return contract stays `confirmed(indices: Array)`** (indices into the list
  it was handed), so the discard-to-limit wiring keeps working with a one-line
  call-site change.
- Source-agnostic: renders whatever `Array[CardInstance]` it is given (hand,
  discard, deck subset), serving Gray Alien (hand), Priority Raise (discard),
  etc.

The scene/class is renamed; `match.gd`'s `_discard` reference and the
`test_overlays` / `test_pending_choice_routing` tests are updated in the same
step (mechanical — the `confirmed(indices)` signal is preserved).

### Layer 4 — REQUEST primitive

Per the leader's rules text, REQUEST's only universal effect is **+2 Damage /
+2 Health during a fight the unit initiates**; beyond that it is a queryable
boolean.

- Cards with a REQUEST override `condition_met(card, ctx)` and return `true`
  from `has_request()`.
- `ctx.request_met(card)` =
  `state.players[owner].all_requests_met_this_turn OR card.script.condition_met(card, ctx)`.
- **Combat integration:** in `_declare_attack`, before `Combat.compute`, gather
  the attacker's `combat_mods`; REQUEST contributes `{damage: +2, health: +2}`
  when `request_met`. The mods are applied to the attacker's current stats as a
  normal buff at the moment it attacks; combat (including the death check)
  resolves on the buffed stats, and the buff clears at the existing end-of-turn
  `reset_stats()`. Because the attacker taps when it attacks and all boards reset
  at end of turn, this is observationally equivalent to "during the fight": the
  +2 HP can save the attacker in this combat, and is gone before the opponent's
  turn. (Pinned down by the combat-mod test: a 3-HP REQUEST attacker survives a
  4-damage trade, then is back to base next turn.)
- When a unit with a REQUEST attacks while met, emit `REQUEST_MET`
  `{player, instance}` — the concrete trigger Bounty Striker keys off.
  **Assumption:** `REQUEST_MET` fires at that attack moment, not retroactively
  when Battle Bjorn flips the global flag.

**Ruling (confirmed):** a card's ability is not gated on its own REQUEST unless
the text says "if the REQUEST is met." Only Request Board, Bjorn Hammer, Wrong
Mascot, and Strike Social read REQUEST state.

### Layer 5 — Trap firing + minimal replacement hook

The stubbed `_check_traps` / `_trap_condition_met` are removed. Trap scripts
live in `active_zones = [Enums.Zone.TRAP_SET]`, react to events, and call
`ctx.fire_trap(self)` which moves TRAP_SET → resolves → DISCARD and emits
`TRAP_FIRED`. Traps **auto-fire** when their condition is met (the "may reveal"
opt-in is a documented later enhancement).

**Minimal replacement hook:** a per-unit `immortal_this_turn` flag (in
`CardInstance.vars`) is checked in `_kill` so Strike Social can prevent deaths
this turn. This is the seed of the fuller replacement-effect system the Writing
deck will require.

**Turn-scoped flags** — `all_requests_met_this_turn`, per-unit
`immortal_this_turn`, and per-card once-per-turn `vars` — are cleared in
`_start_turn` (alongside the existing `reset_turn_counters`).

## The 14 unique Strike cards

| # | Card | Type | Primary hook | Logic |
|---|------|------|--------------|-------|
| 1 | Battle Bjorn | Leader | `on_cast` | Set owner's `all_requests_met_this_turn = true` |
| 2 | Strike Request Form | Minion | `on_cast` | `search_deck(has_request)` → draw first match |
| 3 | Priority Raise | Minion | `activated_abilities` | Tap → choose a REQUEST card in discard → move it to deck |
| 4 | Bounty Striker | Minion | `react` REQUEST_MET, zone=DISCARD | If in discard & owner met a REQUEST → return self to hand |
| 5 | Red Alien | Minion | `react` UNIT_ATTACKED (self), once/turn | Opponent `choose_option`: discard 1 from hand **or** mill 2 |
| 6 | Headphones Ghost | Minion | `react` UNIT_ATTACKED | On the attacker's 2nd attack this turn → controller `select_target` a unit ≤8 HP → kill it |
| 7 | Gray Alien | Minion | `on_cast` | `select_cards(HAND, 0, n)` → discard chosen → draw count+1 |
| 8 | Cactus Guy | Minion | `react` UNIT_ATTACKED (self, deck target) | Steal top of opp discard → your hand (tagged `stolen_from`; returns to opp discard top if later discarded) |
| 9 | Request Slacker | Minion | `on_cast` | `select_target` an enemy minion → put it on top of their deck |
| 10 | Overstriker | Minion | `react` CARD_PLAYED (opp, cost ≥ 7), once/turn | Opponent mills 1 |
| 11 | Request Board | Spell | `on_cast` | For each minion in hand with `request_met` → `summon_free` |
| 12 | Bjorn Hammer | Spell | `on_cast` | Kill every unit not meeting a REQUEST, then `end_turn()` |
| 13 | Wrong Mascot | Trap | `react` UNIT_ATTACKED (opp → my REQUEST minion) | If that minion's REQUEST met → `fire_trap`, kill the attacker |
| 14 | Strike Social | Trap | `react` UNIT_ATTACKED (by opp) | `fire_trap` → my met-REQUEST minions gain `immortal_this_turn` |

Notes / documented rulings:
- **Bjorn Hammer** kills *all* units (both boards, leaders included) that do not
  meet a REQUEST — a unit with no REQUEST never "meets" one and is killed.
- **Cactus Guy**'s stolen card returns to the opponent's discard top if it is
  later discarded; tracked via a `stolen_from` var and a small reaction.
- **Headphones Ghost** lets the controller target any unit (either board) with
  ≤8 HP; the trigger fires on the attacker's exact 2nd attack of the turn
  (`attacks_made == 2`).
- **Red Alien / Overstriker** once-per-turn gating uses a per-card `vars` flag
  reset at turn start.

## Testing strategy

GdUnit4, headless. The engine's determinism (seeded RNG, synchronous
resolution) makes pure-engine unit tests the primary tool; no UI needed for card
logic.

- **Per-card tests** (`tests/cards/strike/test_<card>.gd`): build a minimal
  `GameState`, place the card + fixtures in the right zones, drive the engine via
  `Action`s, assert zones/stats/counters. A new `CardFactory` builds real
  `CardDefinition`s from the registry by `(deck, id)` so tests use shipping card
  data, not fakes.
- **Primitive tests:** event queue (ordering, re-entrant enqueue, suspend/
  resume), each new `EffectContext` verb, REQUEST combat math (the +2/+2
  transient-health semantics), trap firing, `immortal_this_turn`.
- **Choice tests:** suspend → `RESOLVE_CHOICE` → resume for Gray Alien, Priority
  Raise, Request Slacker, Red Alien (opponent choice via AI auto-resolve),
  Headphones Ghost.
- **Regression guard:** the full existing engine + UI suites stay green after
  the `publish → emit` migration and the `card_select_panel` rename.
- **UI tests:** extend `test_overlays` / `test_pending_choice_routing` for the
  renamed selection page and the three ChoiceSpec shapes.

## Build order

Each step lands green before the next.

1. **Engine queue migration** — `emit()` + `_drain()` + `publish → emit`;
   existing suite stays green. *(Riskiest; isolated first.)*
2. **CardScript base + registry + EffectContext skeleton** — wired into
   `make_instance`; default no-op script; vanilla cards behave exactly as today.
3. **Trigger dispatch** — `react`/`reacts_to`/`active_zones` indexing after each
   event; a throwaway test script proves dispatch + ordering.
4. **Generic choice system** — suspend/resume, `ChoiceSpec`, `PendingChoice`
   generalization, AI generic resolver.
5. **`card_select_panel` refactor** — generalize the discard panel, migrate
   `match.gd` + tests; route the three ChoiceSpec shapes; targeting-arrow +
   option-prompt paths.
6. **REQUEST primitive** — `condition_met`/`has_request`/`request_met`,
   combat-mod integration, `REQUEST_MET` event, turn-flag reset.
7. **Trap firing + minimal replacement hook** — replace the trap stub;
   `immortal_this_turn`.
8. **The 14 Strike scripts** — added in dependency order (no-choice on-cast
   first, then triggered, then choice-driven, then traps), each with its
   per-card test.

## Risks

- **The `publish → emit` migration** is the highest-risk change; mitigated by
  isolating it as step 1 behind the existing regression suite.
- **Transient combat-health semantics** (REQUEST +2 HP "during the fight") are
  fiddly; pinned down by an explicit combat-mod test.
- **Suspend/resume across a draining queue** must preserve `_event_queue`
  exactly; covered by a re-entrant-enqueue-then-suspend test.
