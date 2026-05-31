# Card Logic — Raccoon, Audio & Writing Decks

**Date:** 2026-05-30
**Status:** Design approved, pending spec review
**Scope:** Implement all card logic for the Raccoon, Audio, and Writing decks as pure-GDScript `CardScript`s, plus the shared engine machinery their mechanics require. The Strike deck (already implemented) is the reference pattern and is not changed except where it shares the new foundational engine code.

---

## 1. Goals & Non-Goals

**Goals**

- One pure-GDScript `CardScript` subclass per unique card (~35 scripts covering ~60 card rows across the three decks).
- All shared mechanics (RUMMAGE, HARMONIZE, TRASH, TAUNT, CLEF, ORANGE, cost reduction, damage/kill interception) implemented once in the engine layer and exposed to cards through `EffectContext` verbs and `CardScript` hooks — never duplicated inside individual card scripts.
- GdUnit4 test coverage: a test per non-trivial card plus dedicated tests for each new mechanic.

**Non-Goals**

- No UI/rendering work. This is pure rules/engine logic.
- No changes to Strike-deck card behavior.
- No AI tuning beyond making the new actions/targets appear in `get_legal_actions`.

---

## 2. Conventions (inherited from Strike)

- Scripts live in `src/cards/scripts/<deck>/<card_name>.gd`, `class_name <CardName> extends CardScript`.
- Every card row is wired in `card_script_registry.gd` via `_register("<deck>", <id>, <Script>.new())`. Duplicate rows (e.g. the two Rats) each get their own `.new()` instance, matching the existing Strike registrations.
- Cards interact with the game **only** through `EffectContext` verbs and by reacting to `Enums.EventType`s. They never reach into `GameEngine` internals directly.
- Triggered abilities declare `reacts_to()` (event types) and `active_zones()` (zones in which the card listens).
- Pure predicates (`condition_met`, `has_request`, new `cost_modifier`) must be side-effect free.

---

## 3. Foundational Engine Work

This is the highest-risk part of the project and is built and tested **first**, before any card that depends on it.

### 3.1 Suspendable damage / kill / deck-damage pipeline

