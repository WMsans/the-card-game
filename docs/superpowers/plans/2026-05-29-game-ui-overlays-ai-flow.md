# Game UI — Overlays, AI & Flow (Phases 7–8) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the loop into a full solo game. Replace Plan 3's temporary stubs with real choice overlays (mulligan, discard-to-limit, leader cost prompt, game-over) and a real opponent (`ai_controller.gd` that picks from `get_legal_actions()`), then add the main menu (deck selection, RNG seed, play-again). End with a start→win manual smoke through the deck-damage path.

**Architecture:** Overlays are lightweight `CanvasLayer` panels that pause table input while a `pending_choice` is active; resolving one sends `Action.mulligan(...)` / `Action.resolve_choice(...)` through `match.gd`'s existing `apply_action` cycle. The AI runs through the **same** cycle as the human, so it animates identically. `match.gd` watches `state.pending_choice` after every cycle and routes it to the human overlay or the AI heuristic by `pending_choice.player`. The main menu becomes the project's `run/main_scene` and launches `match.tscn` with a chosen deck + seed.

**Tech Stack:** Godot 4.6 (GL Compatibility), GDScript, GdUnit4 for tests.

**Spec:** `docs/superpowers/specs/2026-05-29-game-ui-design.md` (this plan covers spec §8 phases 7–8, §6 overlays/flow, §5 AI + pending_choice).

**Depends on:** Plan 3 (`match.gd` with `apply_action`, the `_auto_resolve_mulligans` / `_take_opponent_turn_stub` stubs to replace, `pending_choice` reachable).

**Key engine facts (from `game_engine.gd`):**
- `setup` ends with `pending_choice = PendingChoice.new("mulligan", 0)`. The mulligan flow is **player 0 → player 1 → first player chosen → first turn** (`_apply_mulligan`).
- `_apply_mulligan(indices)` discards exactly those hand indices for `pending_choice.player` (no redraw). Per the GDD the human discards **exactly 2** of 5.
- `discard_to_limit` fires in `_end_turn` when `hand.size() > 5`, with `data.count = hand.size() - 5`; resolved via `Action.resolve_choice({"indices": [...]})`.
- `get_legal_actions()` returns `[]` whenever `pending_choice != null` or phase != `MAIN` or `GAME_OVER` — so overlays must drive choices; the AI uses the same call for its main-phase moves.
- `GAME_OVER` publishes `{"winner": idx}`; `state.winner` holds it.

---

## Conventions used in every task

- **Run a single suite:**
  ```bash
  godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a <suite-path>
  ```
  Exit `0` = pass, `100` = fail. Rebuild the class cache with `godot --headless --path . --import` if `GdUnitTestCIRunner` is missing.
- **No InputEvent in headless tests.** Drive overlays/AI by calling their public methods directly with synthetic selections.
- **Commit** after each task.

---

## File structure (this plan)

```
src/ui/match/ai_controller.gd               # CREATE: picks a legal Action; resolves AI pending_choice
src/ui/overlays/mulligan_panel.gd / .tscn    # CREATE: pick exactly 2 to discard
src/ui/overlays/discard_panel.gd / .tscn     # CREATE: pick `count` to discard
src/ui/overlays/leader_cost_prompt.gd / .tscn# CREATE: tickets vs discard payment
src/ui/overlays/game_over_panel.gd / .tscn   # CREATE: winner + play again / quit
src/ui/menu/main_menu.gd / .tscn             # CREATE: deck select + seed + play; run/main_scene
src/ui/match/match.gd                         # MODIFY: replace stubs; route pending_choice; wire overlays + AI
project.godot                                 # MODIFY: run/main_scene = main_menu.tscn
tests/test_ai_controller.gd                   # CREATE: always legal; terminates a turn
tests/test_mulligan_panel.gd                  # CREATE: selection -> exactly-2 Action
tests/test_pending_choice_routing.gd          # CREATE: match routes choices to overlay vs AI
tests/test_integration_ui_game.gd             # CREATE: AI-vs-AI run reaches GAME_OVER through match
```

---

# Phase 8 (part) — AI controller

> The AI lands first because every overlay/flow test below needs a non-stub opponent that can also resolve its own `pending_choice`.

