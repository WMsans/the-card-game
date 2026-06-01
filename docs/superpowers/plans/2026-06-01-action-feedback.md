# Action Feedback for Every Card Action — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every card action (play, cast, deploy trap, trap fired, condition met, harmonize, rummage, trash) a clear, readable feedback beat, and add a clickable trap pile so deployed traps are visible.

**Architecture:** Mirror the existing `CombatDirector` split — a pure static mapping (`ActionCue.descriptors`) plus a thin async player (`ActionCue.play`) — and reuse the existing `PileView`/`PileOverlay` for the trap pile. Extract the shared speed-ramp and pile-bump into a `FeedbackFx` helper. Bespoke center-feature beats (spell cast, trap deploy) and the trap-fired enhancement live in `match.gd`, sequenced under the existing `_anim_busy` input lock. Every beat holds `HOLD_TIME = 2.0s`, ramping faster across a chain.

**Tech Stack:** Godot 4 / GDScript, gdUnit4 tests (headless).

**Spec:** `docs/superpowers/specs/2026-06-01-action-feedback-design.md`

---

## Conventions

**Run a single test suite** (replace `<file>`):

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/<file>
```

The `--import` step is only strictly needed once per worktree but is idempotent and safe to prepend.

**Commit cadence:** one commit per task (after its tests pass). End commit messages with:

```
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
```

---

## File Structure

**Create:**
- `src/ui/match/feedback_fx.gd` — shared `next_speed` ramp + `bump_pile` (extracted from `CombatDirector`).
- `src/ui/match/action_cue.gd` — `ActionCue`: pure `descriptors()` + async `play()` for unified in-place cues.
- `tests/test_feedback_fx.gd`, `tests/test_action_cue.gd`, `tests/test_card_juice.gd`, `tests/test_card_flight.gd` (if absent — check first), `tests/test_trap_pile.gd`.

**Modify:**
- `src/ui/match/card_juice.gd` — add `spring_wiggle`, `popup_in`, `popup_out`.
- `src/ui/card/card_flight.gd` — add `flourish_arc`.
- `src/ui/match/combat_director.gd` — delegate ramp + pile-bump to `FeedbackFx`.
- `src/ui/match/flight_anchors.gd` — add `Zone.TRAP_SET`.
- `src/ui/table/pile_overlay.gd` — add `face_down` param to `open()`.
- `src/ui/match/match.gd` — trap-pile wiring, feedback orchestration, bespoke beats.
- `src/ui/match/match.tscn` — add `PlayerTrap` / `OppTrap` pile instances.
- `src/ui/overlays/trap_reveal_overlay.gd`, `card_select_panel`, `option_prompt`, `leader_cost_prompt`, `mulligan_panel` — popup entrance.

---

## Task 1: `FeedbackFx` helper (extract ramp + pile-bump)

**Files:**
- Create: `src/ui/match/feedback_fx.gd`
- Create: `tests/test_feedback_fx.gd`
- Modify: `src/ui/match/combat_director.gd`

- [ ] **Step 1: Write the failing test**

`tests/test_feedback_fx.gd`:

```gdscript
extends GdUnitTestSuite

func test_next_speed_ramps_up_on_quick_chain() -> void:
	assert_float(FeedbackFx.next_speed(1.0, 0.1)).is_equal_approx(1.35, 0.001)

func test_next_speed_caps_at_max() -> void:
	assert_float(FeedbackFx.next_speed(2.4, 0.1)).is_equal_approx(2.5, 0.001)

func test_next_speed_resets_after_a_lull() -> void:
	assert_float(FeedbackFx.next_speed(2.0, 1.0)).is_equal_approx(1.0, 0.001)

func test_bump_pile_runs_without_error_and_restores_scale() -> void:
	var pile := Control.new()
	add_child(pile)
	auto_free(pile)
	pile.scale = Vector2.ONE
	FeedbackFx.bump_pile(pile, 1.0)
	await get_tree().create_timer(0.3).timeout
	assert_vector(pile.scale).is_equal_approx(Vector2.ONE, Vector2(0.02, 0.02))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_feedback_fx.gd`
Expected: FAIL — `Identifier "FeedbackFx" not declared`.

- [ ] **Step 3: Create `src/ui/match/feedback_fx.gd`**

```gdscript
class_name FeedbackFx
extends RefCounted

# Shared feedback constants + helpers used by CombatDirector and ActionCue.
const CHAIN_GAP := 0.6
const RAMP_STEP := 0.35
const MAX_SPEED := 2.5
const PILE_BUMP_UP := 0.08
const PILE_BUMP_DOWN := 0.12
const HOLD_TIME := 2.0

# Accelerate while beats chain quickly; reset to 1.0 after a lull.
static func next_speed(current: float, gap: float) -> float:
	if gap <= CHAIN_GAP:
		return minf(current + RAMP_STEP, MAX_SPEED)
	return 1.0

# Quick scale-punch on a pile Control (the "thunk").
static func bump_pile(pile: Control, spd: float) -> void:
	if pile == null:
		return
	var s: Vector2 = pile.scale
	var tw: Tween = pile.create_tween()
	tw.tween_property(pile, "scale", s * 1.18, PILE_BUMP_UP / maxf(spd, 0.01)).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(pile, "scale", s, PILE_BUMP_DOWN / maxf(spd, 0.01)).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
```

- [ ] **Step 4: Run test to verify it passes**

Run: same command as Step 2.
Expected: PASS (4 tests).

- [ ] **Step 5: Refactor `CombatDirector` to delegate to `FeedbackFx`**

In `src/ui/match/combat_director.gd`, replace the local ramp/bump implementation. Change `next_speed` to delegate and `_bump_pile` to call the helper. Specifically:

Replace:
```gdscript
static func next_speed(current: float, gap: float) -> float:
	if gap <= CHAIN_GAP:
		return minf(current + RAMP_STEP, MAX_SPEED)
	return 1.0
```
with:
```gdscript
static func next_speed(current: float, gap: float) -> float:
	return FeedbackFx.next_speed(current, gap)
```

Replace the body of `_bump_pile`:
```gdscript
func _bump_pile(m, deck_player: int, spd: float) -> void:
	var pile: Control = m._player_deck if deck_player == m.HUMAN else m._opp_deck
	FeedbackFx.bump_pile(pile, spd)