**Problem.** Interception traps (Rest, Garbage Guard, Offering, Safety Net, Ancient One's Protection) must fire *interactively* — the player is asked whether to fire and, where relevant, which unit to choose. Today `_deck_damage` and `_kill` run synchronously inside `_declare_attack` and inside card scripts, so there is no clean point to suspend for a `pending_choice`.

**Approach.** Make damage resolution, deck damage, and kills **queue-driven continuation steps** so the existing suspend/resume mechanism (`_suspended` + `state.pending_choice` + `_pump()`) can pause and resume them cleanly.

- `_declare_attack` stops applying combat consequences inline. After computing combat and emitting `UNIT_DAMAGED`, it enqueues a `_resolve_combat_deaths(attacker, defender, result)` step and returns. Death checks then run as their own queue items.
- `_kill(owner, unit)` consults the owner's `set_traps` for a kill interceptor (`intercept_kill`) **before** moving the unit to discard. If an interceptor is applicable and optional, it raises a `pending_choice` (asked of the trap's owner) and suspends; the resume path either applies the interception (e.g. trash a chosen unit in place, redirect destination) or proceeds with the normal kill.
- `_deck_damage(player, amount)` routes through `_begin_deck_damage`, which first checks the player's `set_traps` for a deck-damage interceptor (`intercept_deck_damage`). If applicable, it suspends and asks the owner; on resume it applies negation, fires the trap, runs the trap's follow-up (e.g. Garbage Guard's rummage), and then mills any remaining damage and emits `DECK_DAMAGED`.
- The in-flight context for a suspended damage/kill (remaining amount, attacker/defender ids, follow-up step) is stored in `state.pending_choice.data` so the resume can continue exactly where it left off.

**Invariant.** Any code path that previously called `_deck_damage`/`_kill` synchronously must tolerate those operations completing later (after a suspend/resume). Card scripts already run as queued `call` items, so a kill triggered inside a script naturally enqueues its consequences rather than recursing.

**Targeted tests:** combat death with no interceptor (unchanged behavior); Rest negating a deck attack; Garbage Guard negating + rummaging; Offering negating + minting an opponent Orange; Safety Net redirecting a battle death to the bottom of discard; Ancient One's Protection trashing another unit in place; a suspend that is correctly resumed when the choosing player answers.

### 3.2 New events, counters, verbs, hooks

**`Enums.EventType` additions:** `CARD_RUMMAGED`, `RUMMAGE_PERFORMED`, `HARMONIZE`, `UNIT_TRASHED`.

**`PlayerState.turn_counters` addition:** `rummages_made` (reset each turn). Resets via `reset_turn_counters()`.

**Dispatch change:** `GameEngine._trigger_candidates` adds `ps.hand` to the scanned zones. Reactions are still gated by `active_zones()`, so only scripts that explicitly list `Enums.Zone.HAND` ever fire from hand (needed for Rat). Existing scripts are unaffected.

**`CardScript` hook additions (all default to no-op / 0 / false):**

- `cost_modifier(card, ctx) -> int` — additive ticket-cost delta (Sixteenth Note returns `-(notes on board)`).
- `intercept_deck_damage(card, player, amount, ctx) -> ...` — interception entry point for deck-damage traps.
- `intercept_kill(card, dying_unit, reason, ctx) -> ...` — interception entry point for kill traps.
- `on_trashed(card, ctx)` semantics are handled through `react()` on `UNIT_TRASHED`; no new hook required.

**`EffectContext` verb additions:**

- `rummage(n)` — RUMMAGE primitive (§4.1).
- `harmonize()` — HARMONIZE primitive (§4.2).
- `trash(unit)` — TRASH primitive (§4.3).
- `untap(unit)` — set `unit.tapped = false`.
- `gain_orange(player)` — mint an Orange token into `player`'s hand, respecting the cap (§3.4).
- `set_taunt(unit)` — `unit.vars["taunt"] = true`.
- `add_fee_modifier(card, delta)` — adjust a card instance's persistent `fee_modifier`.
- Small helpers as needed: `bottom_of_discard(player, card)`, `to_deck_bottom(card)`, `mill_own_to_choose(...)`.

### 3.3 Cost system

- `GameEngine.effective_cost(card, player) -> int` returns `max(0, def.ticket_cost + script.cost_modifier(card, ctx) + card.vars.get("fee_modifier", 0))`.
- `get_legal_actions` uses `effective_cost` for affordability; `_play_card` charges `effective_cost`.
- `fee_modifier` is a persistent per-instance integer (starts 0, decremented by Orange plays; stackable, no lower bound on the modifier itself — the clamp happens in `effective_cost`).
- `cost_modifier` is dynamic and recomputed on demand (board-state dependent for Sixteenth Note).

### 3.4 Orange token card

ORANGE is modeled as a real **card**, not a counter.

- **Definition:** a synthetic `CardDefinition` minted in code (not present in any CSV). Reserved id (e.g. `100`), `deck_color = "writing"`, `type = SPELL`, `name = "Orange"`, `ticket_cost = 0`, no stats. Created by a small factory (`OrangeToken.make_definition()` or equivalent) so every minted instance shares one definition object. Registered in `CardScriptRegistry` under `writing:100 -> OrangeCard.new()`.
- **`gain_orange(player)`** mints an Orange instance into `player`'s hand via `state.make_instance(...)`, **capped at 5 Orange cards held** per player; mints beyond the cap are discarded/not created (excess wasted).
- **On play (`OrangeCard.on_cast`):** if the hand is non-empty, request a `select_cards(hand, 0, 1, ...)` choice; the chosen card (any type) gets `add_fee_modifier(chosen, -1)`. Stackable: multiple Oranges, and multiple applications to the same card, accumulate. Playable even with no other hand cards (no effect then). Cost 0.
- **While in hand:** raises the owner's end-of-turn hand limit. `_end_turn` computes the limit as `5 + (number of Orange cards in hand)` instead of a flat 5.

### 3.5 Interception & trash-choice UX

All interactive interception and the trash-replacement choice are driven through the existing `pending_choice` plumbing (`match.gd:_route_pending_choice`), which already asks the correct player (`pending_choice.player`) and auto-routes to the AI when the asked player is not the human. Because traps belong to the **defending** (non-active) player, a human's interceptor naturally prompts during the opponent's turn, and an AI's interceptor auto-resolves — no new routing concept is needed, only new presentation.

**Interceptor prompt — dedicated trap-reveal overlay.** A new overlay (`src/ui/overlays/trap_reveal_overlay.{gd,tscn}`) flips the hidden trap face-up near the trap-set zone, showing the trap's card art, name, and rules text, with **Fire / Decline** buttons, while the affected object on the table flashes (the deck pile for deck-damage traps; the dying unit for kill traps). Driven by a new `ChoiceSpec` shape:

- `ChoiceSpec.intercept(trap_card, context_text, flash_ref)` → `ui_shape = "intercept"`, carrying the trap `CardInstance`, a human-readable context line (e.g. "Your Deck will take 6 damage"), and a reference to the object to flash. `match.gd` routes `"intercept"` to the overlay; Fire/Decline resolve as a two-option `choose_option`-style result.
- **Always prompt:** every interceptor asks before firing, including the pure-upside ones (Rest, Garbage Guard, Safety Net) — maximum control and consistency (Ruling §6).

**Two-step target for Ancient One's Protection.** Firing raises the overlay (step 1: Fire/Decline). On Fire, the engine resolves the trap and raises a **follow-up** `select_target` choice over the eligible allied Units; the overlay closes and the board highlights candidates for a click, exactly like attack targeting (`_begin_target_selection`). No new targeting UI — it reuses the existing highlight + arrow flow.

**Opponent's interceptors (read-only).** When the AI fires one of these on the human's turn, the same overlay is shown **non-interactively** for a short beat (no buttons, auto-dismiss) so the player sees which trap fired and why, then the AI's decision is applied. Sequencing is automatic: `apply_action` plays the triggering flourish first, then `_post_action` surfaces the prompt, so the cause is always seen before the reveal.

**Trash-replacement menu.** When the human trashes a Unit and one or more "may instead" replacements apply, a labeled menu lists the applicable options plus **"Just KO it"**, presented as a **single horizontal row** of buttons (reusing `OptionPrompt`), titled with the trashed unit's name. This is a `choose_option` choice asked of the trashing player; it is distinct from the trap-reveal overlay (it is the player's own effect, not a hidden trap).

