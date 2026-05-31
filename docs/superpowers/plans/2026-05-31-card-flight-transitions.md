# Card Flight Transitions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make cards visibly travel between zones (draw, rummage, mill, discard, death, reshuffle) with Balatro-grade juice — arcs, overshoot-settle, dealt-card stagger, and a back→front squash flip — instead of popping into existence or dissolving in place.

**Architecture:** Per-zone `CardView` ownership stays. A pure `TransitionPlan` diffs each card's zone before/after an action; `match.gd` enriches those transitions with pile screen positions via `FlightAnchors`, threads the plan through the existing zone `render` calls, and drives pile→pile travelers on a `CardFlightLayer`. A shared `CardFlight` tween library is the one juicy mover, reused by the zone views and (later) the in-hand selection overlay. The flip is a scale-x squash on the inner `CardSurface` node.

**Tech Stack:** Godot 4 / GDScript, GdUnit4 tests (`extends GdUnitTestSuite`, files `tests/test_*.gd`).

**Test command (headless, one suite):**
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/<suite>.gd
```
Exit code 0 = pass. Harmless headless noise to ignore: `ERROR: Required object "rp_font" is null` and the "InputEvents not transported in headless" notice.

---

## File Structure

- **Create** `src/ui/match/transition_plan.gd` — pure `TransitionPlan` helper: diff `{id -> {zone, player}}` snapshots into an ordered zone-change list. No scene deps, fully unit-testable.
- **Create** `src/ui/match/flight_anchors.gd` — static `FlightAnchors.of(zone, player, match_node)`: maps `DECK`/`DISCARD` to that player's pile node center.
- **Create** `src/ui/card/card_flight.gd` — static `CardFlight` tween library: `fly_in`, `fly_out`, `move_to`. The one shared juicy mover.
- **Create** `src/ui/match/card_flight_layer.gd` — `Node2D` container owning airborne nodes (reparented leavers + pile→pile travelers); frees them on landing.
- **Modify** `src/ui/card/card_view.gd` — add `flip_to_face_up()` (scale-x squash on `$CardSurface`).
- **Modify** `src/ui/table/hand_view.gd` — `render(cards, player, plan := [])`: fly-in pile-sourced new cards, emit `card_departed` for pile-bound leavers.
- **Modify** `src/ui/table/board_view.gd` — `render(units, player, plan := [])`: emit `card_departed` for pile-bound leavers (death/put-on-deck).
- **Modify** `src/ui/match/match.gd` + `src/ui/match/match.tscn` — add `CardFlightLayer` node + `_flight`; snapshot/diff/enrich; thread plan into `render_all`; spawn pile travelers; wire `card_departed`.
- **Create** test suites: `tests/test_transition_plan.gd`, `tests/test_flight_anchors.gd`, `tests/test_card_flight.gd`, `tests/test_card_flip.gd`, `tests/test_card_flight_layer.gd`, `tests/test_card_flight_render.gd`, `tests/test_match_transitions.gd`.
- **Modify** `docs/superpowers/plans/2026-05-31-in-hand-card-selection.md` — dependency note + swap its two hand-rolled tweens for `CardFlight.move_to`.

**Coordinate convention (used throughout):** a `CardView`'s `position` is the unscaled top-left; it scales/rotates about `pivot_offset = CARD_PIVOT = (175, 245)`, so the point `position + CARD_PIVOT` is the card's visual center and is invariant under scale. To center a card on a screen point `C`, set `position = C - BoardLayout.CARD_PIVOT` — exactly what `BoardLayout.slot(...).origin - CARD_PIVOT` already does for hand/board.

---

## Task 1: `TransitionPlan` pure helper

**Files:**
- Create: `src/ui/match/transition_plan.gd`
- Test: `tests/test_transition_plan.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_transition_plan.gd`:

```gdscript
extends GdUnitTestSuite

# before/after are { instance_id(int) -> { "zone": int, "player": int } }.

func test_detects_zone_change() -> void:
	var before := {10: {"zone": Enums.Zone.DECK, "player": 0}}
	var after := {10: {"zone": Enums.Zone.HAND, "player": 0}}
	var plan := TransitionPlan.compute(before, after)
	assert_int(plan.size()).is_equal(1)
	assert_int(plan[0]["instance_id"]).is_equal(10)
	assert_int(plan[0]["from"]).is_equal(Enums.Zone.DECK)
	assert_int(plan[0]["to"]).is_equal(Enums.Zone.HAND)
	assert_int(plan[0]["player"]).is_equal(0)

func test_ignores_unchanged_zone() -> void:
	var before := {10: {"zone": Enums.Zone.HAND, "player": 0}}
	var after := {10: {"zone": Enums.Zone.HAND, "player": 0}}
	assert_array(TransitionPlan.compute(before, after)).is_empty()

func test_ignores_cards_absent_before() -> void:
	var before := {}
	var after := {10: {"zone": Enums.Zone.HAND, "player": 0}}
	assert_array(TransitionPlan.compute(before, after)).is_empty()

