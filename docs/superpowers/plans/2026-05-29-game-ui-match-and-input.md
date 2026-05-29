# Game UI — Match & Player Input (Phases 5–6) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the live game. `match.gd` owns the engine + state, runs the **apply → reconcile → flourish** cycle that drives every visual from authoritative `GameState`, and shows a turn banner. Then add player interaction: drag a hand card to play it, click an attacker then a target to attack, end the turn, choose a Leader's payment, and highlight legal moves — all gated by `get_legal_actions()` so the UI never reimplements rules.

**Architecture:** `match.gd` is the **only** node that touches `GameEngine` / `Action`. After each applied action it (1) reconciles every `CardView` to its `BoardLayout` home and tweens it there, then (2) fires one-shot flourishes from the events that action published, then (3) refreshes highlights from `get_legal_actions()`. Input never mutates state directly — it produces an `Action`, validates it against the legal set, and feeds it to the same cycle. The opponent's turn is a **temporary auto-end stub** here; the real `ai_controller` arrives in Plan 4. The opening mulligan is likewise a temporary auto-resolve until Plan 4's overlay replaces it.

**Tech Stack:** Godot 4.6 (GL Compatibility), GDScript, GdUnit4 for tests.

**Spec:** `docs/superpowers/specs/2026-05-29-game-ui-design.md` (this plan covers spec §8 phases 5–6, §5 core cycle, §4 highlights/targeting).

**Depends on:** Plan 2 (`BoardLayout`, `CardView` signals + `dissolve()`, `hand_view`/`board_view`/`pile_view`/`ticket_tray`/`opponent_hand`).

---

## Conventions used in every task

- **Run a single suite:**
  ```bash
  godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a <suite-path>
  ```
  Exit `0` = pass, `100` = fail. Rebuild the class cache with `godot --headless --path . --import` if `GdUnitTestCIRunner` is missing.
- **No InputEvent in headless tests.** Input→`Action` mapping is extracted into pure functions on a helper/`match.gd` and tested by **calling those functions directly** with synthetic drop/target data — never by synthesizing `InputEvent`s.
- **Event capture:** `state.bus.log` is append-only. To get "the events this action published," record `var from := state.bus.log.size()` before `engine.apply(...)`, then `state.bus.log.slice(from)` after.
- **Commit** after each task.

---

## File structure (this plan)

```
src/ui/match/match.tscn / match.gd        # CREATE: root match scene; engine+state, cycle, turn loop, input routing
src/ui/match/input_map.gd                  # CREATE: pure input(drop/target) -> Action + legality filter (testable)
src/ui/table/targeting_arrow.gd            # CREATE: bezier attacker -> cursor/target
src/ui/overlays/turn_banner.gd / .tscn     # CREATE: "Your Turn / Opponent's Turn" sweep
src/ui/match/flourishes.gd                 # CREATE: event -> cosmetic effect dispatch (damage numbers, shake, dissolve, mill)
tests/test_input_map.gd                    # CREATE: drop/target -> Action; illegal rejected
tests/test_match_reconcile.gd              # CREATE: scripted play_card/kill reconciles CardViews
tests/test_match_flow.gd                   # CREATE: end-turn + opponent stub advances turns
```

---

# Phase 5 — Match controller, reconciliation, flourishes

## Task 1: `match.tscn` scene skeleton

A 1920×1080 root that composes the Plan 2 widgets plus a top-level drag layer, an End Turn button, the targeting arrow, the turn banner, and a flourish layer. No logic yet.

**Files:**
- Create: `src/ui/match/match.tscn`

- [ ] **Step 1: Author the scene**

```
Match            (Control)              # full rect; attach match.gd in Task 2
├── Table        (Control)
│   ├── OppBoard      (board_view.gd Node2D)
│   ├── PlayerBoard   (board_view.gd Node2D)
│   ├── PlayerHand    (hand_view.gd Node2D)
│   ├── OppHand       (opponent_hand.gd Node2D)
│   ├── PlayerDeck/PlayerDiscard/PlayerLeader   (pile_view instances)
│   ├── OppDeck/OppDiscard/OppLeader            (pile_view instances)
│   └── PlayerTickets (ticket_tray)
├── DragLayer    (Control)              # dragged CardView reparents here (renders on top)
├── ArrowLayer   (Node2D)              # attach targeting_arrow.gd (Task 6)
├── EndTurnButton(Button)              # bottom-right; text "End Turn"
├── FxLayer      (Control)             # flourishes (damage numbers, mill burst) spawn here
└── Banner       (CanvasLayer)         # turn_banner instance (Task 5)
```