```

Leave the `CHAIN_GAP`/`RAMP_STEP`/`MAX_SPEED`/`PILE_BUMP_UP`/`PILE_BUMP_DOWN` constants in `CombatDirector` in place (they remain referenced by existing tests and other methods); they now simply mirror `FeedbackFx`.

- [ ] **Step 6: Run the combat-director test to confirm no regression**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_combat_director.gd`
Expected: PASS (existing suite unchanged).

- [ ] **Step 7: Commit**

```bash
git add src/ui/match/feedback_fx.gd tests/test_feedback_fx.gd src/ui/match/combat_director.gd
git commit -m "feat: extract FeedbackFx ramp/bump helper shared with CombatDirector

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `CardJuice.spring_wiggle`

**Files:**
- Modify: `src/ui/match/card_juice.gd`
- Create: `tests/test_card_juice.gd`

- [ ] **Step 1: Write the failing test**

`tests/test_card_juice.gd`:

```gdscript
extends GdUnitTestSuite

func _card() -> CardView:
	var cv: CardView = load("res://src/ui/card/card_view.tscn").instantiate()
	add_child(cv)
	auto_free(cv)
	return cv

func test_spring_wiggle_returns_to_upright() -> void:
	var cv := _card()
	cv.rotation = 0.0
	await CardJuice.spring_wiggle(cv, 10.0).finished
	assert_float(cv.rotation).is_equal_approx(0.0, 0.01)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_juice.gd`
Expected: FAIL — `Invalid call. Nonexistent function 'spring_wiggle'`.

- [ ] **Step 3: Add `spring_wiggle` to `src/ui/match/card_juice.gd`**

Add this constant near the top alongside the other `*_TIME` constants:
```gdscript
const WIGGLE_TIME := 0.5
```

Add this method at the end of the file:
```gdscript
# Balatro joker-trigger feel: tilt a few degrees, then elastically spring back to upright.
static func spring_wiggle(cv: CanvasItem, degrees: float = 9.0, speed: float = 1.0) -> Tween:
	var start := cv.rotation
	var t := _t(WIGGLE_TIME, speed)
	var tw := cv.create_tween()
	tw.tween_property(cv, "rotation", start + deg_to_rad(degrees), t * 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "rotation", start, t * 0.75).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	return tw
```

- [ ] **Step 4: Run test to verify it passes**

Run: same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/card_juice.gd tests/test_card_juice.gd
git commit -m "feat: add CardJuice.spring_wiggle

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `CardJuice.popup_in` / `popup_out`

**Files:**
- Modify: `src/ui/match/card_juice.gd`
- Modify: `tests/test_card_juice.gd`

- [ ] **Step 1: Add failing tests**

Append to `tests/test_card_juice.gd`:

```gdscript
func _panel() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(200, 200)
	c.size = Vector2(200, 200)
	add_child(c)
	auto_free(c)
	return c

func test_popup_in_ends_at_full_scale_and_alpha() -> void:
	var p := _panel()
	await CardJuice.popup_in(p).finished
	assert_vector(p.scale).is_equal_approx(Vector2.ONE, Vector2(0.01, 0.01))
	assert_float(p.modulate.a).is_equal_approx(1.0, 0.01)

func test_popup_out_ends_hidden() -> void:
	var p := _panel()
	await CardJuice.popup_out(p).finished
	assert_float(p.modulate.a).is_equal_approx(0.0, 0.01)
```

- [ ] **Step 2: Run to verify failure**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_juice.gd`
Expected: FAIL — `Nonexistent function 'popup_in'`.

- [ ] **Step 3: Add the methods**

Add to `src/ui/match/card_juice.gd`:
```gdscript
const POPUP_TIME := 0.28

# Bouncy entrance for card-displaying overlays: scale up with overshoot + fade in.
static func popup_in(panel: Control, speed: float = 1.0) -> Tween:
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.85, 0.85)
	panel.modulate.a = 0.0
	var t := _t(POPUP_TIME, speed)
	var tw := panel.create_tween().set_parallel(true)
	tw.tween_property(panel, "scale", Vector2.ONE, t).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, t * 0.6)
	return tw

static func popup_out(panel: Control, speed: float = 1.0) -> Tween:
	var t := _t(POPUP_TIME * 0.5, speed)
	var tw := panel.create_tween().set_parallel(true)
	tw.tween_property(panel, "scale", Vector2(0.9, 0.9), t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(panel, "modulate:a", 0.0, t)
	return tw
```

- [ ] **Step 4: Run to verify pass**

Run: same command as Step 2.
Expected: PASS (all `test_card_juice.gd` tests).

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/card_juice.gd tests/test_card_juice.gd
git commit -m "feat: add CardJuice.popup_in/popup_out overlay entrance

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: `CardFlight.flourish_arc`

**Files:**
- Modify: `src/ui/card/card_flight.gd`
- Test: `tests/test_card_flight.gd` (this suite already exists — append to it; if missing, create with `extends GdUnitTestSuite`)

- [ ] **Step 1: Add failing test**

Append to `tests/test_card_flight.gd`:

```gdscript
func test_flourish_arc_samples_a_curved_path() -> void:
	var from := Vector2(960, 540)
	var to := Vector2(1735, 855)
	var pts := CardFlight.arc_points(from, to, Vector2(0, -260), 6)
	# Endpoints honored.
	assert_vector(pts[0]).is_equal_approx(from, Vector2(0.5, 0.5))
	assert_vector(pts[pts.size() - 1]).is_equal_approx(to, Vector2(0.5, 0.5))
	# A genuine curve: the midpoint sits off the straight line between endpoints.
	var mid := pts[pts.size() / 2]
	var straight := from.lerp(to, 0.5)
	assert_float(mid.distance_to(straight)).is_greater(20.0)
```

- [ ] **Step 2: Run to verify failure**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_flight.gd`
Expected: FAIL — `Nonexistent function 'arc_points'`.

- [ ] **Step 3: Add `arc_points` (pure) and `flourish_arc` (tween)**

Add to `src/ui/card/card_flight.gd`:
```gdscript
const FLOURISH_TIME := 0.42