func test_multiple_changes_preserve_after_order() -> void:
	var before := {10: {"zone": Enums.Zone.DECK, "player": 0},
		20: {"zone": Enums.Zone.DECK, "player": 0}}
	var after := {10: {"zone": Enums.Zone.HAND, "player": 0},
		20: {"zone": Enums.Zone.HAND, "player": 0}}
	var plan := TransitionPlan.compute(before, after)
	assert_int(plan.size()).is_equal(2)
	assert_int(plan[0]["instance_id"]).is_equal(10)
	assert_int(plan[1]["instance_id"]).is_equal(20)
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_transition_plan.gd
```
Expected: FAIL — `TransitionPlan` is not defined.

- [ ] **Step 3: Write the implementation**

Create `src/ui/match/transition_plan.gd`:

```gdscript
class_name TransitionPlan
extends RefCounted

# Pure zone-change diff for card flight transitions. `before`/`after` are
# snapshots of the form { instance_id(int) -> { "zone": int, "player": int } }.
# Returns an ordered Array of { "instance_id": int, "from": int, "to": int,
# "player": int } for every card whose zone changed. Order follows `after`'s
# iteration order, which drives the deal stagger. Scene-free and unit-testable.

static func compute(before: Dictionary, after: Dictionary) -> Array:
	var out: Array = []
	for iid in after:
		if not before.has(iid):
			continue
		var b: Dictionary = before[iid]
		var a: Dictionary = after[iid]
		if b["zone"] != a["zone"]:
			out.append({
				"instance_id": iid,
				"from": b["zone"],
				"to": a["zone"],
				"player": a["player"],
			})
	return out
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_transition_plan.gd
```
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/transition_plan.gd tests/test_transition_plan.gd
git commit -m "feat: TransitionPlan pure zone-change diff for card flights"
```

---

## Task 2: `FlightAnchors` pile position helper

**Files:**
- Create: `src/ui/match/flight_anchors.gd`
- Test: `tests/test_flight_anchors.gd`

**Context:** Hand/board flight endpoints are the card's own computed slot (the zone view already knows it). Only the pile endpoints (`DECK`/`DISCARD`) need a lookup, which maps to the pile `Control` nodes already living in `match.gd` (`_player_deck`, `_player_discard`, `_opp_deck`, `_opp_discard`). `FlightAnchors.of` returns the pile's screen **center**; callers subtract `CARD_PIVOT` to get the card top-left.

- [ ] **Step 1: Write the failing test**

Create `tests/test_flight_anchors.gd`:

```gdscript
extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"

func _spawn() -> Node:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(7, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	return m

func test_deck_anchor_is_player_deck_center() -> void:
	var m := _spawn()
	var expected: Vector2 = m._player_deck.global_position + m._player_deck.size * 0.5
	assert_vector(FlightAnchors.of(Enums.Zone.DECK, 0, m)).is_equal_approx(expected, Vector2(1, 1))

func test_discard_anchor_is_player_discard_center() -> void:
	var m := _spawn()
	var expected: Vector2 = m._player_discard.global_position + m._player_discard.size * 0.5
	assert_vector(FlightAnchors.of(Enums.Zone.DISCARD, 0, m)).is_equal_approx(expected, Vector2(1, 1))

func test_opponent_deck_anchor_uses_opp_pile() -> void:
	var m := _spawn()
	var expected: Vector2 = m._opp_deck.global_position + m._opp_deck.size * 0.5
	assert_vector(FlightAnchors.of(Enums.Zone.DECK, 1, m)).is_equal_approx(expected, Vector2(1, 1))
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_flight_anchors.gd
```
Expected: FAIL — `FlightAnchors` is not defined.

- [ ] **Step 3: Write the implementation**

Create `src/ui/match/flight_anchors.gd`:

```gdscript
class_name FlightAnchors
extends RefCounted

# Screen-space anchor (center) for a flight endpoint. Only piles need a lookup;
# HAND/BOARD endpoints are the card's own slot, supplied by the zone view.
# Callers subtract BoardLayout.CARD_PIVOT to convert this center to a card
# top-left position.

static func of(zone: int, player: int, match_node) -> Vector2:
	var pile = _pile_for(zone, player, match_node)
	if pile != null:
		return pile.global_position + pile.size * 0.5
	# Fallback (HAND/BOARD or unknown) — a sane row center, rarely used.
	var y := BoardLayout.PLAYER_HAND_Y if player == 0 else BoardLayout.OPP_HAND_Y
	return Vector2(BoardLayout.CENTER_X, y)

static func _pile_for(zone: int, player: int, m):
	if zone == Enums.Zone.DECK:
		return m._player_deck if player == 0 else m._opp_deck
	if zone == Enums.Zone.DISCARD:
		return m._player_discard if player == 0 else m._opp_discard
	return null
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_flight_anchors.gd
```
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/flight_anchors.gd tests/test_flight_anchors.gd
git commit -m "feat: FlightAnchors pile-position lookup for card flights"
```

---

## Task 3: `CardFlight` tween library

**Files:**
- Create: `src/ui/card/card_flight.gd`
- Test: `tests/test_card_flight.gd`

**Context:** The single juicy mover. `fly_in` places a card at a source point then arcs it to its already-set `_rest_position` with an overshoot scale-pop (draw/rummage landing). `fly_out` slides a card to a pile and shrinks it (death/discard). `move_to` repositions an on-screen card with an overshoot-settle (hand reflow and, later, the in-hand selection staging). All read `cv.base_scale` and `cv._rest_position`, which the zone views set before calling.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_card_flight.gd`:

```gdscript
extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"

# A real CardView from a populated hand (base_scale already set to CARD_SCALE).
# Wait out the initial render tween so it can't race the flight tween under test.
func _a_card() -> CardView:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(3, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	await get_tree().create_timer(0.35).timeout
	return m.hand_view.card_views.values()[0]

func test_fly_in_starts_at_source_and_lands_at_rest() -> void:
	var cv := await _a_card()
	cv.set_rest(Vector2(500, 900), 0.0)
	var tw := CardFlight.fly_in(cv, Vector2(1700, 800))
	# Placed at the source synchronously, before the tween steps.
	assert_vector(cv.position).is_equal_approx(Vector2(1700, 800), Vector2(1, 1))
	await tw.finished
	assert_vector(cv.position).is_equal_approx(Vector2(500, 900), Vector2(1.5, 1.5))
	assert_float(cv.scale.x).is_equal_approx(cv.base_scale, 0.02)

func test_fly_out_moves_to_destination() -> void:
	var cv := await _a_card()
	var tw := CardFlight.fly_out(cv, Vector2(1700, 600))
	await tw.finished
	assert_vector(cv.position).is_equal_approx(Vector2(1700, 600), Vector2(1.5, 1.5))

func test_move_to_reaches_target() -> void:
	var cv := await _a_card()
	var tw := CardFlight.move_to(cv, Vector2(700, 850), 0.0)
	await tw.finished
	assert_vector(cv.position).is_equal_approx(Vector2(700, 850), Vector2(2, 2))
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_flight.gd
```
Expected: FAIL — `CardFlight` is not defined.

- [ ] **Step 3: Write the implementation**

Create `src/ui/card/card_flight.gd`:

```gdscript
class_name CardFlight
extends RefCounted

# The shared juicy mover for card transitions. Durations/curves are tuned to the
# existing 0.25s render-tween family; constants are free to tweak.

const FLY_TIME := 0.34
const STAGGER := 0.06      # per-card deal delay
const ARC_HEIGHT := 80.0   # how high flights bow upward

# Place `cv` at `from_pos` (top-left), then arc it to its already-set
# _rest_position with a landing scale-pop. `delay` staggers multi-card deals.
static func fly_in(cv: CardView, from_pos: Vector2, delay: float = 0.0) -> Tween:
	cv.position = from_pos
	var rest: Vector2 = cv._rest_position
	var mid := (from_pos + rest) * 0.5 + Vector2(0.0, -ARC_HEIGHT)
	var base := cv.base_scale
	var tw := cv.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(cv, "position", mid, FLY_TIME * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "position", rest, FLY_TIME * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(cv, "scale", Vector2(base, base) * 1.12, FLY_TIME * 0.55).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(cv, "scale", Vector2(base, base), 0.12).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	return tw

# Slide `cv` to a pile anchor and shrink it. Caller frees the node on finished.
static func fly_out(cv: CardView, to_pos: Vector2, delay: float = 0.0) -> Tween:
	var base := cv.base_scale
	var tw := cv.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(cv, "position", to_pos, FLY_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(cv, "scale", Vector2(base, base) * 0.7, FLY_TIME).set_trans(Tween.TRANS_CUBIC)
	return tw

# Reposition an already-on-screen card with an overshoot-settle (hand reflow,
# in-hand selection staging).
static func move_to(cv: CardView, pos: Vector2, rot: float, delay: float = 0.0) -> Tween:
	var tw := cv.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(cv, "position", pos, FLY_TIME * 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "rotation", rot, FLY_TIME * 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tw
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_flight.gd
```
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/ui/card/card_flight.gd tests/test_card_flight.gd
git commit -m "feat: CardFlight shared tween library (fly_in/fly_out/move_to)"
```

---

## Task 4: `CardView` squash flip

**Files:**
- Modify: `src/ui/card/card_view.gd`
- Test: `tests/test_card_flip.gd`

**Context:** The card face lives in a single `$CardSurface` (`SubViewportContainer`) that shows whichever texture the viewport renders (back or front, toggled by `set_face_down`). A two-sided flip squashes `CardSurface.scale.x` to 0, swaps the face at the sliver, then back to 1 — isolated on the inner node so it never fights the root `CardView` scale used by `base_scale`/hover/drag. We center the squash by setting `pivot_offset` to the surface center first.

- [ ] **Step 1: Write the failing test**

Create `tests/test_card_flip.gd`:

```gdscript
extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"