Reuse `table_view.tscn`'s positions from Plan 2 for the `Table` subtree (copy the node layout). Save and `--import`.

- [ ] **Step 2: Verify load**

```bash
godot --headless --path . --import
```
Expected: no errors mentioning `match.tscn`.

- [ ] **Step 3: Commit**

```bash
git add src/ui/match/match.tscn
git commit -m "feat: match scene skeleton (table + drag/arrow/fx layers + end turn)"
```

---

## Task 2: `match.gd` — setup, render, and the reconcile core

The heart of the UI. Builds the engine, renders initial state, and implements `_apply_and_sync(action)` = apply → reconcile → (flourish in Task 4) → refresh.

**Files:**
- Create: `src/ui/match/match.gd`
- Modify: `src/ui/match/match.tscn` (attach script)
- Test: `tests/test_match_reconcile.gd`

- [ ] **Step 1: Write the failing reconcile test**

Create `tests/test_match_reconcile.gd`:

```gdscript
extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"

func _spawn() -> Node:
	var m := load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(999, "res://src/data/decks/strike.csv", "res://src/data/decks/raccoon.csv")
	return m

func test_played_minion_moves_from_hand_to_board() -> void:
	var m := _spawn()
	# Find a legal play_card action and a minion to play.
	var legal: Array = m.engine.get_legal_actions()
	var play := legal.filter(func(a): return a.type == Enums.ActionType.PLAY_CARD)
	if play.is_empty():
		return   # no affordable card on turn 1 with this seed; reconcile covered by other seeds
	var act = play[0]
	var iid: int = act.params["instance_id"]
	m.apply_action(act)
	# Reconcile: the CardView for iid is no longer in the hand row.
	assert_bool(m.hand_view.card_views.has(iid)).is_false()

func test_state_is_source_of_truth_after_apply() -> void:
	var m := _spawn()
	var before := m.state.players[0].hand.size()
	m.apply_action(Action.end_turn())
	# End turn does not change player 0 hand count immediately (opponent stub runs).
	assert_int(m.state.active_player).is_between(0, 1)
```

- [ ] **Step 2: Run to verify failure**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_match_reconcile.gd
```
Expected: FAIL — `match.gd` / `start_game` not found, exit `100`.

- [ ] **Step 3: Implement `match.gd`**

```gdscript
extends Control

const HUMAN := 0

var state: GameState
var engine: GameEngine

@onready var opp_board: Node2D = $Table/OppBoard
@onready var player_board: Node2D = $Table/PlayerBoard
@onready var hand_view: Node2D = $Table/PlayerHand
@onready var opp_hand: Node2D = $Table/OppHand
@onready var _player_deck = $Table/PlayerDeck
@onready var _player_discard = $Table/PlayerDiscard
@onready var _opp_deck = $Table/OppDeck
@onready var _opp_discard = $Table/OppDiscard
@onready var _tickets = $Table/PlayerTickets
@onready var _end_turn: Button = $EndTurnButton

func _ready() -> void:
	_end_turn.pressed.connect(_on_end_turn_pressed)

# Entry point (menu calls this in Plan 4; tests call it directly).
func start_game(seed_value: int, deck0_path: String, deck1_path: String) -> void:
	state = GameState.new(seed_value)
	engine = GameEngine.new(state)
	var d0: Array[CardDefinition] = CardDatabase.load_deck(deck0_path, "P0")
	var d1: Array[CardDefinition] = CardDatabase.load_deck(deck1_path, "P1")
	engine.setup(d0, d1)
	_auto_resolve_mulligans()           # TEMP stub; replaced by overlay in Plan 4
	render_all()
	_post_action()

