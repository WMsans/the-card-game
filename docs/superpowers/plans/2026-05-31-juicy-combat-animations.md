# Juicy Combat Animations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make card actions (attacks, deaths, damage) read clearly through choreographed, bouncy, cartoony animation that matches the rest of the game.

**Architecture:** A new async `CombatDirector` runs *between* `engine.apply` and `render_all` in `match.gd::apply_action`, so the attacker and the dying defender's `CardView`s still exist when it animates them. It plays a wind-up → lunge → hit-stop → impact → recoil → death-pop recipe out of small static juice primitives (`CardJuice`) and Slay-the-Spire-2 falling-number particles (`DamageNumber`), with a Balatro-style speed ramp (`anim_speed`) that accelerates chained attacks. Non-attack actions skip the director entirely.

**Tech Stack:** Godot 4.6 (GL Compatibility), GDScript, GdUnit4 for tests.

---

## Background the implementer needs

- **Tests use GdUnit4, NOT GUT.** Suites `extends GdUnitTestSuite`, live flat in `tests/` as `test_*.gd`. Run one suite headless:
  ```bash
  godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_juice.gd
  ```
  Whole dir: `-a res://tests`. Exit code `0` = pass; reports land in `reports/report_N/`. If `godot` is not on PATH, use the absolute binary path or export `GODOT_BIN` and run `addons/gdUnit4/runtest.sh`. Harmless headless noise to ignore: `ERROR: Required object "rp_font" is null` and the "InputEvents not transported in headless" notice.
- **Existing animation siblings to match style:** `src/ui/card/card_flight.gd` (static tween lib), `src/ui/match/flight_anchors.gd` (pile screen anchors), `src/ui/match/card_flight_layer.gd` (airborne cards).
- **Key types:**
  - `CardView` (`src/ui/card/card_view.gd`): `Control`. Has `base_scale: float`, `_rest_position: Vector2`, `_rest_rotation: float`, `scale`, `position`, `modulate`, `z_index`, `size`, `global_position`. `create_tween()` works when it is in the tree.
  - `GameEvent` (`src/data/game_event.gd`): `GameEvent.new(type: int, data: Dictionary)`, fields `.type`, `.data`.
  - `Enums.EventType`: `UNIT_ATTACKED`, `UNIT_DAMAGED`, `UNIT_DIED`, `DECK_DAMAGED`, `TURN_STARTED`, etc. `Enums.Zone.DECK`.
  - Event payloads: `UNIT_ATTACKED {attacker, player, target_unit}` (`target_unit == -1` means deck attack); `UNIT_DAMAGED {target, amount}`; `UNIT_DIED {owner, instance}`; `DECK_DAMAGED {player, amount}`.
  - `FlightAnchors.of(Enums.Zone.DECK, player_idx, match_node) -> Vector2` returns the deck pile's global center.
  - `BoardLayout.CARD_SCALE == 0.42`, `BoardLayout.CARD_PIVOT == Vector2(140, 196)`.
  - `match.gd` (`src/ui/match/match.gd`) exposes `player_board`, `opp_board`, `hand_view`, `_player_deck`, `_opp_deck`, `state`, `HUMAN` (== 0), and node `FxLayer` (a `Control` at `$FxLayer`).
- **Coordinate assumption (already relied on by `CardFlight`):** the board `Node2D`s are translation-only (no scale/rotation), so a global-space delta equals a local-space delta. The director computes target deltas in global space and applies them to the attacker's local `position`. Keep this assumption.

## File structure

New files:

| File | Responsibility |
|---|---|
| `src/ui/match/card_juice.gd` | `class_name CardJuice` — static tween primitives: `windup`, `lunge`, `recoil`, `squash`, `pop`. Pure feel, no game logic. |
| `src/ui/match/damage_number.gd` | `class_name DamageNumber` — self-animating falling-number particle. `static func spawn(parent, at, amount, big)`. |
| `src/ui/match/combat_director.gd` | `class_name CombatDirector` — pure helpers (`has_attack`, `parse_cluster`, `next_speed`) + async `play(events, m)` recipe + `anim_speed` ramp state. |
| `tests/test_card_juice.gd` | End-state tests for the juice primitives. |
| `tests/test_damage_number.gd` | Spawn/lifetime tests for the particle. |
| `tests/test_combat_director.gd` | Pure-function tests + a deterministic deck-attack recipe smoke test. |

Modified files:

| File | Change |
|---|---|
| `src/ui/match/match.gd` | `apply_action` becomes a coroutine that awaits the director; add `_director`, `_anim_busy`, input gating, ramp reset on `TURN_STARTED`. |
| `src/ui/match/flourishes.gd` | Use `DamageNumber` for damage popups; add `attack` param so the director owns combat numbers (no double-spawn); drop the old `_shake`. |
| `tests/test_match_flourish.gd` | (Only if needed) existing calls stay valid via the defaulted `attack` param — verify, don't rewrite. |

---

## Task 1: CardJuice primitives

**Files:**
- Create: `src/ui/match/card_juice.gd`
- Test: `tests/test_card_juice.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_card_juice.gd`:

```gdscript
extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"

# A real CardView from a populated hand (base_scale already set). Wait out the
# initial render tween so it can't race the juice tween under test.
func _a_card() -> CardView:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(3, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	await get_tree().create_timer(0.35).timeout
	return m.hand_view.card_views.values()[0]

func test_windup_lands_at_target_and_scales_up() -> void:
	var cv := await _a_card()
	var base := cv.base_scale
	var tw := CardJuice.windup(cv, Vector2(400, 800))
	await tw.finished
	assert_vector(cv.position).is_equal_approx(Vector2(400, 800), Vector2(1.5, 1.5))
	assert_float(cv.scale.x).is_equal_approx(base * 1.08, 0.02)

func test_lunge_reaches_target() -> void:
	var cv := await _a_card()
	var tw := CardJuice.lunge(cv, Vector2(1200, 300))
	await tw.finished
	assert_vector(cv.position).is_equal_approx(Vector2(1200, 300), Vector2(2, 2))

func test_recoil_returns_to_rest_pos_rot_and_base_scale() -> void:
	var cv := await _a_card()
	var base := cv.base_scale
	var tw := CardJuice.recoil(cv, Vector2(700, 850), 0.1)
	await tw.finished
	assert_vector(cv.position).is_equal_approx(Vector2(700, 850), Vector2(2, 2))
	assert_float(cv.rotation).is_equal_approx(0.1, 0.02)
	assert_float(cv.scale.x).is_equal_approx(base, 0.02)

func test_squash_returns_to_base_scale() -> void:
	var cv := await _a_card()
	var base := cv.base_scale
	var tw := CardJuice.squash(cv)
	await tw.finished
	assert_float(cv.scale.x).is_equal_approx(base, 0.02)

func test_pop_ends_at_base_scale_and_white_modulate() -> void:
	var cv := await _a_card()
	var base := cv.base_scale
	var tw := CardJuice.pop(cv)
	await tw.finished
	assert_float(cv.scale.x).is_equal_approx(base, 0.03)
	assert_float(cv.modulate.r).is_equal_approx(1.0, 0.02)

func test_speed_shortens_duration() -> void:
	var cv := await _a_card()
	# Faster speed must finish sooner. Both tween the same trivial move.
	var t0 := Time.get_ticks_msec()
	await CardJuice.recoil(cv, cv.position, cv.rotation, 1.0).finished
	var slow := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	await CardJuice.recoil(cv, cv.position, cv.rotation, 2.5).finished
	var fast := Time.get_ticks_msec() - t0
	assert_int(fast).is_less(slow)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_juice.gd`
Expected: FAIL — `Identifier "CardJuice" not declared`.

- [ ] **Step 3: Implement `CardJuice`**

Create `src/ui/match/card_juice.gd`:

```gdscript
class_name CardJuice
extends RefCounted

# Cartoony, bouncy tween primitives shared by the combat choreography. Each takes
# a `speed` multiplier (>1 = faster) so the director's Balatro ramp can shorten
# every beat uniformly. All tweens are created on the CardView (must be in tree).

const WINDUP_TIME := 0.12
const LUNGE_TIME := 0.14
const RECOIL_TIME := 0.24
const SQUASH_TIME := 0.10
const POP_TIME := 0.18
const HITSTOP := 0.05

static func _t(base_time: float, speed: float) -> float:
	return base_time / maxf(speed, 0.01)

# Anticipation: ease to `to_pos` (a small step AWAY from the target) and scale up.
static func windup(cv: CardView, to_pos: Vector2, speed: float = 1.0) -> Tween:
	var base := cv.base_scale
	var t := _t(WINDUP_TIME, speed)
	var tw := cv.create_tween().set_parallel(true)
	tw.tween_property(cv, "position", to_pos, t).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "scale", Vector2(base, base) * 1.08, t).set_trans(Tween.TRANS_QUAD)
	return tw

# Snap forward into `to_pos`, overshooting (TRANS_BACK / EASE_IN).
static func lunge(cv: CardView, to_pos: Vector2, speed: float = 1.0) -> Tween:
	var tw := cv.create_tween()
	tw.tween_property(cv, "position", to_pos, _t(LUNGE_TIME, speed)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	return tw

# Bouncy return home: position + rotation + scale settle back to rest/base.
static func recoil(cv: CardView, to_pos: Vector2, rot: float, speed: float = 1.0) -> Tween:
	var base := cv.base_scale
	var t := _t(RECOIL_TIME, speed)
	var tw := cv.create_tween().set_parallel(true)
	tw.tween_property(cv, "position", to_pos, t).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "rotation", rot, t).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "scale", Vector2(base, base), t).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	return tw

# Quick squash-stretch in place (impact reaction); returns to base scale.
static func squash(cv: CardView, speed: float = 1.0) -> Tween:
	var base := cv.base_scale
	var t := _t(SQUASH_TIME, speed)
	var tw := cv.create_tween()
	tw.tween_property(cv, "scale", Vector2(1.18, 0.82) * base, t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "scale", Vector2(base, base), t).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	return tw

# Death pop: scale up with a bright flash, then settle back to base. The card is
# swept to the discard afterwards by the existing leaver mechanism in render_all.
static func pop(cv: CardView, speed: float = 1.0) -> Tween:
	var base := cv.base_scale
	var t := _t(POP_TIME, speed)
	var tw := cv.create_tween()
	tw.tween_property(cv, "scale", Vector2(base, base) * 1.35, t * 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(cv, "modulate", Color(1.6, 1.6, 1.6), t * 0.45)
	tw.tween_property(cv, "scale", Vector2(base, base), t * 0.55).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(cv, "modulate", Color.WHITE, t * 0.55)
	return tw
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_juice.gd`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/card_juice.gd tests/test_card_juice.gd
git commit -m "feat: CardJuice cartoony tween primitives for combat"
```

---

## Task 2: DamageNumber falling particle

**Files:**
- Create: `src/ui/match/damage_number.gd`
- Test: `tests/test_damage_number.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_damage_number.gd`:

```gdscript
extends GdUnitTestSuite

func _host() -> Control:
	var c := Control.new()
	add_child(c)
	auto_free(c)
	return c

func test_spawn_adds_node_with_minus_label() -> void:
	var host := _host()
	var dn := DamageNumber.spawn(host, Vector2(500, 500), 3)
	assert_object(dn).is_not_null()
	assert_bool(host.is_ancestor_of(dn)).is_true()
	var found := ""
	for child in dn.get_children():
		if child is Label:
			found = child.text
	assert_str(found).is_equal("-3")

func test_big_hit_uses_distinct_tint() -> void:
	var host := _host()
	var small := DamageNumber.spawn(host, Vector2(0, 0), 1, false)
	var big := DamageNumber.spawn(host, Vector2(0, 0), 7, true)
	var small_label: Label = _first_label(small)
	var big_label: Label = _first_label(big)
	assert_bool(small_label.modulate.is_equal_approx(big_label.modulate)).is_false()

func test_particle_self_frees_after_lifetime() -> void:
	var host := _host()
	var dn := DamageNumber.spawn(host, Vector2(100, 100), 2)
	await get_tree().create_timer(DamageNumber.LIFETIME + 0.3).timeout
	assert_bool(is_instance_valid(dn)).is_false()

func _first_label(dn: Node) -> Label:
	for child in dn.get_children():
		if child is Label:
			return child
	return null
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_damage_number.gd`
Expected: FAIL — `Identifier "DamageNumber" not declared`.

- [ ] **Step 3: Implement `DamageNumber`**

Create `src/ui/match/damage_number.gd`:

```gdscript
class_name DamageNumber
extends Node2D

# Slay-the-Spire-2 style floating damage: pops in over-scaled, then becomes a
# small physics object — initial upward+sideways velocity, gravity, spin, fade —
# and self-frees. Reusable by anyone dealing damage (combat director, flourishes).

const GRAVITY := 1400.0
const LIFETIME := 0.6
const SMALL_TINT := Color(1.0, 0.30, 0.30)
const BIG_TINT := Color(1.0, 0.85, 0.20)

var _vel: Vector2 = Vector2.ZERO
var _life: float = LIFETIME

static func spawn(parent: Node, at: Vector2, amount: int, big: bool = false) -> DamageNumber:
	var dn := DamageNumber.new()
	parent.add_child(dn)
	dn.global_position = at
	dn._setup(amount, big)
	return dn

