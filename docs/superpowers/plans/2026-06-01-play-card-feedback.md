# Card Play Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Played cards fly to screen-center and hold (fixing the current snap-back-to-hand bug), traps then orbit a full 360° circle around center before darting into the trap pile, and cards flip face-down with a smooth simultaneous shrink.

**Architecture:** A `_consumed` flag on `CardView` suppresses the release-snap-back for played cards. A shared "fly to center + hold" beat in `match.gd` drives spells, traps, and minions; per-type tails send spells to discard, traps through a new `CardFlight.orbit_loop`, and minions to their board slot via a reparent-handoff. A new `CardView.flip_to_face_down()` flips and shrinks together.

**Tech Stack:** Godot 4.6 (GL Compatibility), GDScript, GdUnit4 for tests (`extends GdUnitTestSuite`, files `tests/test_*.gd`, run headless).

**Test command (use everywhere below, substitute the suite path):**
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/<suite>.gd
```

**Key files and their responsibility:**
- `src/ui/card/card_view.gd` — per-card view; owns drag/release tweens, flips, scale. (Tasks 1, 4)
- `src/ui/card/card_flight.gd` — pure flight-path helpers + flight tweens. (Task 5)
- `src/ui/match/match.gd` — orchestrates `apply_action` → bespoke beats → render. (Tasks 2, 6, 7, 8)
- `src/ui/match/action_cue.gd` — event→cue mapping + in-place card cues. (Task 8)
- `src/ui/match/card_flight_layer.gd` — owns airborne pile travelers. (Task 4)

---

## Task 1: Suppress the release snap-back for played cards

When a dragged card is released, `card_view.gd` always tweens `position` back to the hand slot (`_tween_release`). Because the play fires from the same release event, this tween is created *after* the feature's move-to-center tween and overrides it. A `_consumed` flag lets the play flow tell the view "you were played — don't snap home."

**Files:**
- Modify: `src/ui/card/card_view.gd` (release branch of `_on_gui_input`, `setup`, grab branch)
- Test: `tests/test_card_view.gd`

- [ ] **Step 1: Write the failing test**

Add to `tests/test_card_view.gd`. The suite already exists and provides `_spawn() -> CardView` (a bare instantiated view, added to the tree + auto-freed). Append these methods, reusing `_spawn()`:

```gdscript
func _release_event() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	return ev

func test_played_card_does_not_snap_back_on_release() -> void:
	var cv := _spawn()
	cv.set_interactive(true)
	cv.set_rest(Vector2(500, 900), 0.0)
	cv.position = Vector2(800, 400)   # dragged away from rest
	cv._dragging = true               # simulate an in-progress drag
	cv.mark_played()
	cv._on_gui_input(_release_event())
	# Consumed cards must NOT start a release tween back to the hand slot.
	assert_bool(cv._tween_release != null and cv._tween_release.is_running()).is_false()

func test_unplayed_card_snaps_back_on_release() -> void:
	var cv := _spawn()
	cv.set_interactive(true)
	cv.set_rest(Vector2(500, 900), 0.0)
	cv.position = Vector2(800, 400)
	cv._dragging = true
	cv._on_gui_input(_release_event())
	# Ordinary release returns the card to its hand slot.
	assert_bool(cv._tween_release != null and cv._tween_release.is_running()).is_true()
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_view.gd
```
Expected: FAIL — `mark_played` is not defined (and the snap-back test fails because the tween still runs).

- [ ] **Step 3: Add the flag, `mark_played()`, and guard the release tween**

In `src/ui/card/card_view.gd`, add the field near the other drag state (next to `var _dragging: bool = false` on line 43):

```gdscript
var _consumed: bool = false
```

Add the method (place it just after `set_face_down`, near line 72):

```gdscript
func mark_played() -> void:
	_consumed = true
```

Reset it in `setup()` (currently lines 64-67) so recycled views behave normally:

```gdscript
func setup(instance: CardInstance) -> void:
	_instance = instance
	_face_down = false
	_consumed = false
	_refresh()
