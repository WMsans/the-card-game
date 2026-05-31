# Audio Deck Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement all 12 unique Audio-deck card scripts (HARMONIZE / CLEF / TAUNT) as pure-GDScript `CardScript`s with per-card GdUnit4 tests, plus the damage-doubling engine support Bass Clef and Staccato need.

**Architecture:** One `CardScript` per unique card in `src/cards/scripts/audio/`, registered by `audio:<id>`. Notes react once to `HARMONIZE`; a shared `ClefCard` base provides the "one clef / bounce to hand" behavior. Depends on the Foundation plan's API (`harmonize()`, `set_taunt()`, `untap()`, `is_note`, `is_clef`, `cost_modifier`, deck-damage interception).

**Tech Stack:** Godot 4 / GDScript; GdUnit4 tests.

**Run a suite (headless):**
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/audio/<suite>.gd
```

**Card id → script map (`src/data/decks/audio.csv`):** 1 Plop (Leader); 2,3 Quarter Note; 4,5 Half Note; 6,7 Eighth Note; 8,9 Sixteenth Note; 10,11 Whole Note; 12 Treble Clef; 13 Bass Clef; 14,15 Harmonize; 16,17 Staccato; 18,19 Legato; 20,21 Rest.

---

## File Structure

- `tests/cards/audio/audio_test_base.gd` — test helper.
- `src/cards/scripts/audio/<card>.gd` — one per unique card.
- `src/cards/scripts/audio/clef_card.gd` — shared CLEF base.
- `src/cards/card_script.gd` — `doubles_all_damage()` hook (Task 2).
- `src/engine/game_state.gd` — `turn_flags` dict (Task 2).
- `src/engine/game_engine.gd` — `damage_to()` multiplier + combat/`_damage_unit` integration; clear `turn_flags` each turn (Task 2).

---

## Task 1: Audio test base

**Files:**
- Create: `tests/cards/audio/audio_test_base.gd`

- [ ] **Step 1: Create the helper**

```gdscript
# tests/cards/audio/audio_test_base.gd
class_name AudioTestBase
extends CardTestBase

func audio_def(id: int) -> CardDefinition:
	for d in CardDatabase.load_deck("res://src/data/decks/audio.csv", "audio"):
		if d.id == id:
			return d
	return null
```

- [ ] **Step 2: Sanity-run an existing suite**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_registry.gd`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/cards/audio/audio_test_base.gd
git commit -m "test(audio): shared test base"
```

---

## Task 2: Damage-doubling engine support (Bass Clef + Staccato)

**Files:**
- Modify: `src/cards/card_script.gd` (`doubles_all_damage()`)
- Modify: `src/engine/game_state.gd` (`turn_flags`)
- Modify: `src/engine/game_engine.gd` (`damage_to`, `_damage_unit`, `_declare_attack`, clear flags in `_finish_end_turn`)
- Test: `tests/cards/audio/test_damage_doubling.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/audio/test_damage_doubling.gd
extends AudioTestBase

class DoublerStub extends CardScript:
	func doubles_all_damage() -> bool: return true

func test_bass_clef_style_doubles_effect_damage() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var clef := place_on_board(eng, me, TestFactory.minion(5, 0, 5, 13))
	clef.card_script = DoublerStub.new()
	var victim := place_on_board(eng, me, TestFactory.minion(1, 1, 10, 1))
	eng._damage_unit(victim, 3)  # doubled to 6
	assert_int(victim.current_health).is_equal(4)

class NoteStub extends CardScript:
	func is_note() -> bool: return true

