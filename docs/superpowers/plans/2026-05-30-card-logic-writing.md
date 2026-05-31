# Writing Deck Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement all 12 unique Writing-deck card scripts (TRASH / ORANGE) as pure-GDScript `CardScript`s with per-card GdUnit4 tests.

**Architecture:** One `CardScript` per unique card in `src/cards/scripts/writing/`, registered by `writing:<id>`. Cards use the Foundation plan's `trash()`, `gain_orange()`, interception hooks (`can_intercept_*`, `kill_on_fire`, `deck_damage_on_fire`), and trash-replacement hooks (`trash_replacement_for`, `apply_trash_replacement`). The Orange token itself (id 100) is delivered by the Foundation plan. **Requires the Foundation plan complete.**

**Tech Stack:** Godot 4 / GDScript; GdUnit4 tests.

**Run a suite (headless):**
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/writing/<suite>.gd
```

**Card id → script map (`src/data/decks/writing.csv`):** 1 Shelley (Leader); 2,3 Melon Zombie Hulk; 4,5 Citrus Werewolf; 6 Avatar of the Ancient Evil; 7,8 Cultist of the Ancient Evil; 9,10 Melon Zombie Warlock; 11,12 Melon Zombie; 13,14 Mercenary Trader; 15,16 Citrus Sacrifice; 17 Pain Split (the CSV lists id 17 twice and has no id 18 — one script); 19,20 Ancient One's Protection; 21 Offering.

**Key rule reminders (spec §6):** "damage the opponent" = dealing **deck** damage (deck attack → `UNIT_ATTACKED` with `target_unit == -1`). Trash replacements are presented as an interactive menu. Ancient One's Protection only intercepts **battle** kills.

---

## File Structure

- `tests/cards/writing/writing_test_base.gd` — test helper.
- `src/cards/scripts/writing/<card>.gd` — one per unique card.
- `src/cards/card_script_registry.gd` — register writing ids.

---

## Task 1: Writing test base

**Files:**
- Create: `tests/cards/writing/writing_test_base.gd`

- [ ] **Step 1: Create the helper**

```gdscript
# tests/cards/writing/writing_test_base.gd
class_name WritingTestBase
extends CardTestBase

func writing_def(id: int) -> CardDefinition:
	for d in CardDatabase.load_deck("res://src/data/decks/writing.csv", "writing"):
		if d.id == id:
			return d
	return null

func oranges_in_hand(eng: GameEngine, p: int) -> int:
	var n := 0
	for c in eng.state.players[p].hand:
		if OrangeToken.is_orange(c):
			n += 1
	return n
```

- [ ] **Step 2: Sanity-run an existing suite**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_registry.gd`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/cards/writing/writing_test_base.gd
git commit -m "test(writing): shared test base"
```

---

## Task 2: Mercenary Trader (ids 13, 14)

**Files:**
- Create: `src/cards/scripts/writing/mercenary_trader.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/writing/test_mercenary_trader.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/writing/test_mercenary_trader.gd
extends WritingTestBase