func _setup(amount: int, big: bool) -> void:
	var label := Label.new()
	label.text = "-%d" % amount
	label.modulate = BIG_TINT if big else SMALL_TINT
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)
	var s := 1.5 if big else 1.0
	scale = Vector2(1.4, 1.4) * s
	_vel = Vector2(randf_range(-90.0, 90.0), randf_range(-260.0, -180.0))
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(s, s), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _physics_process(delta: float) -> void:
	_vel.y += GRAVITY * delta
	position += _vel * delta
	rotation += delta * 2.0
	_life -= delta
	modulate.a = clampf(_life / LIFETIME, 0.0, 1.0)
	if _life <= 0.0:
		queue_free()
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_damage_number.gd`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/damage_number.gd tests/test_damage_number.gd
git commit -m "feat: DamageNumber falling-number particle"
```

---

## Task 3: CombatDirector pure helpers

**Files:**
- Create: `src/ui/match/combat_director.gd`
- Test: `tests/test_combat_director.gd`

This task adds only the pure, fully-testable parts of the director. The async recipe comes in Task 4.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_combat_director.gd`:

```gdscript
extends GdUnitTestSuite

func _ev(type: int, data: Dictionary) -> GameEvent:
	return GameEvent.new(type, data)

func test_has_attack_true_when_unit_attacked_present() -> void:
	var events := [_ev(Enums.EventType.UNIT_ATTACKED, {"attacker": 1, "player": 0, "target_unit": 2})]
	assert_bool(CombatDirector.has_attack(events)).is_true()

func test_has_attack_false_for_non_attack_events() -> void:
	var events := [_ev(Enums.EventType.CARD_DRAWN, {"player": 0, "instance": 9})]
	assert_bool(CombatDirector.has_attack(events)).is_false()

func test_parse_cluster_unit_attack() -> void:
	var events := [
		_ev(Enums.EventType.UNIT_ATTACKED, {"attacker": 5, "player": 0, "target_unit": 9}),
		_ev(Enums.EventType.UNIT_DAMAGED, {"target": 9, "amount": 3}),
		_ev(Enums.EventType.UNIT_DAMAGED, {"target": 5, "amount": 1}),
		_ev(Enums.EventType.UNIT_DIED, {"owner": 1, "instance": 9}),
	]
	var c := CombatDirector.parse_cluster(events)
	assert_int(c["attacker"]).is_equal(5)
	assert_int(c["target_unit"]).is_equal(9)
	assert_int(c["player"]).is_equal(0)
	assert_int(c["damaged"].size()).is_equal(2)
	assert_int(c["damaged"][0]["id"]).is_equal(9)
	assert_int(c["damaged"][0]["amount"]).is_equal(3)
	assert_array(c["died"]).contains([9])

func test_parse_cluster_deck_attack_captures_deck_amount() -> void:
	var events := [
		_ev(Enums.EventType.UNIT_ATTACKED, {"attacker": 4, "player": 0, "target_unit": -1}),
		_ev(Enums.EventType.DECK_DAMAGED, {"player": 1, "amount": 2}),
	]
	var c := CombatDirector.parse_cluster(events)
	assert_int(c["target_unit"]).is_equal(-1)
	assert_int(c["deck_amount"]).is_equal(2)

func test_next_speed_ramps_up_on_quick_chain() -> void:
	assert_float(CombatDirector.next_speed(1.0, 0.1)).is_equal_approx(1.35, 0.001)

func test_next_speed_caps_at_max() -> void:
	assert_float(CombatDirector.next_speed(2.4, 0.1)).is_equal_approx(2.5, 0.001)

func test_next_speed_resets_after_a_lull() -> void:
	assert_float(CombatDirector.next_speed(2.0, 1.0)).is_equal_approx(1.0, 0.001)

func test_reset_ramp_sets_speed_to_one() -> void:
	var d := CombatDirector.new()
	d.anim_speed = 2.2
	d.reset_ramp()
	assert_float(d.anim_speed).is_equal_approx(1.0, 0.001)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_combat_director.gd`
Expected: FAIL — `Identifier "CombatDirector" not declared`.

- [ ] **Step 3: Implement the pure helpers**

Create `src/ui/match/combat_director.gd`:

```gdscript
class_name CombatDirector
extends RefCounted

# Async choreography brain for combat. Runs between engine.apply and render_all
# so the attacker and dying defenders' CardViews still exist when it animates
# them. Owns the Balatro-style anim_speed ramp. The async recipe (play) is added
# in a later task; this file starts with the pure, testable decision functions.

const CHAIN_GAP := 0.6     # seconds; chaining faster than this ramps speed up
const RAMP_STEP := 0.35    # speed added per chained attack
const MAX_SPEED := 2.5     # ramp ceiling

var anim_speed: float = 1.0