**New/changed UI surface:** `trap_reveal_overlay.{gd,tscn}` (new); `match.gd` routing for `"intercept"` and the read-only AI variant; `OptionPrompt` confirmed to lay options out in a single row for the trash menu. The engine side adds the `intercept` `ChoiceSpec` shape and the follow-up `select_target` raised by Ancient One's Protection.

---

## 4. Mechanics

### 4.1 RUMMAGE (Raccoon)

"RUMMAGE: Draw from the bottom of your Discard Pile." Bottom = front of the `discard` array (index 0), consistent with deck draws using `pop_front`. Safety Net's "bottom of the Discard Pile" pushes to the same front.

`ctx.rummage(n)` performs one **rummage instance**:

1. Compute `total = n + bonus`, where `bonus` is the sum of rummage bonuses from the owner's board (Coyote contributes `+1` each).
2. Increment `turn_counters["rummages_made"]`.
3. Emit `RUMMAGE_PERFORMED {player, count: total}` (the per-instance event).
4. For each of `total` cards, pop the bottom of the discard pile, move it to hand, and emit `CARD_RUMMAGED {player, instance}` (the per-card event). Stop early if the discard pile empties.

Rationale for event split: "When you RUMMAGE (instance, not per card)" (Trash Cannon) and "first time you RUMMAGE each turn" (Skunk) react to `RUMMAGE_PERFORMED`; "When RUMMAGED" (Rat, as the drawn card) reacts to `CARD_RUMMAGED`.

### 4.2 HARMONIZE (Audio)

"HARMONIZE only triggers when another card activates Harmonize" and "only applies to Units currently on the Board."

`ctx.harmonize()` emits a `HARMONIZE {player}` event. Each Note on the board with a harmonize effect reacts (active zone BOARD), applies its buff, and locks via a per-card flag/counter so it cannot re-trigger:

- Threshold support: a Note may require multiple HARMONIZE triggers before its effect fires. Track `card.vars["harmonize_count"]`; when it reaches the Note's threshold, apply the buff once and set `card.vars["harmonized"] = true`. All Notes in this set use threshold 1, but the threshold is a per-script constant so future cards can use higher values.
- Stat buffs adjust `current_damage` / `current_health` and persist for the unit's lifetime (not reset at end of turn — these are permanent growth, distinct from temporary turn buffs).