func test_gains_orange_when_trashed() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var merc := place_on_board(eng, me, writing_def(13))
	var before := oranges_in_hand(eng, me)
	EffectContext.new(eng, me).trash(merc)
	assert_int(oranges_in_hand(eng, me)).is_equal(before + 1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/writing/test_mercenary_trader.gd`
Expected: FAIL.

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/writing/mercenary_trader.gd
class_name MercenaryTrader
extends CardScript

func reacts_to() -> Array: return [Enums.EventType.UNIT_TRASHED]
func active_zones() -> Array: return [Enums.Zone.BOARD, Enums.Zone.DISCARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("instance", -1) == card.instance_id:
		ctx.gain_orange(ctx.me())
```

In `_build()`:

```gdscript
	_register("writing", 13, MercenaryTrader.new())
	_register("writing", 14, MercenaryTrader.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/writing/mercenary_trader.gd src/cards/card_script_registry.gd tests/cards/writing/test_mercenary_trader.gd
git commit -m "feat(writing): Mercenary Trader gains an Orange when trashed"
```

---

## Task 3: Citrus Sacrifice (ids 15, 16)

**Files:**
- Create: `src/cards/scripts/writing/citrus_sacrifice.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/writing/test_citrus_sacrifice.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/writing/test_citrus_sacrifice.gd
extends WritingTestBase

func test_gains_one_orange_per_discard_card_capped_at_five() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	for i in range(7):
		var c := eng.state.make_instance(TestFactory.minion(1, 1, 1, 600 + i))
		c.zone = Enums.Zone.DISCARD
		ps.discard.append(c)
	var spell := eng.state.make_instance(writing_def(15))
	ps.hand.append(spell)
	ps.tickets_total = 20
	eng.apply(Action.play_card(spell.instance_id))
	assert_int(oranges_in_hand(eng, me)).is_equal(5)  # capped
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/writing/test_citrus_sacrifice.gd`
Expected: FAIL.

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/writing/citrus_sacrifice.gd
class_name CitrusSacrifice
extends CardScript

func on_cast(_card: CardInstance, ctx: EffectContext) -> void:
	var n := ctx.discard_pile(ctx.me()).size()
	for i in range(n):
		ctx.gain_orange(ctx.me())
```

In `_build()`:

```gdscript
	_register("writing", 15, CitrusSacrifice.new())
	_register("writing", 16, CitrusSacrifice.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/writing/citrus_sacrifice.gd src/cards/card_script_registry.gd tests/cards/writing/test_citrus_sacrifice.gd
git commit -m "feat(writing): Citrus Sacrifice mints Oranges per discard card"
```

---

## Task 4: Citrus Werewolf (ids 4, 5)

**Files:**
- Create: `src/cards/scripts/writing/citrus_werewolf.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/writing/test_citrus_werewolf.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/writing/test_citrus_werewolf.gd
extends WritingTestBase

func test_gains_orange_on_dealing_deck_damage() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var wolf := place_on_board(eng, me, writing_def(4))
	wolf.tapped = false
	var before := oranges_in_hand(eng, me)
	eng.apply(Action.declare_attack(wolf.instance_id, {"deck": true}))
	assert_int(oranges_in_hand(eng, me)).is_equal(before + 1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/writing/test_citrus_werewolf.gd`
Expected: FAIL.

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/writing/citrus_werewolf.gd
class_name CitrusWerewolf
extends CardScript

func reacts_to() -> Array: return [Enums.EventType.UNIT_ATTACKED]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("attacker", -1) != card.instance_id:
		return
	if event.data.get("target_unit", -1) != -1:
		return  # only a deck attack = "damaging the opponent"
	ctx.gain_orange(ctx.me())
```

In `_build()`:

```gdscript
	_register("writing", 4, CitrusWerewolf.new())
	_register("writing", 5, CitrusWerewolf.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/writing/citrus_werewolf.gd src/cards/card_script_registry.gd tests/cards/writing/test_citrus_werewolf.gd
git commit -m "feat(writing): Citrus Werewolf gains an Orange on deck damage"
```

---

## Task 5: Melon Zombie (ids 11, 12) — self-return trash replacement

**Files:**
- Create: `src/cards/scripts/writing/melon_zombie.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/writing/test_melon_zombie.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/writing/test_melon_zombie.gd
extends WritingTestBase

func test_may_return_to_hand_when_trashed() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var z := place_on_board(eng, me, writing_def(11))
	EffectContext.new(eng, me).trash(z)
	# replacement menu: option 0 = "Return to hand", last = "Just KO it"
	assert_str(eng.state.pending_choice.kind).is_equal("trash_choice")
	eng.apply(Action.resolve_choice({"option": 0}))
	assert_bool(eng.state.players[me].hand.has(z)).is_true()
	assert_bool(eng.state.players[me].discard.has(z)).is_false()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/writing/test_melon_zombie.gd`
Expected: FAIL.

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/writing/melon_zombie.gd
class_name MelonZombie
extends CardScript

func trash_replacement_for(card: CardInstance, target: CardInstance, _ctx) -> String:
	return "Return to hand" if card == target else ""

func apply_trash_replacement(_card: CardInstance, target: CardInstance, ctx: EffectContext) -> void:
	var ps := ctx.gs().players[ctx.me()]
	ps.board.erase(target)
	target.reset_stats()
	target.zone = Enums.Zone.HAND
	ps.hand.append(target)
```

In `_build()`:

```gdscript
	_register("writing", 11, MelonZombie.new())
	_register("writing", 12, MelonZombie.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/writing/melon_zombie.gd src/cards/card_script_registry.gd tests/cards/writing/test_melon_zombie.gd
git commit -m "feat(writing): Melon Zombie returns to hand when trashed"
```

---

## Task 6: Melon Zombie Warlock (ids 9, 10) — replay trash replacement

**Files:**
- Create: `src/cards/scripts/writing/melon_zombie_warlock.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/writing/test_melon_zombie_warlock.gd`

Ruling: "replay it for its cost +1" keeps the minion on the board and charges its owner `ticket_cost + 1`.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/writing/test_melon_zombie_warlock.gd
extends WritingTestBase

func test_replay_keeps_minion_and_charges_cost_plus_one() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	ps.tickets_total = 20
	ps.tickets_tapped = 0
	place_on_board(eng, me, writing_def(9))  # Warlock provides the replacement
	var minion := place_on_board(eng, me, TestFactory.minion(3, 2, 2, 1))
	EffectContext.new(eng, me).trash(minion)
	# menu: option 0 = "Replay for cost +1", last = "Just KO it"
	assert_str(eng.state.pending_choice.kind).is_equal("trash_choice")
	eng.apply(Action.resolve_choice({"option": 0}))
	assert_bool(ps.board.has(minion)).is_true()      # stayed on board
	assert_int(ps.tickets_tapped).is_equal(4)         # 3 + 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/writing/test_melon_zombie_warlock.gd`
Expected: FAIL.

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/writing/melon_zombie_warlock.gd
class_name MelonZombieWarlock
extends CardScript

func trash_replacement_for(card: CardInstance, target: CardInstance, ctx: EffectContext) -> String:
	if card == target:
		return ""
	if card.zone != Enums.Zone.BOARD:
		return ""
	if target.definition.type != Enums.CardType.MINION:
		return ""
	return "Replay for cost +1"

func apply_trash_replacement(_card: CardInstance, target: CardInstance, ctx: EffectContext) -> void:
	var ps := ctx.gs().players[ctx.me()]
	ps.tickets_tapped += target.definition.ticket_cost + 1
	target.reset_stats()
```

In `_build()`:

```gdscript
	_register("writing", 9, MelonZombieWarlock.new())
	_register("writing", 10, MelonZombieWarlock.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/writing/melon_zombie_warlock.gd src/cards/card_script_registry.gd tests/cards/writing/test_melon_zombie_warlock.gd
git commit -m "feat(writing): Melon Zombie Warlock replays a trashed minion for cost+1"
```

---

## Task 7: Shelley, Live-Action Roleplayer (Leader, id 1)

**Files:**
- Create: `src/cards/scripts/writing/shelley.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/writing/test_shelley.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/writing/test_shelley.gd
extends WritingTestBase

func test_shelley_can_send_trashed_unit_to_deck_bottom() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	var shelley := place_on_board(eng, me, writing_def(1))
	var victim := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 1))
	EffectContext.new(eng, me).trash(victim)
	# menu: option 0 = "Send to bottom of Deck"
	assert_str(eng.state.pending_choice.kind).is_equal("trash_choice")
	eng.apply(Action.resolve_choice({"option": 0}))
	assert_bool(ps.deck.has(victim)).is_true()
	assert_bool(ps.discard.has(victim)).is_false()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/writing/test_shelley.gd`
Expected: FAIL.

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/writing/shelley.gd
class_name Shelley
extends CardScript

func trash_replacement_for(card: CardInstance, _target: CardInstance, _ctx) -> String:
	if card.zone != Enums.Zone.BOARD:
		return ""
	return "Send to bottom of Deck"

func apply_trash_replacement(_card: CardInstance, target: CardInstance, ctx: EffectContext) -> void:
	ctx.to_deck_bottom(target)
```

In `_build()`:

```gdscript
	_register("writing", 1, Shelley.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/writing/shelley.gd src/cards/card_script_registry.gd tests/cards/writing/test_shelley.gd
git commit -m "feat(writing): Shelley sends trashed units to the deck bottom"
```

---

## Task 8: Melon Zombie Hulk (ids 2, 3)

**Files:**
- Create: `src/cards/scripts/writing/melon_zombie_hulk.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/writing/test_melon_zombie_hulk.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/writing/test_melon_zombie_hulk.gd
extends WritingTestBase

func test_hulk_trashes_a_chosen_ally_on_attack() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var hulk := place_on_board(eng, me, writing_def(2))
	hulk.tapped = false
	var ally := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 1))
	eng.apply(Action.declare_attack(hulk.instance_id, {"deck": true}))
	# Hulk asks which ally to trash
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_target")
	eng.apply(Action.resolve_choice({"target_ids": [ally.instance_id]}))
	assert_bool(eng.state.players[me].discard.has(ally)).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/writing/test_melon_zombie_hulk.gd`
Expected: FAIL.

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/writing/melon_zombie_hulk.gd
class_name MelonZombieHulk
extends CardScript

func reacts_to() -> Array: return [Enums.EventType.UNIT_ATTACKED]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("attacker", -1) != card.instance_id:
		return
	var allies: Array = ctx.board(ctx.me())
	if allies.is_empty():
		return
	ctx.request_choice(card,
		ChoiceSpec.select_target(allies.duplicate(), 1, 1, "TRASH a Unit"), "hulk")

func resume(_card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "hulk" and not result["targets"].is_empty():
		ctx.trash(result["targets"][0])
```

In `_build()`:

```gdscript
	_register("writing", 2, MelonZombieHulk.new())
	_register("writing", 3, MelonZombieHulk.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/writing/melon_zombie_hulk.gd src/cards/card_script_registry.gd tests/cards/writing/test_melon_zombie_hulk.gd
git commit -m "feat(writing): Melon Zombie Hulk trashes a unit on attack"
```

---

## Task 9: Cultist of the Ancient Evil (ids 7, 8)

**Files:**
- Create: `src/cards/scripts/writing/cultist.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/writing/test_cultist.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/writing/test_cultist.gd
extends WritingTestBase

func test_cultist_trashes_self_to_return_a_discard_card() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	var buried := eng.state.make_instance(TestFactory.minion(1, 1, 1, 50))
	buried.zone = Enums.Zone.DISCARD
	ps.discard.append(buried)
	var cultist := place_on_board(eng, me, writing_def(7))
	cultist.tapped = false
	eng.apply(Action.declare_attack(cultist.instance_id, {"deck": true}))
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_cards")
	eng.apply(Action.resolve_choice({"indices": [0]}))  # return the buried card
	assert_bool(ps.hand.has(buried)).is_true()
	assert_bool(ps.discard.has(cultist)).is_true()      # cultist trashed itself
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/writing/test_cultist.gd`
Expected: FAIL.

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/writing/cultist.gd
class_name Cultist
extends CardScript

func reacts_to() -> Array: return [Enums.EventType.UNIT_ATTACKED]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("attacker", -1) != card.instance_id:
		return
	if event.data.get("target_unit", -1) != -1:
		return  # only deck damage
	var disc := ctx.discard_pile(ctx.me())
	if disc.is_empty():
		return
	ctx.request_choice(card,
		ChoiceSpec.select_cards(disc.duplicate(), 0, 1, "Trash Cultist to return a card?"),
		"cultist")

func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "cultist" and not result["cards"].is_empty():
		var c: CardInstance = result["cards"][0]
		ctx.gs().players[ctx.me()].discard.erase(c)
		c.zone = Enums.Zone.HAND
		ctx.gs().players[ctx.me()].hand.append(c)
		ctx.trash(card)
```

In `_build()`:

```gdscript
	_register("writing", 7, Cultist.new())
	_register("writing", 8, Cultist.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/writing/cultist.gd src/cards/card_script_registry.gd tests/cards/writing/test_cultist.gd
git commit -m "feat(writing): Cultist trashes self to recur a discard card on deck damage"
```

---

## Task 10: Pain Split (id 17)

**Files:**
- Create: `src/cards/scripts/writing/pain_split.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/writing/test_pain_split.gd`

Implementation note: gather BOTH targets via sequential choices first, then deal damage and trash **last** (so the trash's own replacement menu, if any, does not collide with this card's pending choices).

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/writing/test_pain_split.gd
extends WritingTestBase

func test_pain_split_trashes_one_and_damages_another() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var ps := eng.state.players[me]
	var sacrifice := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 1))
	var enemy := place_on_board(eng, opp, TestFactory.minion(1, 1, 9, 2))
	var spell := eng.state.make_instance(writing_def(17))
	ps.hand.append(spell)
	ps.tickets_total = 20
	eng.apply(Action.play_card(spell.instance_id))
	# 1) pick the ally to TRASH
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_target")
	eng.apply(Action.resolve_choice({"target_ids": [sacrifice.instance_id]}))
	# 2) pick the unit to take 4 damage
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_target")
	eng.apply(Action.resolve_choice({"target_ids": [enemy.instance_id]}))
	assert_int(enemy.current_health).is_equal(5)
	assert_bool(ps.discard.has(sacrifice)).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/writing/test_pain_split.gd`
Expected: FAIL.

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/writing/pain_split.gd
class_name PainSplit
extends CardScript

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	var allies: Array = ctx.board(ctx.me())
	if allies.is_empty():
		return
	ctx.request_choice(card,
		ChoiceSpec.select_target(allies.duplicate(), 1, 1, "TRASH a Unit"), "ps_trash")

func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "ps_trash":
		if result["targets"].is_empty():
			return
		card.vars["ps_trash_id"] = result["targets"][0].instance_id
		var units: Array = []
		for pidx in [ctx.me(), ctx.opponent()]:
			for u in ctx.board(pidx):
				units.append(u)
		if units.is_empty():
			_do_trash(card, ctx)
			return
		ctx.request_choice(card,
			ChoiceSpec.select_target(units, 1, 1, "Deal 4 damage to any Unit"), "ps_dmg")
	elif tag == "ps_dmg":
		if not result["targets"].is_empty():
			ctx.deal_damage(result["targets"][0], 4)
		_do_trash(card, ctx)

func _do_trash(card: CardInstance, ctx: EffectContext) -> void:
	var tid: int = int(card.vars.get("ps_trash_id", -1))
	var unit := ctx.engine._find_anywhere(tid)
	if unit != null:
		ctx.trash(unit)
```

In `_build()`:

```gdscript
	_register("writing", 17, PainSplit.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/writing/pain_split.gd src/cards/card_script_registry.gd tests/cards/writing/test_pain_split.gd
git commit -m "feat(writing): Pain Split trashes a unit then deals 4 damage"
```

---

## Task 11: Avatar of the Ancient Evil (id 6)

**Files:**
- Create: `src/cards/scripts/writing/avatar.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/writing/test_avatar.gd`

Implementation note (spec §6.7): you choose any number of your **other** units to trash; the opponent then trashes that many of theirs (opponent chooses which). Gather all selections first, then execute every trash **last**.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/writing/test_avatar.gd
extends WritingTestBase

func test_avatar_trashes_own_then_opponent_trashes_same_count() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var ps := eng.state.players[me]
	var mine := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 1))
	var enemy_a := place_on_board(eng, opp, TestFactory.minion(1, 1, 1, 2))
	place_on_board(eng, opp, TestFactory.minion(1, 1, 1, 3))
	var avatar := eng.state.make_instance(writing_def(6))
	ps.hand.append(avatar)
	ps.tickets_total = 20
	eng.apply(Action.play_card(avatar.instance_id))
	# 1) choose own units to trash (asked of me)
	assert_int(eng.state.pending_choice.player).is_equal(me)
	eng.apply(Action.resolve_choice({"target_ids": [mine.instance_id]}))
	# 2) opponent chooses 1 of theirs to trash (asked of opp)
	assert_int(eng.state.pending_choice.player).is_equal(opp)
	eng.apply(Action.resolve_choice({"target_ids": [enemy_a.instance_id]}))
	assert_bool(ps.discard.has(mine)).is_true()
	assert_bool(eng.state.players[opp].discard.has(enemy_a)).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/writing/test_avatar.gd`
Expected: FAIL.

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/writing/avatar.gd
class_name Avatar
extends CardScript

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	var others: Array = []
	for u in ctx.board(ctx.me()):
		if u != card:
			others.append(u)
	if others.is_empty():
		return
	ctx.request_choice(card,
		ChoiceSpec.select_target(others, 0, others.size(), "TRASH any number of your Units"),
		"avatar_self")

func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "avatar_self":
		var ids: Array = []
		for u in result["targets"]:
			ids.append(u.instance_id)
		card.vars["avatar_self_ids"] = ids
		var n := ids.size()
		var opp_units: Array = ctx.board(ctx.opponent())
		if n > 0 and not opp_units.is_empty():
			var k: int = min(n, opp_units.size())
			ctx.request_choice(card,
				ChoiceSpec.select_target(opp_units.duplicate(), k, k, "Opponent: TRASH %d of your Units" % k),
				"avatar_opp", ctx.opponent())
		else:
			_execute(card, ctx, [])
	elif tag == "avatar_opp":
		var opp_ids: Array = []
		for u in result["targets"]:
			opp_ids.append(u.instance_id)
		_execute(card, ctx, opp_ids)

func _execute(card: CardInstance, ctx: EffectContext, opp_ids: Array) -> void:
	for tid in card.vars.get("avatar_self_ids", []):
		var u := ctx.engine._find_anywhere(int(tid))
		if u != null:
			ctx.trash(u)
	for tid in opp_ids:
		var u2 := ctx.engine._find_anywhere(int(tid))
		if u2 != null:
			ctx.trash(u2)
```

In `_build()`:

```gdscript
	_register("writing", 6, Avatar.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/writing/avatar.gd src/cards/card_script_registry.gd tests/cards/writing/test_avatar.gd
git commit -m "feat(writing): Avatar trashes own units and mirrors onto the opponent"
```

---

## Task 12: Offering (Trap, id 21)

**Files:**
- Create: `src/cards/scripts/writing/offering.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/writing/test_offering.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/writing/test_offering.gd
extends WritingTestBase

func test_offering_gives_opponent_orange_and_negates_deck_damage() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var ps := eng.state.players[me]
	var trap := eng.state.make_instance(writing_def(21))
	trap.zone = Enums.Zone.TRAP_SET
	ps.set_traps.append(trap)
	var before := ps.deck.size()
	var opp_oranges := oranges_in_hand(eng, opp)
	eng._deck_damage(me, 4)
	assert_str(eng.state.pending_choice.kind).is_equal("intercept")
	eng.apply(Action.resolve_choice({"option": 0}))  # Fire
	assert_int(ps.deck.size()).is_equal(before)                       # negated
	assert_int(oranges_in_hand(eng, opp)).is_equal(opp_oranges + 1)   # opponent got an Orange
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/writing/test_offering.gd`
Expected: FAIL.

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/writing/offering.gd
class_name Offering
extends CardScript

func active_zones() -> Array: return [Enums.Zone.TRAP_SET]

func can_intercept_deck_damage(_card: CardInstance, _player: int, _amount: int, _ctx) -> bool:
	return true

func deck_damage_on_fire(_card: CardInstance, _player: int, _amount: int, ctx: EffectContext) -> int:
	# ctx is for the defender (the player whose deck is damaged); their opponent is the attacker.
	ctx.gain_orange(ctx.opponent())
	return 0
```

In `_build()`:

```gdscript
	_register("writing", 21, Offering.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/writing/offering.gd src/cards/card_script_registry.gd tests/cards/writing/test_offering.gd
git commit -m "feat(writing): Offering negates deck damage for an opponent Orange"
```

---

## Task 13: Ancient One's Protection (Trap, ids 19, 20)

**Files:**
- Create: `src/cards/scripts/writing/ancient_ones_protection.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/writing/test_ancient_ones_protection.gd`

Behavior: intercepts only **battle** kills. On fire, it prevents the dying unit's death (kept on board, health restored to 1 if it had dropped to 0) and raises a follow-up `select_target` to TRASH another allied unit in its place.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/writing/test_ancient_ones_protection.gd
extends WritingTestBase

func test_protects_unit_by_trashing_another_on_battle_death() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var ps := eng.state.players[me]
	# attacker (opp) will kill my defender in battle
	var attacker := place_on_board(eng, opp, TestFactory.minion(1, 5, 5, 1))
	attacker.tapped = false
	var defender := place_on_board(eng, me, TestFactory.minion(1, 1, 2, 2))
	var scapegoat := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 3))
	var trap := eng.state.make_instance(writing_def(19))
	trap.zone = Enums.Zone.TRAP_SET
	ps.set_traps.append(trap)
	eng.state.active_player = opp
	eng.apply(Action.declare_attack(attacker.instance_id, {"unit": defender.instance_id}))
	# Ancient One's prompts: Fire?
	assert_str(eng.state.pending_choice.kind).is_equal("intercept")
	eng.apply(Action.resolve_choice({"option": 0}))  # Fire
	# then choose another unit to trash in defender's place
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_target")
	eng.apply(Action.resolve_choice({"target_ids": [scapegoat.instance_id]}))
	assert_bool(ps.board.has(defender)).is_true()      # defender survived
	assert_bool(ps.discard.has(scapegoat)).is_true()   # scapegoat trashed
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/writing/test_ancient_ones_protection.gd`
Expected: FAIL.

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/writing/ancient_ones_protection.gd
class_name AncientOnesProtection
extends CardScript

func active_zones() -> Array: return [Enums.Zone.TRAP_SET]

func can_intercept_kill(card: CardInstance, dying: CardInstance, reason: String, ctx: EffectContext) -> bool:
	if reason != "battle":
		return false
	# need at least one OTHER allied unit to sacrifice
	var owner := ctx.engine._owner_of(dying)
	for u in ctx.gs().players[owner].board:
		if u != dying:
			return true
	return false

func kill_on_fire(card: CardInstance, dying: CardInstance, ctx: EffectContext) -> bool:
	var owner := ctx.engine._owner_of(dying)
	var others: Array = []
	for u in ctx.gs().players[owner].board:
		if u != dying:
			others.append(u)
	if others.is_empty():
		return false  # cannot protect; let the kill proceed
	if dying.current_health <= 0:
		dying.current_health = 1  # survives
	card.vars["aop_owner"] = owner
	ctx.request_choice(card,
		ChoiceSpec.select_target(others, 1, 1, "TRASH another Unit in its place"),
		"aop", owner)
	return true  # prevented; the follow-up choice resolves the sacrifice

func resume(_card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "aop" and not result["targets"].is_empty():
		ctx.trash(result["targets"][0])
```

In `_build()`:

```gdscript
	_register("writing", 19, AncientOnesProtection.new())
	_register("writing", 20, AncientOnesProtection.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/writing/ancient_ones_protection.gd src/cards/card_script_registry.gd tests/cards/writing/test_ancient_ones_protection.gd
git commit -m "feat(writing): Ancient One's Protection trashes another unit to save a battler"
```

---

## Task 14: Registry + load verification + full regression

**Files:**
- Test: `tests/cards/writing/test_writing_registry.gd`

- [ ] **Step 1: Write the test**

```gdscript
# tests/cards/writing/test_writing_registry.gd
extends WritingTestBase

func test_every_writing_id_resolves_to_a_non_default_script() -> void:
	var default := DefaultCard.new()
	for d in CardDatabase.load_deck("res://src/data/decks/writing.csv", "writing"):
		var s := CardScriptRegistry.get_script_for("writing", d.id)
		assert_bool(s.get_script() == default.get_script()).override_failure_message(
			"writing id %d has no script" % d.id).is_false()

func test_orange_token_registered() -> void:
	var s := CardScriptRegistry.get_script_for("writing", OrangeToken.ID)
	assert_bool(s is OrangeCard).is_true()
```

- [ ] **Step 2: Run it + full regression**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/writing/test_writing_registry.gd`
Then: `... -a res://tests`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/cards/writing/test_writing_registry.gd
git commit -m "test(writing): every card id resolves to a script"
```

---

## Self-Review Notes (coverage vs spec §5.3)

All 12 unique cards covered: Shelley (Task 7), Melon Zombie Hulk (8), Citrus Werewolf (4), Avatar (11), Cultist (9), Melon Zombie Warlock (6), Melon Zombie (5), Mercenary Trader (2), Citrus Sacrifice (3), Pain Split (10), Ancient One's Protection (13), Offering (12). The Orange token is provided by the Foundation plan (verified in Task 14). Trash-replacement cards (Shelley/Warlock/Melon Zombie) use the Foundation `trash_replacement_for`/`apply_trash_replacement` hooks; the interactive menu and interception come from the Foundation pipeline.