# --- the cycle -------------------------------------------------------------

# Validate against the legal set, then run the full sync cycle.
func apply_action(action: Action) -> void:
	var from := state.bus.log.size()
	engine.apply(action)
	var events := state.bus.log.slice(from)
	render_all()                         # reconcile: every CardView -> its BoardLayout home
	_play_flourishes(events)             # Task 4
	_post_action()

func render_all() -> void:
	var you := state.players[HUMAN]
	var opp := state.players[1 - HUMAN]
	player_board.render(you.board, 0)
	opp_board.render(opp.board, 1)
	hand_view.render(you.hand, 0)
	opp_hand.set_count(opp.hand.size())
	_player_deck.set_count(you.deck.size())
	_player_discard.set_count(you.discard.size())
	_opp_deck.set_count(opp.deck.size())
	_opp_discard.set_count(opp.discard.size())
	_tickets.set_tickets(you.tickets_tapped, you.tickets_total)

# After every cycle: refresh highlights, then drive the non-human turn.
func _post_action() -> void:
	_refresh_highlights()                # Task 8 (no-op until then)
	_end_turn.disabled = state.active_player != HUMAN or state.pending_choice != null
	if state.phase == Enums.Phase.GAME_OVER:
		return
	if state.active_player != HUMAN and state.pending_choice == null:
		_take_opponent_turn_stub()       # TEMP; replaced by ai_controller in Plan 4

func _on_end_turn_pressed() -> void:
	if state.active_player == HUMAN and state.pending_choice == null:
		apply_action(Action.end_turn())

# --- temporary stubs (replaced in Plan 4) ----------------------------------

func _auto_resolve_mulligans() -> void:
	# Opening mulligan: discard the first two non-leader cards for each player.
	while state.pending_choice != null and state.pending_choice.kind == "mulligan":
		engine.apply(Action.mulligan([0, 1]))

func _take_opponent_turn_stub() -> void:
	# Minimal opponent: just end the turn so play can continue.
	await get_tree().create_timer(0.3).timeout
	if state.phase != Enums.Phase.GAME_OVER and state.active_player != HUMAN:
		apply_action(Action.end_turn())

func _refresh_highlights() -> void:
	pass   # implemented in Task 8

func _play_flourishes(_events: Array) -> void:
	pass   # implemented in Task 4
```

Attach `match.gd` to the root of `match.tscn`.

- [ ] **Step 4: Run to verify pass**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_match_reconcile.gd
```
Expected: PASS, exit `0`.

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/match.gd src/ui/match/match.tscn tests/test_match_reconcile.gd
git commit -m "feat: match.gd setup + apply->reconcile->refresh cycle (opponent/mulligan stubbed)"
```

---

## Task 3: Smooth reconcile (tween to home instead of snap)

Right now `render_all()` rebuilds rows and snaps positions. Make `hand_view`/`board_view` **reuse** existing `CardView`s by `instance_id` and tween survivors to their new `BoardLayout` home, spawn entrants, and animate leavers — so draw/play/move read as motion, not pops.

**Files:**
- Modify: `src/ui/table/hand_view.gd`, `src/ui/table/board_view.gd`
- Test: `tests/test_match_reconcile.gd` (add a tween-target assertion)

- [ ] **Step 1: Make `render` reconcile by id with tweens**

Replace the `render(...)` bodies (both widgets) with a diffing version. Sketch (hand_view; board_view mirrors with `BOARD` + `tapped`):

```gdscript
func render(cards: Array, player: int) -> void:
	var n := cards.size()
	var seen := {}
	for i in range(n):
		var inst: CardInstance = cards[i]
		seen[inst.instance_id] = true
		var cv: CardView = card_views.get(inst.instance_id)
		if cv == null:
			cv = preload("res://src/ui/card/card_view.tscn").instantiate()
			add_child(cv)
			cv.setup(inst)
			card_views[inst.instance_id] = cv
		else:
			cv.setup(inst)   # refresh stats (current vs base)
		var t := BoardLayout.slot(Enums.Zone.HAND, i, n, player)
		var tw := cv.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(cv, "position", t.origin, 0.25)
		tw.parallel().tween_property(cv, "rotation", t.get_rotation(), 0.25)
	# Remove leavers.
	for iid in card_views.keys():
		if not seen.has(iid):
			card_views[iid].queue_free()
			card_views.erase(iid)
