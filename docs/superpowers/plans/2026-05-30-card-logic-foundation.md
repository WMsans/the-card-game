# Card Logic Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the shared engine + UI machinery (events, counters, cost system, Orange token, RUMMAGE/HARMONIZE/TRASH/TAUNT/CLEF primitives, and a suspendable damage/kill/deck-damage interception pipeline with its reveal overlay) that the Raccoon, Audio, and Writing card scripts depend on.

**Architecture:** Cards remain pure-GDScript `CardScript` subclasses that touch the game only through `EffectContext` verbs and `CardScript` hooks. All new mechanics live in the engine layer. Kills and deck-damage are refactored into queue-driven `_begin_*`/`_apply_*` pairs so an interceptor trap can raise a `pending_choice`, suspend mid-resolution, and resume — even inside card-script loops.

**Tech Stack:** Godot 4 / GDScript; GdUnit4 for tests (`addons/gdUnit4/`, suites `extends GdUnitTestSuite`).

**How to run a test suite (headless):**
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/<suite>.gd
```
Exit code 0 = pass. Ignore harmless headless noise: `ERROR: Required object "rp_font" is null` and the "InputEvents not transported in headless" notice.

---

## File Structure

- `src/data/enums.gd` — add new `EventType`s.
- `src/engine/player_state.gd` — `rummages_made` counter.
- `src/cards/card_script.gd` — new default hooks.
- `src/cards/effect_context.gd` — new verbs.
- `src/cards/choice_spec.gd` — `intercept` shape.
- `src/cards/scripts/orange_card.gd` + `src/cards/orange_token.gd` — Orange token (lives in `writing` color).
- `src/cards/card_script_registry.gd` — register `writing:100` Orange.
- `src/engine/game_engine.gd` — cost system, rummage/harmonize/trash primitives, taunt/clef enforcement, suspendable kill/deck-damage pipeline, intercept/trash-choice resolution.
- `src/ui/overlays/trap_reveal_overlay.gd` + `.tscn` — interceptor reveal overlay.
- `src/ui/match/match.gd` — route `intercept`/`trash_choice`; read-only AI reveal.
- `src/ui/match/ai_controller.gd` — handle new choice shapes.
- Tests: `tests/test_foundation_*.gd`, `tests/test_trap_reveal_overlay.gd`.

**API surface locked by this plan** (deck plans depend on these exact names):

`EffectContext` verbs: `rummage(n)`, `harmonize()`, `trash(unit)`, `untap(unit)`, `set_taunt(unit)`, `gain_orange(player)`, `add_fee_modifier(card, delta)`, `to_deck_bottom(card)` (plus existing verbs).

`CardScript` hooks (defaults no-op): `cost_modifier(card, ctx) -> int`, `is_clef() -> bool`, `is_note() -> bool`, `rummage_bonus(card, ctx) -> int`, `can_intercept_deck_damage(card, player, amount, ctx) -> bool`, `deck_damage_on_fire(card, player, amount, ctx) -> int`, `can_intercept_kill(card, dying, reason, ctx) -> bool`, `kill_on_fire(card, dying, ctx) -> bool`, `trash_replacement_for(card, target, ctx) -> String`, `apply_trash_replacement(card, target, ctx) -> void`.

Engine: `effective_cost(card, player) -> int`; pending-choice kinds `"intercept"` and `"trash_choice"`; kill `reason` is `"battle"` or `"effect"`.

---

## Task 1: New EventTypes + rummages_made counter

**Files:**
- Modify: `src/data/enums.gd`
- Modify: `src/engine/player_state.gd:30-36` (`reset_turn_counters`)
- Test: `tests/test_foundation_basics.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_foundation_basics.gd
extends GdUnitTestSuite

func test_new_event_types_exist_and_are_distinct() -> void:
	var types := [
		Enums.EventType.CARD_RUMMAGED, Enums.EventType.RUMMAGE_PERFORMED,
		Enums.EventType.HARMONIZE, Enums.EventType.UNIT_TRASHED,
	]
	# all distinct
	assert_int(types.size()).is_equal(4)
	for i in range(types.size()):
		for j in range(i + 1, types.size()):
			assert_bool(types[i] == types[j]).is_false()