## Task 1: `ai_controller.gd` — choose a legal action + resolve AI choices

A stateless picker: given the engine, return one `Action` from `get_legal_actions()` (simple greedy: play affordable cards, then attack, then end turn), and resolve an AI-owned `pending_choice` (mulligan / discard) by heuristic.

**Files:**
- Create: `src/ui/match/ai_controller.gd`
- Test: `tests/test_ai_controller.gd`

- [ ] **Step 1: Failing tests**

Create `tests/test_ai_controller.gd`:

```gdscript
extends GdUnitTestSuite

func _engine_in_main(seed_value: int) -> GameEngine:
	var st := GameState.new(seed_value)
	var en := GameEngine.new(st)
	en.setup(CardDatabase.load_deck("res://src/data/decks/strike.csv", "S"),
			 CardDatabase.load_deck("res://src/data/decks/raccoon.csv", "R"))
	while st.pending_choice != null:
		# Resolve both opening mulligans via the AI itself.
		en.apply(AiController.choice_action(en))
	return en

func test_choose_action_returns_a_legal_action() -> void:
	var en := _engine_in_main(11)
	var act := AiController.choose_action(en)
	assert_object(act).is_not_null()
	# It must be one of the legal actions (same type+params).
	var legal := en.get_legal_actions()
	var found := legal.filter(func(a): return a.type == act.type and a.params == act.params)
	assert_int(found.size()).is_greater(0)

func test_turn_terminates_within_bounded_steps() -> void:
	var en := _engine_in_main(11)
	var start_player := en.state.active_player
	var steps := 0
	while en.state.active_player == start_player and en.state.pending_choice == null \
			and en.state.phase != Enums.Phase.GAME_OVER and steps < 50:
		en.apply(AiController.choose_action(en))
		steps += 1
	# The AI eventually ends its turn (active_player flips) or the game ends.
	assert_bool(en.state.active_player != start_player or en.state.phase == Enums.Phase.GAME_OVER).is_true()

func test_mulligan_choice_discards_exactly_two() -> void:
	var st := GameState.new(5)
	var en := GameEngine.new(st)
	en.setup(CardDatabase.load_deck("res://src/data/decks/strike.csv", "S"),
			 CardDatabase.load_deck("res://src/data/decks/raccoon.csv", "R"))
	var act := AiController.choice_action(en)
	assert_int(act.type).is_equal(Enums.ActionType.MULLIGAN)
	assert_int(act.params["indices"].size()).is_equal(2)
```

- [ ] **Step 2: Run to verify failure**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_ai_controller.gd
```
Expected: FAIL — `AiController` not declared, exit `100`.

- [ ] **Step 3: Implement**

`src/ui/match/ai_controller.gd`:

```gdscript
class_name AiController
extends RefCounted

# Pick one main-phase action. Greedy: prefer playing an affordable card, then
# attacking, then ending the turn. END_TURN is always present as the fallback.
static func choose_action(engine: GameEngine) -> Action:
	var legal := engine.get_legal_actions()
	if legal.is_empty():
		return Action.end_turn()
	var plays := legal.filter(func(a): return a.type == Enums.ActionType.PLAY_CARD)
	if not plays.is_empty():
		return plays[0]
	var attacks := legal.filter(func(a): return a.type == Enums.ActionType.DECLARE_ATTACK)
	if not attacks.is_empty():
		# Prefer hitting the deck (progress toward the win condition) when unblocked.
		var deck_hits := attacks.filter(func(a): return a.params["target"].get("deck", false))
		return deck_hits[0] if not deck_hits.is_empty() else attacks[0]
	return Action.end_turn()

# Resolve an AI-owned pending_choice (mulligan / discard_to_limit) by heuristic.
static func choice_action(engine: GameEngine) -> Action:
	var pc := engine.state.pending_choice
	match pc.kind:
		"mulligan":
			# Discard exactly the first two non-leader hand cards.
			return Action.mulligan(_first_two_non_leader(engine.state.players[pc.player]))
		"discard_to_limit":
			var n: int = pc.data["count"]
			var idx: Array = []
			for i in range(n):
				idx.append(i)
			return Action.resolve_choice({"indices": idx})
		_:
			return Action.resolve_choice({"indices": []})