```

> `board_view` leavers should call `dissolve()` then free (death animation); `UNIT_DIED` flourish (Task 4) coordinates timing — for now, dissolve-then-free is fine since the kill already removed the unit from state.

- [ ] **Step 2: Add a reconcile target assertion**

In `tests/test_match_reconcile.gd`, after a `play_card`, assert the played minion's `CardView` (if it entered the board) has a board-row target. Use `BoardLayout.slot(...)` to compute the expected x and assert the `CardView` exists in `player_board.card_views`. Drive any tween to completion with `custom_step` if asserting final position.

- [ ] **Step 3: Run**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_match_reconcile.gd
```
Expected: PASS, exit `0`.

- [ ] **Step 4: Commit**

```bash
git add src/ui/table/hand_view.gd src/ui/table/board_view.gd tests/test_match_reconcile.gd
git commit -m "feat: reconcile by instance_id with tweens (CardViews reused, leavers animate out)"
```

---

## Task 4: Flourishes from captured events

Implement `flourishes.gd` and wire `_play_flourishes(events)`: `UNIT_DAMAGED`→floating damage number + shake on the target `CardView`; `UNIT_DIED`→dissolve (already handled by reconcile leaver, here add the burst); `DECK_DAMAGED`→mill burst on the pile; `CARD_DRAWN`→fly-from-deck (reconcile handles position; this just times it); `GAME_OVER`→defer to Plan 4 panel (no-op flag here).

**Files:**
- Create: `src/ui/match/flourishes.gd`
- Modify: `src/ui/match/match.gd` (`_play_flourishes`)
- Test: `tests/test_match_flourish.gd`

- [ ] **Step 1: Failing test (event dispatch, not pixels)**

Create `tests/test_match_flourish.gd`:

```gdscript
extends GdUnitTestSuite

func test_unit_damaged_event_spawns_a_damage_number() -> void:
	var m := load("res://src/ui/match/match.tscn").instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(7, "res://src/data/decks/strike.csv", "res://src/data/decks/raccoon.csv")
	var fx_before := m.get_node("FxLayer").get_child_count()
	var evt := GameEvent.new(Enums.EventType.UNIT_DAMAGED, {"target": 1, "amount": 3})
	m._play_flourishes([evt])
	assert_int(m.get_node("FxLayer").get_child_count()).is_greater(fx_before)
```

- [ ] **Step 2: Implement `flourishes.gd` + wire `_play_flourishes`**

`flourishes.gd` exposes static helpers operating on the `Match` (so it can find the right `CardView` by `target`/`instance` id and the `FxLayer`):

```gdscript
class_name Flourishes
extends RefCounted

static func play(match_node, events: Array) -> void:
	for e in events:
		match e.type:
			Enums.EventType.UNIT_DAMAGED:
				_damage_number(match_node, e.data.get("target", -1), e.data.get("amount", 0))
				_shake(match_node, e.data.get("target", -1))
			Enums.EventType.DECK_DAMAGED:
				_mill_burst(match_node, e.data.get("player", -1))
			# UNIT_DIED handled by reconcile leaver dissolve; GAME_OVER -> Plan 4 panel.

static func _find_card_view(match_node, iid: int) -> CardView:
	for row in [match_node.player_board, match_node.opp_board]:
		if row.card_views.has(iid):
			return row.card_views[iid]
	return null

static func _damage_number(match_node, iid: int, amount: int) -> void:
	if amount <= 0: return
	var lbl := Label.new()
	lbl.text = "-%d" % amount
	lbl.modulate = Color(1, 0.3, 0.3)
	var cv := _find_card_view(match_node, iid)
	lbl.position = cv.position if cv else Vector2(960, 540)
	match_node.get_node("FxLayer").add_child(lbl)
	var t := lbl.create_tween()
	t.tween_property(lbl, "position:y", lbl.position.y - 60.0, 0.6)
	t.parallel().tween_property(lbl, "modulate:a", 0.0, 0.6)
	t.tween_callback(lbl.queue_free)

static func _shake(match_node, iid: int) -> void:
	var cv := _find_card_view(match_node, iid)
	if cv == null: return
	var base := cv.position
	var t := cv.create_tween()
	for i in range(3):
		t.tween_property(cv, "position", base + Vector2(randf_range(-6, 6), 0), 0.04)
	t.tween_property(cv, "position", base, 0.04)

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

In `match.gd` replace the stub:

```gdscript
func _play_flourishes(events: Array) -> void:
	Flourishes.play(self, events)