func test_rummages_made_counter_starts_zero() -> void:
	var ps := PlayerState.new()
	assert_int(ps.turn_counters["rummages_made"]).is_equal(0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_foundation_basics.gd`
Expected: FAIL (CARD_RUMMAGED not a valid member / key "rummages_made" missing).

- [ ] **Step 3: Add the enum members**

In `src/data/enums.gd`, extend the `EventType` enum's trailing members:

```gdscript
enum EventType {
	CARD_PLAYED, CARD_DRAWN, CARD_DISCARDED,
	UNIT_ATTACKED, UNIT_DAMAGED, UNIT_DIED,
	DECK_DAMAGED, DECK_RESHUFFLED,
	TURN_STARTED, TURN_ENDED, GAME_OVER,
	REQUEST_MET, TRAP_FIRED,
	CARD_RUMMAGED, RUMMAGE_PERFORMED, HARMONIZE, UNIT_TRASHED,
}
```

- [ ] **Step 4: Add the counter**

In `src/engine/player_state.gd`, inside `reset_turn_counters()`, add `"rummages_made": 0,` to the `turn_counters` dictionary:

```gdscript
	turn_counters = {
		"cards_played": 0,
		"cards_discarded": 0,
		"attacks_made": 0,
		"units_died": 0,
		"rummages_made": 0,
	}
```

- [ ] **Step 5: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/data/enums.gd src/engine/player_state.gd tests/test_foundation_basics.gd
git commit -m "feat(engine): add rummage/harmonize/trash events + rummages_made counter"
```

---

## Task 2: CardScript default hooks

**Files:**
- Modify: `src/cards/card_script.gd`
- Test: `tests/test_foundation_basics.gd` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/test_foundation_basics.gd`:

```gdscript
func test_default_hooks_return_neutral_values() -> void:
	var s := CardScript.new()
	assert_int(s.cost_modifier(null, null)).is_equal(0)
	assert_int(s.rummage_bonus(null, null)).is_equal(0)
	assert_bool(s.is_clef()).is_false()
	assert_bool(s.is_note()).is_false()
	assert_bool(s.can_intercept_deck_damage(null, 0, 0, null)).is_false()
	assert_int(s.deck_damage_on_fire(null, 0, 5, null)).is_equal(5)
	assert_bool(s.can_intercept_kill(null, null, "battle", null)).is_false()
	assert_bool(s.kill_on_fire(null, null, null)).is_false()
	assert_str(s.trash_replacement_for(null, null, null)).is_equal("")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_foundation_basics.gd`
Expected: FAIL (method not found, e.g. `cost_modifier`).

- [ ] **Step 3: Add the hooks**

Append to `src/cards/card_script.gd`:

```gdscript
# Cost system. Additive ticket delta (negative = cheaper). Pure.
func cost_modifier(_card: CardInstance, _ctx) -> int: return 0

# Classification predicates for "every Note" / "one CLEF" rules.
func is_clef() -> bool: return false
func is_note() -> bool: return false

# RUMMAGE: extra cards added per rummage instance while this card is on board.
func rummage_bonus(_card: CardInstance, _ctx) -> int: return 0

# Deck-damage interception (trap, in TRAP_SET).
func can_intercept_deck_damage(_card: CardInstance, _player: int, _amount: int, _ctx) -> bool: return false
# Called after the trap fires. Returns the remaining (un-negated) deck damage.
func deck_damage_on_fire(_card: CardInstance, _player: int, _amount: int, _ctx) -> int: return _amount

# Kill interception (trap, in TRAP_SET). reason is "battle" or "effect".
func can_intercept_kill(_card: CardInstance, _dying: CardInstance, _reason: String, _ctx) -> bool: return false
# Called after the trap fires. Return true if it PREVENTED the death (engine must not kill).
func kill_on_fire(_card: CardInstance, _dying: CardInstance, _ctx) -> bool: return false

# TRASH replacements. Return a non-empty button label if this card offers a
# "may instead" replacement for trashing `target`; "" means not applicable.
func trash_replacement_for(_card: CardInstance, _target: CardInstance, _ctx) -> String: return ""
func apply_trash_replacement(_card: CardInstance, _target: CardInstance, _ctx) -> void: pass
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/card_script.gd tests/test_foundation_basics.gd
git commit -m "feat(cards): add CardScript hooks for cost/clef/note/rummage/intercept/trash"
```

---

## Task 3: effective_cost + cost_modifier integration

**Files:**
- Modify: `src/engine/game_engine.gd` (add `effective_cost`; use it in `_play_card` and `get_legal_actions`)
- Test: `tests/test_foundation_cost.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_foundation_cost.gd
extends CardTestBase

class CheapWhenBoarded extends CardScript:
	func cost_modifier(_card: CardInstance, ctx) -> int:
		return -ctx.board(ctx.me()).size()

func test_effective_cost_applies_script_modifier_and_clamps() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var def := TestFactory.minion(10, 1, 16, 8)
	var card := eng.state.make_instance(def)
	card.card_script = CheapWhenBoarded.new()
	# 3 dummy minions on board -> cost 10 - 3 = 7
	for i in range(3):
		place_on_board(eng, me, TestFactory.minion(1, 1, 1, 200 + i))
	assert_int(eng.effective_cost(card, me)).is_equal(7)

func test_effective_cost_never_negative() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var def := TestFactory.minion(1, 1, 1, 9)
	var card := eng.state.make_instance(def)
	card.card_script = CheapWhenBoarded.new()
	for i in range(5):
		place_on_board(eng, me, TestFactory.minion(1, 1, 1, 300 + i))
	assert_int(eng.effective_cost(card, me)).is_equal(0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_foundation_cost.gd`
Expected: FAIL (`effective_cost` not found).

- [ ] **Step 3: Add `effective_cost` and wire it in**

In `src/engine/game_engine.gd`, add the method (place it near `_play_card`):

```gdscript
func effective_cost(card: CardInstance, player_idx: int) -> int:
	var base := card.definition.ticket_cost
	var modd := 0
	if card.card_script != null:
		modd = card.card_script.cost_modifier(card, _ctx_for(player_idx))
	var fee: int = card.vars.get("fee_modifier", 0)
	return max(0, base + modd + fee)
```

In `_play_card`, replace the ticket charge line:

```gdscript
	if def.type == Enums.CardType.LEADER and pay_by_discard:
		_mill(state.active_player, def.alt_discard_cost)
	else:
		ps.tickets_tapped += effective_cost(card, state.active_player)
```

In `get_legal_actions`, replace the affordability check `if ps.available_tickets() >= def.ticket_cost:` with:

```gdscript
		if ps.available_tickets() >= effective_cost(c, state.active_player):
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Run the full engine regression**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_legal_actions.gd` and `... -a res://tests/test_engine_play.gd`
Expected: PASS (existing behavior unchanged for cards with no modifier).

- [ ] **Step 6: Commit**

```bash
git add src/engine/game_engine.gd tests/test_foundation_cost.gd
git commit -m "feat(engine): effective_cost with script cost modifier"
```

---

## Task 4: fee_modifier + add_fee_modifier verb

**Files:**
- Modify: `src/cards/effect_context.gd`
- Test: `tests/test_foundation_cost.gd` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/test_foundation_cost.gd`:

```gdscript
func test_add_fee_modifier_stacks_and_reduces_cost() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ctx := EffectContext.new(eng, me)
	var def := TestFactory.minion(5, 1, 1, 11)
	var card := eng.state.make_instance(def)
	ctx.add_fee_modifier(card, -1)
	ctx.add_fee_modifier(card, -1)
	assert_int(eng.effective_cost(card, me)).is_equal(3)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_foundation_cost.gd`
Expected: FAIL (`add_fee_modifier` not found).

- [ ] **Step 3: Add the verb**

Append to `src/cards/effect_context.gd`:

```gdscript
func add_fee_modifier(card: CardInstance, delta: int) -> void:
	card.vars["fee_modifier"] = int(card.vars.get("fee_modifier", 0)) + delta
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/effect_context.gd tests/test_foundation_cost.gd
git commit -m "feat(cards): add_fee_modifier persistent cost discount"
```

---

## Task 5: Orange token card

**Files:**
- Create: `src/cards/orange_token.gd`
- Create: `src/cards/scripts/orange_card.gd`
- Modify: `src/cards/card_script_registry.gd`
- Modify: `src/cards/effect_context.gd` (`gain_orange`)
- Modify: `src/engine/game_engine.gd` (`_gain_orange`, end-turn hand limit)
- Test: `tests/test_foundation_orange.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_foundation_orange.gd
extends CardTestBase

func _oranges_in_hand(eng: GameEngine, p: int) -> int:
	var n := 0
	for c in eng.state.players[p].hand:
		if c.definition == OrangeToken.DEF:
			n += 1
	return n

func test_gain_orange_mints_into_hand() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var before := _oranges_in_hand(eng, me)
	EffectContext.new(eng, me).gain_orange(me)
	assert_int(_oranges_in_hand(eng, me)).is_equal(before + 1)

func test_gain_orange_capped_at_five() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ctx := EffectContext.new(eng, me)
	for i in range(8):
		ctx.gain_orange(me)
	assert_int(_oranges_in_hand(eng, me)).is_equal(5)

func test_orange_play_reduces_chosen_card_fee() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	ps.tickets_total = 20
	var target := eng.state.make_instance(TestFactory.minion(5, 1, 1, 12))
	target.zone = Enums.Zone.HAND
	ps.hand.append(target)
	var orange := eng.state.make_instance(OrangeToken.DEF)
	orange.zone = Enums.Zone.HAND
	ps.hand.append(orange)
	eng.apply(Action.play_card(orange.instance_id))
	# Orange asks which hand card to discount
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_cards")
	var idx := ps.hand.find(target)
	eng.apply(Action.resolve_choice({"indices": [idx]}))
	assert_int(eng.effective_cost(target, me)).is_equal(4)

func test_orange_in_hand_raises_end_turn_limit() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	ps.hand.clear()
	# 6 cards incl. one Orange -> limit 5 + 1 = 6, so no discard prompt
	for i in range(5):
		var c := eng.state.make_instance(TestFactory.minion(1, 1, 1, 400 + i))
		c.zone = Enums.Zone.HAND
		ps.hand.append(c)
	var orange := eng.state.make_instance(OrangeToken.DEF)
	orange.zone = Enums.Zone.HAND
	ps.hand.append(orange)
	eng.apply(Action.end_turn())
	assert_bool(eng.state.pending_choice != null and eng.state.pending_choice.kind == "discard_to_limit").is_false()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_foundation_orange.gd`
Expected: FAIL (`OrangeToken` not declared).

- [ ] **Step 3: Create the token definition factory**

```gdscript
# src/cards/orange_token.gd
class_name OrangeToken
extends RefCounted

const ID := 100
const MAX_HELD := 5

static var DEF: CardDefinition = _make_def()

static func _make_def() -> CardDefinition:
	var d := CardDefinition.new()
	d.id = ID
	d.deck_color = "writing"
	d.type = Enums.CardType.SPELL
	d.name = "Orange"
	d.ticket_cost = 0
	return d

static func is_orange(card: CardInstance) -> bool:
	return card != null and card.definition == DEF
```

- [ ] **Step 4: Create the Orange card script**

```gdscript
# src/cards/scripts/orange_card.gd
class_name OrangeCard
extends CardScript

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	var hand := ctx.hand(ctx.me())
	if hand.is_empty():
		return
	ctx.request_choice(card, ChoiceSpec.select_cards(hand.duplicate(), 0, 1, "Reduce a card's fee by 1"), "orange_fee")

func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "orange_fee" and not result["cards"].is_empty():
		ctx.add_fee_modifier(result["cards"][0], -1)
```

- [ ] **Step 5: Register the token**

In `src/cards/card_script_registry.gd`, inside `_build()`, add (after the strike registrations):

```gdscript
	_register("writing", OrangeToken.ID, OrangeCard.new())
```

- [ ] **Step 6: Add `gain_orange` verb and `_gain_orange`**

Append to `src/cards/effect_context.gd`:

```gdscript
func gain_orange(player: int) -> void: engine._gain_orange(player)
```

In `src/engine/game_engine.gd`, add:

```gdscript
func _gain_orange(player_idx: int) -> void:
	var ps := state.players[player_idx]
	var held := 0
	for c in ps.hand:
		if OrangeToken.is_orange(c):
			held += 1
	if held >= OrangeToken.MAX_HELD:
		return
	var ci := state.make_instance(OrangeToken.DEF)
	ci.zone = Enums.Zone.HAND
	ps.hand.append(ci)

func _hand_limit(ps: PlayerState) -> int:
	var oranges := 0
	for c in ps.hand:
		if OrangeToken.is_orange(c):
			oranges += 1
	return 5 + oranges
```

In `_end_turn`, replace `if ps.hand.size() > 5:` with `if ps.hand.size() > _hand_limit(ps):` and replace the count `{"count": ps.hand.size() - 5}` with `{"count": ps.hand.size() - _hand_limit(ps)}`.

- [ ] **Step 7: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add src/cards/orange_token.gd src/cards/scripts/orange_card.gd src/cards/card_script_registry.gd src/cards/effect_context.gd src/engine/game_engine.gd tests/test_foundation_orange.gd
git commit -m "feat(writing): Orange token card (fee discount + hand-size bump)"
```

---

## Task 6: RUMMAGE primitive

**Files:**
- Modify: `src/cards/effect_context.gd` (`rummage`)
- Modify: `src/engine/game_engine.gd` (`_rummage`)
- Test: `tests/test_foundation_rummage.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_foundation_rummage.gd
extends CardTestBase

class RummageBonusUnit extends CardScript:
	func rummage_bonus(_card: CardInstance, _ctx) -> int: return 1

func _seed_discard(eng: GameEngine, p: int, n: int) -> Array:
	var out: Array = []
	for i in range(n):
		var c := eng.state.make_instance(TestFactory.minion(1, 1, 1, 500 + i))
		c.zone = Enums.Zone.DISCARD
		eng.state.players[p].discard.append(c)
		out.append(c)
	return out

func test_rummage_draws_from_bottom_front_of_discard() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var disc := _seed_discard(eng, me, 3)  # disc[0] is the bottom
	EffectContext.new(eng, me).rummage(1)
	assert_bool(eng.state.players[me].hand.has(disc[0])).is_true()
	assert_int(eng.state.players[me].discard.size()).is_equal(2)

func test_rummage_increments_counter_and_emits_instance_event() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	_seed_discard(eng, me, 3)
	var from := eng.state.bus.log.size()
	EffectContext.new(eng, me).rummage(2)
	assert_int(eng.state.players[me].turn_counters["rummages_made"]).is_equal(1)
	var perf := eng.state.bus.log.slice(from).filter(
		func(e): return e.type == Enums.EventType.RUMMAGE_PERFORMED)
	assert_int(perf.size()).is_equal(1)
	assert_int(perf[0].data["count"]).is_equal(2)

func test_rummage_bonus_from_board_adds_cards() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	_seed_discard(eng, me, 5)
	var coyote := place_on_board(eng, me, TestFactory.minion(4, 6, 3, 8))
	coyote.card_script = RummageBonusUnit.new()
	EffectContext.new(eng, me).rummage(2)  # 2 + 1 bonus = 3
	assert_int(eng.state.players[me].hand.size() >= 3).is_true()
	assert_int(eng.state.players[me].discard.size()).is_equal(2)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_foundation_rummage.gd`
Expected: FAIL (`rummage` not found).

- [ ] **Step 3: Add verb + primitive**

Append to `src/cards/effect_context.gd`:

```gdscript
func rummage(n: int) -> void: engine._rummage(pidx, n)
```

In `src/engine/game_engine.gd`, add:

```gdscript
func _rummage(player_idx: int, n: int) -> void:
	var ps := state.players[player_idx]
	var bonus := 0
	for u in ps.board:
		if u.card_script != null:
			bonus += u.card_script.rummage_bonus(u, _ctx_for(player_idx))
	var total := n + bonus
	ps.turn_counters["rummages_made"] += 1
	emit(GameEvent.new(Enums.EventType.RUMMAGE_PERFORMED,
		{"player": player_idx, "count": total}))
	for i in range(total):
		if ps.discard.is_empty():
			break
		var card: CardInstance = ps.discard.pop_front()
		card.zone = Enums.Zone.HAND
		ps.hand.append(card)
		emit(GameEvent.new(Enums.EventType.CARD_RUMMAGED,
			{"player": player_idx, "instance": card.instance_id}))
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/effect_context.gd src/engine/game_engine.gd tests/test_foundation_rummage.gd
git commit -m "feat(engine): RUMMAGE primitive (bottom-of-discard, per-card + per-instance events, board bonus)"
```

---

## Task 7: HARMONIZE primitive

**Files:**
- Modify: `src/cards/effect_context.gd` (`harmonize`)
- Modify: `src/engine/game_engine.gd` (`_harmonize`)
- Test: `tests/test_foundation_harmonize.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_foundation_harmonize.gd
extends CardTestBase

class NoteStub extends CardScript:
	func reacts_to() -> Array: return [Enums.EventType.HARMONIZE]
	func active_zones() -> Array: return [Enums.Zone.BOARD]
	func react(card: CardInstance, _event: GameEvent, _ctx) -> void:
		if card.vars.get("harmonized", false): return
		card.vars["harmonized"] = true
		card.current_damage += 2

func test_harmonize_emits_event_and_buffs_notes_once() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var note := place_on_board(eng, me, TestFactory.minion(2, 1, 4, 2))
	note.card_script = NoteStub.new()
	var ctx := EffectContext.new(eng, me)
	ctx.harmonize()
	assert_int(note.current_damage).is_equal(3)
	ctx.harmonize()  # second harmonize does not re-trigger
	assert_int(note.current_damage).is_equal(3)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_foundation_harmonize.gd`
Expected: FAIL (`harmonize` not found).

- [ ] **Step 3: Add verb + primitive**

Append to `src/cards/effect_context.gd`:

```gdscript
func harmonize() -> void: engine._harmonize(pidx)
```

In `src/engine/game_engine.gd`, add:

```gdscript
func _harmonize(player_idx: int) -> void:
	emit(GameEvent.new(Enums.EventType.HARMONIZE, {"player": player_idx}))
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/effect_context.gd src/engine/game_engine.gd tests/test_foundation_harmonize.gd
git commit -m "feat(engine): HARMONIZE primitive"
```

---

## Task 8: untap + set_taunt verbs

**Files:**
- Modify: `src/cards/effect_context.gd`
- Test: `tests/test_foundation_basics.gd` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/test_foundation_basics.gd`:

```gdscript
func test_untap_and_set_taunt_verbs() -> void:
	var state := GameState.new(1)
	var eng := GameEngine.new(state)
	var ctx := EffectContext.new(eng, 0)
	var u := CardInstance.new(1, TestFactory.minion(1, 1, 1, 1))
	u.tapped = true
	ctx.untap(u)
	assert_bool(u.tapped).is_false()
	ctx.set_taunt(u)
	assert_bool(u.vars.get("taunt", false)).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_foundation_basics.gd`
Expected: FAIL (`untap` not found).

- [ ] **Step 3: Add the verbs**

Append to `src/cards/effect_context.gd`:

```gdscript
func untap(unit: CardInstance) -> void: unit.tapped = false
func set_taunt(unit: CardInstance) -> void: unit.vars["taunt"] = true
func to_deck_bottom(card: CardInstance) -> void: engine._to_deck_bottom(card)
```

In `src/engine/game_engine.gd`, add:

```gdscript
func _to_deck_bottom(card: CardInstance) -> void:
	var owner := _owner_of(card)
	if owner < 0:
		return
	var ps := state.players[owner]
	ps.board.erase(card)
	ps.hand.erase(card)
	ps.discard.erase(card)
	card.reset_stats()
	card.zone = Enums.Zone.DECK
	ps.deck.append(card)
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/effect_context.gd src/engine/game_engine.gd tests/test_foundation_basics.gd
git commit -m "feat(cards): untap, set_taunt, to_deck_bottom verbs"
```

---

## Task 9: TAUNT enforcement in legal actions + attack validation

**Files:**
- Modify: `src/engine/game_engine.gd` (`get_legal_actions`, `_declare_attack`)
- Test: `tests/test_foundation_taunt.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_foundation_taunt.gd
extends CardTestBase

func _attack_targets(eng: GameEngine, attacker_id: int) -> Array:
	var out: Array = []
	for a in eng.get_legal_actions():
		if a.type == Enums.ActionType.DECLARE_ATTACK and a.params["attacker_id"] == attacker_id:
			out.append(a.params["target"])
	return out

func test_taunt_restricts_targets_and_blocks_deck() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var attacker := place_on_board(eng, me, TestFactory.minion(1, 2, 2, 1))
	attacker.tapped = false
	var taunt := place_on_board(eng, opp, TestFactory.minion(1, 1, 5, 2))
	var plain := place_on_board(eng, opp, TestFactory.minion(1, 1, 5, 3))
	taunt.vars["taunt"] = true
	var targets := _attack_targets(eng, attacker.instance_id)
	# only the taunt unit is a legal target; deck attack disallowed
	assert_int(targets.size()).is_equal(1)
	assert_int(targets[0].get("unit", -1)).is_equal(taunt.instance_id)

func test_no_taunt_allows_deck_and_all_units() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var attacker := place_on_board(eng, me, TestFactory.minion(1, 2, 2, 1))
	attacker.tapped = false
	place_on_board(eng, opp, TestFactory.minion(1, 1, 5, 2))
	var targets := _attack_targets(eng, attacker.instance_id)
	var has_deck := targets.any(func(t): return t.get("deck", false))
	assert_bool(has_deck).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_foundation_taunt.gd`
Expected: FAIL (`test_taunt_restricts...` — deck attack + plain unit still offered).

- [ ] **Step 3: Add a taunt helper and use it in `get_legal_actions`**

In `src/engine/game_engine.gd`, add:

```gdscript
func _taunt_units(player_idx: int) -> Array:
	var out: Array = []
	for u in state.players[player_idx].board:
		if u.vars.get("taunt", false):
			out.append(u)
	return out
```

In `get_legal_actions`, replace the attack-target block:

```gdscript
	for u in ps.board:
		if u.tapped or not u.is_unit():
			continue
		out.append(Action.declare_attack(u.instance_id, {"deck": true}))
		for d in opp.board:
			out.append(Action.declare_attack(u.instance_id, {"unit": d.instance_id}))
```

with:

```gdscript
	var taunts := _taunt_units(state.opponent())
	for u in ps.board:
		if u.tapped or not u.is_unit():
			continue
		if taunts.is_empty():
			out.append(Action.declare_attack(u.instance_id, {"deck": true}))
			for d in opp.board:
				out.append(Action.declare_attack(u.instance_id, {"unit": d.instance_id}))
		else:
			for d in taunts:
				out.append(Action.declare_attack(u.instance_id, {"unit": d.instance_id}))
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Run combat regression**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_legal_actions.gd`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/engine/game_engine.gd tests/test_foundation_taunt.gd
git commit -m "feat(engine): TAUNT restricts attack targets and blocks deck attacks"
```

---

## Task 10: CLEF one-active play restriction

**Files:**
- Modify: `src/engine/game_engine.gd` (`get_legal_actions`)
- Test: `tests/test_foundation_clef.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_foundation_clef.gd
extends CardTestBase

class ClefStub extends CardScript:
	func is_clef() -> bool: return true

func _can_play(eng: GameEngine, iid: int) -> bool:
	for a in eng.get_legal_actions():
		if a.type == Enums.ActionType.PLAY_CARD and a.params["instance_id"] == iid:
			return true
	return false

func test_second_clef_not_playable_while_one_on_board() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	ps.tickets_total = 20
	var on_board := place_on_board(eng, me, TestFactory.minion(5, 0, 5, 12))
	on_board.card_script = ClefStub.new()
	var in_hand := eng.state.make_instance(TestFactory.minion(5, 0, 5, 13))
	in_hand.card_script = ClefStub.new()
	in_hand.zone = Enums.Zone.HAND
	ps.hand.append(in_hand)
	assert_bool(_can_play(eng, in_hand.instance_id)).is_false()

func test_clef_playable_when_none_on_board() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	ps.tickets_total = 20
	var in_hand := eng.state.make_instance(TestFactory.minion(5, 0, 5, 13))
	in_hand.card_script = ClefStub.new()
	in_hand.zone = Enums.Zone.HAND
	ps.hand.append(in_hand)
	assert_bool(_can_play(eng, in_hand.instance_id)).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_foundation_clef.gd`
Expected: FAIL (`test_second_clef_not_playable...`).

- [ ] **Step 3: Add the restriction**

In `src/engine/game_engine.gd`, add a helper:

```gdscript
func _has_clef_on_board(player_idx: int) -> bool:
	for u in state.players[player_idx].board:
		if u.card_script != null and u.card_script.is_clef():
			return true
	return false
```

In `get_legal_actions`, within the hand loop, wrap the `play_card` append with a clef guard:

```gdscript
	for c in ps.hand:
		var def := c.definition
		var is_clef := c.card_script != null and c.card_script.is_clef()
		if is_clef and _has_clef_on_board(state.active_player):
			continue
		if ps.available_tickets() >= effective_cost(c, state.active_player):
			out.append(Action.play_card(c.instance_id))
		if def.type == Enums.CardType.LEADER \
				and ps.deck.size() + ps.discard.size() >= def.alt_discard_cost:
			out.append(Action.play_card(c.instance_id, {"pay_by_discard": true}))
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/engine/game_engine.gd tests/test_foundation_clef.gd
git commit -m "feat(engine): only one CLEF playable at a time"
```

---

## Task 11: Dispatch reactions from hand

**Files:**
- Modify: `src/engine/game_engine.gd` (`_trigger_candidates`)
- Test: `tests/test_foundation_basics.gd` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/test_foundation_basics.gd`:

```gdscript
class HandReactor extends CardScript:
	func reacts_to() -> Array: return [Enums.EventType.CARD_RUMMAGED]
	func active_zones() -> Array: return [Enums.Zone.HAND]
	func react(card: CardInstance, _event: GameEvent, _ctx) -> void:
		card.vars["reacted"] = true

func test_hand_cards_can_react_when_active_zone_includes_hand() -> void:
	var state := GameState.new(2)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	eng.apply(Action.mulligan([])); eng.apply(Action.mulligan([]))
	var me := eng.state.active_player
	var c := eng.state.make_instance(TestFactory.minion(1, 1, 1, 1))
	c.card_script = HandReactor.new()
	c.zone = Enums.Zone.HAND
	eng.state.players[me].hand.append(c)
	eng.emit(GameEvent.new(Enums.EventType.CARD_RUMMAGED, {"player": me, "instance": c.instance_id}))
	assert_bool(c.vars.get("reacted", false)).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_foundation_basics.gd`
Expected: FAIL (hand card never reacts).

- [ ] **Step 3: Add hand to trigger candidates**

In `src/engine/game_engine.gd`, in `_trigger_candidates`, add the hand:

```gdscript
func _trigger_candidates(ps: PlayerState) -> Array:
	var out: Array = []
	out.append_array(ps.board)
	out.append_array(ps.set_traps)
	out.append_array(ps.discard)
	out.append_array(ps.hand)
	return out
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Run engine regression**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests` (whole suite)
Expected: PASS (no existing script lists HAND in `active_zones`, so behavior is unchanged).

- [ ] **Step 6: Commit**

```bash
git add src/engine/game_engine.gd tests/test_foundation_basics.gd
git commit -m "feat(engine): dispatch triggered abilities from hand (gated by active_zones)"
```

---

## Task 12: ChoiceSpec.intercept + AiController handling

**Files:**
- Modify: `src/cards/choice_spec.gd`
- Modify: `src/ui/match/ai_controller.gd`
- Test: `tests/test_foundation_basics.gd` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/test_foundation_basics.gd`:

```gdscript
func test_intercept_spec_carries_trap_and_options() -> void:
	var trap := CardInstance.new(9, TestFactory.trap(4, 9))
	var spec := ChoiceSpec.intercept(trap, "Your Deck will take 6 damage", ["Fire", "Decline"])
	assert_str(spec.ui_shape).is_equal("intercept")
	assert_object(spec.cards[0]).is_same(trap)
	assert_str(spec.title).is_equal("Your Deck will take 6 damage")
	assert_array(spec.labels).is_equal(["Fire", "Decline"])
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_foundation_basics.gd`
Expected: FAIL (`ChoiceSpec.intercept` not found).

- [ ] **Step 3: Add the spec factory**

Append to `src/cards/choice_spec.gd`:

```gdscript
static func intercept(trap_card, context: String, options: Array) -> ChoiceSpec:
	var s := ChoiceSpec.new()
	s.ui_shape = "intercept"
	s.cards = [trap_card]
	s.labels = options
	s.title = context
	return s
```

- [ ] **Step 4: Teach the AI to answer intercept + trash_choice**

In `src/ui/match/ai_controller.gd`, in `choice_action`, add cases. Replace the outer `match pc.kind:` block's `"card_effect":` branch by also handling the new kinds — add these two cases before the final `_:`:

```gdscript
		"intercept":
			# AI declines interceptors (option index 1 = "Decline") to avoid self-harm.
			return Action.resolve_choice({"option": 1})
		"trash_choice":
			# AI always picks the last option ("Just KO it").
			var spec: ChoiceSpec = pc.data["spec"]
			return Action.resolve_choice({"option": spec.labels.size() - 1})
```

- [ ] **Step 5: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/cards/choice_spec.gd src/ui/match/ai_controller.gd tests/test_foundation_basics.gd
git commit -m "feat: ChoiceSpec.intercept shape + AI handling for intercept/trash_choice"
```

---

## Task 13: Suspendable deck-damage interception

**Files:**
- Modify: `src/engine/game_engine.gd` (`_deck_damage` → `_begin_deck_damage`/`_apply_deck_damage`; `_apply_resolve_choice`; `_resolve_intercept`)
- Test: `tests/test_foundation_intercept_deck.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_foundation_intercept_deck.gd
extends CardTestBase

class RestStub extends CardScript:
	func active_zones() -> Array: return [Enums.Zone.TRAP_SET]
	func can_intercept_deck_damage(_card: CardInstance, _player: int, _amount: int, _ctx) -> bool:
		return true
	func deck_damage_on_fire(_card: CardInstance, _player: int, _amount: int, _ctx) -> int:
		return 0  # fully negate

func _set_trap(eng: GameEngine, p: int, script: CardScript) -> CardInstance:
	var t := eng.state.make_instance(TestFactory.trap(4, 20))
	t.card_script = script
	t.zone = Enums.Zone.TRAP_SET
	eng.state.players[p].set_traps.append(t)
	return t

func test_deck_damage_without_interceptor_mills_normally() -> void:
	var eng := fresh_engine()
	var opp := eng.state.opponent()
	var before := eng.state.players[opp].deck.size()
	eng._deck_damage(opp, 2)
	assert_int(eng.state.players[opp].deck.size()).is_equal(before - 2)
	assert_bool(eng.state.pending_choice == null).is_true()

func test_deck_damage_with_interceptor_suspends_then_fire_negates() -> void:
	var eng := fresh_engine()
	var opp := eng.state.opponent()
	_set_trap(eng, opp, RestStub.new())
	var before := eng.state.players[opp].deck.size()
	eng._deck_damage(opp, 6)
	# suspended, asking the defender (opp)
	assert_bool(eng.state.pending_choice != null).is_true()
	assert_str(eng.state.pending_choice.kind).is_equal("intercept")
	assert_int(eng.state.pending_choice.player).is_equal(opp)
	eng.apply(Action.resolve_choice({"option": 0}))  # Fire
	assert_int(eng.state.players[opp].deck.size()).is_equal(before)  # nothing milled
	assert_bool(eng.state.players[opp].set_traps.is_empty()).is_true()  # trap fired

func test_deck_damage_decline_applies_full_damage() -> void:
	var eng := fresh_engine()
	var opp := eng.state.opponent()
	_set_trap(eng, opp, RestStub.new())
	var before := eng.state.players[opp].deck.size()
	eng._deck_damage(opp, 3)
	eng.apply(Action.resolve_choice({"option": 1}))  # Decline
	assert_int(eng.state.players[opp].deck.size()).is_equal(before - 3)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_foundation_intercept_deck.gd`
Expected: FAIL (suspension never happens).

- [ ] **Step 3: Refactor `_deck_damage` into begin/apply with interception**

In `src/engine/game_engine.gd`, replace the existing `_deck_damage`:

```gdscript
func _deck_damage(player_idx: int, amount: int) -> void:
	_push({"kind": "call", "fn": func(): _begin_deck_damage(player_idx, amount)})
	_pump()

func _begin_deck_damage(player_idx: int, amount: int) -> void:
	var ps := state.players[player_idx]
	for trap in ps.set_traps:
		if trap.card_script != null and trap.card_script.can_intercept_deck_damage(
				trap, player_idx, amount, _ctx_for(player_idx)):
			state.pending_choice = PendingChoice.new("intercept", player_idx, {
				"op": "deck_damage", "trap_id": trap.instance_id,
				"player": player_idx, "amount": amount,
				"spec": ChoiceSpec.intercept(trap,
					"Your Deck will take %d damage" % amount, ["Fire", "Decline"]),
				"ui_shape": "intercept",
			})
			_suspended = true
			return
	_apply_deck_damage(player_idx, amount)

func _apply_deck_damage(player_idx: int, amount: int) -> void:
	if amount > 0:
		_mill(player_idx, amount)
	emit(GameEvent.new(Enums.EventType.DECK_DAMAGED,
		{"player": player_idx, "amount": amount}))
```

- [ ] **Step 4: Route the `intercept` resolution**

In `_apply_resolve_choice`, add a branch at the top (after `var pc := state.pending_choice`):

```gdscript
	if pc.kind == "intercept":
		_resolve_intercept(params)
		return
```

Add the resolver:

```gdscript
func _resolve_intercept(params: Dictionary) -> void:
	var d := state.pending_choice.data
	var option: int = params.get("option", 1)
	var trap := _find_anywhere(d["trap_id"])
	state.pending_choice = null
	_suspended = false
	match d["op"]:
		"deck_damage":
			if option == 0 and trap != null and trap.card_script != null:
				_fire_trap(trap)
				var remaining: int = trap.card_script.deck_damage_on_fire(
					trap, d["player"], d["amount"], _ctx_for(d["player"]))
				_apply_deck_damage(d["player"], remaining)
			else:
				_apply_deck_damage(d["player"], d["amount"])
		"kill":
			var unit := _find_anywhere(d["unit_id"])
			if option == 0 and trap != null and trap.card_script != null and unit != null:
				_fire_trap(trap)
				var prevented: bool = trap.card_script.kill_on_fire(
					trap, unit, _ctx_for(d["owner"]))
				if not prevented:
					_apply_kill(d["owner"], unit)
			elif unit != null:
				_apply_kill(d["owner"], unit)
	if not _suspended:
		_pump()
```

> Note: the `"kill"` branch references `_apply_kill`, added in Task 14. If you run this task's tests before Task 14, GDScript still parses (the method is resolved at call time), and the deck-damage tests never hit the `"kill"` branch.

- [ ] **Step 5: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 6: Run regression (Cactus Guy / deck attacks)**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/strike/test_cactus_guy.gd` and `... -a res://tests/test_engine_attack.gd`
Expected: PASS (no interceptor present → deck damage applies synchronously within `apply`).

- [ ] **Step 7: Commit**

```bash
git add src/engine/game_engine.gd tests/test_foundation_intercept_deck.gd
git commit -m "feat(engine): suspendable deck-damage interception pipeline"
```

---

## Task 14: Suspendable kill interception

**Files:**
- Modify: `src/engine/game_engine.gd` (`_kill` → `_begin_kill`/`_apply_kill`; `_declare_attack` reason; `_damage_unit` path)
- Test: `tests/test_foundation_intercept_kill.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_foundation_intercept_kill.gd
extends CardTestBase

class SafetyNetStub extends CardScript:
	func active_zones() -> Array: return [Enums.Zone.TRAP_SET]
	func can_intercept_kill(_card: CardInstance, _dying: CardInstance, _reason: String, _ctx) -> bool:
		return true
	func kill_on_fire(_card: CardInstance, dying: CardInstance, _ctx) -> bool:
		dying.vars["discard_to_bottom"] = true
		return false  # let the kill proceed, but redirected

func _set_trap(eng: GameEngine, p: int, script: CardScript) -> CardInstance:
	var t := eng.state.make_instance(TestFactory.trap(3, 20))
	t.card_script = script
	t.zone = Enums.Zone.TRAP_SET
	eng.state.players[p].set_traps.append(t)
	return t

func test_kill_without_interceptor_goes_to_discard_top() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var u := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 1))
	eng._kill(me, u, "effect")
	assert_bool(eng.state.players[me].discard.has(u)).is_true()
	assert_object(eng.state.players[me].discard.back()).is_same(u)

func test_safety_net_redirects_kill_to_bottom_on_fire() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	# pre-seed discard so "bottom" (front) is observable
	var filler := eng.state.make_instance(TestFactory.minion(1, 1, 1, 99))
	filler.zone = Enums.Zone.DISCARD
	eng.state.players[me].discard.append(filler)
	_set_trap(eng, me, SafetyNetStub.new())
	var u := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 1))
	eng._kill(me, u, "effect")
	assert_str(eng.state.pending_choice.kind).is_equal("intercept")
	eng.apply(Action.resolve_choice({"option": 0}))  # Fire
	# u is at the front (bottom) of the discard pile
	assert_object(eng.state.players[me].discard.front()).is_same(u)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_foundation_intercept_kill.gd`
Expected: FAIL (`_kill` takes 2 args / no suspension).

- [ ] **Step 3: Refactor `_kill` into begin/apply with interception**

In `src/engine/game_engine.gd`, replace the existing `_kill`:

```gdscript
func _kill(owner_idx: int, unit: CardInstance, reason: String = "effect") -> void:
	_push({"kind": "call", "fn": func(): _begin_kill(owner_idx, unit, reason)})
	_pump()

func _begin_kill(owner_idx: int, unit: CardInstance, reason: String) -> void:
	if unit.vars.get("immortal_this_turn", false):
		return
	if not state.players[owner_idx].board.has(unit):
		return
	for trap in state.players[owner_idx].set_traps:
		if trap.card_script != null and trap.card_script.can_intercept_kill(
				trap, unit, reason, _ctx_for(owner_idx)):
			state.pending_choice = PendingChoice.new("intercept", owner_idx, {
				"op": "kill", "trap_id": trap.instance_id,
				"owner": owner_idx, "unit_id": unit.instance_id,
				"spec": ChoiceSpec.intercept(trap,
					"%s would be killed" % unit.definition.name, ["Fire", "Decline"]),
				"ui_shape": "intercept",
			})
			_suspended = true
			return
	_apply_kill(owner_idx, unit)

func _apply_kill(owner_idx: int, unit: CardInstance) -> void:
	var owner := state.players[owner_idx]
	if not owner.board.has(unit):
		return
	owner.board.erase(unit)
	unit.zone = Enums.Zone.DISCARD
	unit.reset_stats()
	if unit.vars.get("discard_to_bottom", false):
		unit.vars.erase("discard_to_bottom")
		owner.discard.push_front(unit)
	else:
		owner.discard.append(unit)
	owner.turn_counters["units_died"] += 1
	emit(GameEvent.new(Enums.EventType.UNIT_DIED,
		{"owner": owner_idx, "instance": unit.instance_id}))
```

- [ ] **Step 4: Pass the battle reason from combat**

In `_declare_attack`, update the two combat kill calls:

```gdscript
	if r["def_dies"]:
		_kill(state.opponent(), defender, "battle")
	if r["atk_dies"]:
		_kill(state.active_player, attacker, "battle")
```

(`_damage_unit`'s `_kill_unit` and `ctx.kill` keep the default `"effect"` reason.)

- [ ] **Step 5: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 6: Full regression (kills are now queue-driven)**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
Expected: PASS. If a strike test that kills inside a loop (e.g. Bjorn Hammer) regresses, confirm the kills still all resolve within `apply()` — they do, because `_pump` drains the queue until empty when no interceptor suspends.

- [ ] **Step 7: Commit**

```bash
git add src/engine/game_engine.gd tests/test_foundation_intercept_kill.gd
git commit -m "feat(engine): suspendable kill interception + discard-to-bottom redirect"
```

---

## Task 15: Interactive TRASH primitive

**Files:**
- Modify: `src/cards/effect_context.gd` (`trash`)
- Modify: `src/engine/game_engine.gd` (`_trash`, `_begin_trash`, `_trash_kill`, `_collect_trash_replacements`, `_apply_resolve_choice` branch)
- Test: `tests/test_foundation_trash.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_foundation_trash.gd
extends CardTestBase

class ReturnToHandRep extends CardScript:
	func trash_replacement_for(card: CardInstance, target: CardInstance, _ctx) -> String:
		return "Return to hand" if card == target else ""
	func apply_trash_replacement(_card: CardInstance, target: CardInstance, ctx) -> void:
		var p := ctx.me()
		ctx.gs().players[p].board.erase(target)
		target.zone = Enums.Zone.HAND
		target.reset_stats()
		ctx.gs().players[p].hand.append(target)

class TrashCounter extends CardScript:
	func reacts_to() -> Array: return [Enums.EventType.UNIT_TRASHED]
	func active_zones() -> Array: return [Enums.Zone.BOARD, Enums.Zone.DISCARD]
	func react(card: CardInstance, event: GameEvent, _ctx) -> void:
		if event.data.get("instance", -1) == card.instance_id:
			card.vars["was_trashed"] = true

func test_trash_without_replacement_kos_unit_and_emits_event() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var u := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 1))
	u.card_script = TrashCounter.new()
	EffectContext.new(eng, me).trash(u)
	assert_bool(eng.state.players[me].discard.has(u)).is_true()
	assert_bool(u.vars.get("was_trashed", false)).is_true()

func test_trash_with_replacement_prompts_and_returns_to_hand() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var u := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 1))
	u.card_script = ReturnToHandRep.new()
	EffectContext.new(eng, me).trash(u)
	assert_str(eng.state.pending_choice.kind).is_equal("trash_choice")
	# option 0 = the replacement, last option = "Just KO it"
	eng.apply(Action.resolve_choice({"option": 0}))
	assert_bool(eng.state.players[me].hand.has(u)).is_true()
	assert_bool(eng.state.players[me].discard.has(u)).is_false()

func test_trash_choose_just_ko_when_replacement_available() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var u := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 1))
	u.card_script = ReturnToHandRep.new()
	EffectContext.new(eng, me).trash(u)
	eng.apply(Action.resolve_choice({"option": 1}))  # Just KO it
	assert_bool(eng.state.players[me].discard.has(u)).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_foundation_trash.gd`
Expected: FAIL (`trash` not found).

- [ ] **Step 3: Add the `trash` verb**

Append to `src/cards/effect_context.gd`:

```gdscript
func trash(unit: CardInstance) -> void: engine._trash(unit)
```

- [ ] **Step 4: Add the engine trash framework**

In `src/engine/game_engine.gd`, add:

```gdscript
func _trash(unit: CardInstance) -> void:
	var owner := _owner_of(unit)
	if owner < 0:
		return
	emit(GameEvent.new(Enums.EventType.UNIT_TRASHED,
		{"owner": owner, "instance": unit.instance_id}))
	_push({"kind": "call", "fn": func(): _begin_trash(owner, unit)})
	_pump()

func _collect_trash_replacements(owner_idx: int, unit: CardInstance) -> Array:
	var out: Array = []
	var ctx := _ctx_for(owner_idx)
	var ps := state.players[owner_idx]
	var sources: Array = [unit]
	if ps.leader != null and ps.leader != unit:
		sources.append(ps.leader)
	for u in ps.board:
		if u != unit:
			sources.append(u)
	for src in sources:
		if src.card_script == null:
			continue
		var label: String = src.card_script.trash_replacement_for(src, unit, ctx)
		if label != "":
			out.append({"label": label, "card": src})
	return out

func _begin_trash(owner_idx: int, unit: CardInstance) -> void:
	if not state.players[owner_idx].board.has(unit):
		return
	var reps := _collect_trash_replacements(owner_idx, unit)
	if reps.is_empty():
		_trash_kill(owner_idx, unit)
		return
	var labels: Array = []
	for r in reps:
		labels.append(r["label"])
	labels.append("Just KO it")
	state.pending_choice = PendingChoice.new("trash_choice", owner_idx, {
		"unit_id": unit.instance_id, "owner": owner_idx, "reps": reps,
		"spec": ChoiceSpec.choose_option(labels, "TRASH %s — replace?" % unit.definition.name),
		"ui_shape": "choose_option",
	})
	_suspended = true

func _trash_kill(owner_idx: int, unit: CardInstance) -> void:
	var ps := state.players[owner_idx]
	if not ps.board.has(unit):
		return
	ps.board.erase(unit)
	unit.zone = Enums.Zone.DISCARD
	unit.reset_stats()
	ps.discard.append(unit)
	ps.turn_counters["units_died"] += 1
	emit(GameEvent.new(Enums.EventType.UNIT_DIED,
		{"owner": owner_idx, "instance": unit.instance_id}))

func _resolve_trash_choice(params: Dictionary) -> void:
	var d := state.pending_choice.data
	var reps: Array = d["reps"]
	var option: int = params.get("option", reps.size())
	var unit := _find_anywhere(d["unit_id"])
	var owner: int = d["owner"]
	state.pending_choice = null
	_suspended = false
	if unit != null:
		if option < reps.size():
			var rep = reps[option]
			rep["card"].card_script.apply_trash_replacement(rep["card"], unit, _ctx_for(owner))
		else:
			_trash_kill(owner, unit)
	if not _suspended:
		_pump()
```

- [ ] **Step 5: Route `trash_choice` resolution**

In `_apply_resolve_choice`, add (after the `intercept` branch from Task 13):

```gdscript
	if pc.kind == "trash_choice":
		_resolve_trash_choice(params)
		return
```

- [ ] **Step 6: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/cards/effect_context.gd src/engine/game_engine.gd tests/test_foundation_trash.gd
git commit -m "feat(engine): interactive TRASH primitive with replacement-choice menu"
```

---

## Task 16: Trap-reveal overlay UI component

**Files:**
- Create: `src/ui/overlays/trap_reveal_overlay.gd`
- Create: `src/ui/overlays/trap_reveal_overlay.tscn`
- Test: `tests/test_trap_reveal_overlay.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_trap_reveal_overlay.gd
extends GdUnitTestSuite

func _trap_inst() -> CardInstance:
	var defs := CardDatabase.load_deck("res://src/data/decks/strike.csv", "strike")
	var trap_def: CardDefinition = null
	for d in defs:
		if d.type == Enums.CardType.TRAP:
			trap_def = d
			break
	return CardInstance.new(1, trap_def)

func _spawn() -> Node:
	var p = load("res://src/ui/overlays/trap_reveal_overlay.tscn").instantiate()
	add_child(p)
	auto_free(p)
	return p

func test_interactive_reveal_emits_fire() -> void:
	var p := _spawn()
	var got := {"picked": -1}
	p.picked.connect(func(i): got["picked"] = i)
	p.show_reveal(_trap_inst(), "Your Deck will take 6 damage", ["Fire", "Decline"], true)
	p.press_option(0)
	assert_int(got["picked"]).is_equal(0)

func test_readonly_reveal_hides_buttons() -> void:
	var p := _spawn()
	p.show_reveal(_trap_inst(), "Opponent fired Rest", ["Fire", "Decline"], false)
	assert_bool(p.buttons_visible()).is_false()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_trap_reveal_overlay.gd`
Expected: FAIL (scene does not exist).

- [ ] **Step 3: Create the overlay script**

```gdscript
# src/ui/overlays/trap_reveal_overlay.gd
extends CanvasLayer

signal picked(option: int)

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")

@onready var _slot: Control = $Panel/CardSlot
@onready var _name: Label = $Panel/TrapName
@onready var _context: Label = $Panel/Context
@onready var _buttons: HBoxContainer = $Panel/Buttons

func _ready() -> void:
	$Panel.theme = preload("res://src/ui/theme/game_theme.tres")

func show_reveal(trap: CardInstance, context: String, options: Array, interactive: bool) -> void:
	if not is_node_ready(): await ready
	for c in _slot.get_children(): c.queue_free()
	var cv: CardView = CARD_VIEW.instantiate()
	cv.set_interactive(false)
	_slot.add_child(cv)
	cv.setup(trap)
	_name.text = trap.definition.name
	_context.text = context
	for b in _buttons.get_children(): b.queue_free()
	_buttons.visible = interactive
	if interactive:
		for i in range(options.size()):
			var b := Button.new()
			b.text = options[i]
			var idx := i
			b.pressed.connect(func(): press_option(idx))
			_buttons.add_child(b)
			JuicyButton.apply(b)
	visible = true

func press_option(i: int) -> void:
	visible = false
	picked.emit(i)

func buttons_visible() -> bool:
	return _buttons.visible

func dismiss() -> void:
	visible = false
```

- [ ] **Step 4: Create the overlay scene**

```
# src/ui/overlays/trap_reveal_overlay.tscn
[gd_scene format=3]

[ext_resource type="Script" path="res://src/ui/overlays/trap_reveal_overlay.gd" id="1_script"]
[ext_resource type="Theme" path="res://src/ui/theme/game_theme.tres" id="2_theme"]

[node name="TrapRevealOverlay" type="CanvasLayer"]
visible = false
script = ExtResource("1_script")

[node name="Panel" type="Panel" parent="."]
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -300.0
offset_top = -200.0
offset_right = 300.0
offset_bottom = 200.0
theme = ExtResource("2_theme")

[node name="TrapName" type="Label" parent="Panel"]
layout_mode = 0
offset_left = 20.0
offset_top = 10.0
offset_right = 580.0
offset_bottom = 44.0
theme_override_font_sizes/font_size = 28
text = "Trap"

[node name="CardSlot" type="Control" parent="Panel"]
layout_mode = 0
offset_left = 20.0
offset_top = 50.0
offset_right = 200.0
offset_bottom = 300.0

[node name="Context" type="Label" parent="Panel"]
layout_mode = 0
offset_left = 220.0
offset_top = 60.0
offset_right = 580.0
offset_bottom = 200.0
autowrap_mode = 2
text = ""

[node name="Buttons" type="HBoxContainer" parent="Panel"]
layout_mode = 0
offset_left = 220.0
offset_top = 320.0
offset_right = 580.0
offset_bottom = 370.0
theme_override_constants/separation = 16
```

- [ ] **Step 5: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/ui/overlays/trap_reveal_overlay.gd src/ui/overlays/trap_reveal_overlay.tscn tests/test_trap_reveal_overlay.gd
git commit -m "feat(ui): trap-reveal overlay (interactive + read-only modes)"
```

---

## Task 17: Wire interception + trash-choice into match.gd

**Files:**
- Modify: `src/ui/match/match.tscn` (add `TrapRevealOverlay` node)
- Modify: `src/ui/match/match.gd` (route `intercept` + `trash_choice`; read-only AI reveal)
- Test: `tests/test_match_interception.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_match_interception.gd
extends GdUnitTestSuite

func _match() -> Node:
	var m = load("res://src/ui/match/match.tscn").instantiate()
	add_child(m)
	auto_free(m)
	return m

func test_human_intercept_opens_reveal_overlay() -> void:
	var m := _match()
	m.start_game(7, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	# Force a human (player 0) intercept pending choice directly.
	var trap := m.state.make_instance(CardDatabase.load_deck("res://src/data/decks/strike.csv", "strike")[18])
	m.state.pending_choice = PendingChoice.new("intercept", 0, {
		"op": "deck_damage", "trap_id": trap.instance_id, "player": 0, "amount": 6,
		"spec": ChoiceSpec.intercept(trap, "Your Deck will take 6 damage", ["Fire", "Decline"]),
		"ui_shape": "intercept",
	})
	m._route_pending_choice()
	assert_bool(m._trap_reveal.visible).is_true()
	assert_bool(m._trap_reveal.buttons_visible()).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_match_interception.gd`
Expected: FAIL (`_trap_reveal` not found).

- [ ] **Step 3: Add the overlay node to the match scene**

In `src/ui/match/match.tscn`, add an instance of the overlay as a child of the root node. Append these lines: add the ext_resource for the scene and a node entry. (If editing the `.tscn` by hand, add to the `[ext_resource]` list and node list.)

```
[ext_resource type="PackedScene" path="res://src/ui/overlays/trap_reveal_overlay.tscn" id="trap_reveal"]

[node name="TrapRevealOverlay" parent="." instance=ExtResource("trap_reveal")]
```

- [ ] **Step 4: Wire routing in match.gd**

In `src/ui/match/match.gd`, add the onready ref near the other overlays:

```gdscript
@onready var _trap_reveal = $TrapRevealOverlay
```

In `_ready()`, connect its signal:

```gdscript
	_trap_reveal.picked.connect(func(i): apply_action(Action.resolve_choice({"option": i})))
```

In `_route_pending_choice()`, handle the AI read-only case and the new kinds. Replace the method body with:

```gdscript
func _route_pending_choice() -> void:
	var pc := state.pending_choice
	if pc.player != HUMAN:
		if pc.kind == "intercept":
			await _show_readonly_intercept(pc)
		await get_tree().create_timer(0.2).timeout
		apply_action(AiController.choice_action(engine))
		return
	match pc.kind:
		"mulligan":
			_mulligan.show_hand(state.players[HUMAN].hand)
		"discard_to_limit":
			var n: int = pc.data["count"]
			_select.show_selection(state.players[HUMAN].hand, n, n, "Discard %d card(s)" % n)
		"intercept":
			var spec: ChoiceSpec = pc.data["spec"]
			_trap_reveal.show_reveal(spec.cards[0], spec.title, spec.labels, true)
		"trash_choice":
			var spec2: ChoiceSpec = pc.data["spec"]
			_option_prompt.show_options(spec2.labels, spec2.title)
		"card_effect":
			_route_card_effect(pc)

func _show_readonly_intercept(pc: PendingChoice) -> void:
	var spec: ChoiceSpec = pc.data["spec"]
	_trap_reveal.show_reveal(spec.cards[0], spec.title, spec.labels, false)
	await get_tree().create_timer(0.8).timeout
	_trap_reveal.dismiss()
```

> Note: `trash_choice` reuses the existing `OptionPrompt` (whose `picked` signal already maps to `resolve_choice({"option": i})` from `_ready`). Confirm the OptionPrompt connection from `_ready` exists; it does.

- [ ] **Step 5: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 6: Full regression**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/ui/match/match.tscn src/ui/match/match.gd tests/test_match_interception.gd
git commit -m "feat(ui): route interceptor reveal + trash-choice menu in match"
```

---

## Self-Review Notes (coverage vs spec §3 + §3.5)

- §3.1 suspendable pipeline → Tasks 13–15 (deck damage, kills, trash).
- §3.2 events/counters/hooks/dispatch → Tasks 1, 2, 11.
- §3.3 cost system → Tasks 3, 4.
- §3.4 Orange token → Task 5.
- §3.5 interception/trash UX → Tasks 12, 16, 17.
- Mechanics primitives RUMMAGE/HARMONIZE/TAUNT/CLEF/untap → Tasks 6, 7, 8, 9, 10.

Card-specific behavior (the actual Raccoon/Audio/Writing scripts that implement `can_intercept_*`, `deck_damage_on_fire`, `kill_on_fire`, `trash_replacement_for`, `is_note`, `is_clef`, `rummage_bonus`, harmonize buffs, etc.) lives in the three deck plans, which depend on this foundation's locked API surface.