# Pure: sample a quadratic Bezier (from -> control -> to) into `segments`+1 points.
# `control_offset` bends the path off the straight line so it reads as a sweep.
static func arc_points(from_pos: Vector2, to_pos: Vector2, control_offset: Vector2, segments: int = 8) -> PackedVector2Array:
	var control := (from_pos + to_pos) * 0.5 + control_offset
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var a := from_pos.lerp(control, t)
		var b := control.lerp(to_pos, t)
		pts.append(a.lerp(b, t))
	return pts

# Fly a card along the sampled curve, scaling down slightly as it lands.
static func flourish_arc(cv: CardView, to_pos: Vector2, control_offset: Vector2, speed: float = 1.0) -> Tween:
	var base := cv.base_scale
	var pts := arc_points(cv.position, to_pos, control_offset, 8)
	var seg_time: float = (FLOURISH_TIME / maxf(speed, 0.01)) / float(pts.size() - 1)
	var tw := cv.create_tween()
	for i in range(1, pts.size()):
		tw.tween_property(cv, "position", pts[i], seg_time).set_trans(Tween.TRANS_LINEAR)
	tw.parallel().tween_property(cv, "scale", Vector2(base, base) * 0.55, FLOURISH_TIME / maxf(speed, 0.01)).set_trans(Tween.TRANS_QUAD)
	return tw
```

- [ ] **Step 4: Run to verify pass**

Run: same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/ui/card/card_flight.gd tests/test_card_flight.gd
git commit -m "feat: add CardFlight.flourish_arc curved sweep

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: `FlightAnchors` supports `Zone.TRAP_SET`

**Files:**
- Modify: `src/ui/match/flight_anchors.gd`
- Test: `tests/test_flight_anchors.gd` (exists — append)

This depends on the trap pile nodes existing on `match`. We add them to the scene in Task 8, but `FlightAnchors._pile_for` only needs the node references `m._player_trap` / `m._opp_trap`. We add those `@onready` references here and the scene nodes in Task 8; until then the test uses a stub match object.

- [ ] **Step 1: Add failing test**

Append to `tests/test_flight_anchors.gd`:

```gdscript
func test_trap_set_resolves_to_trap_pile_anchor() -> void:
	var stub := Control.new()
	add_child(stub)
	auto_free(stub)
	var player_trap := Control.new()
	player_trap.position = Vector2(1660, 280)
	player_trap.size = Vector2(150, 210)
	stub.add_child(player_trap)
	var opp_trap := Control.new()
	opp_trap.position = Vector2(1660, 520)
	opp_trap.size = Vector2(150, 210)
	stub.add_child(opp_trap)
	stub.set("_player_trap", player_trap)
	stub.set("_opp_trap", opp_trap)
	var at := FlightAnchors.of(Enums.Zone.TRAP_SET, 0, stub)
	assert_vector(at).is_equal_approx(player_trap.global_position + player_trap.size * 0.5, Vector2(1, 1))
```

- [ ] **Step 2: Run to verify failure**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_flight_anchors.gd`
Expected: FAIL — returns the fallback row center, not the trap pile center.

- [ ] **Step 3: Add the `TRAP_SET` case**

In `src/ui/match/flight_anchors.gd`, extend `_pile_for`:
```gdscript
static func _pile_for(zone: int, player: int, m):
	if zone == Enums.Zone.DECK:
		return m._player_deck if player == 0 else m._opp_deck
	if zone == Enums.Zone.DISCARD:
		return m._player_discard if player == 0 else m._opp_discard
	if zone == Enums.Zone.TRAP_SET:
		return m._player_trap if player == 0 else m._opp_trap
	return null
```

- [ ] **Step 4: Run to verify pass**

Run: same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/flight_anchors.gd tests/test_flight_anchors.gd
git commit -m "feat: FlightAnchors resolves Zone.TRAP_SET to trap pile

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: `PileOverlay.open` face-down mode

**Files:**
- Modify: `src/ui/table/pile_overlay.gd`
- Modify: `tests/test_pile_overlay.gd`

- [ ] **Step 1: Add failing test**

Append to `tests/test_pile_overlay.gd`:

```gdscript
func test_face_down_open_keeps_cards_face_down() -> void:
	var o := _overlay()
	o.open(_three_cards(), Vector2(1700, 400), "Opponent's Traps", true)
	# Wait past the normal flip window.
	await get_tree().create_timer(1.2).timeout
	var grid: GridContainer = o.find_child("Grid") as GridContainer
	for cv in grid.get_children():
		assert_bool(cv._face_down).is_true()

func test_default_open_flips_cards_face_up() -> void:
	var o := _overlay()
	o.open(_three_cards(), Vector2(1700, 400), "Your Traps")
	await get_tree().create_timer(1.2).timeout
	var grid: GridContainer = o.find_child("Grid") as GridContainer
	var any_face_up := false
	for cv in grid.get_children():
		if not cv._face_down:
			any_face_up = true
	assert_bool(any_face_up).is_true()
```

- [ ] **Step 2: Run to verify failure**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_pile_overlay.gd`
Expected: FAIL — `open()` takes 3 args, called with 4 (`test_face_down_open...`).

- [ ] **Step 3: Add the `face_down` parameter**

In `src/ui/table/pile_overlay.gd`:

Change the signature and store the flag:
```gdscript
var _face_down_mode: bool = false

func open(cards: Array[CardInstance], from_pos: Vector2, title: String, face_down: bool = false) -> void:
	if _open or cards.is_empty():
		return
	_face_down_mode = face_down
	_open = true
	...
```

In `_animate_in`, guard the flip schedule:
```gdscript
		CardFlight.fly_in(cv, from_local, delay)
		if not _face_down_mode:
			_schedule_flip(cv, delay + CardFlight.FLY_TIME * 0.6)
```

- [ ] **Step 4: Run to verify pass**

Run: same command as Step 2.
Expected: PASS (all `test_pile_overlay.gd` tests, including pre-existing ones).

- [ ] **Step 5: Commit**

```bash
git add src/ui/table/pile_overlay.gd tests/test_pile_overlay.gd
git commit -m "feat: PileOverlay face-down mode for hidden opponent piles

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Trap pile UI — scene nodes, counts, click-to-open