static func has_attack(events: Array) -> bool:
	for e in events:
		if e.type == Enums.EventType.UNIT_ATTACKED:
			return true
	return false

static func parse_cluster(events: Array) -> Dictionary:
	var c := {
		"attacker": -1, "target_unit": -1, "player": -1,
		"deck_amount": 0, "damaged": [], "died": [],
	}
	for e in events:
		match e.type:
			Enums.EventType.UNIT_ATTACKED:
				c["attacker"] = e.data.get("attacker", -1)
				c["target_unit"] = e.data.get("target_unit", -1)
				c["player"] = e.data.get("player", -1)
			Enums.EventType.UNIT_DAMAGED:
				c["damaged"].append({"id": e.data.get("target", -1), "amount": e.data.get("amount", 0)})
			Enums.EventType.UNIT_DIED:
				c["died"].append(e.data.get("instance", -1))
			Enums.EventType.DECK_DAMAGED:
				c["deck_amount"] = e.data.get("amount", 0)
	return c

static func next_speed(current: float, gap: float) -> float:
	if gap <= CHAIN_GAP:
		return minf(current + RAMP_STEP, MAX_SPEED)
	return 1.0

func reset_ramp() -> void:
	anim_speed = 1.0
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_combat_director.gd`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/combat_director.gd tests/test_combat_director.gd
git commit -m "feat: CombatDirector cluster parsing and speed ramp"
```

---

## Task 4: CombatDirector async recipe (`play`)

**Files:**
- Modify: `src/ui/match/combat_director.gd`
- Test: `tests/test_combat_director.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/test_combat_director.gd`. This drives a deterministic **deck attack**: it puts one fake unit on the human board (no engine legality needed), then runs the recipe and asserts the attacker returns to its rest slot and a damage number was spawned.

```gdscript
const MATCH := "res://src/ui/match/match.tscn"

func _spawn_match() -> Node:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(7, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	return m

func _put_unit_on_player_board(m: Node, iid: int) -> CardView:
	var def := CardDefinition.new()
	def.name = "Tester"
	def.type = Enums.CardType.MINION
	def.base_damage = 2
	def.base_health = 3
	var inst := CardInstance.new(iid, def)
	inst.current_damage = 2
	inst.current_health = 3
	m.player_board.render([inst], 0)
	await get_tree().create_timer(0.35).timeout   # let the render tween settle
	return m.player_board.card_views[iid]

func test_deck_attack_returns_attacker_home_and_spawns_number() -> void:
	var m := _spawn_match()
	var cv := await _put_unit_on_player_board(m, 42)
	var rest := cv._rest_position
	var fx_before: int = m.get_node("FxLayer").get_child_count()
	var events := [
		GameEvent.new(Enums.EventType.UNIT_ATTACKED, {"attacker": 42, "player": 0, "target_unit": -1}),
		GameEvent.new(Enums.EventType.DECK_DAMAGED, {"player": 1, "amount": 2}),
	]
	var director := CombatDirector.new()
	await director.play(events, m)
	assert_vector(cv.position).is_equal_approx(rest, Vector2(3, 3))
	assert_int(m.get_node("FxLayer").get_child_count()).is_greater(fx_before)

func test_play_no_attack_is_a_noop() -> void:
	var m := _spawn_match()
	var director := CombatDirector.new()
	# Must simply return without error when there is no attack cluster.
	await director.play([GameEvent.new(Enums.EventType.CARD_DRAWN, {"player": 0, "instance": 1})], m)
	assert_bool(true).is_true()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_combat_director.gd`
Expected: FAIL — `Invalid call. Nonexistent function 'play' in base 'RefCounted (CombatDirector)'`.

- [ ] **Step 3: Implement the recipe**

Add these constants near the top of `src/ui/match/combat_director.gd` (below `MAX_SPEED`):

```gdscript
const LUNGE_FRAC := 0.7      # fraction of the gap to a unit the attacker crosses
const WINDUP_DIST := 26.0    # pixels pulled back during anticipation
const DEATH_STAGGER := 0.06  # delay between staggered death pops
const PILE_BUMP_UP := 0.08
const PILE_BUMP_DOWN := 0.12
```

Add the ramp-timing field next to `anim_speed`:

```gdscript
var _last_end: float = -999.0
```

Then append the recipe and helpers to the file:

```gdscript
func play(events: Array, m) -> void:
	if not has_attack(events):
		return
	var c := parse_cluster(events)
	var atk: CardView = _find_unit(m, c["attacker"])
	if atk == null:
		return
	anim_speed = next_speed(anim_speed, _now() - _last_end)
	var spd := anim_speed
	var rest_pos: Vector2 = atk._rest_position
	var rest_rot: float = atk._rest_rotation
	var from_center := _center(atk)
	var target_center := _target_center(m, c)
	var to_target := target_center - from_center
	var dir := to_target.normalized()
	atk.z_index = 200

	# Anticipation: pull back away from the target.
	await CardJuice.windup(atk, rest_pos - dir * WINDUP_DIST, spd).finished
	# Lunge: full travel to the deck, partial overshoot into a unit.
	var frac := 1.0 if c["target_unit"] == -1 else LUNGE_FRAC
	await CardJuice.lunge(atk, rest_pos + to_target * frac, spd).finished
	# Hit-stop.
	await m.get_tree().create_timer(CardJuice.HITSTOP / maxf(spd, 0.01)).timeout
	# Impact: damage numbers, defender squash, deck-pile bump.
	_spawn_numbers(m, c)
	for d in c["damaged"]:
		if d["id"] != c["attacker"]:
			var dv: CardView = _find_unit(m, d["id"])
			if dv != null:
				CardJuice.squash(dv, spd)
	if c["target_unit"] == -1:
		_bump_pile(m, 1 - c["player"], spd)
	# Recoil home.
	await CardJuice.recoil(atk, rest_pos, rest_rot, spd).finished
	atk.z_index = 0
	# Death pops (staggered), before render_all sweeps them to the discard.
	var stagger := 0.0
	for died_id in c["died"]:
		var cv: CardView = _find_unit(m, died_id)
		if cv != null:
			if stagger > 0.0:
				await m.get_tree().create_timer(stagger).timeout
			await CardJuice.pop(cv, spd).finished
			stagger = DEATH_STAGGER
	_last_end = _now()

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _find_unit(m, iid: int) -> CardView:
	if m.player_board.card_views.has(iid):
		return m.player_board.card_views[iid]
	if m.opp_board.card_views.has(iid):
		return m.opp_board.card_views[iid]
	return null

func _center(cv: CardView) -> Vector2:
	return cv.global_position + cv.size * cv.scale * 0.5

func _target_center(m, c: Dictionary) -> Vector2:
	if c["target_unit"] == -1:
		return FlightAnchors.of(Enums.Zone.DECK, 1 - c["player"], m)
	var dv: CardView = _find_unit(m, c["target_unit"])
	if dv != null:
		return _center(dv)
	return FlightAnchors.of(Enums.Zone.DECK, 1 - c["player"], m)

func _spawn_numbers(m, c: Dictionary) -> void:
	var fx: Node = m.get_node("FxLayer")
	if c["target_unit"] == -1:
		var amt: int = c["deck_amount"]
		if amt > 0:
			DamageNumber.spawn(fx, FlightAnchors.of(Enums.Zone.DECK, 1 - c["player"], m), amt, amt >= 4)
		return
	for d in c["damaged"]:
		var cv: CardView = _find_unit(m, d["id"])
		if cv != null and d["amount"] > 0:
			DamageNumber.spawn(fx, _center(cv), d["amount"], d["amount"] >= 4)

func _bump_pile(m, deck_player: int, spd: float) -> void:
	var pile = m._player_deck if deck_player == m.HUMAN else m._opp_deck
	if pile == null:
		return
	var s = pile.scale
	var tw := pile.create_tween()
	tw.tween_property(pile, "scale", s * 1.18, PILE_BUMP_UP / maxf(spd, 0.01)).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(pile, "scale", s, PILE_BUMP_DOWN / maxf(spd, 0.01)).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_combat_director.gd`
Expected: PASS (10 tests).

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/combat_director.gd tests/test_combat_director.gd
git commit -m "feat: CombatDirector wind-up/lunge/recoil/death-pop recipe"
```

---

## Task 5: Wire the director into the match flow

**Files:**
- Modify: `src/ui/match/match.gd`
- Test: `tests/test_match_gating.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/test_match_gating.gd`:

```gdscript
extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"