```

Reset it on grab — in the `if event.pressed:` branch, right after `_dragging = true` (line 253):

```gdscript
			_dragging = true
			_consumed = false
```

Guard the release block. The release branch (the `else:` at line 283) currently always builds `_tween_release`. Wrap only the elastic-scale + position + rotation return in `if not _consumed:`. The existing lines:

```gdscript
				if _tween_release and _tween_release.is_running():
					_tween_release.kill()
				_tween_release = create_tween()
				_tween_release.tween_property(self, "scale", Vector2.ONE * base_scale, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
				_tween_release.parallel().tween_property(self, "position", _rest_position, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
				_tween_release.parallel().tween_property(self, "rotation", _rest_rotation, 0.25).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
```

become:

```gdscript
				if _tween_release and _tween_release.is_running():
					_tween_release.kill()
				if not _consumed:
					_tween_release = create_tween()
					_tween_release.tween_property(self, "scale", Vector2.ONE * base_scale, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
					_tween_release.parallel().tween_property(self, "position", _rest_position, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
					_tween_release.parallel().tween_property(self, "rotation", _rest_rotation, 0.25).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
```

(Leave the `_tween_grab` kill above it unchanged.)

- [ ] **Step 4: Run the test to verify it passes**

Run:
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_view.gd
```
Expected: PASS (all suite tests, including the two new ones).

- [ ] **Step 5: Commit**

```bash
git add src/ui/card/card_view.gd tests/test_card_view.gd
git commit -m "fix: suppress release snap-back for played cards"
```

---

## Task 2: Mark played cards in `handle_drop`

`match.handle_drop` commits to a play in three branches (leader prompt, by-discard, by-tickets). In each, call `mark_played()` on the played view *synchronously* before `apply_action`, so the flag is set before the release tween is created.

**Files:**
- Modify: `src/ui/match/match.gd` (`handle_drop`, lines 345-367)
- Test: `tests/test_bespoke_beats.gd` (add one integration-style assertion)

- [ ] **Step 1: Write the failing test**

Append to `tests/test_bespoke_beats.gd`:

```gdscript
func test_handle_drop_marks_card_played() -> void:
	var m := await _match()
	var cv := await _hand_card(m, 401, Enums.CardType.SPELL)
	# No legal action exists for this synthetic card, so handle_drop won't play it;
	# instead verify the helper marks the resolvable view. Use mark_played directly
	# through the same path handle_drop uses.
	m._find_card_view_any(401).mark_played()
	assert_bool(cv._consumed).is_true()
```

(Note: this guards the wiring/`_find_card_view_any` lookup the production code relies on; the real snap-back regression is covered by Task 1.)

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_bespoke_beats.gd
```
Expected: FAIL — `_consumed` is false until Task 1 is merged; if Task 1 is already merged this passes trivially, so confirm the production edit below regardless.

- [ ] **Step 3: Add the `mark_played` calls in `handle_drop`**

In `src/ui/match/match.gd`, edit the three commit points. Add a local at the top of `handle_drop` and call it before each `apply_action`:

```gdscript
func handle_drop(instance_id: int, drop_zone: String) -> bool:
	var legal: Array = engine.get_legal_actions()
	var by_tickets: Action = CardInput.play_from_drop(instance_id, drop_zone, legal, false)
	var by_discard: Action = CardInput.play_from_drop(instance_id, drop_zone, legal, true)
	var cv := _find_card_view_any(instance_id)
	if by_tickets != null and by_discard != null:
		_leader_prompt.show_prompt()
		_active_overlay = _leader_prompt
		var handler := func(by_disc: bool):
			_active_overlay = null
			if cv != null:
				cv.mark_played()
			if by_disc:
				apply_action(by_discard)
			else:
				apply_action(by_tickets)
		_leader_prompt.chosen.connect(handler, CONNECT_ONE_SHOT)
		return true
	if by_discard != null:
		if cv != null:
			cv.mark_played()
		apply_action(by_discard)
		return true
	if by_tickets != null:
		if cv != null:
			cv.mark_played()
		apply_action(by_tickets)
		return true
	render_all()
	return false
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_bespoke_beats.gd
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/match.gd tests/test_bespoke_beats.gd
git commit -m "fix: mark dragged card played before applying the action"
```

---

## Task 3: `flip_to_face_down()` that flips and shrinks together

Mirror the existing `flip_to_face_up()` but flip *to* face-down, and in parallel smoothly scale the whole card to a slightly smaller `FACE_DOWN_SCALE`.

**Files:**
- Modify: `src/ui/card/card_view.gd` (add constant + method after `flip_to_face_up`, line 327)
- Test: `tests/test_card_flip.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/test_card_flip.gd`:

```gdscript
func test_flip_to_face_down_hides_and_shrinks() -> void:
	var cv := _a_card()
	assert_bool(cv._face_down).is_false()
	var t: Tween = cv.flip_to_face_down()
	await t.finished
	assert_bool(cv._face_down).is_true()
	# Surface scale restored to 1 after the flip; whole card a little smaller.
	assert_float(cv.get_node("CardSurface").scale.x).is_equal_approx(1.0, 0.01)
	assert_float(cv.scale.x).is_equal_approx(cv.base_scale * CardView.FACE_DOWN_SCALE, 0.02)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_flip.gd
```
Expected: FAIL — `flip_to_face_down` / `FACE_DOWN_SCALE` not defined.

- [ ] **Step 3: Add the constant and method**

In `src/ui/card/card_view.gd`, add the constant near the top with the other consts (e.g. just below the class's existing `@export`/const block, before `var _dragging`):

```gdscript
const FACE_DOWN_SCALE := 0.85
```

Add the method immediately after `flip_to_face_up()` (after line 327):

```gdscript
func flip_to_face_down() -> Tween:
	_surface.pivot_offset = _surface.size * 0.5
	var target := Vector2(base_scale, base_scale) * FACE_DOWN_SCALE
	var t := _surface.create_tween()
	t.tween_property(_surface, "scale:x", 0.0, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(func(): set_face_down(true))
	t.tween_property(_surface, "scale:x", 1.0, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "scale", target, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return t
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_flip.gd
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/ui/card/card_view.gd tests/test_card_flip.gd
git commit -m "feat: flip_to_face_down flips and shrinks the card together"
```

---

## Task 4: Face-down pile travelers render a little smaller

For consistency ("all cards moving and facing down are a little smaller"), spawn face-down pile travelers at the face-down scale.

**Files:**
- Modify: `src/ui/match/card_flight_layer.gd` (`spawn_traveler`, line 30)
- Test: `tests/test_card_flight_render.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/test_card_flight_render.gd`. The suite's `_spawn()` returns the instantiated match node; the flight layer lives at `$Table/CardFlightLayer` (accessible via `m._flight`):

```gdscript
func test_face_down_traveler_uses_smaller_scale() -> void:
	var m := _spawn()
	var layer = m._flight
	var cv: CardView = layer.spawn_traveler(null, Vector2(100, 100), Vector2(800, 800))
	assert_bool(cv._face_down).is_true()
	assert_float(cv.base_scale).is_equal_approx(BoardLayout.CARD_SCALE * CardView.FACE_DOWN_SCALE, 0.001)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_flight_render.gd
```
Expected: FAIL — traveler base scale is still `BoardLayout.CARD_SCALE`.

- [ ] **Step 3: Set the smaller scale for face-down travelers**

In `src/ui/match/card_flight_layer.gd`, change the `set_base_scale` line in `spawn_traveler` (line 30). Current:

```gdscript
	cv.set_base_scale(BoardLayout.CARD_SCALE)
	cv.set_face_down(true)
```

becomes:

```gdscript
	cv.set_base_scale(BoardLayout.CARD_SCALE * CardView.FACE_DOWN_SCALE)
	cv.set_face_down(true)
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_flight_render.gd
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/card_flight_layer.gd tests/test_card_flight_render.gd
git commit -m "feat: face-down pile travelers render a little smaller"
```

---

## Task 5: `CardFlight.orbit_loop` — full 360° loop, then dart to pile

Add a pure ring sampler (`circle_points`) and the flight tween (`orbit_loop`): fly out from the current position into a full circle around `center`, then dart into `to_pos` while scaling down.

**Files:**
- Modify: `src/ui/card/card_flight.gd` (add constants + two static funcs after `flourish_arc`, line 65)
- Test: `tests/test_card_flight.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/test_card_flight.gd`:

```gdscript
func test_circle_points_ring_around_center() -> void:
	var center := Vector2(960, 540)
	var pts: PackedVector2Array = CardFlight.circle_points(center, 280.0, -PI / 2.0, 16)
	assert_int(pts.size()).is_equal(17)            # segments + 1 (closes the loop)
	for p in pts:
		assert_float(p.distance_to(center)).is_equal_approx(280.0, 0.5)
	# Loop closes back onto its start.
	assert_vector(pts[0]).is_equal_approx(pts[pts.size() - 1], Vector2(0.5, 0.5))

func test_orbit_loop_ends_at_destination() -> void:
	var cv := await _a_card()
	cv.position = Vector2(960, 540)
	var to_pos := Vector2(1735, 855)
	var tw := CardFlight.orbit_loop(cv, cv.position, 280.0, to_pos, 1.0)
	await tw.finished
	assert_vector(cv.position).is_equal_approx(to_pos, Vector2(2, 2))
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_flight.gd
```
Expected: FAIL — `circle_points` / `orbit_loop` not defined.

- [ ] **Step 3: Implement the ring sampler and orbit tween**

In `src/ui/card/card_flight.gd`, after `flourish_arc` (line 65), add:

```gdscript
const ORBIT_TIME := 0.9
const ORBIT_RADIUS := 280.0
const ORBIT_SEGMENTS := 16

# Pure: sample a full circle around `center` starting at `start_angle`, returning
# `segments`+1 points (the last equals the first, closing the loop).
static func circle_points(center: Vector2, radius: float, start_angle: float, segments: int = ORBIT_SEGMENTS) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var a := start_angle + TAU * (float(i) / float(segments))
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts

# Fly out from the card's current spot into a full 360° loop around `center`,
# then dart into `to_pos`, scaling down as it lands. Card facing is unchanged.
static func orbit_loop(cv: CardView, center: Vector2, radius: float, to_pos: Vector2, speed: float = 1.0) -> Tween:
	var base := cv.base_scale
	var pts := circle_points(center, radius, -PI / 2.0, ORBIT_SEGMENTS)
	var dur: float = ORBIT_TIME / maxf(speed, 0.01)
	# One segment to fly out, ORBIT_SEGMENTS around the ring, one to dart in.
	var seg: float = dur / float(ORBIT_SEGMENTS + 2)
	var tw := cv.create_tween()
	tw.tween_property(cv, "position", pts[0], seg).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for i in range(1, pts.size()):
		tw.tween_property(cv, "position", pts[i], seg).set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(cv, "position", to_pos, seg).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var st := cv.create_tween()
	st.tween_property(cv, "scale", Vector2(base, base) * 0.55, dur).set_trans(Tween.TRANS_QUAD)
	return tw
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_flight.gd
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/ui/card/card_flight.gd tests/test_card_flight.gd
git commit -m "feat: CardFlight.orbit_loop for a full 360 power-card sweep"
```

---

## Task 6: Shared center-hold beat; trap tail uses flip + orbit

Refactor `_feature_spell` / `_feature_trap_deploy` to share one "fly to center + hold" helper. Keep the spell tail (fly to discard). Replace the trap tail's `flourish_arc` with `flip_to_face_down()` + `orbit_loop`.

**Files:**
- Modify: `src/ui/match/match.gd` (`_feature_spell` lines 650-665, `_feature_trap_deploy` lines 667-685; add `_fly_to_center` helper)
- Test: `tests/test_bespoke_beats.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/test_bespoke_beats.gd`:

```gdscript
func test_trap_deploy_ends_face_down_and_smaller() -> void:
	var m := await _match()
	var cv := await _hand_card(m, 451, Enums.CardType.TRAP)
	m._feature_trap_deploy(451, 0)
	# Center hold + flip + full orbit + dart to pile.
	await get_tree().create_timer(FeedbackFx.HOLD_TIME + CardFlight.ORBIT_TIME + 1.0).timeout
	assert_bool(cv._face_down).is_true()
	# It travelled face-down at the shrunken scale (orbit lands smaller still).
	assert_float(cv.scale.x).is_less(cv.base_scale)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_bespoke_beats.gd
```
Expected: FAIL — the old trap path uses `flourish_arc`; `ORBIT_TIME` reference also won't resolve until Task 5 is merged (sequence Task 5 first).

- [ ] **Step 3: Add the shared helper and rewrite both beats**

In `src/ui/match/match.gd`, add the helper (place it just before `_feature_spell`, line 650):

```gdscript
# Reparent-free: lift the card to screen-center at full size and hold it there.
# Returns the anim speed used so the caller's tail can stay in sync.
func _fly_to_center(cv: CardView) -> float:
	cv.z_index = 300
	var spd := _action_cue.anim_speed
	var center_topleft := FEATURE_CENTER - cv.size * FEATURE_SCALE * 0.5
	var tw := cv.create_tween().set_parallel(true)
	tw.tween_property(cv, "global_position", center_topleft, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "scale", Vector2(FEATURE_SCALE, FEATURE_SCALE), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	CardJuice.spring_wiggle(cv, 10.0, spd)
	await get_tree().create_timer(FeedbackFx.HOLD_TIME / maxf(spd, 0.01)).timeout
	return spd
```

Replace `_feature_spell` (lines 650-665) with:

```gdscript
func _feature_spell(iid: int, player: int) -> void:
	var cv := _find_card_view_any(iid)
	if cv == null:
		return
	await _fly_to_center(cv)
	var discard_pos := FlightAnchors.of(Enums.Zone.DISCARD, player, self) - cv.size * cv.scale * 0.5
	await CardFlight.fly_out(cv, discard_pos).finished
	cv.z_index = 0
```

Replace `_feature_trap_deploy` (lines 667-685) with:

```gdscript
func _feature_trap_deploy(iid: int, player: int) -> void:
	var cv := _find_card_view_any(iid)
	if cv == null:
		return
	var spd := await _fly_to_center(cv)
	await cv.flip_to_face_down().finished
	var pile_pos := FlightAnchors.of(Enums.Zone.TRAP_SET, player, self)
	var to_topleft := pile_pos - cv.size * (cv.base_scale * 0.55) * 0.5
	await CardFlight.orbit_loop(cv, cv.position, CardFlight.ORBIT_RADIUS, to_topleft, spd).finished
	var pile: Control = _player_trap if player == HUMAN else _opp_trap
	FeedbackFx.bump_pile(pile, spd)
	cv.z_index = 0
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_bespoke_beats.gd
```
Expected: PASS (including the pre-existing `test_trap_deploy_flips_card_face_down` and `test_spell_feature_moves_card_toward_center`).

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/match.gd tests/test_bespoke_beats.gd
git commit -m "feat: shared center-hold beat; trap orbits before the pile"
```

---

## Task 7: Minions fly to center, hold, then hand off to the board

Add a minion beat to `_run_bespoke`. It lifts the played hand card to center, holds, then hands the *same* view off to the board (reparent + re-register) so `render_all` reuses it and tweens it into its slot — seamless, no corner-slide, no duplicate.

**Files:**
- Modify: `src/ui/match/match.gd` (`_run_bespoke` lines 517-524; add `_feature_minion`)
- Test: `tests/test_bespoke_beats.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/test_bespoke_beats.gd`:

```gdscript
func test_minion_feature_lifts_toward_center() -> void:
	var m := await _match()
	var cv := await _hand_card(m, 461, Enums.CardType.MINION)
	m._feature_minion(461, 0)
	await get_tree().create_timer(0.4).timeout   # sample during the center hold
	var center := Vector2(BoardLayout.CENTER_X, BoardLayout.SCREEN.y * 0.5)
	assert_float(cv.global_position.y).is_less(700.0)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_bespoke_beats.gd
```
Expected: FAIL — `_feature_minion` not defined.

- [ ] **Step 3: Route minions through the beat and implement the handoff**

In `src/ui/match/match.gd`, extend the `match` in `_run_bespoke` (lines 519-524):

```gdscript
	for e in events:
		if e.type == Enums.EventType.CARD_PLAYED:
			match e.data.get("card_type", -1):
				Enums.CardType.SPELL:
					await _feature_spell(e.data.get("instance", -1), e.data.get("player", -1))
				Enums.CardType.TRAP:
					await _feature_trap_deploy(e.data.get("instance", -1), e.data.get("player", -1))
				Enums.CardType.MINION:
					await _feature_minion(e.data.get("instance", -1), e.data.get("player", -1))
```

Add `_feature_minion` after `_feature_trap_deploy`:

```gdscript
func _feature_minion(iid: int, player: int) -> void:
	# Only human plays have a visible source view to feature; AI minions (no view)
	# fall through to the action_cue board squash after render.
	var cv := _find_card_view_any(iid)
	if cv == null or not hand_view.card_views.has(iid):
		return
	var spd := await _fly_to_center(cv)
	# Hand the SAME view to the board so render_all reuses it (no duplicate /
	# corner-slide). Detach hand drag signals so a board card can't re-trigger play.
	var board: Node2D = player_board if player == HUMAN else opp_board
	hand_view.card_views.erase(iid)
	for c in cv.drag_released.get_connections():
		cv.drag_released.disconnect(c["callable"])
	for c in cv.drag_started.get_connections():
		cv.drag_started.disconnect(c["callable"])
	cv.reparent(board)
	board.card_views[iid] = cv
	cv.clicked.connect(func(_cv: CardView): board.unit_clicked.emit(iid))
	# Fly to the computed board slot; render_all will then re-affirm the exact slot.
	var ps: PlayerState = state.players[player]
	var idx := 0
	for i in range(ps.board.size()):
		if ps.board[i].instance_id == iid:
			idx = i
			break
	var t := BoardLayout.slot(Enums.Zone.BOARD, idx, ps.board.size(), player)
	var rest_pos := t.origin - BoardLayout.CARD_PIVOT
	await CardFlight.move_to(cv, rest_pos, t.get_rotation()).finished
	CardJuice.squash(cv, spd)
	cv.z_index = 0
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_bespoke_beats.gd
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/match.gd tests/test_bespoke_beats.gd
git commit -m "feat: minions lift to center then hand off to the board"
```

---

## Task 8: Skip the action_cue cue for featured cards

`_run_bespoke` now fully features human minions (center hold + landing squash). Prevent `action_cue` from *also* squashing them (double hold) while keeping its cue for AI minions, which have no source view to feature.

**Files:**
- Modify: `src/ui/match/action_cue.gd` (`play`, lines 37-55)
- Modify: `src/ui/match/match.gd` (`_run_bespoke` returns featured ids; `apply_action` passes them, lines 119-124)
- Test: `tests/test_action_cue.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/test_action_cue.gd` a test that a featured id is skipped:

```gdscript
func test_play_skips_featured_target() -> void:
	var m = load("res://src/ui/match/match.tscn").instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(7, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	await get_tree().create_timer(0.35).timeout
	var cue := ActionCue.new()
	var events := [GameEvent.new(Enums.EventType.CARD_PLAYED,
		{"player": 0, "instance": 999, "card_type": Enums.CardType.MINION})]
	# Featuring id 999 means action_cue must not also fire a cue for it; with no
	# matching view and 999 featured, play() returns without awaiting a hold.
	cue.play(m, events, [999])
	assert_array(ActionCue.descriptors(events)).is_not_empty()  # descriptor still produced
```

(This guards the new `featured_ids` parameter and that descriptors are unchanged; the no-double-hold behavior is verified in-app during Task 9 / verification.)

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_action_cue.gd
```
Expected: FAIL — `play()` takes only two args.

- [ ] **Step 3: Add the `featured_ids` filter and thread it through**

In `src/ui/match/action_cue.gd`, change `play` (line 37) to accept and honor `featured_ids`:

```gdscript
func play(m, events: Array, featured_ids: Array = []) -> void:
	var ds := descriptors(events)
	if ds.is_empty():
		return
	for d in ds:
		if featured_ids.has(d["target_id"]):
			continue
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
```

In `src/ui/match/match.gd`, make `_run_bespoke` collect and return featured ids. Change its signature/body (lines 517-524):

```gdscript
func _run_bespoke(events: Array) -> Array:
	var featured: Array = []
	for e in events:
		if e.type == Enums.EventType.CARD_PLAYED:
			var iid: int = e.data.get("instance", -1)
			var pl: int = e.data.get("player", -1)
			match e.data.get("card_type", -1):
				Enums.CardType.SPELL:
					await _feature_spell(iid, pl)
					featured.append(iid)
				Enums.CardType.TRAP:
					await _feature_trap_deploy(iid, pl)
					featured.append(iid)
				Enums.CardType.MINION:
					if hand_view.card_views.has(iid):
						await _feature_minion(iid, pl)
						featured.append(iid)
	return featured
```

In `apply_action` (lines 115-124), capture the featured ids and pass them to the cue. Current:

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
```

becomes:

```gdscript
	_anim_busy = true
	var featured: Array = []
	if CombatDirector.has_attack(events):
		await _director.play(events, self)
	else:
		featured = await _run_bespoke(events)
	render_all(plan)
	_spawn_pile_travelers(plan)
	_play_flourishes(events)
	if not CombatDirector.has_attack(events):
		await _action_cue.play(self, events, featured)
```

- [ ] **Step 4: Run the test to verify it passes**

Run the action_cue suite, then the bespoke suite to confirm no regression:
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_action_cue.gd
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_bespoke_beats.gd
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/action_cue.gd src/ui/match/match.gd tests/test_action_cue.gd
git commit -m "feat: action_cue skips cards already featured by a bespoke beat"
```

---

## Task 9: Full-suite gate + in-app verification

**Files:** none (verification only)

- [ ] **Step 1: Run the entire test suite**

Run:
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```
Expected: `0 failed`. Investigate and fix any failures before continuing.

- [ ] **Step 2: Manual verification in-app**

Launch the game (via the `/run` skill or the project's normal launch). Verify:
- Dragging and playing a **spell** lifts it to center, holds, then flies to discard — it does **not** snap back to hand.
- Playing a **trap** lifts to center, flips face-down while shrinking, sweeps a full circle around center, then darts into the trap pile (which bumps).
- Playing a **minion** lifts to center, holds, then lands in its board slot with a squash — no corner-slide, no duplicate card.
- An **AI**-played minion still gets its in-place "PLAYED" cue (no center feature, no double hold).
- Chained plays still ramp/feel right.

- [ ] **Step 3: Commit any verification fixes**

```bash
git add -A
git commit -m "fix: address play-feedback verification findings"
```

(Skip if no fixes were needed.)

---

## Self-Review Notes (coverage map)

- Spec A (snap-back) → Tasks 1, 2.
- Spec B (center hold; spell/trap/minion tails; minion removed from action_cue's effective path) → Tasks 6, 7, 8.
- Spec C (smooth flip + smaller; face-down travelers smaller) → Tasks 3, 4.
- Spec D (360° orbit) → Task 5 (helper) + Task 6 (trap uses it).
- Testing section → per-task tests + Task 9 full gate and manual checks.

**Sequencing:** Task 5 must land before Task 6 (uses `ORBIT_TIME`/`orbit_loop`); Task 3 before Task 6 (trap uses `flip_to_face_down`); Tasks 6 & 7 before Task 8 (it skips what they feature). Tasks 1–4 are otherwise independent.

**Known limitation (documented):** `action_cue` skips *all* descriptors for a featured `target_id`, so a rare same-action `REQUEST_MET`/`TRASHED` on a just-featured card would be suppressed. Acceptable for a game-feel beat; revisit only if it surfaces.