**Files:**
- Modify: `src/ui/match/match.tscn`
- Modify: `src/ui/match/match.gd`
- Create: `tests/test_trap_pile.gd`

- [ ] **Step 1: Add the two pile instances to `match.tscn`**

After the `OppLeader` pile node block (around line 125-131), add two more `pile_view` instances reusing `ExtResource("4_pile")`. Place the player trap in the player pile column and the opp trap in the opp pile column:

```
[node name="PlayerTrap" parent="Table" unique_id=512000201 instance=ExtResource("4_pile")]
layout_mode = 0
offset_left = 1660.0
offset_top = 310.0
offset_right = 1810.0
offset_bottom = 520.0

[node name="OppTrap" parent="Table" unique_id=512000202 instance=ExtResource("4_pile")]
layout_mode = 0
offset_left = 1810.0
offset_top = 270.0
offset_right = 1960.0
offset_bottom = 480.0
```

(These offsets place the trap piles beside the existing deck/discard columns; exact pixels can be nudged when running the app. The wiring test below does not assert positions.)

- [ ] **Step 2: Write the failing test**

`tests/test_trap_pile.gd`:

```gdscript
extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"
const STRIKE := "res://src/data/decks/strike.csv"

func _match() -> Node:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(7, STRIKE, STRIKE)
	await get_tree().create_timer(0.35).timeout
	return m

func _set_trap(m: Node, player: int, iid: int) -> void:
	var d := CardDefinition.new()
	d.type = Enums.CardType.TRAP
	d.name = "Snare"
	var inst := CardInstance.new(iid, d)
	inst.zone = Enums.Zone.TRAP_SET
	m.state.players[player].set_traps.append(inst)

func test_trap_pile_count_reflects_set_traps() -> void:
	var m := await _match()
	_set_trap(m, 0, 501)
	_set_trap(m, 0, 502)
	m.render_all()
	assert_str(m._player_trap.find_child("Count").text).is_equal("2")

func test_clicking_player_trap_opens_overlay() -> void:
	var m := await _match()
	_set_trap(m, 0, 501)
	m.render_all()
	m._on_trap_pile_clicked(0)
	assert_bool(m._pile_overlay.is_open()).is_true()

func test_clicking_empty_trap_pile_does_not_open() -> void:
	var m := await _match()
	m.render_all()
	m._on_trap_pile_clicked(0)
	assert_bool(m._pile_overlay.is_open()).is_false()
```

- [ ] **Step 3: Run to verify failure**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_trap_pile.gd`
Expected: FAIL — `Invalid get index '_player_trap'` (node references not declared).

- [ ] **Step 4: Wire the trap piles in `match.gd`**

Add `@onready` references after the existing leader pile refs (near line 38):
```gdscript
@onready var _player_trap = $Table/PlayerTrap
@onready var _opp_trap = $Table/OppTrap
```

In `_ready()`, after the existing pile `clicked` connections (near line 69), add:
```gdscript
	_player_trap.clicked.connect(_on_trap_pile_clicked.bind(HUMAN))
	_opp_trap.clicked.connect(_on_trap_pile_clicked.bind(1 - HUMAN))
```

In `render_all()`, after the leader counts (near line 130-131), add:
```gdscript
	_player_trap.set_count(you.set_traps.size())
	_opp_trap.set_count(opp.set_traps.size())
```

Add the click handler (near `_on_pile_clicked`, ~line 380):
```gdscript
func _on_trap_pile_clicked(player: int) -> void:
	if _anim_busy or _pile_overlay.is_open() or _selected_attacker != -1:
		return
	if _active_overlay != null and _minimized_overlay == null:
		return
	var cards: Array[CardInstance] = state.players[player].set_traps
	if cards.is_empty():
		return
	var pos := FlightAnchors.of(Enums.Zone.TRAP_SET, player, self)
	var title := "Your Traps" if player == HUMAN else "Opponent's Traps"
	_pile_overlay.open(cards, pos, title, player != HUMAN)
```

- [ ] **Step 5: Run to verify pass**

Run: same command as Step 3.
Expected: PASS (3 tests).

- [ ] **Step 6: Run the broader match suites for regressions**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_pile_view_wiring.gd`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/ui/match/match.tscn src/ui/match/match.gd tests/test_trap_pile.gd
git commit -m "feat: add clickable trap pile (face-down for opponent)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: `ActionCue.descriptors` (pure mapping)

**Files:**
- Create: `src/ui/match/action_cue.gd`
- Create: `tests/test_action_cue.gd`

- [ ] **Step 1: Write the failing test**

`tests/test_action_cue.gd`:

```gdscript
extends GdUnitTestSuite

func _ev(type: int, data: Dictionary) -> GameEvent:
	return GameEvent.new(type, data)

func test_minion_played_makes_played_cue_on_card() -> void:
	var ds := ActionCue.descriptors([_ev(Enums.EventType.CARD_PLAYED,
		{"player": 0, "instance": 7, "card_type": Enums.CardType.MINION})])
	assert_int(ds.size()).is_equal(1)
	assert_str(ds[0]["label"]).is_equal("PLAYED")
	assert_int(ds[0]["target_id"]).is_equal(7)
	assert_str(ds[0]["anchor"]).is_equal("card")

func test_spell_and_trap_played_make_no_generic_cue() -> void:
	var ds := ActionCue.descriptors([
		_ev(Enums.EventType.CARD_PLAYED, {"player": 0, "instance": 8, "card_type": Enums.CardType.SPELL}),
		_ev(Enums.EventType.CARD_PLAYED, {"player": 0, "instance": 9, "card_type": Enums.CardType.TRAP}),
	])
	assert_int(ds.size()).is_equal(0)

func test_request_met_makes_cue_on_card() -> void:
	var ds := ActionCue.descriptors([_ev(Enums.EventType.REQUEST_MET, {"player": 0, "instance": 5})])
	assert_str(ds[0]["label"]).is_equal("REQUEST MET")
	assert_int(ds[0]["target_id"]).is_equal(5)

func test_harmonize_makes_board_anchored_cue() -> void:
	var ds := ActionCue.descriptors([_ev(Enums.EventType.HARMONIZE, {"player": 1})])
	assert_str(ds[0]["label"]).is_equal("HARMONIZE")
	assert_str(ds[0]["anchor"]).is_equal("board")
	assert_int(ds[0]["player"]).is_equal(1)

func test_rummage_makes_discard_anchored_cue_with_count() -> void:
	var ds := ActionCue.descriptors([_ev(Enums.EventType.RUMMAGE_PERFORMED, {"player": 0, "count": 3})])
	assert_str(ds[0]["label"]).is_equal("RUMMAGE x3")
	assert_str(ds[0]["anchor"]).is_equal("discard")

func test_trashed_makes_cue_on_unit() -> void:
	var ds := ActionCue.descriptors([_ev(Enums.EventType.UNIT_TRASHED, {"owner": 0, "instance": 11})])
	assert_str(ds[0]["label"]).is_equal("TRASHED")
	assert_int(ds[0]["target_id"]).is_equal(11)

func test_passive_movement_events_make_no_cue() -> void:
	var ds := ActionCue.descriptors([
		_ev(Enums.EventType.CARD_DRAWN, {"player": 0, "instance": 1}),
		_ev(Enums.EventType.CARD_DISCARDED, {"player": 0, "instance": 2}),
		_ev(Enums.EventType.CARD_RUMMAGED, {"player": 0, "instance": 3}),
	])
	assert_int(ds.size()).is_equal(0)
```