func test_staccato_flag_doubles_note_damage_only() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var note := place_on_board(eng, me, TestFactory.minion(2, 1, 10, 2))
	note.card_script = NoteStub.new()
	var plain := place_on_board(eng, me, TestFactory.minion(2, 1, 10, 3))
	eng.state.turn_flags["notes_double_damage"] = true
	eng._damage_unit(note, 2)    # note -> doubled to 4
	eng._damage_unit(plain, 2)   # non-note -> unchanged
	assert_int(note.current_health).is_equal(6)
	assert_int(plain.current_health).is_equal(8)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/audio/test_damage_doubling.gd`
Expected: FAIL (`doubles_all_damage` / `turn_flags` not found).

- [ ] **Step 3: Add the hook**

Append to `src/cards/card_script.gd`:

```gdscript
# Bass Clef: while on board, all units take double damage.
func doubles_all_damage() -> bool: return false
```

- [ ] **Step 4: Add `turn_flags` to game state**

In `src/engine/game_state.gd`, add the field near the other vars:

```gdscript
var turn_flags: Dictionary = {}
```

- [ ] **Step 5: Add the multiplier and integrate it**

In `src/engine/game_engine.gd`, add:

```gdscript
func _any_damage_doubler() -> bool:
	for ps in state.players:
		for u in ps.board:
			if u.card_script != null and u.card_script.doubles_all_damage():
				return true
	return false

func damage_to(unit: CardInstance, base: int) -> int:
	var m := 1
	if _any_damage_doubler():
		m *= 2
	if state.turn_flags.get("notes_double_damage", false) \
			and unit.card_script != null and unit.card_script.is_note():
		m *= 2
	return base * m
```

In `_damage_unit`, replace the body's first two lines:

```gdscript
func _damage_unit(unit: CardInstance, n: int) -> void:
	var dmg := damage_to(unit, n)
	unit.current_health -= dmg
	emit(GameEvent.new(Enums.EventType.UNIT_DAMAGED, {"target": unit.instance_id, "amount": dmg}))
	if unit.current_health <= 0:
		_kill_unit(unit)
```

In `_declare_attack`, replace the combat-damage block (this is the **post-Foundation** version, where the kill calls already pass `"battle"` — see Foundation Task 14):

```gdscript
	var r := Combat.compute(attacker, defender)
	defender.current_health -= r["dmg_to_def"]
	attacker.current_health -= r["dmg_to_atk"]
	emit(GameEvent.new(Enums.EventType.UNIT_DAMAGED,
		{"target": defender.instance_id, "amount": r["dmg_to_def"]}))
	emit(GameEvent.new(Enums.EventType.UNIT_DAMAGED,
		{"target": attacker.instance_id, "amount": r["dmg_to_atk"]}))
	if r["def_dies"]:
		_kill(state.opponent(), defender, "battle")
	if r["atk_dies"]:
		_kill(state.active_player, attacker, "battle")
```

with:

```gdscript
	var r := Combat.compute(attacker, defender)
	var dmg_def := damage_to(defender, r["dmg_to_def"])
	var dmg_atk := damage_to(attacker, r["dmg_to_atk"])
	defender.current_health -= dmg_def
	attacker.current_health -= dmg_atk
	emit(GameEvent.new(Enums.EventType.UNIT_DAMAGED,
		{"target": defender.instance_id, "amount": dmg_def}))
	emit(GameEvent.new(Enums.EventType.UNIT_DAMAGED,
		{"target": attacker.instance_id, "amount": dmg_atk}))
	if defender.current_health <= 0:
		_kill(state.opponent(), defender, "battle")
	if attacker.current_health <= 0:
		_kill(state.active_player, attacker, "battle")
```

In `_finish_end_turn`, clear the flags at the top:

```gdscript
	state.turn_flags.clear()
```

- [ ] **Step 6: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 7: Combat regression (multiplier = 1 must be transparent)**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_combat.gd` and `... -a res://tests/test_engine_attack.gd`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add src/cards/card_script.gd src/engine/game_state.gd src/engine/game_engine.gd tests/cards/audio/test_damage_doubling.gd
git commit -m "feat(engine): damage-doubling support (doubles_all_damage + turn_flags)"
```

---

## Task 3: Quarter Note (ids 2, 3)

**Files:**
- Create: `src/cards/scripts/audio/quarter_note.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/audio/test_quarter_note.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/audio/test_quarter_note.gd
extends AudioTestBase