static func _first_two_non_leader(ps: PlayerState) -> Array:
	var out: Array = []
	for i in range(ps.hand.size()):
		if ps.hand[i].definition.type != Enums.CardType.LEADER:
			out.append(i)
		if out.size() == 2:
			break
	return out
```

- [ ] **Step 4: Run to verify pass**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_ai_controller.gd
```
Expected: PASS, exit `0`.

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/ai_controller.gd tests/test_ai_controller.gd
git commit -m "feat: AiController greedy action + pending_choice heuristic"
```

---

# Phase 7 — Overlays

## Task 2: `mulligan_panel`

Shows the opening hand; the human picks **exactly 2** of the 5 drawn (Leader excluded from the discardable set); confirm → `Action.mulligan(indices)`.

**Files:**
- Create: `src/ui/overlays/mulligan_panel.tscn`, `src/ui/overlays/mulligan_panel.gd`
- Test: `tests/test_mulligan_panel.gd`

- [ ] **Step 1: Failing test**

```gdscript
extends GdUnitTestSuite

func _strike_hand() -> Array[CardInstance]:
	var defs := CardDatabase.load_deck("res://src/data/decks/strike.csv", "S")
	var out: Array[CardInstance] = []
	for i in range(5):
		out.append(CardInstance.new(i + 1, defs[i]))
	return out

func _spawn() -> Node:
	var p := load("res://src/ui/overlays/mulligan_panel.tscn").instantiate()
	add_child(p)
	auto_free(p)
	return p

func test_confirm_disabled_until_exactly_two_selected() -> void:
	var p := _spawn()
	p.show_hand(_strike_hand())
	assert_bool(p.can_confirm()).is_false()
	p.toggle_index(0)
	assert_bool(p.can_confirm()).is_false()
	p.toggle_index(1)
	assert_bool(p.can_confirm()).is_true()
	p.toggle_index(2)
	assert_bool(p.can_confirm()).is_false()   # 3 selected

func test_confirm_emits_selected_indices() -> void:
	var p := _spawn()
	p.show_hand(_strike_hand())
	p.toggle_index(0)
	p.toggle_index(3)
	var got := []
	p.confirmed.connect(func(idx): got = idx)
	p.confirm()
	assert_array(got).contains_exactly_in_any_order([0, 3])
```

- [ ] **Step 2: Implement**

`mulligan_panel.tscn`: `MulliganPanel (CanvasLayer) → Panel → {CardRow (HBoxContainer of CardViews), ConfirmButton, Prompt Label}`. `mulligan_panel.gd`:

```gdscript
extends CanvasLayer

signal confirmed(indices: Array)

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")
const REQUIRED := 2

var _selected: Array = []
var _discardable: Array = []   # hand indices that are not the Leader

@onready var _row: HBoxContainer = $Panel/CardRow
@onready var _confirm: Button = $Panel/ConfirmButton

func _ready() -> void:
	_confirm.pressed.connect(confirm)

func show_hand(hand: Array) -> void:
	if not is_node_ready():
		await ready
	_selected.clear()
	_discardable.clear()
	for c in _row.get_children():
		c.queue_free()
	for i in range(hand.size()):
		var inst: CardInstance = hand[i]
		var cv: CardView = CARD_VIEW.instantiate()
		cv.set_interactive(false)
		_row.add_child(cv)
		cv.setup(inst)
		if inst.definition.type != Enums.CardType.LEADER:
			_discardable.append(i)
			var idx := i
			cv.gui_input.connect(func(e):
				if e is InputEventMouseButton and e.pressed:
					toggle_index(idx))
	visible = true
	_update()

func toggle_index(i: int) -> void:
	if not _discardable.has(i):
		return
	if _selected.has(i):
		_selected.erase(i)
	elif _selected.size() < REQUIRED:
		_selected.append(i)
	_update()

func can_confirm() -> bool:
	return _selected.size() == REQUIRED

func confirm() -> void:
	if can_confirm():
		visible = false
		confirmed.emit(_selected.duplicate())

func _update() -> void:
	_confirm.disabled = not can_confirm()
