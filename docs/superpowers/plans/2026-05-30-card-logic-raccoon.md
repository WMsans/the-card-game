# Raccoon Deck Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement all 11 unique Raccoon-deck card scripts (RUMMAGE deck) as pure-GDScript `CardScript`s with per-card GdUnit4 tests.

**Architecture:** Each card is a `CardScript` subclass in `src/cards/scripts/raccoon/`, registered by `raccoon:<id>` in `card_script_registry.gd`. Cards use only the `EffectContext` verbs and `CardScript` hooks delivered by the Foundation plan (`docs/superpowers/plans/2026-05-30-card-logic-foundation.md`). **This plan requires the Foundation plan to be complete.**

**Tech Stack:** Godot 4 / GDScript; GdUnit4 tests.

**Run a suite (headless):**
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/raccoon/<suite>.gd
```

**Card id → script map (from `src/data/decks/raccoon.csv`):** 1 Raccoon (Leader); 2,3 Rat; 4,5 Opossum; 6,7 Skunk; 8,9 Coyote; 10,11 Trash Cannon; 12,13 Trash Day; 14,15 Trash to Treasure; 16,17 Trashalanche; 18,19 Garbage Guard; 20,21 Safety Net.

---

## File Structure

- `tests/cards/raccoon/raccoon_test_base.gd` — shared test helper.
- `src/cards/scripts/raccoon/<card>.gd` — one script per unique card.
- `src/cards/card_script_registry.gd` — register raccoon ids.
- `src/cards/card_script.gd` + `src/engine/game_engine.gd` — one small generic hook for "return to hand on reshuffle" (Task 2).

---

## Task 1: Raccoon test base

**Files:**
- Create: `tests/cards/raccoon/raccoon_test_base.gd`

- [ ] **Step 1: Create the helper**

```gdscript
# tests/cards/raccoon/raccoon_test_base.gd
class_name RaccoonTestBase
extends CardTestBase

func raccoon_def(id: int) -> CardDefinition:
	for d in CardDatabase.load_deck("res://src/data/decks/raccoon.csv", "raccoon"):
		if d.id == id:
			return d
	return null

func seed_discard(eng: GameEngine, p: int, n: int) -> Array:
	var out: Array = []
	for i in range(n):
		var c := eng.state.make_instance(TestFactory.minion(1, 1, 1, 700 + i))
		c.zone = Enums.Zone.DISCARD
		eng.state.players[p].discard.append(c)
		out.append(c)
	return out
```

- [ ] **Step 2: Verify it parses** by running any existing raccoon-free suite (sanity):

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_registry.gd`
Expected: PASS (no errors loading the new base class).

- [ ] **Step 3: Commit**

```bash
git add tests/cards/raccoon/raccoon_test_base.gd
git commit -m "test(raccoon): shared test base"
```

---

## Task 2: returns_on_reshuffle hook (for the Raccoon leader)

**Files:**
- Modify: `src/cards/card_script.gd`
- Modify: `src/engine/game_engine.gd` (`_reshuffle_or_lose`)
- Test: `tests/cards/raccoon/test_reshuffle_hook.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/raccoon/test_reshuffle_hook.gd
extends RaccoonTestBase

class ReturnerStub extends CardScript:
	func returns_on_reshuffle() -> bool: return true

func test_marked_card_returns_to_hand_on_reshuffle() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	ps.deck.clear()
	# one normal card in discard so reshuffle has something to shuffle
	var normal := eng.state.make_instance(TestFactory.minion(1, 1, 1, 800))
	normal.zone = Enums.Zone.DISCARD
	ps.discard.append(normal)
	var special := eng.state.make_instance(TestFactory.minion(1, 1, 1, 801))
	special.card_script = ReturnerStub.new()
	special.zone = Enums.Zone.DISCARD
	ps.discard.append(special)
	var ok := eng._reshuffle_or_lose(me)
	assert_bool(ok).is_true()
	assert_bool(ps.hand.has(special)).is_true()
	assert_bool(ps.deck.has(special)).is_false()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/raccoon/test_reshuffle_hook.gd`
Expected: FAIL (`returns_on_reshuffle` not found).

- [ ] **Step 3: Add the hook**

Append to `src/cards/card_script.gd`:

```gdscript
# When this card would be reshuffled from discard, instead return to owner's hand.
func returns_on_reshuffle() -> bool: return false
```

- [ ] **Step 4: Divert marked cards in `_reshuffle_or_lose`**

In `src/engine/game_engine.gd`, in `_reshuffle_or_lose`, replace:

```gdscript
	ps.reshuffles_remaining -= 1
	ps.deck.append_array(ps.discard)
	ps.discard.clear()
```

with:

```gdscript
	ps.reshuffles_remaining -= 1
	var returners: Array = []
	for c in ps.discard:
		if c.card_script != null and c.card_script.returns_on_reshuffle():
			returners.append(c)
	for c in returners:
		ps.discard.erase(c)
		c.zone = Enums.Zone.HAND
		ps.hand.append(c)
	ps.deck.append_array(ps.discard)
	ps.discard.clear()
```

- [ ] **Step 5: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 6: Regression**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_engine_deck_ops.gd`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/cards/card_script.gd src/engine/game_engine.gd tests/cards/raccoon/test_reshuffle_hook.gd
git commit -m "feat(engine): returns_on_reshuffle hook"
```

---

## Task 3: Rat (ids 2, 3)

**Files:**
- Create: `src/cards/scripts/raccoon/rat.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/raccoon/test_rat.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/raccoon/test_rat.gd
extends RaccoonTestBase

func test_rat_plays_free_when_rummaged() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	# put a Rat at the bottom (front) of the discard pile
	var rat := eng.state.make_instance(raccoon_def(2))
	rat.zone = Enums.Zone.DISCARD
	ps.discard.append(rat)
	EffectContext.new(eng, me).rummage(1)
	assert_bool(ps.board.has(rat)).is_true()
	assert_bool(ps.hand.has(rat)).is_false()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/raccoon/test_rat.gd`
Expected: FAIL (Rat resolves to DefaultCard; stays in hand).

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/raccoon/rat.gd
class_name Rat
extends CardScript

func reacts_to() -> Array: return [Enums.EventType.CARD_RUMMAGED]
func active_zones() -> Array: return [Enums.Zone.HAND]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("instance", -1) != card.instance_id:
		return
	if not ctx.hand(ctx.me()).has(card):
		return
	ctx.summon_free(card)