func test_quarter_note_gains_two_damage_once_on_harmonize() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var note := place_on_board(eng, me, audio_def(2))
	var base := note.current_damage
	var ctx := EffectContext.new(eng, me)
	ctx.harmonize()
	assert_int(note.current_damage).is_equal(base + 2)
	ctx.harmonize()
	assert_int(note.current_damage).is_equal(base + 2)  # only once

func test_quarter_note_is_a_note() -> void:
	assert_bool(CardScriptRegistry.get_script_for("audio", 2).is_note()).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/audio/test_quarter_note.gd`
Expected: FAIL (no buff).

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/audio/quarter_note.gd
class_name QuarterNote
extends CardScript

func is_note() -> bool: return true
func reacts_to() -> Array: return [Enums.EventType.HARMONIZE]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, _event: GameEvent, _ctx) -> void:
	if card.vars.get("harmonized", false):
		return
	card.vars["harmonized"] = true
	card.current_damage += 2
```

In `_build()`:

```gdscript
	_register("audio", 2, QuarterNote.new())
	_register("audio", 3, QuarterNote.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/audio/quarter_note.gd src/cards/card_script_registry.gd tests/cards/audio/test_quarter_note.gd
git commit -m "feat(audio): Quarter Note (+2 damage on harmonize)"
```

---

## Task 4: Half Note (ids 4, 5)

**Files:**
- Create: `src/cards/scripts/audio/half_note.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/audio/test_half_note.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/audio/test_half_note.gd
extends AudioTestBase

func test_half_note_gains_damage_and_health_once() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var note := place_on_board(eng, me, audio_def(4))
	var bd := note.current_damage
	var bh := note.current_health
	EffectContext.new(eng, me).harmonize()
	assert_int(note.current_damage).is_equal(bd + 1)
	assert_int(note.current_health).is_equal(bh + 2)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/audio/test_half_note.gd`
Expected: FAIL.

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/audio/half_note.gd
class_name HalfNote
extends CardScript

func is_note() -> bool: return true
func reacts_to() -> Array: return [Enums.EventType.HARMONIZE]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, _event: GameEvent, _ctx) -> void:
	if card.vars.get("harmonized", false):
		return
	card.vars["harmonized"] = true
	card.current_damage += 1
	card.current_health += 2
```

In `_build()`:

```gdscript
	_register("audio", 4, HalfNote.new())
	_register("audio", 5, HalfNote.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/audio/half_note.gd src/cards/card_script_registry.gd tests/cards/audio/test_half_note.gd
git commit -m "feat(audio): Half Note (+1 damage, +2 health on harmonize)"
```

---

## Task 5: Eighth Note (ids 6, 7)

**Files:**
- Create: `src/cards/scripts/audio/eighth_note.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/audio/test_eighth_note.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/audio/test_eighth_note.gd
extends AudioTestBase

func test_eighth_note_gains_three_damage_once() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var note := place_on_board(eng, me, audio_def(6))
	var bd := note.current_damage
	EffectContext.new(eng, me).harmonize()
	assert_int(note.current_damage).is_equal(bd + 3)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/audio/test_eighth_note.gd`
Expected: FAIL.

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/audio/eighth_note.gd
class_name EighthNote
extends CardScript

func is_note() -> bool: return true
func reacts_to() -> Array: return [Enums.EventType.HARMONIZE]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, _event: GameEvent, _ctx) -> void:
	if card.vars.get("harmonized", false):
		return
	card.vars["harmonized"] = true
	card.current_damage += 3
```

In `_build()`:

```gdscript
	_register("audio", 6, EighthNote.new())
	_register("audio", 7, EighthNote.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/audio/eighth_note.gd src/cards/card_script_registry.gd tests/cards/audio/test_eighth_note.gd
git commit -m "feat(audio): Eighth Note (+3 damage on harmonize)"
```

---

## Task 6: Whole Note (ids 10, 11)

**Files:**
- Create: `src/cards/scripts/audio/whole_note.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/audio/test_whole_note.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/audio/test_whole_note.gd
extends AudioTestBase

func test_whole_note_gains_health_and_taunt_once() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var note := place_on_board(eng, me, audio_def(10))
	var bh := note.current_health
	EffectContext.new(eng, me).harmonize()
	assert_int(note.current_health).is_equal(bh + 2)
	assert_bool(note.vars.get("taunt", false)).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/audio/test_whole_note.gd`
Expected: FAIL.

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/audio/whole_note.gd
class_name WholeNote
extends CardScript

func is_note() -> bool: return true
func reacts_to() -> Array: return [Enums.EventType.HARMONIZE]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, _event: GameEvent, ctx: EffectContext) -> void:
	if card.vars.get("harmonized", false):
		return
	card.vars["harmonized"] = true
	card.current_health += 2
	ctx.set_taunt(card)