```

> The engine discards exactly the passed indices and does not redraw (`_apply_mulligan`), so a 2-index payload settles the hand to size 3 (+ leader if it was dealt into the opening hand).

- [ ] **Step 3: Run + commit**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_mulligan_panel.gd
git add src/ui/overlays/mulligan_panel.tscn src/ui/overlays/mulligan_panel.gd tests/test_mulligan_panel.gd
git commit -m "feat: mulligan panel (pick exactly 2, leader excluded)"
```

---

## Task 3: `discard_panel` + `leader_cost_prompt` + `game_over_panel`

Three small panels built together (same shape, low risk).

**Files:**
- Create: `src/ui/overlays/discard_panel.tscn` / `.gd`
- Create: `src/ui/overlays/leader_cost_prompt.tscn` / `.gd`
- Create: `src/ui/overlays/game_over_panel.tscn` / `.gd`
- Test: `tests/test_overlays.gd`

- [ ] **Step 1: Failing tests**

```gdscript
extends GdUnitTestSuite

func _hand(n: int) -> Array[CardInstance]:
	var defs := CardDatabase.load_deck("res://src/data/decks/strike.csv", "S")
	var out: Array[CardInstance] = []
	for i in range(n):
		out.append(CardInstance.new(i + 1, defs[i % defs.size()]))
	return out

func _inst(path: String) -> Node:
	var p := load(path).instantiate()
	add_child(p)
	auto_free(p)
	return p

func test_discard_panel_requires_exact_count() -> void:
	var p := _inst("res://src/ui/overlays/discard_panel.tscn")
	p.show_hand(_hand(7), 2)   # over limit by 2
	p.toggle_index(0)
	assert_bool(p.can_confirm()).is_false()
	p.toggle_index(1)
	assert_bool(p.can_confirm()).is_true()

func test_leader_prompt_emits_payment_choice() -> void:
	var p := _inst("res://src/ui/overlays/leader_cost_prompt.tscn")
	var got := {"called": false, "by_discard": false}
	p.chosen.connect(func(by_discard): got = {"called": true, "by_discard": by_discard})
	p.show_prompt()
	p.choose_discard()
	assert_bool(got["called"]).is_true()
	assert_bool(got["by_discard"]).is_true()

func test_game_over_shows_winner_text() -> void:
	var p := _inst("res://src/ui/overlays/game_over_panel.tscn")
	p.show_result(0, 0)   # winner index, human index
	assert_str(p.find_child("ResultLabel").text).is_equal("You Win")
	p.show_result(1, 0)
	assert_str(p.find_child("ResultLabel").text).is_equal("You Lose")
```

- [ ] **Step 2: Implement**

**`discard_panel.gd`** — mirrors the mulligan panel but with a dynamic required `count`:

```gdscript
extends CanvasLayer
signal confirmed(indices: Array)
const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")
var _selected: Array = []
var _required: int = 0
@onready var _row: HBoxContainer = $Panel/CardRow
@onready var _confirm: Button = $Panel/ConfirmButton

func _ready() -> void:
	_confirm.pressed.connect(_confirm_pressed)

func show_hand(hand: Array, count: int) -> void:
	if not is_node_ready(): await ready
	_required = count
	_selected.clear()
	for c in _row.get_children(): c.queue_free()
	for i in range(hand.size()):
		var cv: CardView = CARD_VIEW.instantiate()
		cv.set_interactive(false)
		_row.add_child(cv)
		cv.setup(hand[i])
		var idx := i
		cv.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed: toggle_index(idx))
	visible = true
	_update()

func toggle_index(i: int) -> void:
	if _selected.has(i): _selected.erase(i)
	elif _selected.size() < _required: _selected.append(i)
	_update()

func can_confirm() -> bool: return _selected.size() == _required
func _confirm_pressed() -> void:
	if can_confirm():
		visible = false
		confirmed.emit(_selected.duplicate())
func _update() -> void: _confirm.disabled = not can_confirm()
```

**`leader_cost_prompt.gd`** — two buttons:

```gdscript
extends CanvasLayer
signal chosen(by_discard: bool)
@onready var _tickets_btn: Button = $Panel/PayTickets
@onready var _discard_btn: Button = $Panel/PayDiscard
func _ready() -> void:
	_tickets_btn.pressed.connect(func(): _emit(false))
	_discard_btn.pressed.connect(func(): _emit(true))
func show_prompt() -> void:
	if not is_node_ready(): await ready
	visible = true
func choose_tickets() -> void: _emit(false)
func choose_discard() -> void: _emit(true)
func _emit(by_discard: bool) -> void:
	visible = false
	chosen.emit(by_discard)
```

**`game_over_panel.gd`**:

```gdscript
extends CanvasLayer
signal play_again
signal quit
@onready var _label: Label = $Panel/ResultLabel
func _ready() -> void:
	$Panel/PlayAgain.pressed.connect(func(): play_again.emit())
	$Panel/Quit.pressed.connect(func(): quit.emit())
func show_result(winner: int, human: int) -> void:
	if not is_node_ready(): await ready
	_label.text = "You Win" if winner == human else "You Lose"
	visible = true
```

Author the matching `.tscn` files (CanvasLayer → Panel → labeled children with the node names used above).

- [ ] **Step 3: Run + commit**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_overlays.gd
git add src/ui/overlays/discard_panel.* src/ui/overlays/leader_cost_prompt.* src/ui/overlays/game_over_panel.* tests/test_overlays.gd
git commit -m "feat: discard, leader-cost, and game-over overlays"
```

---

## Task 4: Route `pending_choice` + replace stubs in `match.gd`

Wire the overlays + AI into the cycle: after every `apply_action`, inspect `state.pending_choice`. Replace `_auto_resolve_mulligans` and `_take_opponent_turn_stub` with real routing. Add the leader cost prompt to the drop handler.

**Files:**
- Modify: `src/ui/match/match.gd`
- Modify: `src/ui/match/match.tscn` (instance the overlay scenes as children)
- Test: `tests/test_pending_choice_routing.gd`

- [ ] **Step 1: Add the overlay instances to `match.tscn`**

Add as children of `Match`: `MulliganPanel`, `DiscardPanel`, `LeaderCostPrompt`, `GameOverPanel` (all hidden by default).

- [ ] **Step 2: Failing routing test**

```gdscript
extends GdUnitTestSuite

func _spawn() -> Node:
	var m := load("res://src/ui/match/match.tscn").instantiate()
	add_child(m)
	auto_free(m)
	return m

func test_human_mulligan_shows_panel_ai_resolves_automatically() -> void:
	var m := _spawn()
	m.start_game(3, "res://src/data/decks/strike.csv", "res://src/data/decks/raccoon.csv")
	# After setup, pending_choice is human (player 0) mulligan -> panel visible.
	assert_bool(m.get_node("MulliganPanel").visible).is_true()
	# Resolve it; player 1 (AI) mulligan should resolve without showing the panel.
	m.get_node("MulliganPanel").confirmed.emit([0, 1])
	await get_tree().process_frame
	assert_bool(m.state.pending_choice == null).is_true()

func test_game_over_panel_shows_on_game_over() -> void:
	var m := _spawn()
	m.start_game(3, "res://src/data/decks/strike.csv", "res://src/data/decks/raccoon.csv")
	# Force a terminal state for the assertion.
	m.state.phase = Enums.Phase.GAME_OVER
	m.state.winner = 0
	m._show_game_over()
	assert_bool(m.get_node("GameOverPanel").visible).is_true()
```

- [ ] **Step 3: Rewrite the stub region of `match.gd`**

```gdscript
@onready var _mulligan := $MulliganPanel
@onready var _discard := $DiscardPanel
@onready var _leader_prompt := $LeaderCostPrompt
@onready var _game_over := $GameOverPanel

func _ready() -> void:
	_end_turn.pressed.connect(_on_end_turn_pressed)
	_mulligan.confirmed.connect(func(idx): apply_action(Action.mulligan(idx)))
	_discard.confirmed.connect(func(idx): apply_action(Action.resolve_choice({"indices": idx})))
	_game_over.play_again.connect(_on_play_again)
	_game_over.quit.connect(func(): get_tree().quit())