```

- [ ] **Step 3: Run**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_match_flourish.gd
```
Expected: PASS, exit `0`.

- [ ] **Step 4: Commit**

```bash
git add src/ui/match/flourishes.gd src/ui/match/match.gd tests/test_match_flourish.gd
git commit -m "feat: event flourishes (damage numbers, shake, mill burst) from captured EventBus events"
```

---

## Task 5: Turn banner

A `CanvasLayer` panel that sweeps "Your Turn" / "Opponent's Turn" when a `TURN_STARTED` event is seen in a cycle.

**Files:**
- Create: `src/ui/overlays/turn_banner.tscn`, `src/ui/overlays/turn_banner.gd`
- Modify: `src/ui/match/match.gd` (handle `TURN_STARTED` in `_play_flourishes` or a dedicated hook)
- Test: `tests/test_turn_banner.gd`

- [ ] **Step 1: Failing test**

```gdscript
extends GdUnitTestSuite

func test_show_sets_text_for_player() -> void:
	var b := load("res://src/ui/overlays/turn_banner.tscn").instantiate()
	add_child(b)
	auto_free(b)
	b.show_turn(true)
	assert_str(b.find_child("Label").text).is_equal("Your Turn")
	b.show_turn(false)
	assert_str(b.find_child("Label").text).is_equal("Opponent's Turn")
```

- [ ] **Step 2: Implement**

`turn_banner.tscn`: `TurnBanner (CanvasLayer) → Panel → Label`. `turn_banner.gd`:

```gdscript
extends CanvasLayer

@onready var _label: Label = $Panel/Label

func show_turn(is_player: bool) -> void:
	if not is_node_ready():
		await ready
	_label.text = "Your Turn" if is_player else "Opponent's Turn"
	visible = true
	var t := create_tween()
	t.tween_interval(0.8)
	t.tween_callback(func(): visible = false)
```

In `match.gd`, inside `_play_flourishes` (or a sibling called from `apply_action`), detect `TURN_STARTED` events and call `$Banner.show_turn(e.data["player"] == HUMAN)`.

- [ ] **Step 3: Run + commit**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_turn_banner.gd
git add src/ui/overlays/turn_banner.tscn src/ui/overlays/turn_banner.gd src/ui/match/match.gd tests/test_turn_banner.gd
git commit -m "feat: turn banner sweep on TURN_STARTED"
```

---

# Phase 6 — Player input

## Task 6: `targeting_arrow` widget

A `Node2D` that draws a bezier from a start point to the cursor (or a snapped target). Pure draw; toggled on/off by `match.gd` during attack targeting.

**Files:**
- Create: `src/ui/table/targeting_arrow.gd`
- Test: `tests/test_targeting_arrow.gd`

- [ ] **Step 1: Failing test (geometry, not pixels)**

```gdscript
extends GdUnitTestSuite

func _spawn() -> Node2D:
	var n := Node2D.new()
	n.set_script(load("res://src/ui/table/targeting_arrow.gd"))
	add_child(n)
	auto_free(n)
	return n

func test_inactive_by_default() -> void:
	assert_bool(_spawn().active).is_false()

func test_begin_sets_active_and_start() -> void:
	var a := _spawn()
	a.begin(Vector2(100, 200))
	assert_bool(a.active).is_true()
	assert_vector(a.start).is_equal(Vector2(100, 200))