- [ ] **Step 2: Run to verify failure**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_action_cue.gd`
Expected: FAIL — `Identifier "ActionCue" not declared`.

- [ ] **Step 3: Create `src/ui/match/action_cue.gd` with the pure mapping**

```gdscript
class_name ActionCue
extends RefCounted

const COL_PLAYED := Color(0.45, 1.0, 0.55)
const COL_REQUEST := Color(1.0, 0.85, 0.25)
const COL_HARMONIZE := Color(0.55, 0.8, 1.0)
const COL_RUMMAGE := Color(1.0, 0.7, 0.35)
const COL_TRASH := Color(0.8, 0.8, 0.85)

var anim_speed: float = 1.0
var _last_end: float = -999.0

# Pure: map events to in-place cue descriptors.
# Each descriptor: { label, color, target_id (instance or -1), anchor ("card"/"board"/"discard"), player }
static func descriptors(events: Array) -> Array:
	var out: Array = []
	for e in events:
		match e.type:
			Enums.EventType.CARD_PLAYED:
				if e.data.get("card_type", -1) == Enums.CardType.MINION:
					out.append(_card("PLAYED", COL_PLAYED, e.data.get("instance", -1), e.data.get("player", -1)))
			Enums.EventType.REQUEST_MET:
				out.append(_card("REQUEST MET", COL_REQUEST, e.data.get("instance", -1), e.data.get("player", -1)))
			Enums.EventType.UNIT_TRASHED:
				out.append(_card("TRASHED", COL_TRASH, e.data.get("instance", -1), e.data.get("owner", -1)))
			Enums.EventType.HARMONIZE:
				out.append({"label": "HARMONIZE", "color": COL_HARMONIZE, "target_id": -1, "anchor": "board", "player": e.data.get("player", -1)})
			Enums.EventType.RUMMAGE_PERFORMED:
				var n: int = e.data.get("count", 0)
				out.append({"label": "RUMMAGE x%d" % n, "color": COL_RUMMAGE, "target_id": -1, "anchor": "discard", "player": e.data.get("player", -1)})
	return out

static func _card(label: String, color: Color, iid: int, player: int) -> Dictionary:
	return {"label": label, "color": color, "target_id": iid, "anchor": "card", "player": player}
```

- [ ] **Step 4: Run to verify pass**

Run: same command as Step 2.
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/action_cue.gd tests/test_action_cue.gd
git commit -m "feat: ActionCue.descriptors pure event-to-cue mapping

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: `ActionCue.play` (animate cues, ramped) + wire into match

**Files:**
- Modify: `src/ui/match/action_cue.gd`
- Modify: `src/ui/match/match.gd`
- Modify: `tests/test_action_cue.gd`

- [ ] **Step 1: Add the integration test**

Append to `tests/test_action_cue.gd`:

```gdscript
const MATCH := "res://src/ui/match/match.tscn"
const STRIKE := "res://src/data/decks/strike.csv"

func _match() -> Node:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(7, STRIKE, STRIKE)
	await get_tree().create_timer(0.35).timeout
	return m

func test_play_spawns_a_label_for_harmonize() -> void:
	var m := await _match()
	var fx_before: int = m.get_node("FxLayer").get_child_count()
	var cue := ActionCue.new()
	# Use a single descriptor's worth of events; harmonize needs no card view.
	await cue.play(m, [GameEvent.new(Enums.EventType.HARMONIZE, {"player": 0})])
	assert_int(m.get_node("FxLayer").get_child_count()).is_greater(fx_before)

func test_play_with_no_cue_events_is_noop() -> void:
	var m := await _match()
	var fx_before: int = m.get_node("FxLayer").get_child_count()
	var cue := ActionCue.new()
	await cue.play(m, [GameEvent.new(Enums.EventType.CARD_DRAWN, {"player": 0, "instance": 1})])
	assert_int(m.get_node("FxLayer").get_child_count()).is_equal(fx_before)
```

- [ ] **Step 2: Run to verify failure**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_action_cue.gd`
Expected: FAIL — `Nonexistent function 'play'`.

- [ ] **Step 3: Add `play` and helpers to `action_cue.gd`**