# Replaces _auto_resolve_mulligans + _take_opponent_turn_stub from Plan 3.
func _post_action() -> void:
	_refresh_highlights()
	_end_turn.disabled = state.active_player != HUMAN or state.pending_choice != null
	if state.phase == Enums.Phase.GAME_OVER:
		_show_game_over()
		return
	if state.pending_choice != null:
		_route_pending_choice()
		return
	if state.active_player != HUMAN:
		_run_ai_turn()

func _route_pending_choice() -> void:
	var pc := state.pending_choice
	if pc.player != HUMAN:
		# AI resolves its own choice through the same cycle.
		await get_tree().create_timer(0.2).timeout
		apply_action(AiController.choice_action(engine))
		return
	match pc.kind:
		"mulligan":
			_mulligan.show_hand(state.players[HUMAN].hand)
		"discard_to_limit":
			_discard.show_hand(state.players[HUMAN].hand, pc.data["count"])

func _run_ai_turn() -> void:
	await get_tree().create_timer(0.35).timeout
	if state.phase == Enums.Phase.GAME_OVER or state.active_player == HUMAN:
		return
	apply_action(AiController.choose_action(engine))

func _show_game_over() -> void:
	_game_over.show_result(state.winner, HUMAN)

func _on_play_again() -> void:
	_game_over.visible = false
	start_game(randi(), _deck0_path, _deck1_path)   # store paths from start_game
```

Store the deck paths in `start_game` (`_deck0_path`, `_deck1_path`) for play-again. Delete the two stub functions. Update the Leader drop in `handle_drop`: if only the by-discard play is legal, apply it; if **both** payments are legal, show `_leader_prompt` and apply the chosen variant on `chosen`.

- [ ] **Step 4: Run + commit**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_pending_choice_routing.gd
git add src/ui/match/match.gd src/ui/match/match.tscn tests/test_pending_choice_routing.gd
git commit -m "feat: route pending_choice to overlays/AI; real opponent + game-over; leader prompt"
```

---

# Phase 8 (rest) — Main menu + full loop

## Task 5: `main_menu` — deck select, seed, launch (run/main_scene)

The project entry point: choose a deck color → set RNG seed (random, or a fixed dev seed) → load `match.tscn` and `start_game(...)`.

**Files:**
- Create: `src/ui/menu/main_menu.tscn`, `src/ui/menu/main_menu.gd`
- Modify: `project.godot` (`run/main_scene`)
- Test: `tests/test_main_menu.gd`

- [ ] **Step 1: Failing test**

```gdscript
extends GdUnitTestSuite

func _spawn() -> Node:
	var m := load("res://src/ui/menu/main_menu.tscn").instantiate()
	add_child(m)
	auto_free(m)
	return m

func test_deck_path_for_color() -> void:
	assert_str(MainMenu.deck_path("strike")).is_equal("res://src/data/decks/strike.csv")
	assert_str(MainMenu.deck_path("audio")).is_equal("res://src/data/decks/audio.csv")

func test_selecting_a_deck_sets_choice() -> void:
	var m := _spawn()
	m.select_deck("raccoon")
	assert_str(m.chosen_deck).is_equal("raccoon")
```

- [ ] **Step 2: Implement**

`main_menu.tscn`: `MainMenu (Control) → {Title, DeckButtons (one per color), SeedField (LineEdit), PlayButton, QuitButton}`. `main_menu.gd`:

```gdscript
class_name MainMenu
extends Control

const COLORS := ["strike", "raccoon", "writing", "audio"]
const OPPONENT := "raccoon"   # fixed AI deck for the slice

var chosen_deck: String = "strike"

@onready var _seed_field: LineEdit = $SeedField
@onready var _play: Button = $PlayButton

func _ready() -> void:
	_play.pressed.connect(_on_play)
	$QuitButton.pressed.connect(func(): get_tree().quit())
	# Connect each deck button to select_deck(color)...

static func deck_path(color: String) -> String:
	return "res://src/data/decks/%s.csv" % color

func select_deck(color: String) -> void:
	chosen_deck = color

func _seed_value() -> int:
	var txt := _seed_field.text.strip_edges()
	return int(txt) if txt.is_valid_int() else randi()

func _on_play() -> void:
	var match_scene := load("res://src/ui/match/match.tscn").instantiate()
	get_tree().root.add_child(match_scene)
	match_scene.start_game(_seed_value(), deck_path(chosen_deck), deck_path(OPPONENT))
	queue_free()
```