func test_bezier_point_endpoints() -> void:
	var a := _spawn()
	a.begin(Vector2(0, 0))
	a.point_at(Vector2(100, 0))
	assert_vector(a._curve_point(0.0)).is_equal(Vector2(0, 0))
	assert_vector(a._curve_point(1.0)).is_equal(Vector2(100, 0))
```

- [ ] **Step 2: Implement**

```gdscript
extends Node2D

var active: bool = false
var start: Vector2
var target: Vector2

func begin(from: Vector2) -> void:
	active = true
	start = from
	target = from
	queue_redraw()

func point_at(to: Vector2) -> void:
	target = to
	queue_redraw()

func end() -> void:
	active = false
	queue_redraw()

func _curve_point(t: float) -> Vector2:
	# Quadratic bezier with a control point lifted toward the start for an arc feel.
	var ctrl := start.lerp(target, 0.5) + Vector2(0, -120)
	return start.lerp(ctrl, t).lerp(ctrl.lerp(target, t), t)

func _draw() -> void:
	if not active:
		return
	var pts: PackedVector2Array = []
	for i in range(21):
		pts.append(_curve_point(float(i) / 20.0))
	draw_polyline(pts, Color(1, 0.9, 0.3), 4.0)
	draw_circle(target, 8.0, Color(1, 0.9, 0.3))
```

- [ ] **Step 3: Run + commit**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_targeting_arrow.gd
git add src/ui/table/targeting_arrow.gd tests/test_targeting_arrow.gd
git commit -m "feat: targeting_arrow bezier widget"
```

---

## Task 7: `input_map.gd` — pure input → Action (+ legality)

Extract the input→`Action` decision into a pure, testable module: given a drop (dragged hand instance + drop zone) or a target selection (attacker + target), return the `Action` or `null`, and confirm it is in `get_legal_actions()`.

**Files:**
- Create: `src/ui/match/input_map.gd`
- Test: `tests/test_input_map.gd`

- [ ] **Step 1: Failing tests**

```gdscript
extends GdUnitTestSuite

func _state_in_main(seed_value: int) -> Array:
	var st := GameState.new(seed_value)
	var en := GameEngine.new(st)
	en.setup(CardDatabase.load_deck("res://src/data/decks/strike.csv", "S"),
			 CardDatabase.load_deck("res://src/data/decks/raccoon.csv", "R"))
	while st.pending_choice != null:
		en.apply(Action.mulligan([0, 1]))
	return [st, en]

func test_drop_on_play_zone_yields_play_card_when_legal() -> void:
	var pair := _state_in_main(3)
	var st: GameState = pair[0]
	var en: GameEngine = pair[1]
	var legal: Array = en.get_legal_actions()
	var play := legal.filter(func(a): return a.type == Enums.ActionType.PLAY_CARD)
	if play.is_empty():
		return
	var iid: int = play[0].params["instance_id"]
	var act = CardInput.play_from_drop(iid, "play_zone", legal)
	assert_object(act).is_not_null()
	assert_int(act.type).is_equal(Enums.ActionType.PLAY_CARD)

func test_illegal_play_returns_null() -> void:
	var pair := _state_in_main(3)
	var en: GameEngine = pair[1]
	# instance_id 99999 is not in hand -> not legal.
	assert_object(CardInput.play_from_drop(99999, "play_zone", en.get_legal_actions())).is_null()

func test_attack_target_unit_yields_declare_attack() -> void:
	var act = CardInput.attack_from_target(5, {"unit": 8},
		[Action.declare_attack(5, {"unit": 8})])
	assert_object(act).is_not_null()
	assert_int(act.type).is_equal(Enums.ActionType.DECLARE_ATTACK)

func test_attack_deck_target() -> void:
	var act = CardInput.attack_from_target(5, {"deck": true},
		[Action.declare_attack(5, {"deck": true})])
	assert_object(act).is_not_null()
```

> The class is named `CardInput` to avoid colliding with Godot's built-in `InputMap` singleton.

- [ ] **Step 2: Implement**

`src/ui/match/input_map.gd`:

```gdscript
class_name CardInput
extends RefCounted

# Does `candidate` appear in the legal set? Compares type + key params.
static func _is_legal(candidate: Action, legal: Array) -> bool:
	for a in legal:
		if a.type != candidate.type:
			continue
		if a.params == candidate.params:
			return true
	return false

# A hand card dropped on a legal play zone.
static func play_from_drop(instance_id: int, drop_zone: String, legal: Array, pay_by_discard: bool = false) -> Action:
	if drop_zone == "":
		return null
	var act := Action.play_card(instance_id, {"pay_by_discard": true} if pay_by_discard else {})
	return act if _is_legal(act, legal) else null

# An attacker + chosen target (unit or deck).
static func attack_from_target(attacker_id: int, target: Dictionary, legal: Array) -> Action:
	var act := Action.declare_attack(attacker_id, target)
	return act if _is_legal(act, legal) else null
```

> Matching on `params` equality works because `Action.declare_attack` / `play_card` build their dicts identically to `get_legal_actions()`. The `pay_by_discard` play variant carries `{"pay_by_discard": true}`, matching the engine's legal entry.

- [ ] **Step 3: Run + commit**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_input_map.gd
git add src/ui/match/input_map.gd tests/test_input_map.gd
git commit -m "feat: CardInput pure input->Action mapping with legality filter"
```

---

## Task 8: Wire interaction into `match.gd` (drag-to-play, attacks, highlights, leader prompt)

Connect `CardView` signals to the cycle, draw the targeting arrow, drive deck-as-target, and implement `_refresh_highlights()` from `get_legal_actions()`. Illegal drops snap back.

**Files:**
- Modify: `src/ui/match/match.gd`
- Test: `tests/test_match_flow.gd`

- [ ] **Step 1: Failing test (drives the cycle via signals' resulting Actions, not InputEvents)**

Create `tests/test_match_flow.gd`:

```gdscript
extends GdUnitTestSuite

func _spawn() -> Node:
	var m := load("res://src/ui/match/match.tscn").instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(42, "res://src/data/decks/strike.csv", "res://src/data/decks/raccoon.csv")
	return m

func test_play_via_drop_handler_moves_card_to_board_or_discard() -> void:
	var m := _spawn()
	var legal: Array = m.engine.get_legal_actions()
	var play := legal.filter(func(a): return a.type == Enums.ActionType.PLAY_CARD)
	if play.is_empty():
		return
	var iid: int = play[0].params["instance_id"]
	var handled := m.handle_drop(iid, "play_zone")   # the drop handler used by drag_released
	assert_bool(handled).is_true()
	assert_bool(m.hand_view.card_views.has(iid)).is_false()

func test_illegal_drop_is_rejected() -> void:
	var m := _spawn()
	assert_bool(m.handle_drop(99999, "play_zone")).is_false()

func test_highlights_mark_legal_attackers() -> void:
	var m := _spawn()
	# After playing nothing, the human may have no untapped attackers; just assert no crash + returns a set.
	var attackers := m.legal_attacker_ids()
	assert_object(attackers).is_not_null()
```

- [ ] **Step 2: Implement the handlers in `match.gd`**

Add: connect `hand_view` `CardView` `drag_released` → `_on_card_dropped`; `board_view` `clicked` → `_on_unit_clicked`; a drop-zone hit test; targeting state; and highlight helpers.

```gdscript
var _selected_attacker: int = -1

# Called by a CardView's drag_released; returns true if a legal play happened.
func handle_drop(instance_id: int, drop_zone: String) -> bool:
	if state.active_player != HUMAN or state.pending_choice != null:
		return false
	var legal := engine.get_legal_actions()
	var act := CardInput.play_from_drop(instance_id, drop_zone, legal)
	if act == null:
		# Leader paid-by-discard fallback handled via leader prompt (Plan 4 overlay).
		render_all()   # snap the card back to its hand home
		return false
	apply_action(act)
	return true

# Attack flow: first click selects an untapped attacker; second resolves a target.
func handle_unit_clicked(instance_id: int) -> void:
	if state.active_player != HUMAN or state.pending_choice != null:
		return
	if _selected_attacker == -1:
		if legal_attacker_ids().has(instance_id):
			_selected_attacker = instance_id
			$ArrowLayer.begin(player_board.card_views[instance_id].position)
	else:
		_resolve_attack_target({"unit": instance_id})