```gdscript
func reset_ramp() -> void:
	anim_speed = 1.0

func play(m, events: Array) -> void:
	var ds := descriptors(events)
	if ds.is_empty():
		return
	for d in ds:
		anim_speed = FeedbackFx.next_speed(anim_speed, _now() - _last_end)
		var spd := anim_speed
		var at := _resolve_pos(m, d)
		var cv: CardView = _resolve_card(m, d["target_id"])
		if cv != null:
			cv.z_index = 150
			CardJuice.squash(cv, spd)
			CardJuice.spring_wiggle(cv, 8.0, spd)
			_tint(cv, d["color"], spd)
		_spawn_label(m, at, d["label"], d["color"])
		await m.get_tree().create_timer(FeedbackFx.HOLD_TIME / maxf(spd, 0.01)).timeout
		if cv != null:
			cv.z_index = 0
		_last_end = _now()

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _resolve_card(m, iid: int) -> CardView:
	if iid < 0:
		return null
	if m.player_board.card_views.has(iid):
		return m.player_board.card_views[iid]
	if m.opp_board.card_views.has(iid):
		return m.opp_board.card_views[iid]
	return null

func _resolve_pos(m, d: Dictionary) -> Vector2:
	match d["anchor"]:
		"card":
			var cv: CardView = _resolve_card(m, d["target_id"])
			if cv != null:
				return cv.global_position + cv.size * cv.scale * 0.5
			return Vector2(BoardLayout.CENTER_X, BoardLayout.SCREEN.y * 0.5)
		"discard":
			return FlightAnchors.of(Enums.Zone.DISCARD, d["player"], m)
		_: # "board"
			var y := BoardLayout.PLAYER_BOARD_Y if d["player"] == m.HUMAN else BoardLayout.OPP_BOARD_Y
			return Vector2(BoardLayout.CENTER_X, y)

func _tint(cv: CardView, color: Color, spd: float) -> void:
	var tw := cv.create_tween()
	tw.tween_property(cv, "modulate", color, 0.12 / maxf(spd, 0.01))
	tw.tween_property(cv, "modulate", Color.WHITE, (FeedbackFx.HOLD_TIME * 0.8) / maxf(spd, 0.01))

func _spawn_label(m, at: Vector2, text: String, color: Color) -> void:
	var fx: Node = m.get_node("FxLayer")
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = color
	lbl.z_index = 200
	fx.add_child(lbl)
	lbl.global_position = at - Vector2(0, 40)
	lbl.scale = Vector2(1.6, 1.6)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "global_position", lbl.global_position - Vector2(0, 30), FeedbackFx.HOLD_TIME)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.3)
	tw.tween_callback(lbl.queue_free)
```

- [ ] **Step 4: Wire into `match.gd`**

Add the instance field near `_director` (line 20):
```gdscript
var _action_cue := ActionCue.new()
```

Replace `apply_action` (lines 104-117) with a version that locks input across the whole feedback sequence and runs the unified cue after render:
```gdscript
func apply_action(action: Action) -> void:
	var before := _snapshot_zones()
	var from := state.bus.log.size()
	engine.apply(action)
	var events := state.bus.log.slice(from)
	var plan := _enrich(TransitionPlan.compute(before, _snapshot_zones()))
	_anim_busy = true
	if CombatDirector.has_attack(events):
		await _director.play(events, self)
	render_all(plan)
	_spawn_pile_travelers(plan)
	_play_flourishes(events)
	if not CombatDirector.has_attack(events):
		await _action_cue.play(self, events)
	_anim_busy = false
	_post_action()
```

In `_play_flourishes` (lines 481-486), reset the cue ramp alongside the existing director reset on `TURN_STARTED`:
```gdscript
func _play_flourishes(events: Array) -> void:
	Flourishes.play(self, events, CombatDirector.has_attack(events))
	for e in events:
		if e.type == Enums.EventType.TURN_STARTED:
			$Banner.show_turn(e.data["player"] == HUMAN)
			_director.reset_ramp()
			_action_cue.reset_ramp()
```

- [ ] **Step 5: Run to verify pass**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_action_cue.gd`
Expected: PASS (all tests).

- [ ] **Step 6: Regression — integration + combat suites**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_integration_ui_game.gd`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/ui/match/action_cue.gd src/ui/match/match.gd tests/test_action_cue.gd
git commit -m "feat: animate unified action cues with chain ramp

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 10: Bespoke beat — spell cast (center feature → wiggle → discard)

**Files:**
- Modify: `src/ui/match/match.gd`
- Modify: `tests/test_action_cue.gd` (routing test) — or create `tests/test_bespoke_beats.gd`

The bespoke beats run **before** `render_all` (the played card view still exists in `hand_view`). Add a `_run_feedback` step ahead of `render_all`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_bespoke_beats.gd`:

```gdscript
extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"
const STRIKE := "res://src/data/decks/strike.csv"

func _match() -> Node:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(7, STRIKE, STRIKE)
	await get_tree().create_timer(0.35).timeout
	return m

func _hand_card(m: Node, iid: int, type: int) -> CardView:
	var d := CardDefinition.new()
	d.type = type
	d.name = "Test"
	var inst := CardInstance.new(iid, d)
	inst.zone = Enums.Zone.HAND
	m.hand_view.render([inst], 0)
	await get_tree().create_timer(0.35).timeout
	return m.hand_view.card_views[iid]

func test_spell_feature_moves_card_toward_center() -> void:
	var m := await _match()
	var cv := await _hand_card(m, 301, Enums.CardType.SPELL)
	# Start the beat; sample position partway through the hold.
	m._feature_spell(301, 0)
	await get_tree().create_timer(0.4).timeout
	var center := Vector2(BoardLayout.CENTER_X, BoardLayout.SCREEN.y * 0.5)
	# It should be much closer to center than a hand card's resting Y (~940).
	assert_float(cv.global_position.y).is_less(700.0)
```

- [ ] **Step 2: Run to verify failure**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_bespoke_beats.gd`
Expected: FAIL — `Nonexistent function '_feature_spell'`.

- [ ] **Step 3: Add `_feature_spell` and a card-view lookup to `match.gd`**

Add a helper that finds a card view in any zone view:
```gdscript
func _find_card_view_any(iid: int) -> CardView:
	for view in [hand_view, player_board, opp_board, opp_hand]:
		if view.card_views.has(iid):
			return view.card_views[iid]
	return null
```