func _spawn() -> Node:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(7, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	return m

func test_match_has_director() -> void:
	var m := _spawn()
	assert_object(m._director).is_not_null()

func test_end_turn_is_ignored_while_animating() -> void:
	var m := _spawn()
	# Human's turn; an end-turn would normally append events to the bus log.
	m._anim_busy = true
	var before: int = m.state.bus.log.size()
	m._on_end_turn_pressed()
	assert_int(m.state.bus.log.size()).is_equal(before)

func test_unit_click_is_ignored_while_animating() -> void:
	var m := _spawn()
	m._anim_busy = true
	# Should early-return without selecting an attacker or erroring.
	m.handle_unit_clicked(999)
	assert_int(m._selected_attacker).is_equal(-1)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_match_gating.gd`
Expected: FAIL — `Invalid get index '_director'` (member does not exist yet).

- [ ] **Step 3: Add the director, busy flag, and gating to `match.gd`**

In `src/ui/match/match.gd`, add the two members directly below the existing `var _targeting_for_choice: bool = false` / `var _target_candidates: Array = []` block (near line 12):

```gdscript
var _director := CombatDirector.new()
var _anim_busy: bool = false
```

Replace the existing `apply_action` (currently lines 69-78) with this coroutine version:

```gdscript
func apply_action(action: Action) -> void:
	var before := _snapshot_zones()
	var from := state.bus.log.size()
	engine.apply(action)
	var events := state.bus.log.slice(from)
	var plan := _enrich(TransitionPlan.compute(before, _snapshot_zones()))
	if CombatDirector.has_attack(events):
		_anim_busy = true
		await _director.play(events, self)
		_anim_busy = false
	render_all(plan)
	_spawn_pile_travelers(plan)
	_play_flourishes(events)
	_post_action()
```

Add a guard line as the first statement of each of these human-input handlers:

In `handle_unit_clicked` (currently line 299):
```gdscript
func handle_unit_clicked(instance_id: int) -> void:
	if _anim_busy:
		return
```

In `handle_deck_target_clicked` (currently line 314):
```gdscript
func handle_deck_target_clicked() -> void:
	if _anim_busy:
		return
```

In `_on_end_turn_pressed` (currently line 241):
```gdscript
func _on_end_turn_pressed() -> void:
	if _anim_busy:
		return
```

In `_on_hand_card_drag_released` (currently line 354):
```gdscript
func _on_hand_card_drag_released(instance_id: int, _at: Vector2) -> void:
	if _anim_busy:
		return
```

Finally, update `_play_flourishes` (currently lines 400-404) to pass the attack flag and reset the ramp at turn start:

```gdscript
func _play_flourishes(events: Array) -> void:
	Flourishes.play(self, events, CombatDirector.has_attack(events))
	for e in events:
		if e.type == Enums.EventType.TURN_STARTED:
			$Banner.show_turn(e.data["player"] == HUMAN)
			_director.reset_ramp()
```

> Note: `Flourishes.play` gains an `attack` parameter in Task 6. It has a default value there, so this call compiles and runs correctly whether Task 6 is done before or after — but run Task 6 before the full-suite run in Task 7.

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_match_gating.gd`
Expected: PASS (3 tests). (`Flourishes.play` still accepts 2 args today, so this compiles before Task 6.)

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/match.gd tests/test_match_gating.gd
git commit -m "feat: route attacks through CombatDirector with input gating"
```

---

## Task 6: Move combat damage numbers into the new system

**Files:**
- Modify: `src/ui/match/flourishes.gd`
- Test: `tests/test_match_flourish.gd` (add cases; keep existing)

The director now owns damage numbers for attack clusters. `Flourishes` should (a) upgrade its damage popup to the `DamageNumber` particle, and (b) skip `UNIT_DAMAGED` when the action was an attack so the same hit isn't drawn twice. The deck "MILL" feedback stays.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_match_flourish.gd`:

```gdscript
func test_attack_flag_suppresses_unit_damage_number() -> void:
	var m := _spawn()
	var before := m.get_node("FxLayer").get_child_count()
	# attack == true: the director already drew this number; Flourishes must skip it.
	Flourishes.play(m, [GameEvent.new(Enums.EventType.UNIT_DAMAGED, {"target": -1, "amount": 3})], true)
	assert_int(m.get_node("FxLayer").get_child_count()).is_equal(before)

func test_deck_mill_still_fires_during_attack() -> void:
	var m := _spawn()
	var before := m.get_node("FxLayer").get_child_count()
	Flourishes.play(m, [GameEvent.new(Enums.EventType.DECK_DAMAGED, {"player": 0, "amount": 2})], true)
	assert_int(m.get_node("FxLayer").get_child_count()).is_greater(before)
```

The existing `test_unit_damaged_spawns_damage_number_in_fxlayer` (2-arg call, no attack flag) must still pass — it relies on the new `attack` parameter defaulting to `false`.

- [ ] **Step 2: Run the tests to verify the new ones fail**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_match_flourish.gd`
Expected: FAIL on `test_attack_flag_suppresses_unit_damage_number` — `Flourishes.play` takes 2 args, not 3.

- [ ] **Step 3: Update `flourishes.gd`**

Replace the entire contents of `src/ui/match/flourishes.gd` with:

```gdscript
class_name Flourishes
extends RefCounted

# Lightweight, fire-and-forget reactions to engine events that the CombatDirector
# does NOT own. When `attack` is true, the director already drew the combat damage
# numbers and recoils, so we skip UNIT_DAMAGED here to avoid double popups. The
# deck "MILL" feedback always fires.

static func play(match_node, events: Array, attack: bool = false) -> void:
	for e in events:
		match e.type:
			Enums.EventType.UNIT_DAMAGED:
				if not attack:
					_damage_number(match_node, e.data.get("target", -1), e.data.get("amount", 0))
			Enums.EventType.DECK_DAMAGED:
				_mill_burst(match_node, e.data.get("player", -1))

static func _find_card_view(match_node, iid: int) -> CardView:
	for row in [match_node.player_board, match_node.opp_board]:
		if row.card_views.has(iid):
			return row.card_views[iid]
	return null

static func _damage_number(match_node, iid: int, amount: int) -> void:
	if amount <= 0:
		return
	var cv := _find_card_view(match_node, iid)
	var at := Vector2(960, 540)
	if cv != null:
		at = cv.global_position + cv.size * cv.scale * 0.5
	DamageNumber.spawn(match_node.get_node("FxLayer"), at, amount, amount >= 4)

static func _mill_burst(match_node, player: int) -> void:
	var pile = match_node._opp_discard if player == (1 - match_node.HUMAN) else match_node._player_discard
	var lbl := Label.new()
	lbl.text = "MILL"
	lbl.position = pile.position
	match_node.get_node("FxLayer").add_child(lbl)
	var t := lbl.create_tween()
	t.tween_property(lbl, "modulate:a", 0.0, 0.7)
	t.tween_callback(lbl.queue_free)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_match_flourish.gd`
Expected: PASS (existing cases + 2 new).

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/flourishes.gd tests/test_match_flourish.gd
git commit -m "refactor: Flourishes uses DamageNumber and yields combat to director"
```

---

## Task 7: Full-suite regression run

**Files:** none (verification only)

- [ ] **Step 1: Run the entire test suite**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
Expected: exit code `0`, all suites green. Pay special attention to `test_match_flow.gd`, `test_match_flourish.gd`, `test_integration_ui_game.gd`, `test_card_flight.gd`, and the three new suites.

- [ ] **Step 2: Manual smoke (optional but recommended)**

Launch the game (`godot --path .`), play a turn, and confirm: a unit attack winds up, lunges, and bounces home; damage numbers pop and fall; a killed unit pops before sweeping to the discard; attacking the deck flies the attacker over and back; rapid AI attacks visibly speed up. Human input is ignored mid-sequence.

- [ ] **Step 3: Commit (only if Step 2 prompted tuning)**

```bash
git add -A
git commit -m "tune: combat animation timings"
```

---

## Self-review

**Spec coverage:**
- Attacks (unit & deck): Task 4 recipe — wind-up/lunge/recoil for units, full fly-over for deck (`LUNGE_FRAC` vs `frac = 1.0`). ✓
- Deaths/destruction pop before discard: Task 4 death-pop loop + existing `render_all` leaver sweep. ✓
- Enhanced damage reactions: Task 1 `squash` applied to damaged defenders in Task 4. ✓
- Slay-the-Spire-2 falling damage numbers: Task 2 `DamageNumber`, spawned by director (Task 4) and flourishes (Task 6). ✓
- Choreographed & blocking pacing: Task 5 `await _director.play(...)` with `_anim_busy` gating. ✓
- Balatro speed ramp: Task 3 `next_speed` + Task 4 application + Task 5 reset on `TURN_STARTED`. ✓
- Edge cases (missing CardView, multiple deaths, no-attack no-op): Task 4 guards + `test_play_no_attack_is_a_noop`, staggered death loop. ✓
- GAME_OVER mid-sequence: `_post_action` runs after the awaited sequence in Task 5's `apply_action`, unchanged. ✓
- Tests mirror GdUnit4 patterns: all tasks. ✓

**Placeholder scan:** none — every code step is complete.

**Type consistency:** `CombatDirector.has_attack`/`parse_cluster`/`next_speed` (static) and `play`/`reset_ramp`/`anim_speed` (instance) are used consistently across Tasks 3-5. `DamageNumber.spawn(parent, at, amount, big)` signature matches all call sites (Tasks 2, 4, 6). `CardJuice.windup/lunge/recoil/squash/pop(cv, ..., speed)` match the director's calls. `Flourishes.play(match_node, events, attack := false)` is backward-compatible with the existing 2-arg call in `test_match_flourish.gd` and the new call in `match.gd`.