func _a_card() -> CardView:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(3, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	return m.hand_view.card_views.values()[0]

func test_flip_reveals_face_up_and_restores_scale() -> void:
	var cv := _a_card()
	cv.set_face_down(true)
	assert_bool(cv._face_down).is_true()
	var t := cv.flip_to_face_up()
	await t.finished
	assert_bool(cv._face_down).is_false()
	assert_float(cv.get_node("CardSurface").scale.x).is_equal_approx(1.0, 0.01)
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_flip.gd
```
Expected: FAIL — `flip_to_face_up` not found.

- [ ] **Step 3: Implement the change**

In `src/ui/card/card_view.gd`, append this method to the end of the file (after `dissolve()`):

```gdscript
# Back-to-front squash flip on the inner CardSurface only, so it never fights the
# root CardView scale (base_scale / hover / drag). The face content swaps at the
# edge-on sliver. Returns the tween so callers can await it.
func flip_to_face_up() -> Tween:
	_surface.pivot_offset = _surface.size * 0.5
	var t := _surface.create_tween()
	t.tween_property(_surface, "scale:x", 0.0, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(func(): set_face_down(false))
	t.tween_property(_surface, "scale:x", 1.0, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return t
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_flip.gd
```
Expected: PASS (1 test).

- [ ] **Step 5: Run the existing card_view suite to confirm no regression**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_view.gd
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/ui/card/card_view.gd tests/test_card_flip.gd
git commit -m "feat: CardView.flip_to_face_up squash flip"
```

---

## Task 5: `CardFlightLayer` node + container

**Files:**
- Create: `src/ui/match/card_flight_layer.gd`
- Modify: `src/ui/match/match.tscn` (add the node)
- Modify: `src/ui/match/match.gd` (add `_flight` reference)
- Test: `tests/test_card_flight_layer.gd`

**Context:** Owns nodes no zone owns while airborne: reparented *leavers* (death/discard, via `take_leaver`) and *pile→pile travelers* (mill/reshuffle, via `spawn_traveler`). Each self-frees on landing. Mill travelers carry the real milled `CardInstance` so the flip reveals the right card; reshuffle travelers use a face-down placeholder. The node is a child of `Table` (same coordinate space as the hand/board views and pile centers) and is added last so it draws on top.

- [ ] **Step 1: Add the node to `match.tscn`**

In `src/ui/match/match.tscn`, add this `ext_resource` line after the existing `id="16_trap_reveal"` line (around line 18):

```
[ext_resource type="Script" path="res://src/ui/match/card_flight_layer.gd" id="17_flight"]
```

Then add this node as the **last** child of `Table`, immediately after the `PlayerTickets` node block (after line 141):

```
[node name="CardFlightLayer" type="Node2D" parent="Table"]
script = ExtResource("17_flight")
```

- [ ] **Step 2: Add the `_flight` reference in `match.gd`**

In `src/ui/match/match.gd`, add this `@onready` line next to the other `Table` child references (after the `_trap_reveal` line, ~line 34):

```gdscript
@onready var _flight = $Table/CardFlightLayer
```

- [ ] **Step 3: Write the failing test**

Create `tests/test_card_flight_layer.gd`:

```gdscript
extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"

func _spawn() -> Node:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(5, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	return m

func test_spawn_traveler_adds_then_self_frees() -> void:
	var m := _spawn()
	var inst: CardInstance = m.state.players[0].deck[0]
	var cv: CardView = m._flight.spawn_traveler(inst, Vector2(1700, 800), Vector2(1700, 600), true, 0.0)
	assert_int(m._flight.get_child_count()).is_greater(0)
	await get_tree().create_timer(CardFlight.FLY_TIME + 0.6).timeout
	assert_bool(is_instance_valid(cv)).is_false()

func test_take_leaver_reparents_and_frees() -> void:
	var m := _spawn()
	var hv = m.hand_view
	var hand: Array = m.state.players[0].hand
	hv.render(hand, 0, [])
	var iid: int = hand[0].instance_id
	var cv: CardView = hv.card_views[iid]
	hv.card_views.erase(iid)   # simulate the zone view releasing ownership
	m._flight.take_leaver(cv, Vector2(1700, 600))
	assert_object(cv.get_parent()).is_same(m._flight)
	await get_tree().create_timer(CardFlight.FLY_TIME + 0.4).timeout
	assert_bool(is_instance_valid(cv)).is_false()
```

- [ ] **Step 4: Run test to verify it fails**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_flight_layer.gd
```
Expected: FAIL — `spawn_traveler` / `take_leaver` not found.

- [ ] **Step 5: Write the implementation**

Create `src/ui/match/card_flight_layer.gd`:

```gdscript
extends Node2D

# Owns cards no zone owns while airborne: reparented leavers (death/discard) and
# pile->pile travelers (mill/reshuffle). Each self-frees on landing. Lives under
# Table so its coordinate space matches the hand/board views and pile centers.

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")

var _placeholder: CardDefinition

func _ready() -> void:
	_placeholder = CardDefinition.new()
	_placeholder.name = "?"

# Reparent a zone's card here (keeping its global position) and fly it to a pile.
func take_leaver(cv: CardView, to_pos: Vector2, delay: float = 0.0) -> void:
	if cv.get_parent() != null:
		cv.reparent(self)
	var tw := CardFlight.fly_out(cv, to_pos, delay)
	tw.finished.connect(cv.queue_free)

# Spawn a fresh face-down traveler for a pile->pile move. `inst` may be the real
# card (mill, so the flip reveals it) or null (reshuffle placeholder).
func spawn_traveler(inst: CardInstance, from_pos: Vector2, to_pos: Vector2,
		flip_on_land: bool, delay: float = 0.0) -> CardView:
	var cv: CardView = CARD_VIEW.instantiate()
	add_child(cv)
	cv.set_interactive(false)
	cv.setup(inst if inst != null else CardInstance.new(-1, _placeholder))
	cv.set_base_scale(BoardLayout.CARD_SCALE)
	cv.set_face_down(true)
	cv.position = from_pos
	var tw := cv.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(cv, "position", to_pos, CardFlight.FLY_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if flip_on_land:
		tw.tween_callback(cv.flip_to_face_up)
		tw.tween_interval(0.25)   # let the flip play before freeing
	tw.tween_callback(cv.queue_free)
	return cv
```

- [ ] **Step 6: Run test to verify it passes**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_flight_layer.gd
```
Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
git add src/ui/match/card_flight_layer.gd src/ui/match/match.tscn src/ui/match/match.gd tests/test_card_flight_layer.gd
git commit -m "feat: CardFlightLayer container for leavers and pile travelers"
```

---

## Task 6: Plan-aware `hand_view` and `board_view` renders

**Files:**
- Modify: `src/ui/table/hand_view.gd`
- Modify: `src/ui/table/board_view.gd`
- Test: `tests/test_card_flight_render.gd`

**Context:** Both renders gain an optional `plan` (default `[]`, so existing callers in `table_view.gd` keep working). The rule that bounds scope to exactly our transitions:
- **Fly-in** a new card only when its plan source is a **pile** (`DECK`→ draw, `DISCARD`→ rummage). Draws start face-down and schedule a mid-flight flip.
- **Emit `card_departed`** for a leaver only when its plan destination is a **pile** (`DISCARD`/`DECK` → death, discard, put-on-deck); `match.gd` flies it. Leavers with no pile destination keep the old behavior (hand: `queue_free`; board: `dissolve` + `queue_free`). Plays (`HAND`→`BOARD`) and bounces (`BOARD`→`HAND`) have no pile endpoint, so they are untouched.

- [ ] **Step 1: Write the failing test**

Create `tests/test_card_flight_render.gd`:

```gdscript
extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"

func _spawn() -> Node:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(11, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	return m

func test_hand_fly_in_starts_new_draw_at_deck_and_face_down() -> void:
	var m := _spawn()
	var hv = m.hand_view
	var hand: Array = m.state.players[0].hand.duplicate()
	var def: CardDefinition = hand[0].definition
	var drawn := CardInstance.new(990001, def)
	hand.append(drawn)
	var from_pos := Vector2(1700, 800)
	var plan := [{"instance_id": 990001, "from": Enums.Zone.DECK, "to": Enums.Zone.HAND,
		"player": 0, "from_pos": from_pos}]
	hv.render(hand, 0, plan)
	var cv: CardView = hv.card_views[990001]
	assert_vector(cv.position).is_equal_approx(from_pos, Vector2(1, 1))
	assert_bool(cv._face_down).is_true()

func test_hand_leaver_to_discard_emits_card_departed() -> void:
	var m := _spawn()
	var hv = m.hand_view
	var hand: Array = m.state.players[0].hand
	hv.render(hand, 0, [])
	var leaving_id: int = hand[0].instance_id
	var got := {"cv": null, "to": Vector2.ZERO}
	hv.card_departed.connect(func(cv, to): got["cv"] = cv; got["to"] = to)
	var to_pos := Vector2(1700, 600)
	var plan := [{"instance_id": leaving_id, "from": Enums.Zone.HAND, "to": Enums.Zone.DISCARD,
		"player": 0, "to_pos": to_pos}]
	hv.render(hand.slice(1), 0, plan)
	assert_object(got["cv"]).is_not_null()
	assert_vector(got["to"]).is_equal_approx(to_pos, Vector2(1, 1))
	assert_bool(hv.card_views.has(leaving_id)).is_false()

func test_board_leaver_to_discard_emits_card_departed() -> void:
	var m := _spawn()
	# Put a unit on the player's board so board_view has a card to remove.
	var inst: CardInstance = m.state.players[0].hand[0]
	var bv = m.player_board
	bv.render([inst], 0, [])
	var got := {"cv": null}
	bv.card_departed.connect(func(cv, _to): got["cv"] = cv)
	var plan := [{"instance_id": inst.instance_id, "from": Enums.Zone.BOARD,
		"to": Enums.Zone.DISCARD, "player": 0, "to_pos": Vector2(1700, 600)}]
	bv.render([], 0, plan)
	assert_object(got["cv"]).is_not_null()
	assert_bool(bv.card_views.has(inst.instance_id)).is_false()
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_flight_render.gd
```
Expected: FAIL — `render` takes 2 args / `card_departed` signal missing.

- [ ] **Step 3: Rewrite `hand_view.gd`**

Replace the entire contents of `src/ui/table/hand_view.gd` with:

```gdscript
extends Node2D

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")

signal card_drag_released(instance_id: int, at: Vector2)
signal card_drag_started(instance_id: int)
signal card_departed(card_view: CardView, to_pos: Vector2)

var card_views: Dictionary = {}

func render(cards: Array, player: int, plan: Array = []) -> void:
	var n := cards.size()
	var seen := {}
	var fly_i := 0
	for i in range(n):
		var inst: CardInstance = cards[i]
		seen[inst.instance_id] = true
		var cv: CardView = card_views.get(inst.instance_id)
		var is_new := cv == null
		if is_new:
			cv = CARD_VIEW.instantiate()
			add_child(cv)
			card_views[inst.instance_id] = cv
			var iid := inst.instance_id
			cv.drag_released.connect(func(_cv: CardView, at: Vector2): card_drag_released.emit(iid, at))
			cv.drag_started.connect(func(_cv: CardView): card_drag_started.emit(iid))
		cv.setup(inst)
		cv.lift_on_hover = true
		cv.set_base_scale(BoardLayout.CARD_SCALE)
		var t := BoardLayout.slot(Enums.Zone.HAND, i, n, player)
		var rest_pos := t.origin - BoardLayout.CARD_PIVOT
		cv.set_rest(rest_pos, t.get_rotation())
		var entry := _fly_in_entry(inst.instance_id, plan)
		if is_new and not entry.is_empty():
			cv.rotation = t.get_rotation()
			var delay := float(fly_i) * CardFlight.STAGGER
			if entry["from"] == Enums.Zone.DECK:
				cv.set_face_down(true)
				_schedule_flip(cv, delay)
			CardFlight.fly_in(cv, entry["from_pos"], delay)
			fly_i += 1
		else:
			var tw := cv.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(cv, "position", rest_pos, 0.25)
			tw.parallel().tween_property(cv, "rotation", t.get_rotation(), 0.25)
	for iid in card_views.keys():
		if not seen.has(iid):
			var leaver: CardView = card_views[iid]
			var dest = _pile_dest(iid, plan)
			card_views.erase(iid)
			if dest != null:
				card_departed.emit(leaver, dest)
			else:
				leaver.queue_free()

# Plan entry for a new card flying in from a pile (draw/rummage), or {} if none.
func _fly_in_entry(iid: int, plan: Array) -> Dictionary:
	for e in plan:
		if e["instance_id"] == iid and e["to"] == Enums.Zone.HAND \
				and (e["from"] == Enums.Zone.DECK or e["from"] == Enums.Zone.DISCARD):
			return e
	return {}

# to_pos for a leaver bound for a pile (discard / put-on-deck), or null.
func _pile_dest(iid: int, plan: Array):
	for e in plan:
		if e["instance_id"] == iid and (e["to"] == Enums.Zone.DISCARD or e["to"] == Enums.Zone.DECK):
			return e.get("to_pos", null)
	return null

# Reveal a drawn card ~60% through its flight.
func _schedule_flip(cv: CardView, delay: float) -> void:
	var timer := get_tree().create_timer(delay + CardFlight.FLY_TIME * 0.6)
	timer.timeout.connect(cv.flip_to_face_up, CONNECT_ONE_SHOT)
```

- [ ] **Step 4: Update `board_view.gd`**

In `src/ui/table/board_view.gd`, add the new signal after the existing `signal unit_clicked(instance_id: int)` line:

```gdscript
signal card_departed(card_view: CardView, to_pos: Vector2)
```

Change the `render` signature from:

```gdscript
func render(units: Array, player: int) -> void:
```

to:

```gdscript
func render(units: Array, player: int, plan: Array = []) -> void:
```

Replace the leaver loop at the end of `render` (currently):

```gdscript
	for iid in card_views.keys():
		if not seen.has(iid):
			var leaver: CardView = card_views[iid]
			card_views.erase(iid)
			leaver.dissolve()
			leaver.queue_free()
```

with:

```gdscript
	for iid in card_views.keys():
		if not seen.has(iid):
			var leaver: CardView = card_views[iid]
			var dest = _pile_dest(iid, plan)
			card_views.erase(iid)
			if dest != null:
				card_departed.emit(leaver, dest)
			else:
				leaver.dissolve()
				leaver.queue_free()
```

Then append this helper to the end of `src/ui/table/board_view.gd`:

```gdscript
# to_pos for a leaver bound for a pile (death -> discard, put-on-deck), or null.
func _pile_dest(iid: int, plan: Array):
	for e in plan:
		if e["instance_id"] == iid and (e["to"] == Enums.Zone.DISCARD or e["to"] == Enums.Zone.DECK):
			return e.get("to_pos", null)
	return null
```

- [ ] **Step 5: Run test to verify it passes**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_flight_render.gd
```
Expected: PASS (3 tests).

- [ ] **Step 6: Run existing table/reconcile suites to confirm no regression**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_table_view.gd
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_match_reconcile.gd
```
Expected: PASS for both (plays still move hand→board normally; default `plan := []` keeps `table_view.gd` working).

- [ ] **Step 7: Commit**

```bash
git add src/ui/table/hand_view.gd src/ui/table/board_view.gd tests/test_card_flight_render.gd
git commit -m "feat: plan-aware hand/board renders (fly-in draws, emit pile leavers)"
```

---

## Task 7: Wire the pipeline into `match.gd`

**Files:**
- Modify: `src/ui/match/match.gd`
- Test: `tests/test_match_transitions.gd`

**Context:** `apply_action` snapshots every card's zone before and after the engine call, computes the `TransitionPlan`, enriches it with pile positions, threads it through `render_all`, and spawns pile→pile travelers. The zone views emit `card_departed` for pile-bound leavers; `match.gd` reparents those onto `CardFlightLayer`. All flights are fire-and-forget — state is already updated, so this is non-blocking.

- [ ] **Step 1: Write the failing test**

Create `tests/test_match_transitions.gd`:

```gdscript
extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"

func _spawn() -> Node:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(13, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	return m

func test_snapshot_reports_zone_and_player() -> void:
	var m := _spawn()
	var snap: Dictionary = m._snapshot_zones()
	var deck_card: CardInstance = m.state.players[0].deck[0]
	assert_int(snap[deck_card.instance_id]["zone"]).is_equal(Enums.Zone.DECK)
	assert_int(snap[deck_card.instance_id]["player"]).is_equal(0)
	var hand_card: CardInstance = m.state.players[0].hand[0]
	assert_int(snap[hand_card.instance_id]["zone"]).is_equal(Enums.Zone.HAND)

func test_enrich_fills_pile_positions_only() -> void:
	var m := _spawn()
	var raw := [{"instance_id": 1, "from": Enums.Zone.DECK, "to": Enums.Zone.HAND, "player": 0}]
	var plan: Array = m._enrich(raw)
	assert_bool(plan[0].has("from_pos")).is_true()   # DECK source -> filled
	assert_bool(plan[0].has("to_pos")).is_false()    # HAND dest -> not a pile

func test_spawn_pile_travelers_for_mill() -> void:
	var m := _spawn()
	var iid: int = m.state.players[0].deck[0].instance_id
	var plan: Array = m._enrich([{"instance_id": iid, "from": Enums.Zone.DECK,
		"to": Enums.Zone.DISCARD, "player": 0}])
	m._spawn_pile_travelers(plan)
	assert_int(m._flight.get_child_count()).is_greater(0)

func test_reshuffle_travelers_capped_at_five() -> void:
	var m := _spawn()
	var raw: Array = []
	for k in range(20):
		raw.append({"instance_id": k, "from": Enums.Zone.DISCARD, "to": Enums.Zone.DECK, "player": 0})
	m._spawn_pile_travelers(m._enrich(raw))
	assert_int(m._flight.get_child_count()).is_equal(5)
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_match_transitions.gd
```
Expected: FAIL — `_snapshot_zones` / `_enrich` / `_spawn_pile_travelers` not found.

- [ ] **Step 3: Wire `card_departed` in `_ready`**

In `src/ui/match/match.gd` `_ready()`, after the existing `opp_board.unit_clicked.connect(handle_unit_clicked)` line (~line 41), add:

```gdscript
	hand_view.card_departed.connect(_on_card_departed)
	player_board.card_departed.connect(_on_card_departed)
	opp_board.card_departed.connect(_on_card_departed)
```

- [ ] **Step 4: Rewrite `apply_action` and `render_all`**

In `src/ui/match/match.gd`, replace the current `apply_action` (lines ~63-69):

```gdscript
func apply_action(action: Action) -> void:
	var from := state.bus.log.size()
	engine.apply(action)
	var events := state.bus.log.slice(from)
	render_all()
	_play_flourishes(events)
	_post_action()
```

with:

```gdscript
func apply_action(action: Action) -> void:
	var before := _snapshot_zones()
	var from := state.bus.log.size()
	engine.apply(action)
	var events := state.bus.log.slice(from)
	var plan := _enrich(TransitionPlan.compute(before, _snapshot_zones()))
	render_all(plan)
	_spawn_pile_travelers(plan)
	_play_flourishes(events)
	_post_action()
```

Change the `render_all` signature from:

```gdscript
func render_all() -> void:
```

to:

```gdscript
func render_all(plan: Array = []) -> void:
```

and change its first three render calls from:

```gdscript
	player_board.render(you.board, 0)
	opp_board.render(opp.board, 1)
	hand_view.render(you.hand, 0)
```

to:

```gdscript
	player_board.render(you.board, 0, plan)
	opp_board.render(opp.board, 1, plan)
	hand_view.render(you.hand, 0, plan)
```

- [ ] **Step 5: Add the pipeline helpers**

In `src/ui/match/match.gd`, add these methods (place them right after `render_all`):

```gdscript
# Every card's current zone+owner, keyed by instance_id. Source of truth for the
# transition diff (events can't tell us a card's source; CARD_DISCARDED is shared
# by mill and hand-discard).
func _snapshot_zones() -> Dictionary:
	var snap := {}
	for p in range(state.players.size()):
		var ps: PlayerState = state.players[p]
		for c in ps.deck:
			snap[c.instance_id] = {"zone": Enums.Zone.DECK, "player": p}
		for c in ps.hand:
			snap[c.instance_id] = {"zone": Enums.Zone.HAND, "player": p}
		for c in ps.board:
			snap[c.instance_id] = {"zone": Enums.Zone.BOARD, "player": p}
		for c in ps.discard:
			snap[c.instance_id] = {"zone": Enums.Zone.DISCARD, "player": p}
	return snap

# Add card-top-left screen positions for any pile endpoints (the zone views supply
# their own hand/board slots).
func _enrich(raw: Array) -> Array:
	var out: Array = []
	for t in raw:
		var e: Dictionary = t.duplicate()
		if t["from"] == Enums.Zone.DECK or t["from"] == Enums.Zone.DISCARD:
			e["from_pos"] = FlightAnchors.of(t["from"], t["player"], self) - BoardLayout.CARD_PIVOT
		if t["to"] == Enums.Zone.DECK or t["to"] == Enums.Zone.DISCARD:
			e["to_pos"] = FlightAnchors.of(t["to"], t["player"], self) - BoardLayout.CARD_PIVOT
		out.append(e)
	return out

# Pile->pile moves no zone owns: mill (deck->discard, flip to reveal) and
# reshuffle (discard->deck, face-down, capped).
func _spawn_pile_travelers(plan: Array) -> void:
	var mill_i := 0
	var resh_i := 0
	for e in plan:
		var from_pile := e["from"] == Enums.Zone.DECK or e["from"] == Enums.Zone.DISCARD
		var to_pile := e["to"] == Enums.Zone.DECK or e["to"] == Enums.Zone.DISCARD
		if not (from_pile and to_pile):
			continue
		if e["from"] == Enums.Zone.DECK and e["to"] == Enums.Zone.DISCARD:
			_flight.spawn_traveler(_find_card(e["instance_id"]), e["from_pos"], e["to_pos"],
				true, float(mill_i) * 0.05)
			mill_i += 1
		elif e["from"] == Enums.Zone.DISCARD and e["to"] == Enums.Zone.DECK:
			if resh_i < 5:
				_flight.spawn_traveler(null, e["from_pos"], e["to_pos"], false, float(resh_i) * 0.04)
				resh_i += 1

func _on_card_departed(cv: CardView, to_pos: Vector2) -> void:
	_flight.take_leaver(cv, to_pos)

func _find_card(iid: int) -> CardInstance:
	for p in state.players:
		for coll in [p.deck, p.hand, p.board, p.discard]:
			for c in coll:
				if c.instance_id == iid:
					return c
	return null
```

- [ ] **Step 6: Run test to verify it passes**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_match_transitions.gd
```
Expected: PASS (4 tests).

- [ ] **Step 7: Run the controller/reconcile suites to confirm no regression**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_match_reconcile.gd
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_match_flow.gd
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_match_flourish.gd
```
Expected: PASS for all three.

- [ ] **Step 8: Commit**

```bash
git add src/ui/match/match.gd tests/test_match_transitions.gd
git commit -m "feat: wire snapshot/diff/enrich + pile travelers into match flow"
```

---

## Task 8: Full regression + fold-in note for the selection plan

**Files:**
- Modify: `docs/superpowers/plans/2026-05-31-in-hand-card-selection.md`

- [ ] **Step 1: Run the whole test directory**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```
Expected: exit code 0. Pay attention to `test_table_view.gd`, `test_match_reconcile.gd`, `test_match_flow.gd`, `test_match_flourish.gd`, `test_integration_ui_game.gd`, and `test_opponent_hand.gd` — none should regress (zone-render signatures are backward-compatible via `plan := []`, and the engine is untouched).

- [ ] **Step 2: If anything fails, fix and re-run**

Triage each failure against its cause. The most likely break is a test that called `render(cards, player)` and now wants to assert flight behavior — those keep working because `plan` defaults to `[]`. Do not change engine resolution.

- [ ] **Step 3: Add the dependency note to the selection plan**

In `docs/superpowers/plans/2026-05-31-in-hand-card-selection.md`, add this paragraph immediately after the `**Tech Stack:**` line (before the test-command block):

```markdown
**Depends on:** the Card Flight Transitions layer (`docs/superpowers/specs/2026-05-31-card-flight-transitions-design.md`). Implement this plan **after** that layer ships — the staging animations below call the shared `CardFlight.move_to` mover instead of hand-rolled tweens.
```

- [ ] **Step 4: Swap the Task 2 reflow tween to `CardFlight`**

In the same file, in **Task 2 Step 3**, replace this block inside `set_choice_excluded`:

```gdscript
		var tw := cv.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(cv, "position", rest_pos, 0.2)
		tw.parallel().tween_property(cv, "rotation", t.get_rotation(), 0.2)
```

with:

```gdscript
		CardFlight.move_to(cv, rest_pos, t.get_rotation())
```

- [ ] **Step 5: Swap the Task 3 `_restage` tween to `CardFlight`**

In the same file, in **Task 3 Step 3**, replace this block inside `_restage`:

```gdscript
		var tw := cv.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(cv, "position", pos, 0.2)
		tw.parallel().tween_property(cv, "rotation", 0.0, 0.2)
```

with:

```gdscript
		CardFlight.move_to(cv, pos, 0.0, float(i) * CardFlight.STAGGER)
```

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/plans/2026-05-31-in-hand-card-selection.md
git commit -m "docs: fold in-hand selection staging onto shared CardFlight mover"
```

---

## Notes for the implementer

- **Why a zone snapshot, not events:** `CARD_DISCARDED` is emitted by mill (deck→discard), discard-to-limit (hand→discard), and effect-discards, so it can't tell us a card's source. Snapshotting `CardInstance` zones before/after the engine call and diffing is authoritative and pure.
- **Scope rule:** fly-in only when the source is a pile; emit-and-fly-out only when the destination is a pile. This bounds animation to exactly the six in-scope transitions and leaves plays (hand→board, via drag) and bounces (board→hand) on their existing code paths.
- **Coordinate space:** `Table` is a full-rect Control at the origin, so its children (hand/board views, piles, `CardFlightLayer`) all share one space — no `to_local`/`to_global` juggling. `cv.reparent(self)` in `take_leaver` keeps the global position by default.
- **Pivot invariance:** `position = center - CARD_PIVOT` centers a card on `center` regardless of scale, because the card scales about `pivot_offset = CARD_PIVOT`. This is why pile anchors subtract the full (unscaled) `CARD_PIVOT`.
- **Non-blocking:** all flights are fire-and-forget tweens started after state has already updated. A follow-up `render_all` re-tweens from the live position via `set_rest`, so nothing desyncs; pile travelers are independent and self-free.
- **Headless tests:** input isn't transported, so tests drive behavior by calling `render(...)` with synthetic plans or applying actions, and assert end-state (placed-at-source, leaver reparented, traveler spawned), matching the existing `test_match_reconcile.gd` / `test_overlays.gd` style. Tween end-states are checked via `await tw.finished`.
- **Opponent draws** (deck→hand for player 1) are intentionally not animated — the opponent hand is a face-down count (`opponent_hand.gd`), so those transitions simply have no consuming zone view. Opponent mill/death still animate (pile travelers and `opp_board` leavers).
```