### 4.3 TRASH (Writing)

"TRASH: KO an allied Unit." `ctx.trash(unit)` KOs one of the **caller's own** units. It emits `UNIT_TRASHED {owner, instance}` and routes the unit through the kill pipeline, but first resolves any applicable **"may instead" replacements interactively**. The candidate replacements for a given trash are:

- **Self-return** — the trashed unit's own "When TRASHED, you may return this to your hand" (Melon Zombie).
- **Shelley** (leader present) — "send it to the bottom of your Deck instead."
- **Melon Zombie Warlock** (present, unit is a Minion) — "replay it for its cost +1 instead."

If more than one replacement applies, the owner is **prompted to choose** which one to apply (or "just KO it") via a `choose_option` menu — the same interactive treatment as the interceptor traps. If exactly one applies, it is still offered as a yes/no choice. At most one replacement resolves. If none is chosen/applies, the unit dies normally (to discard). `UNIT_TRASHED` is distinct from `UNIT_DIED`, so "When TRASHED" reactions (Mercenary Trader gains an Orange) fire on trash specifically.

Because this prompt suspends, `trash()` is part of the suspendable pipeline (§3.1): the trashed unit's resolution and any follow-up effects continue on resume.

### 4.4 TAUNT (Audio — Whole Note)

`unit.vars["taunt"] = true`. Enforcement:

- `get_legal_actions`: when listing attacks against the opponent, if the opponent's board contains any taunt unit, restrict legal unit-targets to taunt units and **disallow deck attacks**.
- `_declare_attack`: validate the same rule defensively.
- Taunt is granted by Whole Note's HARMONIZE buff; it persists for the unit's lifetime.

### 4.5 CLEF (Audio — Treble/Bass Clef)

- Clef minions carry `is_clef = true` (script-level predicate `is_clef() -> bool`).
- **One active:** `get_legal_actions` excludes playing a Clef from hand while the player already has a Clef on the board (a second Clef is simply not playable).
- **Activated ability:** "spend 2 Tickets to return a Clef to your hand" — exposed via `activated_abilities` when the owner has ≥2 available tickets; `activate` taps 2 tickets and bounces the Clef to hand.
- **Treble Clef:** reacts to `TURN_STARTED` (owner); every second owner turn (track `turns_taken` parity or a per-card counter) → `harmonize()` (harmonizes all Notes).
- **Bass Clef:** contributes a global "all units take double damage" modifier consulted by combat/`_damage_unit`; reacts to `UNIT_DAMAGED` where the damaged unit survived → `harmonize()`.

### 4.6 Damage-doubling modifiers (Bass Clef, Staccato)

- Bass Clef: while on board, all units take double damage (global, both sides) — applied in the damage-application path.
- Staccato: "all Notes take double Damage this turn" — a turn-scoped modifier flag on the owner, cleared at end of turn, consulted when damaging a Note.
- Modifiers compose multiplicatively where both apply.

---

## 5. Per-Deck Card Specifications

Behavior is keyed by the source CSV id (`src/data/decks/<deck>.csv`). Paired duplicate ids share one script class.

### 5.1 Raccoon (`raccoon`)