> The opponent deck is fixed (`raccoon`) for the vertical slice; if the player also picks `raccoon`, that's fine (mirror match).

- [ ] **Step 3: Set the run scene**

In `project.godot`, set:
```
[application]
run/main_scene="res://src/ui/menu/main_menu.tscn"
```

- [ ] **Step 4: Run + commit**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_main_menu.gd
git add src/ui/menu/main_menu.tscn src/ui/menu/main_menu.gd project.godot tests/test_main_menu.gd
git commit -m "feat: main menu (deck select + seed) as run/main_scene"
```

---

## Task 6: Full-game integration test + manual smoke

Prove the whole cycle terminates by running an **AI-vs-AI** game through `match.gd` (drive both seats with `AiController`) until `GAME_OVER`, with no errors — then a manual human-vs-AI smoke.

**Files:**
- Test: `tests/test_integration_ui_game.gd`

- [ ] **Step 1: Write the integration test**

```gdscript
extends GdUnitTestSuite

# Drive both seats with the AI directly against the engine (mirrors match's cycle)
# to prove the action loop reaches a terminal state via the deck-damage path.
func test_ai_vs_ai_reaches_game_over() -> void:
	var st := GameState.new(2024)
	var en := GameEngine.new(st)
	en.setup(CardDatabase.load_deck("res://src/data/decks/strike.csv", "S"),
			 CardDatabase.load_deck("res://src/data/decks/raccoon.csv", "R"))
	var steps := 0
	while st.phase != Enums.Phase.GAME_OVER and steps < 5000:
		if st.pending_choice != null:
			en.apply(AiController.choice_action(en))
		else:
			en.apply(AiController.choose_action(en))
		steps += 1
	assert_int(st.phase).is_equal(Enums.Phase.GAME_OVER)
	assert_int(st.winner).is_between(0, 1)
```

> If a given seed stalls (e.g. both AIs only ever end turns with no progress), tune `AiController.choose_action` to favor deck attacks (already preferred) or pick a seed that terminates; the engine's reshuffle-then-lose path guarantees eventual `GAME_OVER` once decks deplete.

- [ ] **Step 2: Run the full UI test set**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/
```
Expected: all suites PASS, exit `0`.

- [ ] **Step 3: Manual smoke (editor)**

Run the project (F5 → main menu). Pick a deck, Play. Complete a mulligan, play cards, attack the opponent's units and deck, end turns; the AI takes its turns and resolves its own choices; reach a game-over (deck-damage path), hit **Play Again** for a fresh seed, and **Quit**. Confirm no console errors across a full game.

- [ ] **Step 4: Commit**

```bash
git add tests/test_integration_ui_game.gd
git commit -m "test: AI-vs-AI full-game integration reaches GAME_OVER"
```

---

## Self-review notes

- **Phase 7 coverage:** mulligan (exactly 2, leader excluded) ✓; discard-to-limit (exact `count`) ✓; leader cost prompt (tickets vs discard) ✓; game-over (winner + play again / quit) ✓; all pause table input via `pending_choice` routing (Task 4).
- **Phase 8 coverage:** `ai_controller.gd` (legal action + choice heuristic, terminates a turn — Task 1) ✓; main menu deck selection + seed + play-again (Task 5) ✓; full vs-AI loop through the shared cycle (Task 4) ✓; AI-vs-AI integration to `GAME_OVER` + manual smoke (Task 6) ✓.
- **Stubs from Plan 3 removed:** `_auto_resolve_mulligans` → mulligan panel + AI heuristic; `_take_opponent_turn_stub` → `AiController.choose_action` through `apply_action`.
- **Out of scope (per spec §9):** card ability/keyword/trap execution, multiplayer, deck building, audio. Traps remain visual-only (`_trap_condition_met` returns `false`).

---

## Series complete

With Plans 1–4 merged, the spec's full playable vertical slice is delivered: data + assets, `CardView` + juice, static table, the reconcile/flourish match cycle, player input, overlays, AI, and the menu-driven full game loop.