```

In `_build()`:

```gdscript
	_register("audio", 10, WholeNote.new())
	_register("audio", 11, WholeNote.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/audio/whole_note.gd src/cards/card_script_registry.gd tests/cards/audio/test_whole_note.gd
git commit -m "feat(audio): Whole Note (+2 health and TAUNT on harmonize)"
```

---

## Task 7: Sixteenth Note (ids 8, 9)

**Files:**
- Create: `src/cards/scripts/audio/sixteenth_note.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/audio/test_sixteenth_note.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/audio/test_sixteenth_note.gd
extends AudioTestBase

func test_costs_one_less_per_note_on_board() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	# two notes on board
	place_on_board(eng, me, audio_def(2))
	place_on_board(eng, me, audio_def(6))
	var sixteenth := eng.state.make_instance(audio_def(8))
	# base cost 10 - 2 notes = 8
	assert_int(eng.effective_cost(sixteenth, me)).is_equal(8)

func test_sixteenth_deals_four_deck_damage_on_harmonize() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	place_on_board(eng, me, audio_def(8))
	var before := eng.state.players[opp].deck.size()
	EffectContext.new(eng, me).harmonize()
	assert_int(eng.state.players[opp].deck.size()).is_equal(before - 4)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/audio/test_sixteenth_note.gd`
Expected: FAIL.

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/audio/sixteenth_note.gd
class_name SixteenthNote
extends CardScript

func is_note() -> bool: return true

func cost_modifier(_card: CardInstance, ctx) -> int:
	var notes := 0
	for u in ctx.board(ctx.me()):
		if u.card_script != null and u.card_script.is_note():
			notes += 1
	return -notes

func reacts_to() -> Array: return [Enums.EventType.HARMONIZE]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, _event: GameEvent, ctx: EffectContext) -> void:
	if card.vars.get("harmonized", false):
		return
	card.vars["harmonized"] = true
	ctx.deal_deck_damage(ctx.opponent(), 4)
```

In `_build()`:

```gdscript
	_register("audio", 8, SixteenthNote.new())
	_register("audio", 9, SixteenthNote.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/audio/sixteenth_note.gd src/cards/card_script_registry.gd tests/cards/audio/test_sixteenth_note.gd
git commit -m "feat(audio): Sixteenth Note (cost scales with notes; 4 deck damage on harmonize)"
```

---

## Task 8: Harmonize, Staccato, Legato spells (ids 14–19)

**Files:**
- Create: `src/cards/scripts/audio/harmonize_spell.gd`
- Create: `src/cards/scripts/audio/staccato.gd`
- Create: `src/cards/scripts/audio/legato.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/audio/test_audio_spells.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/audio/test_audio_spells.gd
extends AudioTestBase

func _cast(eng: GameEngine, me: int, id: int) -> CardInstance:
	var ps := eng.state.players[me]
	var c := eng.state.make_instance(audio_def(id))
	c.zone = Enums.Zone.HAND
	ps.hand.append(c)
	ps.tickets_total = 20
	eng.apply(Action.play_card(c.instance_id))
	return c

func test_harmonize_spell_triggers_harmonize() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var note := place_on_board(eng, me, audio_def(2))
	var bd := note.current_damage
	_cast(eng, me, 14)
	assert_int(note.current_damage).is_equal(bd + 2)

func test_staccato_sets_notes_double_damage_flag() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	_cast(eng, me, 16)
	assert_bool(eng.state.turn_flags.get("notes_double_damage", false)).is_true()

func test_legato_untaps_a_chosen_unit() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var tapped := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 1))
	tapped.tapped = true
	_cast(eng, me, 18)
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_target")
	eng.apply(Action.resolve_choice({"target_ids": [tapped.instance_id]}))
	assert_bool(tapped.tapped).is_false()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/audio/test_audio_spells.gd`
Expected: FAIL.

- [ ] **Step 3: Create the scripts + register**

```gdscript
# src/cards/scripts/audio/harmonize_spell.gd
class_name HarmonizeSpell
extends CardScript

func on_cast(_card: CardInstance, ctx: EffectContext) -> void:
	ctx.harmonize()
```

```gdscript
# src/cards/scripts/audio/staccato.gd
class_name Staccato
extends CardScript

func on_cast(_card: CardInstance, ctx: EffectContext) -> void:
	ctx.harmonize()
	ctx.gs().turn_flags["notes_double_damage"] = true
```

```gdscript
# src/cards/scripts/audio/legato.gd
class_name Legato
extends CardScript

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	ctx.harmonize()
	var tapped: Array = []
	for u in ctx.board(ctx.me()):
		if u.tapped:
			tapped.append(u)
	if tapped.is_empty():
		return
	ctx.request_choice(card,
		ChoiceSpec.select_target(tapped, 0, 1, "Untap one Tapped Unit"), "legato")

func resume(_card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "legato" and not result["targets"].is_empty():
		ctx.untap(result["targets"][0])
```

In `_build()`:

```gdscript
	_register("audio", 14, HarmonizeSpell.new())
	_register("audio", 15, HarmonizeSpell.new())
	_register("audio", 16, Staccato.new())
	_register("audio", 17, Staccato.new())
	_register("audio", 18, Legato.new())
	_register("audio", 19, Legato.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/audio/harmonize_spell.gd src/cards/scripts/audio/staccato.gd src/cards/scripts/audio/legato.gd src/cards/card_script_registry.gd tests/cards/audio/test_audio_spells.gd
git commit -m "feat(audio): Harmonize, Staccato, Legato spells"
```

---

## Task 9: Rest trap (ids 20, 21)

**Files:**
- Create: `src/cards/scripts/audio/rest.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/audio/test_rest.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/audio/test_rest.gd
extends AudioTestBase

func test_rest_negates_next_deck_damage() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	var trap := eng.state.make_instance(audio_def(20))
	trap.zone = Enums.Zone.TRAP_SET
	ps.set_traps.append(trap)
	var before := ps.deck.size()
	eng._deck_damage(me, 5)
	assert_str(eng.state.pending_choice.kind).is_equal("intercept")
	eng.apply(Action.resolve_choice({"option": 0}))  # Fire
	assert_int(ps.deck.size()).is_equal(before)
	assert_bool(ps.set_traps.is_empty()).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/audio/test_rest.gd`
Expected: FAIL.

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/audio/rest.gd
class_name Rest
extends CardScript

func active_zones() -> Array: return [Enums.Zone.TRAP_SET]

func can_intercept_deck_damage(_card: CardInstance, _player: int, _amount: int, _ctx) -> bool:
	return true

func deck_damage_on_fire(_card: CardInstance, _player: int, _amount: int, _ctx) -> int:
	return 0
```

In `_build()`:

```gdscript
	_register("audio", 20, Rest.new())
	_register("audio", 21, Rest.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/audio/rest.gd src/cards/card_script_registry.gd tests/cards/audio/test_rest.gd
git commit -m "feat(audio): Rest negates next deck damage"
```

---

## Task 10: CLEF base + Treble Clef + Bass Clef (ids 12, 13)

**Files:**
- Create: `src/cards/scripts/audio/clef_card.gd`
- Create: `src/cards/scripts/audio/treble_clef.gd`
- Create: `src/cards/scripts/audio/bass_clef.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/audio/test_clefs.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/audio/test_clefs.gd
extends AudioTestBase

func test_clef_bounce_returns_to_hand_for_two_tickets() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	ps.tickets_total = 5
	ps.tickets_tapped = 0
	var clef := place_on_board(eng, me, audio_def(12))
	eng.apply(Action.activate_ability(clef.instance_id, "clef_bounce"))
	assert_bool(ps.hand.has(clef)).is_true()
	assert_bool(ps.board.has(clef)).is_false()
	assert_int(ps.tickets_tapped).is_equal(2)

func test_treble_clef_harmonizes_every_second_turn() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	place_on_board(eng, me, audio_def(12))
	var note := place_on_board(eng, me, audio_def(2))
	var bd := note.current_damage
	# first owner turn-start: no harmonize (count 1)
	eng.emit(GameEvent.new(Enums.EventType.TURN_STARTED, {"player": me}))
	assert_int(note.current_damage).is_equal(bd)
	# second owner turn-start: harmonize (count 2)
	eng.emit(GameEvent.new(Enums.EventType.TURN_STARTED, {"player": me}))
	assert_int(note.current_damage).is_equal(bd + 2)

func test_bass_clef_harmonizes_when_a_unit_survives_damage() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	place_on_board(eng, me, audio_def(13))
	var note := place_on_board(eng, me, audio_def(2))
	var bd := note.current_damage
	var survivor := place_on_board(eng, me, TestFactory.minion(1, 1, 20, 1))
	eng._damage_unit(survivor, 2)  # survives -> triggers Bass Clef harmonize
	assert_int(note.current_damage).is_equal(bd + 2)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/audio/test_clefs.gd`
Expected: FAIL.

- [ ] **Step 3: Create the CLEF base**

```gdscript
# src/cards/scripts/audio/clef_card.gd
class_name ClefCard
extends CardScript

func is_clef() -> bool: return true

func activated_abilities(card: CardInstance, ctx: EffectContext) -> Array:
	if card.zone != Enums.Zone.BOARD:
		return []
	if ctx.gs().players[ctx.me()].available_tickets() < 2:
		return []
	return [{"id": "clef_bounce", "label": "Return this Clef to your hand (2)"}]

func activate(card: CardInstance, ability_id: String, ctx: EffectContext) -> void:
	if ability_id != "clef_bounce":
		return
	var ps := ctx.gs().players[ctx.me()]
	ps.tickets_tapped += 2
	ps.board.erase(card)
	card.reset_stats()
	card.tapped = false
	card.zone = Enums.Zone.HAND
	ps.hand.append(card)
```

- [ ] **Step 4: Create Treble Clef + Bass Clef**

```gdscript
# src/cards/scripts/audio/treble_clef.gd
class_name TrebleClef
extends ClefCard

func reacts_to() -> Array: return [Enums.EventType.TURN_STARTED]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("player", -1) != ctx.me():
		return
	var c: int = int(card.vars.get("treble_turns", 0)) + 1
	card.vars["treble_turns"] = c
	if c % 2 == 0:
		ctx.harmonize()
```

```gdscript
# src/cards/scripts/audio/bass_clef.gd
class_name BassClef
extends ClefCard

func doubles_all_damage() -> bool: return true

func reacts_to() -> Array: return [Enums.EventType.UNIT_DAMAGED]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	var target := ctx.engine._find_anywhere(int(event.data.get("target", -1)))
	if target == null:
		return
	# survived = still on a board with positive health
	if target.current_health <= 0:
		return
	var owner := ctx.engine._owner_of(target)
	if owner < 0 or not ctx.gs().players[owner].board.has(target):
		return
	ctx.harmonize()
```

In `_build()`:

```gdscript
	_register("audio", 12, TrebleClef.new())
	_register("audio", 13, BassClef.new())
```

- [ ] **Step 5: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

> If Bass Clef's harmonize-on-damage appears to loop, confirm `harmonize()` never emits `UNIT_DAMAGED` (it does not — buffs adjust stats directly), so there is no re-entrancy.

- [ ] **Step 6: Commit**

```bash
git add src/cards/scripts/audio/clef_card.gd src/cards/scripts/audio/treble_clef.gd src/cards/scripts/audio/bass_clef.gd src/cards/card_script_registry.gd tests/cards/audio/test_clefs.gd
git commit -m "feat(audio): Treble + Bass Clef (one-clef, bounce, cadence/double-damage)"
```

---

## Task 11: Plop, Grand Conductor (Leader, id 1)

**Files:**
- Create: `src/cards/scripts/audio/plop.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/audio/test_plop.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/cards/audio/test_plop.gd
extends AudioTestBase

func test_plop_harmonizes_on_cast_and_deals_six_deck_damage() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var ps := eng.state.players[me]
	var note := place_on_board(eng, me, audio_def(2))
	var bd := note.current_damage
	var plop := eng.state.make_instance(audio_def(1))
	plop.zone = Enums.Zone.HAND
	ps.hand.append(plop)
	ps.tickets_total = 20
	var opp_deck := eng.state.players[opp].deck.size()
	eng.apply(Action.play_card(plop.instance_id))
	assert_int(note.current_damage).is_equal(bd + 2)          # note harmonized
	assert_int(eng.state.players[opp].deck.size()).is_equal(opp_deck - 6)  # Plop's own harmonize
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/audio/test_plop.gd`
Expected: FAIL.

- [ ] **Step 3: Create the script + register**

```gdscript
# src/cards/scripts/audio/plop.gd
class_name Plop
extends CardScript

func on_cast(_card: CardInstance, ctx: EffectContext) -> void:
	ctx.harmonize()

# Plop's own HARMONIZE effect: deal 6 to the enemy Deck (once).
func reacts_to() -> Array: return [Enums.EventType.HARMONIZE]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, _event: GameEvent, ctx: EffectContext) -> void:
	if card.vars.get("harmonized", false):
		return
	card.vars["harmonized"] = true
	ctx.deal_deck_damage(ctx.opponent(), 6)
```

In `_build()`:

```gdscript
	_register("audio", 1, Plop.new())
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/cards/scripts/audio/plop.gd src/cards/card_script_registry.gd tests/cards/audio/test_plop.gd
git commit -m "feat(audio): Plop leader (harmonize all + 6 deck damage)"
```

---

## Task 12: Registry + load verification

**Files:**
- Test: `tests/cards/audio/test_audio_registry.gd`

- [ ] **Step 1: Write the test**

```gdscript
# tests/cards/audio/test_audio_registry.gd
extends AudioTestBase

func test_every_audio_id_resolves_to_a_non_default_script() -> void:
	var default := DefaultCard.new()
	for d in CardDatabase.load_deck("res://src/data/decks/audio.csv", "audio"):
		var s := CardScriptRegistry.get_script_for("audio", d.id)
		assert_bool(s.get_script() == default.get_script()).override_failure_message(
			"audio id %d has no script" % d.id).is_false()
```

- [ ] **Step 2: Run it + full regression**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/audio/test_audio_registry.gd`
Then: `... -a res://tests`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/cards/audio/test_audio_registry.gd
git commit -m "test(audio): every card id resolves to a script"
```

---

## Self-Review Notes (coverage vs spec §5.2 + §4.5–4.6)

All 12 unique cards covered: Plop (Task 11), Quarter/Half/Eighth/Whole/Sixteenth Notes (Tasks 3–7), Treble/Bass Clef (10), Harmonize/Staccato/Legato (8), Rest (9). Damage-doubling (Bass Clef global, Staccato note-scoped) and `turn_flags` added in Task 2. CLEF one-active enforcement comes from the Foundation plan's `get_legal_actions` change + `is_clef()`. TAUNT enforcement also from Foundation; Whole Note sets it. Registry coverage asserted in Task 12.