| id(s) | Name | Type | Behavior |
|---|---|---|---|
| 1 | Raccoon | Leader | **In discard:** react `TURN_STARTED` (owner) → `rummage(2)`; react `DECK_RESHUFFLED` → move self from discard/deck to hand. **On board:** activated ability "discard any number of hand cards → deal that many damage to a chosen Unit," once per turn. Played from hand like a unit (2 tickets / discard 5). |
| 2,3 | Rat | Minion | React `CARD_RUMMAGED` where `instance == self`, active zone HAND → summon self for free. |
| 4,5 | Opossum | Minion | `on_cast` → `rummage(3)`. |
| 6,7 | Skunk | Minion | React `RUMMAGE_PERFORMED` (owner), first time each turn (`rummages_made == 1`) → choose an opponent Unit, set its `current_damage` to 0 (cleared at end of turn via `reset_stats`). |
| 8,9 | Coyote | Minion | `on_cast` → `rummage(3)`. While on board, contributes `+1` rummage bonus per instance (read by `rummage()`). |
| 10,11 | Trash Cannon | Minion | React `RUMMAGE_PERFORMED` (owner) → `deal_deck_damage(opponent, 2)`. |
| 12,13 | Trash Day | Spell | Choose 0–3 → mill that many from **own** deck → choose a Unit, deal that much damage. |
| 14,15 | Trash to Treasure | Spell | `rummage(2)`, then choose 2 hand cards → bottom of own deck. |
| 16,17 | Trashalanche | Spell | Damage ALL units (both boards) by the size of the caster's discard pile. |
| 18,19 | Garbage Guard | Trap | `intercept_deck_damage` → negate the next instance, then `rummage(negated_amount)`. Interactive fire prompt. |
| 20,21 | Safety Net | Trap | `intercept_kill` → the next killed allied Unit is placed at the **bottom** of the discard pile instead of the top. Interactive fire prompt. |

### 5.2 Audio (`audio`)

| id(s) | Name | Type | Behavior |
|---|---|---|---|
| 1 | Plop, Grand Conductor | Leader | `on_cast` → `harmonize()` (harmonizes all other Units). Own HARMONIZE effect: deal 6 deck damage to the enemy Deck (once). The "HARMONIZE: Trigger HARMONIZE effects for this turn" line is keyword reminder text, not a separate effect (Rulings §6). Played from hand like a unit (10 tickets / discard 5). |
| 2,3 | Quarter Note | Minion | HARMONIZE → +2 Damage (once). `is_note`. |
| 4,5 | Half Note | Minion | HARMONIZE → +1 Damage, +2 Health (once). `is_note`. |
| 6,7 | Eighth Note | Minion | HARMONIZE → +3 Damage (once). `is_note`. |
| 8,9 | Sixteenth Note | Minion | `cost_modifier = -(notes on board)`. HARMONIZE → deal 4 deck damage to enemy Deck (once). `is_note`. |
| 10,11 | Whole Note | Minion | HARMONIZE → +2 Health and gain TAUNT (once). `is_note`. |
| 12 | Treble Clef | Minion | `is_clef`. React `TURN_STARTED` (owner) every 2nd owner turn → `harmonize()`. Clef activated bounce ability. |
| 13 | Bass Clef | Minion | `is_clef`. Global "all units take double damage" modifier. React `UNIT_DAMAGED` (survivor) → `harmonize()`. Clef activated bounce ability. |
| 14,15 | Harmonize | Spell | `harmonize()`. |
| 16,17 | Staccato | Spell | `harmonize()`, and set owner turn-flag "notes take double damage this turn." |
| 18,19 | Legato | Spell | `harmonize()`, then choose one tapped allied Unit → `untap(it)`. |
| 20,21 | Rest | Trap | `intercept_deck_damage` → negate the next instance. Interactive fire prompt. |

Notes (`is_note`): a Note is any minion in the Audio deck named Quarter/Half/Eighth/Sixteenth/Whole Note — used by "every Note on the board" (Sixteenth cost) and "HARMONIZE all Notes" (Clefs). Implemented as a script predicate `is_note() -> bool`.

### 5.3 Writing (`writing`)