Add the spell beat:
```gdscript
const FEATURE_CENTER := Vector2(BoardLayout.CENTER_X, BoardLayout.SCREEN.y * 0.5)
const FEATURE_SCALE := 1.0

func _feature_spell(iid: int, player: int) -> void:
	var cv := _find_card_view_any(iid)
	if cv == null:
		return
	cv.z_index = 300
	var spd := _action_cue.anim_speed
	var center_topleft := FEATURE_CENTER - cv.size * FEATURE_SCALE * 0.5
	var tw := cv.create_tween().set_parallel(true)
	tw.tween_property(cv, "global_position", center_topleft, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "scale", Vector2(FEATURE_SCALE, FEATURE_SCALE), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	CardJuice.spring_wiggle(cv, 10.0, spd)
	await get_tree().create_timer(FeedbackFx.HOLD_TIME / maxf(spd, 0.01)).timeout
	var discard_pos := FlightAnchors.of(Enums.Zone.DISCARD, player, self) - cv.size * cv.scale * 0.5
	await CardFlight.fly_out(cv, discard_pos).finished
	cv.z_index = 0
```

(`CardFlight.fly_out` animates `position`, not `global_position`; since the card view is a child of `hand_view` at `Table` origin, screen and local coordinates coincide here as they do for the existing flight code — keep consistent with `_enrich`'s use of `_flight.to_local`. If positions drift in-app, convert via the same `to_local` pattern used in `apply_action`. Functionally the test only asserts the center move.)

- [ ] **Step 4: Run to verify pass**

Run: same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/match.gd tests/test_bespoke_beats.gd
git commit -m "feat: spell-cast bespoke center-feature beat

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 11: Bespoke beat — trap deploy (center feature → arc to trap pile)

**Files:**
- Modify: `src/ui/match/match.gd`
- Modify: `tests/test_bespoke_beats.gd`

- [ ] **Step 1: Add the failing test**

Append to `tests/test_bespoke_beats.gd`:

```gdscript
func test_trap_deploy_flips_card_face_down() -> void:
	var m := await _match()
	var cv := await _hand_card(m, 311, Enums.CardType.TRAP)
	assert_bool(cv._face_down).is_false()
	m._feature_trap_deploy(311, 0)
	# Past the center hold + the arc; the card should have flipped face-down en route.
	await get_tree().create_timer(FeedbackFx.HOLD_TIME + 0.8).timeout
	assert_bool(cv._face_down).is_true()
```

- [ ] **Step 2: Run to verify failure**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_bespoke_beats.gd`
Expected: FAIL — `Nonexistent function '_feature_trap_deploy'`.

- [ ] **Step 3: Add `_feature_trap_deploy` to `match.gd`**

```gdscript
func _feature_trap_deploy(iid: int, player: int) -> void:
	var cv := _find_card_view_any(iid)
	if cv == null:
		return
	cv.z_index = 300
	var spd := _action_cue.anim_speed
	var center_topleft := FEATURE_CENTER - cv.size * FEATURE_SCALE * 0.5
	var tw := cv.create_tween().set_parallel(true)
	tw.tween_property(cv, "global_position", center_topleft, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "scale", Vector2(FEATURE_SCALE, FEATURE_SCALE), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	await get_tree().create_timer(FeedbackFx.HOLD_TIME / maxf(spd, 0.01)).timeout
	cv.set_face_down(true)
	var pile_pos := FlightAnchors.of(Enums.Zone.TRAP_SET, player, self)
	var to_topleft := pile_pos - cv.size * (cv.base_scale * 0.55) * 0.5
	await CardFlight.flourish_arc(cv, to_topleft, Vector2(-220, -120), spd).finished
	var pile: Control = _player_trap if player == HUMAN else _opp_trap
	FeedbackFx.bump_pile(pile, spd)
	cv.z_index = 0
```

- [ ] **Step 4: Run to verify pass**

Run: same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/match.gd tests/test_bespoke_beats.gd
git commit -m "feat: trap-deploy bespoke arc-to-pile beat

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 12: Sequence bespoke beats into the feedback flow

**Files:**
- Modify: `src/ui/match/match.gd`
- Modify: `tests/test_bespoke_beats.gd`

Wire `_feature_spell` / `_feature_trap_deploy` so they run automatically (before `render_all`) when their `CARD_PLAYED` events occur.

- [ ] **Step 1: Add the failing test**

Append to `tests/test_bespoke_beats.gd`:

```gdscript
func test_run_feedback_features_a_played_spell() -> void:
	var m := await _match()
	var cv := await _hand_card(m, 321, Enums.CardType.SPELL)
	var events := [GameEvent.new(Enums.EventType.CARD_PLAYED,
		{"player": 0, "instance": 321, "card_type": Enums.CardType.SPELL})]
	m._run_bespoke(events)
	await get_tree().create_timer(0.4).timeout
	assert_float(cv.global_position.y).is_less(700.0)
```

- [ ] **Step 2: Run to verify failure**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_bespoke_beats.gd`
Expected: FAIL — `Nonexistent function '_run_bespoke'`.

- [ ] **Step 3: Add `_run_bespoke` and call it in `apply_action`**

Add:
```gdscript
func _run_bespoke(events: Array) -> void:
	for e in events:
		if e.type == Enums.EventType.CARD_PLAYED:
			match e.data.get("card_type", -1):
				Enums.CardType.SPELL:
					await _feature_spell(e.data.get("instance", -1), e.data.get("player", -1))
				Enums.CardType.TRAP:
					await _feature_trap_deploy(e.data.get("instance", -1), e.data.get("player", -1))
```

In `apply_action`, insert the bespoke call between the attack director and `render_all`:
```gdscript
	_anim_busy = true
	if CombatDirector.has_attack(events):
		await _director.play(events, self)
	else:
		await _run_bespoke(events)
	render_all(plan)
	_spawn_pile_travelers(plan)
	_play_flourishes(events)
	if not CombatDirector.has_attack(events):
		await _action_cue.play(self, events)
	_anim_busy = false
	_post_action()
```

- [ ] **Step 4: Run to verify pass**

Run: same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Regression — full play/integration suites**

Run each and expect PASS:
```bash
godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_integration_ui_game.gd
godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_engine_play.gd
```

- [ ] **Step 6: Commit**

```bash
git add src/ui/match/match.gd tests/test_bespoke_beats.gd
git commit -m "feat: sequence bespoke spell/trap beats into apply_action

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 13: Popup entrance for all card popups + trap-fired enhancement

**Files:**
- Modify: `src/ui/overlays/trap_reveal_overlay.gd`
- Modify: `src/ui/overlays/card_select_panel.gd`
- Modify: `src/ui/overlays/option_prompt.gd`
- Modify: `src/ui/overlays/leader_cost_prompt.gd`
- Modify: `src/ui/overlays/mulligan_panel.gd`
- Modify: `src/ui/match/match.gd` (trap pile flash on `TRAP_FIRED`, read-only hold → 2.0s)
- Test: `tests/test_trap_reveal_overlay.gd`

- [ ] **Step 1: Inspect each overlay's show/visible entry point**

Run: `grep -n "visible = true\|func show\|@onready var.*Panel\|func _ready" src/ui/overlays/trap_reveal_overlay.gd src/ui/overlays/card_select_panel.gd src/ui/overlays/option_prompt.gd src/ui/overlays/leader_cost_prompt.gd src/ui/overlays/mulligan_panel.gd`

Each overlay sets `visible = true` (directly or in a `show_*` method) and has a root panel node (e.g. `$Center/Panel`). Note the panel node path for each.

- [ ] **Step 2: Add a failing test for the trap-reveal entrance**

Append to `tests/test_trap_reveal_overlay.gd` (match the existing setup pattern in that file for instantiating the overlay and building a trap `CardInstance`):

```gdscript
func test_show_reveal_pops_panel_in() -> void:
	var o = load("res://src/ui/overlays/trap_reveal_overlay.tscn").instantiate()
	add_child(o)
	auto_free(o)
	var d := CardDefinition.new()
	d.type = Enums.CardType.TRAP
	d.name = "Snare"
	var inst := CardInstance.new(1, d)
	o.show_reveal(inst, "Trap!", [], false)
	# Entrance starts below full scale.
	var panel: Control = o.get_node("Center/Panel")
	await get_tree().process_frame
	assert_float(panel.scale.x).is_less(1.0)
	await get_tree().create_timer(0.4).timeout
	assert_float(panel.scale.x).is_equal_approx(1.0, 0.02)
```

- [ ] **Step 3: Run to verify failure**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_trap_reveal_overlay.gd`
Expected: FAIL — panel stays at scale 1.0 (no entrance).

- [ ] **Step 4: Add `CardJuice.popup_in` to each overlay's reveal path**

In `trap_reveal_overlay.gd`, at the end of `show_reveal`, replace the bare `visible = true` with:
```gdscript
	visible = true
	CardJuice.popup_in($Center/Panel)
```

Apply the same one-line `CardJuice.popup_in(<panel node>)` immediately after the point where each of the other overlays becomes visible, using the panel path identified in Step 1:
- `card_select_panel.gd`
- `option_prompt.gd`
- `leader_cost_prompt.gd`
- `mulligan_panel.gd`

For `PileOverlay`, it is already animated (card fly-in); add `CardJuice.popup_in($Title)` after setting the title in `open()` so the title pops too (optional polish — keep if the panel layout has a `$Title`).

- [ ] **Step 5: Trap-fired pile flash + read-only hold to 2.0s**

In `match.gd`, update `_show_readonly_intercept` (lines 259-263) so the firing trap's pile bumps and the hold matches `HOLD_TIME`:
```gdscript
func _show_readonly_intercept(pc: PendingChoice) -> void:
	var spec: ChoiceSpec = pc.data["spec"]
	FeedbackFx.bump_pile(_opp_trap if pc.player != HUMAN else _player_trap, 1.0)
	_trap_reveal.show_reveal(spec.cards[0], spec.title, spec.labels, false)
	await get_tree().create_timer(FeedbackFx.HOLD_TIME).timeout
	_trap_reveal.dismiss()
```

- [ ] **Step 6: Run to verify pass**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_trap_reveal_overlay.gd`
Expected: PASS.

- [ ] **Step 7: Regression — overlay suites**

Run each and expect PASS:
```bash
godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_overlays.gd
godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_mulligan_panel.gd
```

- [ ] **Step 8: Commit**

```bash
git add src/ui/overlays/*.gd src/ui/match/match.gd tests/test_trap_reveal_overlay.gd
git commit -m "feat: bouncy popup entrance + trap-fired pile flash/hold

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 14: Full-suite regression + manual visual pass

**Files:** none (verification only)

- [ ] **Step 1: Run the whole test suite**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```
Expected: all suites PASS. Fix any regressions before continuing.

- [ ] **Step 2: Manual visual check (run the app)**

Launch the game and confirm, against the spec:
- Playing a minion → "PLAYED" pop on the new board card, held ~2s.
- Casting a spell → flies to center, spring-wiggles, holds ~2s, flies to discard.
- Deploying a trap → flies to center, holds ~2s, arcs into the trap pile face-down with a thunk.
- Clicking your trap pile → traps face-up; clicking the opponent's → face-down; both show counts.
- A request being met / harmonize / rummage / trash each show their labeled cue.
- A trap firing → trap pile flashes and the reveal overlay bounces in (holds ~2s).
- All popups (mulligan, selection, options, leader cost) bounce in rather than snapping.
- Multiple cues in one action play sequentially and visibly speed up across the chain.

- [ ] **Step 3: Final commit (if any manual nudges to scene offsets were needed)**

```bash
git add -A
git commit -m "chore: tune action-feedback scene offsets after visual pass

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review Notes (coverage map)

- Spec §1 unified cue → Tasks 8, 9 (descriptors + play, ramp, labels, tint, spring/pop).
- Spec §2 trap pile → Tasks 5, 6, 7 (anchor, face-down overlay, scene nodes + wiring + counts).
- Spec §3a spell cast → Task 10; §3b trap deploy → Tasks 4, 11 (flourish_arc + beat). Sequencing → Task 12.
- Spec §4 trap fired → Task 13 (pile flash + 2.0s hold + popup entrance).
- Spec §5 popup entrance → Tasks 3, 13.
- Spec §6 timing/sequencing → Tasks 1 (FeedbackFx ramp/HOLD_TIME), 9, 12 (input lock via `_anim_busy`).
- Spec testing bullets → covered by `test_feedback_fx`, `test_action_cue`, `test_card_juice`, `test_card_flight`, `test_pile_overlay`, `test_flight_anchors`, `test_trap_pile`, `test_bespoke_beats`, `test_trap_reveal_overlay`.