func handle_deck_target_clicked() -> void:
	if _selected_attacker != -1:
		_resolve_attack_target({"deck": true})

func _resolve_attack_target(target: Dictionary) -> void:
	var act := CardInput.attack_from_target(_selected_attacker, target, engine.get_legal_actions())
	_selected_attacker = -1
	$ArrowLayer.end()
	if act != null:
		apply_action(act)

func legal_attacker_ids() -> Array:
	var ids: Array = []
	for a in engine.get_legal_actions():
		if a.type == Enums.ActionType.DECLARE_ATTACK:
			var aid: int = a.params["attacker_id"]
			if not ids.has(aid):
				ids.append(aid)
	return ids

func legal_play_ids() -> Array:
	var ids: Array = []
	for a in engine.get_legal_actions():
		if a.type == Enums.ActionType.PLAY_CARD:
			ids.append(a.params["instance_id"])
	return ids

func _refresh_highlights() -> void:
	var plays := legal_play_ids()
	for iid in hand_view.card_views:
		hand_view.card_views[iid].set_playable(plays.has(iid))   # add set_playable() tint to CardView
	var attackers := legal_attacker_ids()
	for iid in player_board.card_views:
		player_board.card_views[iid].set_attackable(attackers.has(iid))
```

Add small `set_playable(bool)` / `set_attackable(bool)` tint helpers to `card_view.gd` (e.g. modulate a subtle glow / outline). Connect the signals in `hand_view`/`board_view` `render(...)` (emit upward to `match` via a signal or a stored `Callable`). Wire `_process` to update the arrow toward the cursor while `_selected_attacker != -1`.

- [ ] **Step 3: Run**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_match_flow.gd
```
Expected: PASS, exit `0`.

- [ ] **Step 4: Manual interaction smoke (editor)**

Make `match.tscn` the temporary run scene (Project Settings → run/main_scene), call `start_game(...)` from `_ready` with a fixed seed for the test, and play (F5): drag an affordable card to the board (illegal drops snap back), click an untapped minion then an enemy unit / the enemy deck to attack, watch damage numbers + reconcile, End Turn, opponent stub ends its turn, banner sweeps. Visual.

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/match.gd src/ui/card/card_view.gd src/ui/table/hand_view.gd src/ui/table/board_view.gd tests/test_match_flow.gd
git commit -m "feat: player input wired (drag-to-play, click-target attacks, highlights, arrow)"
```

---

## Self-review notes

- **Phase 5 coverage:** `match.gd` is the sole engine-touching node ✓; apply→reconcile→flourish cycle (Tasks 2–4) ✓; reconcile reuses `CardView`s by id and tweens to `BoardLayout` homes, leavers animate out (Task 3) ✓; flourishes from captured `EventBus` events — damage numbers, shake, mill burst (Task 4) ✓; turn banner (Task 5) ✓.
- **Phase 6 coverage:** drag-to-play with legality + snap-back (Tasks 7–8) ✓; click-source→click-target attacks, deck-as-target, `targeting_arrow` (Tasks 6, 8) ✓; End Turn (Task 2) ✓; highlights from `get_legal_actions()` (Task 8) ✓; input→`Action` mapping unit-tested without `InputEvent` (Task 7) ✓.
- **Deferred to Plan 4 (clearly stubbed here):** opponent AI (`_take_opponent_turn_stub`), opening mulligan (`_auto_resolve_mulligans`), the leader cost prompt (drop currently rejects the by-discard variant), discard-to-limit + game-over panels.
- **Headless honesty:** Actions, reconcile diffs, flourish dispatch, and input mapping are asserted directly; tweens/InputEvents are exercised manually.

---

## Next plan

**Plan 4 — Overlays, AI & Flow (Phases 7–8):** mulligan / discard-to-limit / game-over panels (replacing the auto-mulligan stub), `ai_controller.gd` (replacing the opponent stub), the leader cost prompt, main menu + deck selection + play-again, and the full vs-AI smoke test.