| id(s) | Name | Type | Behavior |
|---|---|---|---|
| 1 | Shelley, Live-Action Roleplayer | Leader | Trash-replacement: when the owner TRASHes a Unit, may send it to the bottom of the Deck instead. Played from hand like a unit (4 tickets / discard 4). |
| 2,3 | Melon Zombie Hulk | Minion | React `UNIT_ATTACKED` (self) → `trash` a chosen allied Unit. |
| 4,5 | Citrus Werewolf | Minion | React `UNIT_ATTACKED` (self, deck target) → `gain_orange(owner)`. |
| 6 | Avatar of the Ancient Evil | Minion | `on_cast` → may trash any number of **other** allied Units (choice); opponent then trashes that many of theirs (see Rulings §6 for opponent selection). |
| 7,8 | Cultist of the Ancient Evil | Minion | React `UNIT_ATTACKED` (self, deck target) → may `trash` self to return a chosen card from discard to hand. |
| 9,10 | Melon Zombie Warlock | Minion | Trash-replacement: when the owner TRASHes a **Minion**, may instead replay it for its cost +1. |
| 11,12 | Melon Zombie | Minion | Trash-replacement: when this unit is TRASHED, may return it to hand. |
| 13,14 | Mercenary Trader | Minion | React `UNIT_TRASHED` (self) → `gain_orange(owner)`. |
| 15,16 | Citrus Sacrifice | Spell | `gain_orange(owner)` once per card in the caster's discard pile (capped at 5 held). |
| 17 | Pain Split | Spell | `trash` a chosen allied Unit, then deal 4 damage to any chosen Unit. (CSV lists id 17 twice; no id 18 — both rows map to id 17, one script.) |
| 19,20 | Ancient One's Protection | Trap | `intercept_kill` (battle deaths) → may trash another allied Unit in the dying unit's place. Interactive fire + target prompt. |
| 21 | Offering | Trap | `intercept_deck_damage` → may `gain_orange(opponent)` and negate that damage. Interactive fire prompt. |
| (synthetic) 100 | Orange | Spell | 0-cost token (§3.4): on play reduce a chosen hand card's fee by 1 (stackable); while in hand, +1 to owner's hand limit. |

---

## 6. Interpretations & Rulings

All confirmed with the project owner during design.

1. **"Damage the opponent" = deck damage.** With no hero/face health, Citrus Werewolf and both Cultists trigger when their unit deals damage to the opponent's **Deck** (i.e. a deck attack). "Damage the opponent" and "damage the opponent's Deck" are treated identically.
2. **Interceptor traps are fully interactive.** Rest, Garbage Guard, Offering, Safety Net, and Ancient One's Protection suspend and prompt the choosing player (fire? which unit?). This is why the damage/kill pipeline is refactored to be suspendable (§3.1).
3. **Trash replacement choice:** when multiple "may instead" replacements apply to one trash (unit self-return / Shelley / Warlock), the owner is **prompted to choose** which to apply, or to just KO the unit — the same interactive treatment as the interceptor traps. A single applicable replacement is offered as a yes/no choice. At most one replacement resolves per trash.
4. **Clef "one active":** a second Clef cannot be played while one is on the board (excluded from legal actions). No auto-bounce on play.
5. **ORANGE is a token card,** not a counter (§3.4). "Gain 1 ORANGE" mints an Orange spell card into hand. Cap of 5 held per player; excess mints are wasted. Orange's fee reduction targets **any** hand card and is playable even with no other targets.
6. **Plop's second HARMONIZE line** ("HARMONIZE: Trigger HARMONIZE effects for this turn") is **keyword reminder text** explaining what HARMONIZE does — the same way other leaders restate their keyword — not a second effect. Plop has exactly one HARMONIZE effect (deal 6 deck damage) plus its on-cast "HARMONIZE all other Units." No self-retrigger.
7. **Avatar's opponent trash selection:** the opponent trashes `that many` of their own Units; the opponent is the choosing player for which of their Units are trashed (interactive choice asked of the opponent). If the opponent has fewer Units than the count, they trash as many as they have.
8. **Raccoon leader's two modes:** the "discard hand cards → deal damage" ability is an **activated** ability available while the Raccoon is on the **board**; the rummage-2 and return-on-reshuffle effects are **passives that work while it is in the discard pile**.
9. **Bottom of the discard pile** = index 0 (front) of the `discard` array, consistent across RUMMAGE draws and Safety Net's redirect.
10. **HARMONIZE stat buffs are permanent** for the unit's lifetime (not cleared at end of turn), distinct from temporary turn buffs.
11. **Interceptor presentation:** a dedicated trap-reveal overlay (not the plain modal), with the affected deck/unit flashing; **every** interceptor always prompts (no auto-fire, even for pure-upside traps); Ancient One's Protection's target is chosen via a two-step board highlight + click; an AI interceptor is shown read-only on the human's turn (§3.5).
12. **Trash-replacement menu** is presented as a single horizontal row of option buttons (applicable replacements + "Just KO it"), titled with the trashed unit's name, reusing `OptionPrompt` (§3.5).

---

## 7. Testing Plan

GdUnit4, run headless per the project's test-runner notes. Tests live in `tests/cards/<deck>/test_<card>.gd` and `tests/<mechanic>` for engine mechanics, extending the existing `CardTestBase` where useful.