```

In `src/cards/card_script_registry.gd`, in `_build()`, add:

```gdscript
	_register("raccoon", 2, Rat.new())
	_register("raccoon", 3, Rat.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/raccoon/rat.gd src/cards/card_script_registry.gd tests/cards/raccoon/test_rat.gd
git commit -m "feat(raccoon): Rat plays free when rummaged"
```

---

## Task 4: Opossum (ids 4, 5)

**Files:**
- Create: `src/cards/scripts/raccoon/opossum.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/raccoon/test_opossum.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/raccoon/test_opossum.gd
extends RaccoonTestBase

func test_opossum_rummages_three_on_cast() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	seed_discard(eng, me, 4)
	ps.tickets_total = 20
	var op := eng.state.make_instance(raccoon_def(4))
	op.zone = Enums.Zone.HAND
	ps.hand.append(op)
	var hand_before := ps.hand.size()
	eng.apply(Action.play_card(op.instance_id))
	# 3 cards rummaged into hand; opossum itself left hand to the board
	assert_int(ps.hand.size()).is_equal(hand_before - 1 + 3)
	assert_int(ps.discard.size()).is_equal(1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/raccoon/test_opossum.gd`
Expected: FAIL (no rummage happens).

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/raccoon/opossum.gd
class_name Opossum
extends CardScript

func on_cast(_card: CardInstance, ctx: EffectContext) -> void:
	ctx.rummage(3)
```

In `_build()`:

```gdscript
	_register("raccoon", 4, Opossum.new())
	_register("raccoon", 5, Opossum.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/raccoon/opossum.gd src/cards/card_script_registry.gd tests/cards/raccoon/test_opossum.gd
git commit -m "feat(raccoon): Opossum rummages 3 on cast"
```

---

## Task 5: Coyote (ids 8, 9)

**Files:**
- Create: `src/cards/scripts/raccoon/coyote.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/raccoon/test_coyote.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/raccoon/test_coyote.gd
extends RaccoonTestBase

func test_coyote_adds_one_extra_card_per_rummage() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	seed_discard(eng, me, 6)
	place_on_board(eng, me, raccoon_def(8))
	eng.state.players[me].discard  # ensure ref
	EffectContext.new(eng, me).rummage(2)  # 2 + 1 bonus = 3
	assert_int(eng.state.players[me].discard.size()).is_equal(3)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/raccoon/test_coyote.gd`
Expected: FAIL (no bonus; discard size 4).

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/raccoon/coyote.gd
class_name Coyote
extends CardScript

func on_cast(_card: CardInstance, ctx: EffectContext) -> void:
	ctx.rummage(3)

func rummage_bonus(_card: CardInstance, _ctx) -> int:
	return 1
```

In `_build()`:

```gdscript
	_register("raccoon", 8, Coyote.new())
	_register("raccoon", 9, Coyote.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/raccoon/coyote.gd src/cards/card_script_registry.gd tests/cards/raccoon/test_coyote.gd
git commit -m "feat(raccoon): Coyote rummages 3 + grants rummage bonus"
```

---

## Task 6: Trash Cannon (ids 10, 11)

**Files:**
- Create: `src/cards/scripts/raccoon/trash_cannon.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/raccoon/test_trash_cannon.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/raccoon/test_trash_cannon.gd
extends RaccoonTestBase

func test_trash_cannon_deals_two_deck_damage_per_rummage_instance() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	seed_discard(eng, me, 2)
	place_on_board(eng, me, raccoon_def(10))
	var opp_deck_before := eng.state.players[opp].deck.size()
	EffectContext.new(eng, me).rummage(1)
	assert_int(eng.state.players[opp].deck.size()).is_equal(opp_deck_before - 2)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/raccoon/test_trash_cannon.gd`
Expected: FAIL (opponent deck unchanged).

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/raccoon/trash_cannon.gd
class_name TrashCannon
extends CardScript

func reacts_to() -> Array: return [Enums.EventType.RUMMAGE_PERFORMED]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(_card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("player", -1) != ctx.me():
		return
	ctx.deal_deck_damage(ctx.opponent(), 2)
```

In `_build()`:

```gdscript
	_register("raccoon", 10, TrashCannon.new())
	_register("raccoon", 11, TrashCannon.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/raccoon/trash_cannon.gd src/cards/card_script_registry.gd tests/cards/raccoon/test_trash_cannon.gd
git commit -m "feat(raccoon): Trash Cannon deals deck damage per rummage instance"
```

---

## Task 7: Skunk (ids 6, 7)

**Files:**
- Create: `src/cards/scripts/raccoon/skunk.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/raccoon/test_skunk.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/raccoon/test_skunk.gd
extends RaccoonTestBase

func test_skunk_zeroes_opponent_damage_on_first_rummage() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	seed_discard(eng, me, 4)
	place_on_board(eng, me, raccoon_def(6))
	var victim := place_on_board(eng, opp, TestFactory.minion(3, 5, 5, 1))
	EffectContext.new(eng, me).rummage(1)
	# Skunk asks which opponent unit to silence
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_target")
	eng.apply(Action.resolve_choice({"target_ids": [victim.instance_id]}))
	assert_int(victim.current_damage).is_equal(0)

func test_skunk_only_first_rummage_each_turn() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	seed_discard(eng, me, 6)
	place_on_board(eng, me, raccoon_def(6))
	place_on_board(eng, opp, TestFactory.minion(3, 5, 5, 1))
	var ctx := EffectContext.new(eng, me)
	ctx.rummage(1)
	eng.apply(Action.resolve_choice({"target_ids": []}))  # decline first
	ctx.rummage(1)  # second rummage this turn -> no prompt
	assert_bool(eng.state.pending_choice == null).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/raccoon/test_skunk.gd`
Expected: FAIL (no prompt).

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/raccoon/skunk.gd
class_name Skunk
extends CardScript

func reacts_to() -> Array: return [Enums.EventType.RUMMAGE_PERFORMED]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("player", -1) != ctx.me():
		return
	if ctx.counters(ctx.me())["rummages_made"] != 1:
		return
	var targets: Array = ctx.board(ctx.opponent())
	if targets.is_empty():
		return
	ctx.request_choice(card,
		ChoiceSpec.select_target(targets.duplicate(), 0, 1, "Set an opponent Unit's Damage to 0"),
		"skunk")

func resume(_card: CardInstance, tag: String, result: Dictionary, _ctx: EffectContext) -> void:
	if tag == "skunk" and not result["targets"].is_empty():
		result["targets"][0].current_damage = 0
```

In `_build()`:

```gdscript
	_register("raccoon", 6, Skunk.new())
	_register("raccoon", 7, Skunk.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/raccoon/skunk.gd src/cards/card_script_registry.gd tests/cards/raccoon/test_skunk.gd
git commit -m "feat(raccoon): Skunk zeroes an opponent's damage on first rummage each turn"
```

---

## Task 8: Trashalanche (ids 16, 17)

**Files:**
- Create: `src/cards/scripts/raccoon/trashalanche.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/raccoon/test_trashalanche.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/raccoon/test_trashalanche.gd
extends RaccoonTestBase

func test_trashalanche_damages_all_units_by_discard_size() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	seed_discard(eng, me, 3)  # discard size 3
	var a := place_on_board(eng, me, TestFactory.minion(1, 1, 5, 1))
	var b := place_on_board(eng, opp, TestFactory.minion(1, 1, 5, 2))
	var spell := eng.state.make_instance(raccoon_def(16))
	eng.state.players[me].hand.append(spell)
	eng.state.players[me].tickets_total = 20
	eng.apply(Action.play_card(spell.instance_id))
	assert_int(a.current_health).is_equal(2)
	assert_int(b.current_health).is_equal(2)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/raccoon/test_trashalanche.gd`
Expected: FAIL (units undamaged).

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/raccoon/trashalanche.gd
class_name Trashalanche
extends CardScript

func on_cast(_card: CardInstance, ctx: EffectContext) -> void:
	var n := ctx.discard_pile(ctx.me()).size()
	if n <= 0:
		return
	var victims: Array = []
	for pidx in [ctx.me(), ctx.opponent()]:
		for u in ctx.board(pidx):
			victims.append(u)
	for v in victims:
		ctx.deal_damage(v, n)
```

In `_build()`:

```gdscript
	_register("raccoon", 16, Trashalanche.new())
	_register("raccoon", 17, Trashalanche.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/raccoon/trashalanche.gd src/cards/card_script_registry.gd tests/cards/raccoon/test_trashalanche.gd
git commit -m "feat(raccoon): Trashalanche damages all units by discard size"
```

---

## Task 9: Trash to Treasure (ids 14, 15)

**Files:**
- Create: `src/cards/scripts/raccoon/trash_to_treasure.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/raccoon/test_trash_to_treasure.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/raccoon/test_trash_to_treasure.gd
extends RaccoonTestBase

func test_rummages_two_then_puts_two_hand_cards_to_deck_bottom() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	ps.hand.clear()
	seed_discard(eng, me, 3)
	var h1 := eng.state.make_instance(TestFactory.minion(1, 1, 1, 10))
	var h2 := eng.state.make_instance(TestFactory.minion(1, 1, 1, 11))
	h1.zone = Enums.Zone.HAND; h2.zone = Enums.Zone.HAND
	ps.hand.append(h1); ps.hand.append(h2)
	var spell := eng.state.make_instance(raccoon_def(14))
	ps.hand.append(spell)
	ps.tickets_total = 20
	eng.apply(Action.play_card(spell.instance_id))
	# rummaged 2 into hand; now asked to pick 2 to send to deck bottom
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_cards")
	var i1 := ps.hand.find(h1)
	var i2 := ps.hand.find(h2)
	eng.apply(Action.resolve_choice({"indices": [i1, i2]}))
	assert_bool(ps.deck.has(h1) and ps.deck.has(h2)).is_true()
	assert_bool(ps.hand.has(h1) or ps.hand.has(h2)).is_false()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/raccoon/test_trash_to_treasure.gd`
Expected: FAIL (no choice / no rummage).

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/raccoon/trash_to_treasure.gd
class_name TrashToTreasure
extends CardScript

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	ctx.rummage(2)
	var hand := ctx.hand(ctx.me())
	if hand.is_empty():
		return
	var n: int = min(2, hand.size())
	ctx.request_choice(card,
		ChoiceSpec.select_cards(hand.duplicate(), n, n, "Put 2 cards on the bottom of your Deck"),
		"ttt")

func resume(_card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "ttt":
		for c in result["cards"]:
			ctx.to_deck_bottom(c)
```

In `_build()`:

```gdscript
	_register("raccoon", 14, TrashToTreasure.new())
	_register("raccoon", 15, TrashToTreasure.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/raccoon/trash_to_treasure.gd src/cards/card_script_registry.gd tests/cards/raccoon/test_trash_to_treasure.gd
git commit -m "feat(raccoon): Trash to Treasure rummages then bottom-decks two cards"
```

---

## Task 10: Trash Day (ids 12, 13)

**Files:**
- Create: `src/cards/scripts/raccoon/trash_day.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/raccoon/test_trash_day.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/raccoon/test_trash_day.gd
extends RaccoonTestBase

func test_trash_day_mills_then_damages_unit() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var ps := eng.state.players[me]
	var target := place_on_board(eng, opp, TestFactory.minion(1, 1, 5, 1))
	var spell := eng.state.make_instance(raccoon_def(12))
	ps.hand.append(spell)
	ps.tickets_total = 20
	var deck_before := ps.deck.size()
	eng.apply(Action.play_card(spell.instance_id))
	# choose how many to discard from own deck
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("choose_option")
	eng.apply(Action.resolve_choice({"option": 3}))  # discard 3
	assert_int(ps.deck.size()).is_equal(deck_before - 3)
	# now pick a unit to damage by 3
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_target")
	eng.apply(Action.resolve_choice({"target_ids": [target.instance_id]}))
	assert_int(target.current_health).is_equal(2)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/raccoon/test_trash_day.gd`
Expected: FAIL (no choice).

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/raccoon/trash_day.gd
class_name TrashDay
extends CardScript

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	ctx.request_choice(card,
		ChoiceSpec.choose_option(["0", "1", "2", "3"], "Discard how many from your Deck?"),
		"td_count")

func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "td_count":
		var n: int = result["option"]
		var actual: int = min(n, ctx.gs().players[ctx.me()].deck.size())
		if actual <= 0:
			return
		ctx.mill(ctx.me(), actual)
		card.vars["td_amount"] = actual
		var units: Array = []
		for pidx in [ctx.me(), ctx.opponent()]:
			for u in ctx.board(pidx):
				units.append(u)
		if units.is_empty():
			return
		ctx.request_choice(card,
			ChoiceSpec.select_target(units, 1, 1, "Deal %d damage to a Unit" % actual),
			"td_dmg")
	elif tag == "td_dmg" and not result["targets"].is_empty():
		ctx.deal_damage(result["targets"][0], int(card.vars.get("td_amount", 0)))
```

In `_build()`:

```gdscript
	_register("raccoon", 12, TrashDay.new())
	_register("raccoon", 13, TrashDay.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/raccoon/trash_day.gd src/cards/card_script_registry.gd tests/cards/raccoon/test_trash_day.gd
git commit -m "feat(raccoon): Trash Day discards from deck to damage a unit"
```

---

## Task 11: Garbage Guard (ids 18, 19)

**Files:**
- Create: `src/cards/scripts/raccoon/garbage_guard.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/raccoon/test_garbage_guard.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/raccoon/test_garbage_guard.gd
extends RaccoonTestBase

func test_garbage_guard_negates_deck_damage_and_rummages_that_many() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	seed_discard(eng, me, 5)
	var trap := eng.state.make_instance(raccoon_def(18))
	trap.zone = Enums.Zone.TRAP_SET
	ps.set_traps.append(trap)
	var deck_before := ps.deck.size()
	var disc_before := ps.discard.size()
	eng._deck_damage(me, 3)
	assert_str(eng.state.pending_choice.kind).is_equal("intercept")
	eng.apply(Action.resolve_choice({"option": 0}))  # Fire
	# no deck loss, and 3 cards rummaged out of discard into hand
	assert_int(ps.deck.size()).is_equal(deck_before)
	assert_int(ps.discard.size()).is_equal(disc_before - 3)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/raccoon/test_garbage_guard.gd`
Expected: FAIL (no interception).

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/raccoon/garbage_guard.gd
class_name GarbageGuard
extends CardScript

func active_zones() -> Array: return [Enums.Zone.TRAP_SET]

func can_intercept_deck_damage(_card: CardInstance, _player: int, _amount: int, _ctx) -> bool:
	return true

func deck_damage_on_fire(_card: CardInstance, _player: int, amount: int, ctx: EffectContext) -> int:
	ctx.rummage(amount)
	return 0
```

In `_build()`:

```gdscript
	_register("raccoon", 18, GarbageGuard.new())
	_register("raccoon", 19, GarbageGuard.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/raccoon/garbage_guard.gd src/cards/card_script_registry.gd tests/cards/raccoon/test_garbage_guard.gd
git commit -m "feat(raccoon): Garbage Guard negates deck damage and rummages"
```

---

## Task 12: Safety Net (ids 20, 21)

**Files:**
- Create: `src/cards/scripts/raccoon/safety_net.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/raccoon/test_safety_net.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/raccoon/test_safety_net.gd
extends RaccoonTestBase

func test_safety_net_redirects_killed_ally_to_discard_bottom() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	var filler := eng.state.make_instance(TestFactory.minion(1, 1, 1, 99))
	filler.zone = Enums.Zone.DISCARD
	ps.discard.append(filler)
	var trap := eng.state.make_instance(raccoon_def(20))
	trap.zone = Enums.Zone.TRAP_SET
	ps.set_traps.append(trap)
	var u := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 1))
	eng._kill(me, u, "effect")
	assert_str(eng.state.pending_choice.kind).is_equal("intercept")
	eng.apply(Action.resolve_choice({"option": 0}))  # Fire
	assert_object(ps.discard.front()).is_same(u)  # bottom = front
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/raccoon/test_safety_net.gd`
Expected: FAIL (no interception; u at back).

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/raccoon/safety_net.gd
class_name SafetyNet
extends CardScript

func active_zones() -> Array: return [Enums.Zone.TRAP_SET]

func can_intercept_kill(_card: CardInstance, _dying: CardInstance, _reason: String, _ctx) -> bool:
	return true

func kill_on_fire(_card: CardInstance, dying: CardInstance, _ctx) -> bool:
	dying.vars["discard_to_bottom"] = true
	return false  # let the kill proceed, redirected to the bottom
```

In `_build()`:

```gdscript
	_register("raccoon", 20, SafetyNet.new())
	_register("raccoon", 21, SafetyNet.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/raccoon/safety_net.gd src/cards/card_script_registry.gd tests/cards/raccoon/test_safety_net.gd
git commit -m "feat(raccoon): Safety Net redirects a killed ally to the discard bottom"
```

---

## Task 13: Raccoon (Leader, id 1)

**Files:**
- Create: `src/cards/scripts/raccoon/raccoon_leader.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/raccoon/test_raccoon_leader.gd`

The leader has three behaviors (Rulings §6.8): (a) **on board** — an activated ability "discard any number of hand cards, deal that many damage to a Unit", once per turn; (b) **while in discard** — RUMMAGE 2 at the start of your turn; (c) returns to hand on reshuffle (via the Task 2 hook).

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/raccoon/test_raccoon_leader.gd
extends RaccoonTestBase

func test_rummages_two_at_turn_start_while_in_discard() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	seed_discard(eng, me, 4)
	var leader := eng.state.make_instance(raccoon_def(1))
	leader.zone = Enums.Zone.DISCARD
	ps.discard.append(leader)
	var disc_before := ps.discard.size()
	eng.emit(GameEvent.new(Enums.EventType.TURN_STARTED, {"player": me}))
	# 2 cards rummaged out of discard (one of which could be the leader itself is excluded since it's a leader card in discard - still counts as a card)
	assert_int(ps.discard.size()).is_equal(disc_before - 2)

func test_activated_ability_discards_to_damage_unit() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var ps := eng.state.players[me]
	var leader := place_on_board(eng, me, raccoon_def(1))
	var c1 := eng.state.make_instance(TestFactory.minion(1, 1, 1, 10))
	var c2 := eng.state.make_instance(TestFactory.minion(1, 1, 1, 11))
	c1.zone = Enums.Zone.HAND; c2.zone = Enums.Zone.HAND
	ps.hand.append(c1); ps.hand.append(c2)
	var target := place_on_board(eng, opp, TestFactory.minion(1, 1, 5, 1))
	eng.apply(Action.activate_ability(leader.instance_id, "raccoon_throw"))
	# choose which hand cards to discard
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_cards")
	eng.apply(Action.resolve_choice({"indices": [ps.hand.find(c1), ps.hand.find(c2)]}))
	# then choose a target
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_target")
	eng.apply(Action.resolve_choice({"target_ids": [target.instance_id]}))
	assert_int(target.current_health).is_equal(3)  # 5 - 2 discarded
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/raccoon/test_raccoon_leader.gd`
Expected: FAIL (no rummage / no ability).

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/raccoon/raccoon_leader.gd
class_name RaccoonLeader
extends CardScript

func returns_on_reshuffle() -> bool: return true

func reacts_to() -> Array: return [Enums.EventType.TURN_STARTED]
func active_zones() -> Array: return [Enums.Zone.DISCARD]

func react(_card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("player", -1) != ctx.me():
		return
	ctx.rummage(2)

func activated_abilities(card: CardInstance, ctx: EffectContext) -> Array:
	if card.zone != Enums.Zone.BOARD:
		return []
	if card.vars.get("opt_used_this_turn", false):
		return []
	if ctx.hand(ctx.me()).is_empty():
		return []
	return [{"id": "raccoon_throw", "label": "Discard cards to deal damage"}]

func activate(card: CardInstance, ability_id: String, ctx: EffectContext) -> void:
	if ability_id != "raccoon_throw":
		return
	card.vars["opt_used_this_turn"] = true
	var hand := ctx.hand(ctx.me())
	ctx.request_choice(card,
		ChoiceSpec.select_cards(hand.duplicate(), 0, hand.size(), "Discard any number of cards"),
		"rac_discard")

func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "rac_discard":
		var chosen: Array = result["cards"]
		for c in chosen:
			ctx.discard_from_hand(c)
		if chosen.is_empty():
			return
		card.vars["rac_amount"] = chosen.size()
		var units: Array = []
		for pidx in [ctx.me(), ctx.opponent()]:
			for u in ctx.board(pidx):
				units.append(u)
		if units.is_empty():
			return
		ctx.request_choice(card,
			ChoiceSpec.select_target(units, 1, 1, "Deal %d damage to a Unit" % chosen.size()),
			"rac_target")
	elif tag == "rac_target" and not result["targets"].is_empty():
		ctx.deal_damage(result["targets"][0], int(card.vars.get("rac_amount", 0)))
```

In `_build()`:

```gdscript
	_register("raccoon", 1, RaccoonLeader.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/raccoon/raccoon_leader.gd src/cards/card_script_registry.gd tests/cards/raccoon/test_raccoon_leader.gd
git commit -m "feat(raccoon): Raccoon leader (rummage-in-discard + discard-to-damage ability)"
```

---

## Task 14: Registry + load verification

**Files:**
- Test: `tests/cards/raccoon/test_raccoon_registry.gd`

- [ ] **Step 1: Write the test**

```gdscript
# tests/cards/raccoon/test_raccoon_registry.gd
extends RaccoonTestBase

func test_every_raccoon_id_resolves_to_a_non_default_script() -> void:
	var default := DefaultCard.new()
	for d in CardDatabase.load_deck("res://src/data/decks/raccoon.csv", "raccoon"):
		var s := CardScriptRegistry.get_script_for("raccoon", d.id)
		assert_bool(s.get_script() == default.get_script()).override_failure_message(
			"raccoon id %d has no script" % d.id).is_false()
```

- [ ] **Step 2: Run it**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/raccoon/test_raccoon_registry.gd`
Expected: PASS (all ids 1–21 registered across Tasks 3–13).

- [ ] **Step 3: Full regression**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add tests/cards/raccoon/test_raccoon_registry.gd
git commit -m "test(raccoon): every card id resolves to a script"
```

---

## Self-Review Notes (coverage vs spec §5.1)

All 11 unique cards covered: Raccoon leader (Task 13), Rat (3), Opossum (4), Skunk (7), Coyote (5), Trash Cannon (6), Trash Day (10), Trash to Treasure (9), Trashalanche (8), Garbage Guard (11), Safety Net (12). Foundation hook `returns_on_reshuffle` added in Task 2. Registry coverage asserted in Task 14.