**Mechanic tests (foundation, written first):**

- Suspendable interception: combat death (no interceptor) unchanged; Rest/Garbage Guard/Offering deck-damage interception incl. suspend→resume; Safety Net & Ancient One's Protection kill interception; the choosing player is correct.
- RUMMAGE: bottom-of-discard ordering; per-card vs per-instance events; Coyote bonus; Skunk first-time-per-turn; empty-discard early stop.
- HARMONIZE: once-per-unit lock; threshold; Clef-driven harmonize; permanence of buffs.
- TRASH: replacement priority chain; `UNIT_TRASHED` vs `UNIT_DIED`; self-return / Shelley / Warlock paths.
- Cost system: `effective_cost` with `cost_modifier` (Sixteenth Note) and stacked `fee_modifier` (Orange); affordability in `get_legal_actions`.
- Orange token: minting, 5-cap, hand-limit bump, fee reduction stacking.
- TAUNT: legal-action restriction and deck-attack block.
- CLEF: one-active play restriction; bounce ability.

**UI tests (GdUnit4, headless):**

- `trap_reveal_overlay`: renders trap name/text from a CardInstance; emits Fire/Decline; read-only mode hides buttons and auto-dismisses.
- `match.gd` routing: an `intercept` pending_choice opens the overlay for the human and routes to AI (read-only) otherwise; Ancient One's Protection's Fire raises the follow-up `select_target`; the trash menu opens `OptionPrompt` with a single row of options.

**Per-card tests:** one suite per non-trivial card (trivial vanilla stat-line cards may be covered by a smoke/load test). Follow the existing Strike test style (`fresh_engine`, `place_on_board`, `put_in_hand`, assert on resulting zones/stats/pending choices).

**Load/smoke:** extend the card-database/registry tests to assert every id in all three decks resolves to its intended script (not the default), and that the Orange token registers.

---

## 8. File Layout & Build Order

```
src/cards/scripts/raccoon/   # 11 scripts
src/cards/scripts/audio/     # 12 scripts
src/cards/scripts/writing/   # 12 scripts + orange_card.gd (+ token factory)
src/cards/card_script.gd     # new hooks
src/cards/effect_context.gd  # new verbs
src/cards/card_script_registry.gd  # register all new ids + writing:100
src/engine/game_engine.gd    # suspendable pipeline, effective_cost, taunt/clef/orange enforcement
src/engine/player_state.gd   # rummages_made counter, end-turn hand limit
src/data/enums.gd            # new EventTypes
src/cards/choice_spec.gd     # new "intercept" shape
src/ui/overlays/trap_reveal_overlay.{gd,tscn}  # new interceptor overlay
src/ui/match/match.gd        # route "intercept" + read-only AI variant + trash menu
tests/cards/{raccoon,audio,writing}/  # per-card suites
tests/  # mechanic + UI suites
```

**Build order (workstreams):**

1. **Foundation** — new EventTypes, counters, dispatch (hand candidates), CardScript hooks, suspendable damage/kill/deck-damage pipeline, cost system, Orange token. Full mechanic tests green.
2. **Raccoon** — RUMMAGE verb + 11 cards + tests.
3. **Audio** — HARMONIZE/CLEF/TAUNT + 12 cards + tests.
4. **Writing** — TRASH/ORANGE + 12 cards + Orange + tests.

Each workstream ends with the full suite green before the next begins.

---

## 9. Risks

- **Suspendable pipeline (§3.1)** is the largest refactor and touches the core combat loop. Mitigation: build and test it first in isolation, with a regression test asserting unchanged behavior when no interceptor is present.
- **Re-entrancy / infinite loops** in HARMONIZE (e.g. Bass Clef "harmonize on survive" reacting to harmonize-induced damage) and RUMMAGE bonuses. Mitigation: per-turn / per-card locks and explicit recursion guards, covered by tests.
- **Trash replacement chain** interacting with the kill pipeline and with traps. Mitigation: resolve replacements before the unit enters the kill pipeline; test each priority path.
- **Orange token** is a card with no CSV row; ensure database/registry/serialization paths tolerate a synthetic definition. Mitigation: registry/load test for `writing:100`.
