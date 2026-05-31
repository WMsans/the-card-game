# In-hand Card Selection ("fly to middle") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the player pick cards directly from their hand for hand-sourced selections — each picked card flies to a staged row in the middle of the screen, picking past the limit replaces the rightmost staged card, and a floating Confirm finalizes the choice.

**Architecture:** A new `HandChoice` controller (CanvasLayer scene) drives the *real* `CardView` nodes already living in `hand_view`: it stages picked cards at centered slots and asks `hand_view` to reflow the remaining hand. Pure selection bookkeeping lives in a scene-free `StagedSelection` helper. `match.gd` routes hand-pool selections to the controller; non-hand pools (discard pile, deck candidates) keep using the existing `CardSelectPanel` overlay. The engine still resolves choices via `{"indices": [...]}` — no engine changes.

**Tech Stack:** Godot 4 / GDScript, GdUnit4 tests (`extends GdUnitTestSuite`, files `tests/test_*.gd`).

**Test command (headless, one suite):**
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/<suite>.gd
```
Exit code 0 = pass. Harmless headless noise to ignore: `ERROR: Required object "rp_font" is null` and the "InputEvents not transported in headless" notice.

---

## File Structure

- **Create** `src/ui/match/staged_selection.gd` — pure `StagedSelection` helper (staged order, select/deselect/replace-rightmost, index mapping). No scene, fully unit-testable.
- **Create** `src/ui/match/hand_choice.gd` + `src/ui/match/hand_choice.tscn` — the `HandChoice` controller: floating title + Confirm chrome, drives real hand `CardView` nodes.
- **Modify** `src/ui/table/hand_view.gd` — add `set_choice_excluded(ids)` (reflow hand around staged cards) plus order/player tracking in `render`.
- **Modify** `src/ui/match/match.gd` — route hand-pool selections to `HandChoice`, keep non-hand pools on `CardSelectPanel`; add pool discriminator.
- **Modify** `src/ui/match/match.tscn` — instance the `HandChoice` node.
- **Create** `tests/test_staged_selection.gd` — pure helper tests.
- **Create** `tests/test_hand_choice.gd` — controller tests (start → click → confirm → index mapping, replace-rightmost) using a real `hand_view` from a spawned match.
- **Modify** `tests/test_pending_choice_routing.gd` — update the hand-pool case to assert `HandChoice`; add a non-hand case asserting `CardSelectPanel`; add the end-to-end discard-to-limit resolution test.

---

## Task 1: `StagedSelection` pure helper

**Files:**
- Create: `src/ui/match/staged_selection.gd`
- Test: `tests/test_staged_selection.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_staged_selection.gd`:

```gdscript
extends GdUnitTestSuite

# source_ids are the instance_ids of the source card list, index-aligned.
# e.g. source list [cardA, cardB, cardC] -> source_ids [10, 20, 30],
# where index 0 == cardA == instance_id 10.

func _sel(min_n: int, max_n: int) -> StagedSelection:
	return StagedSelection.new([10, 20, 30, 40], min_n, max_n)

func test_select_appends_under_max() -> void:
	var s := _sel(0, 2)
	s.toggle(10)
	s.toggle(30)
	assert_array(s.staged).is_equal([10, 30])

func test_toggle_same_id_deselects() -> void:
	var s := _sel(0, 2)
	s.toggle(10)
	s.toggle(10)
	assert_array(s.staged).is_equal([])

func test_at_max_replaces_rightmost() -> void:
	var s := _sel(0, 2)
	s.toggle(10)
	s.toggle(20)        # staged == [10, 20], now at max
	s.toggle(30)        # replaces rightmost (20) with 30
	assert_array(s.staged).is_equal([10, 30])

func test_toggle_returns_change_info() -> void:
	var s := _sel(0, 2)
	var added := s.toggle(10)
	assert_int(added["added"]).is_equal(10)
	assert_int(added["removed"]).is_equal(-1)
	var removed := s.toggle(10)
	assert_int(removed["added"]).is_equal(-1)
	assert_int(removed["removed"]).is_equal(10)

func test_replace_change_info_reports_both() -> void:
	var s := _sel(0, 1)
	s.toggle(10)
	var change := s.toggle(20)   # at max 1 -> replace 10 with 20
	assert_int(change["added"]).is_equal(20)
	assert_int(change["removed"]).is_equal(10)

func test_can_confirm_boundaries() -> void:
	var s := _sel(1, 2)
	assert_bool(s.can_confirm()).is_false()   # 0 < min
	s.toggle(10)
	assert_bool(s.can_confirm()).is_true()     # 1 in [1,2]
	s.toggle(20)
	assert_bool(s.can_confirm()).is_true()     # 2 in [1,2]

func test_min_zero_can_confirm_immediately() -> void:
	var s := _sel(0, 2)
	assert_bool(s.can_confirm()).is_true()

func test_to_indices_maps_staged_to_source_indices() -> void:
	var s := _sel(0, 3)
	s.toggle(30)   # index 2
	s.toggle(10)   # index 0
	assert_array(s.to_indices()).is_equal([2, 0])   # preserves staged order

func test_to_indices_after_replace() -> void:
	var s := _sel(0, 2)
	s.toggle(10)   # index 0
	s.toggle(20)   # index 1
	s.toggle(40)   # replaces 20 -> staged [10, 40] -> indices [0, 3]
	assert_array(s.to_indices()).is_equal([0, 3])
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_staged_selection.gd
```
Expected: FAIL — `StagedSelection` is not defined.

- [ ] **Step 3: Write the implementation**

Create `src/ui/match/staged_selection.gd`:

```gdscript
class_name StagedSelection
extends RefCounted

# Pure selection bookkeeping for in-hand card choices. Holds the staged
# instance_ids in selection order and maps them back to indices in the source
# card list the engine expects. Scene-free and unit-testable.

var source_ids: Array       # instance_ids, index-aligned to the source card list
var min_n: int
var max_n: int
var staged: Array = []      # instance_ids in selection order

func _init(p_source_ids: Array, p_min: int, p_max: int) -> void:
	source_ids = p_source_ids
	min_n = p_min
	max_n = p_max

# Select / deselect / replace-rightmost. Returns {"added": id|-1, "removed": id|-1}
# so the caller knows which card to fly to center and which to return to hand.
func toggle(id: int) -> Dictionary:
	if staged.has(id):
		staged.erase(id)
		return {"added": -1, "removed": id}
	if staged.size() < max_n:
		staged.append(id)
		return {"added": id, "removed": -1}
	# At max: drop the rightmost staged card, then add the new one in its place.
	var removed: int = staged[staged.size() - 1]
	staged.remove_at(staged.size() - 1)
	staged.append(id)
	return {"added": id, "removed": removed}

func can_confirm() -> bool:
	return staged.size() >= min_n and staged.size() <= max_n

func to_indices() -> Array:
	var out: Array = []
	for id in staged:
		out.append(source_ids.find(id))
	return out
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_staged_selection.gd
```
Expected: PASS (all 9 tests).

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/staged_selection.gd tests/test_staged_selection.gd
git commit -m "feat: StagedSelection helper for in-hand card choices"
```

---

## Task 2: `hand_view` reflow support

**Files:**
- Modify: `src/ui/table/hand_view.gd`
- Test: `tests/test_hand_view_reflow.gd` (create)

**Context:** `hand_view.render(cards, player)` lays out every hand card by index using `BoardLayout.slot(Enums.Zone.HAND, i, n, player)` and positions each `CardView` at `t.origin - BoardLayout.CARD_PIVOT`. We add `set_choice_excluded(ids)` so the controller can have the hand reflow over only the non-excluded cards (excluded = staged-in-the-middle), while the controller itself positions the staged cards. `hand_view` is always the human hand (player 0); the opponent uses a separate `opponent_hand.gd`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_hand_view_reflow.gd`:

```gdscript
extends GdUnitTestSuite

# Spawn a real match so hand_view is populated with real CardView nodes.
func _hand_view_with_cards() -> Node:
	var m: Node = load("res://src/ui/match/match.tscn").instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(3, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	return m.hand_view

func test_excluding_a_card_reflows_remaining_to_n_minus_1() -> void:
	var hv := _hand_view_with_cards()
	var order: Array = hv._hand_order
	var n := order.size()
	assert_int(n).is_greater(1)

	# Exclude the first card; the remaining cards should pack as a row of n-1.
	hv.set_choice_excluded([order[0]])

	var first_visible_id: int = order[1]
	var cv: CardView = hv.card_views[first_visible_id]
	var expected := BoardLayout.slot(Enums.Zone.HAND, 0, n - 1, 0).origin - BoardLayout.CARD_PIVOT
	assert_vector(cv._rest_position).is_equal_approx(expected, Vector2(0.5, 0.5))

func test_clearing_exclusion_restores_full_layout() -> void:
	var hv := _hand_view_with_cards()
	var order: Array = hv._hand_order
	var n := order.size()
	hv.set_choice_excluded([order[0]])
	hv.set_choice_excluded([])

	var cv: CardView = hv.card_views[order[0]]
	var expected := BoardLayout.slot(Enums.Zone.HAND, 0, n, 0).origin - BoardLayout.CARD_PIVOT
	assert_vector(cv._rest_position).is_equal_approx(expected, Vector2(0.5, 0.5))
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_hand_view_reflow.gd
```
Expected: FAIL — `hand_view` has no `set_choice_excluded` / `_hand_order`.

- [ ] **Step 3: Implement the changes**

In `src/ui/table/hand_view.gd`, add these member vars just under the existing `var card_views: Dictionary = {}` line:

```gdscript
var _hand_order: Array = []   # instance_ids in left-to-right hand order
var _player: int = 0
var _excluded: Array = []     # instance_ids currently staged elsewhere (not laid out here)
```

Then in `render(cards, player)`, add these lines at the very top of the function body (before `var n := cards.size()`):

```gdscript
	_player = player
	_hand_order = []
	for c in cards:
		_hand_order.append(c.instance_id)
	_excluded = []
```

Finally, append these two functions to the end of the file:

```gdscript
# Reflow the hand over only the non-excluded cards (excluded ones are staged in
# the middle by HandChoice and positioned by it). Pass [] to restore the full row.
func set_choice_excluded(ids: Array) -> void:
	_excluded = ids.duplicate()
	var visible_ids: Array = []
	for iid in _hand_order:
		if not _excluded.has(iid):
			visible_ids.append(iid)
	var n := visible_ids.size()
	for i in range(n):
		var cv: CardView = card_views.get(visible_ids[i])
		if cv == null:
			continue
		cv.z_index = 0
		var t := BoardLayout.slot(Enums.Zone.HAND, i, n, _player)
		var rest_pos := t.origin - BoardLayout.CARD_PIVOT
		cv.set_rest(rest_pos, t.get_rotation())
		var tw := cv.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(cv, "position", rest_pos, 0.2)
		tw.parallel().tween_property(cv, "rotation", t.get_rotation(), 0.2)
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_hand_view_reflow.gd
```
Expected: PASS (2 tests).

- [ ] **Step 5: Run the existing table test to confirm no regression**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_table_view.gd
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/ui/table/hand_view.gd tests/test_hand_view_reflow.gd
git commit -m "feat: hand_view.set_choice_excluded reflow for staged cards"
```

---

## Task 3: `HandChoice` controller + scene

**Files:**
- Create: `src/ui/match/hand_choice.gd`
- Create: `src/ui/match/hand_choice.tscn`
- Test: `tests/test_hand_choice.gd`

**Context:** The controller is a `CanvasLayer` holding a centered title `Label` and a `Confirm` `Button`. It drives the *real* hand `CardView` nodes (children of `hand_view`). It disables each hand card's internal drag/hover via `set_interactive(false)` but still listens to the card's `gui_input` signal for clicks — the same pattern `mulligan_panel.gd` and `card_select_panel.gd` use (`gui_input` fires regardless of `_interactive`; `_interactive` only gates the card's own drag/hover handlers). Staged cards keep the hand's scale (`BoardLayout.CARD_SCALE`) — they are never scaled up.

- [ ] **Step 1: Write the failing test**

Create `tests/test_hand_choice.gd`:

```gdscript
extends GdUnitTestSuite

# Spawn a real match so HandChoice can drive a populated hand_view.
func _match() -> Node:
	var m: Node = load("res://src/ui/match/match.tscn").instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(3, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	return m

func test_start_shows_chrome_and_title() -> void:
	var m := _match()
	var hc := m._hand_choice
	hc.start(m.hand_view, m.state.players[0].hand, 1, 1, "Pick 1")
	assert_bool(hc.visible).is_true()
	assert_str(hc.find_child("Title").text).is_equal("Pick 1")
	# min not met yet -> confirm disabled
	assert_bool(hc.find_child("Confirm").disabled).is_true()

func test_click_then_confirm_emits_source_index() -> void:
	var m := _match()
	var hc := m._hand_choice
	var hand: Array = m.state.players[0].hand
	hc.start(m.hand_view, hand, 1, 1, "Pick 1")
	var got := {"indices": []}
	hc.confirmed.connect(func(idx): got["indices"] = idx)
	hc._on_card_clicked(hand[2].instance_id)
	assert_bool(hc.find_child("Confirm").disabled).is_false()
	hc._confirm_pressed()
	assert_array(got["indices"]).is_equal([2])

func test_clicking_past_max_replaces_rightmost() -> void:
	var m := _match()
	var hc := m._hand_choice
	var hand: Array = m.state.players[0].hand
	hc.start(m.hand_view, hand, 2, 2, "Pick 2")
	var got := {"indices": []}
	hc.confirmed.connect(func(idx): got["indices"] = idx)
	hc._on_card_clicked(hand[0].instance_id)
	hc._on_card_clicked(hand[1].instance_id)
	hc._on_card_clicked(hand[2].instance_id)   # replaces rightmost (index 1)
	hc._confirm_pressed()
	assert_array(got["indices"]).is_equal([0, 2])

func test_clicking_staged_card_deselects() -> void:
	var m := _match()
	var hc := m._hand_choice
	var hand: Array = m.state.players[0].hand
	hc.start(m.hand_view, hand, 0, 2, "Up to 2")
	hc._on_card_clicked(hand[0].instance_id)
	hc._on_card_clicked(hand[0].instance_id)   # toggle off
	var got := {"indices": [-99]}
	hc.confirmed.connect(func(idx): got["indices"] = idx)
	hc._confirm_pressed()                       # min 0 -> allowed with empty
	assert_array(got["indices"]).is_equal([])
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_hand_choice.gd
```
Expected: FAIL — `_hand_choice` does not exist on match yet (this becomes green after Task 4 wires the node, but the controller code below must exist first). If you run it now it fails on missing `hand_choice.gd`/node.

> Note: this suite depends on the `HandChoice` node being present in `match.tscn` and exposed as `_hand_choice` (Task 4). Implement Step 3 here, then this suite goes green after Task 4 Step 3. Run it again at the end of Task 4.

- [ ] **Step 3: Write the controller script**

Create `src/ui/match/hand_choice.gd`:

```gdscript
extends CanvasLayer

# Drives the real hand CardView nodes for hand-sourced selections: picked cards
# fly to a centered staged row; picking past max replaces the rightmost staged
# card; clicking a staged card returns it. Emits the chosen source indices.

signal confirmed(indices: Array)

const THEME := preload("res://src/ui/theme/game_theme.tres")
const STAGE_SLOT_W := 180.0    # matches BoardLayout.HAND_SLOT_W
const STAGE_Y := 500.0         # vertical center of the staged row (screen space)

@onready var _title: Label = $Title
@onready var _confirm: Button = $Confirm

var _hand_view = null
var _sel: StagedSelection = null
var _handlers: Dictionary = {}   # instance_id -> Callable connected to gui_input
var _locked: Array = []          # instance_ids set non-interactive during selection
var _active: bool = false

func _ready() -> void:
	_title.theme = THEME
	_confirm.theme = THEME
	_confirm.pressed.connect(_confirm_pressed)
	JuicyButton.apply(_confirm)

func start(hand_view, source_cards: Array, min_n: int, max_n: int, title: String) -> void:
	if not is_node_ready():
		await ready
	if _active:
		return
	_hand_view = hand_view
	var source_ids: Array = []
	for c in source_cards:
		source_ids.append(c.instance_id)
	_sel = StagedSelection.new(source_ids, min_n, max_n)
	_title.text = title
	# Lock every hand card's own drag/hover; keep gui_input clicks for source cards.
	_locked = []
	for id in _hand_view.card_views.keys():
		var cv: CardView = _hand_view.card_views[id]
		cv.set_interactive(false)
		_locked.append(id)
	_handlers = {}
	for id in source_ids:
		var cv: CardView = _hand_view.card_views.get(id)
		if cv == null:
			continue
		var cb := _make_click_handler(id)
		cv.gui_input.connect(cb)
		_handlers[id] = cb
	_active = true
	visible = true
	_confirm.disabled = not _sel.can_confirm()

func _make_click_handler(id: int) -> Callable:
	return func(e):
		if e is InputEventMouseButton and e.pressed:
			_on_card_clicked(id)

func _on_card_clicked(id: int) -> void:
	if _sel == null:
		return
	_sel.toggle(id)
	# Reflow the hand around the staged cards; any returned card is re-included here.
	_hand_view.set_choice_excluded(_sel.staged)
	# Position the staged cards in a centered row (same scale as the hand).
	_restage()
	_confirm.disabled = not _sel.can_confirm()

func _restage() -> void:
	var n := _sel.staged.size()
	for i in range(n):
		var cv: CardView = _hand_view.card_views.get(_sel.staged[i])
		if cv == null:
			continue
		var pos := Vector2(_stage_x(i, n), STAGE_Y) - BoardLayout.CARD_PIVOT
		cv.z_index = 50 + i
		cv.set_rest(pos, 0.0)
		var tw := cv.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(cv, "position", pos, 0.2)
		tw.parallel().tween_property(cv, "rotation", 0.0, 0.2)

func _stage_x(index: int, count: int) -> float:
	var total := STAGE_SLOT_W * float(count)
	var start := BoardLayout.CENTER_X - total * 0.5 + STAGE_SLOT_W * 0.5
	return start + STAGE_SLOT_W * float(index)

func _confirm_pressed() -> void:
	if _sel == null or not _sel.can_confirm():
		return
	var indices := _sel.to_indices()
	_deactivate()
	confirmed.emit(indices)

func _deactivate() -> void:
	for id in _handlers:
		var cv: CardView = _hand_view.card_views.get(id)
		if cv != null and cv.gui_input.is_connected(_handlers[id]):
			cv.gui_input.disconnect(_handlers[id])
	_handlers.clear()
	for id in _locked:
		var cv: CardView = _hand_view.card_views.get(id)
		if cv != null:
			cv.set_interactive(true)
	_locked.clear()
	if _hand_view != null:
		_hand_view.set_choice_excluded([])
	_sel = null
	_active = false
	visible = false
```

- [ ] **Step 4: Create the scene**

Create `src/ui/match/hand_choice.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/ui/match/hand_choice.gd" id="1_hc"]

[node name="HandChoice" type="CanvasLayer"]
visible = false
script = ExtResource("1_hc")

[node name="Title" type="Label" parent="."]
offset_left = 560.0
offset_top = 270.0
offset_right = 1360.0
offset_bottom = 320.0
horizontal_alignment = 1
theme_override_font_sizes/font_size = 32
text = "Select cards"

[node name="Confirm" type="Button" parent="."]
offset_left = 860.0
offset_top = 680.0
offset_right = 1060.0
offset_bottom = 730.0
text = "Confirm"
```

- [ ] **Step 5: Commit (controller + scene)**

```bash
git add src/ui/match/hand_choice.gd src/ui/match/hand_choice.tscn tests/test_hand_choice.gd
git commit -m "feat: HandChoice controller and scene (fly-to-middle selection)"
```

(The `tests/test_hand_choice.gd` suite goes green after Task 4 wires the node into the match — it is re-run there.)

---

## Task 4: Route hand-pool selections to `HandChoice`

**Files:**
- Modify: `src/ui/match/match.tscn`
- Modify: `src/ui/match/match.gd`
- Test: `tests/test_pending_choice_routing.gd` (modify), `tests/test_hand_choice.gd` (re-run)

**Context:** `match.gd` routes `pending_choice`s. Today both `discard_to_limit` and the `card_effect` / `select_cards` shape call `_select.show_selection(...)`. We change hand-sourced selections to `_hand_choice.start(...)` and keep non-hand pools (cards not in the human hand) on `_select`. Both `_select` and `_hand_choice` emit `confirmed(indices)` and resolve identically via `Action.resolve_choice({"indices": idx})`.

- [ ] **Step 1: Add the `HandChoice` node to `match.tscn`**

In `src/ui/match/match.tscn`, add this `ext_resource` line after the existing `id="16_trap_reveal"` line (around line 18):

```
[ext_resource type="PackedScene" path="res://src/ui/match/hand_choice.tscn" id="17_hand_choice"]
```

Then add this node instance after the `TrapRevealOverlay` node (after the block ending the file, around line 194):

```
[node name="HandChoice" parent="." instance=ExtResource("17_hand_choice")]
```

- [ ] **Step 2: Wire and route in `match.gd`**

In `src/ui/match/match.gd`, add the `@onready` reference next to the other overlay references (after the `_trap_reveal` line, ~line 34):

```gdscript
@onready var _hand_choice = $HandChoice
```

In `_ready()`, after the existing `_select.confirmed.connect(...)` line (~line 44), add:

```gdscript
	_hand_choice.confirmed.connect(func(idx): apply_action(Action.resolve_choice({"indices": idx})))
```

Replace the `"discard_to_limit"` branch in `_route_pending_choice` (currently):

```gdscript
		"discard_to_limit":
			var n: int = pc.data["count"]
			_select.show_selection(state.players[HUMAN].hand, n, n, "Discard %d card(s)" % n)
```

with:

```gdscript
		"discard_to_limit":
			var n: int = pc.data["count"]
			_hand_choice.start(hand_view, state.players[HUMAN].hand, n, n, "Discard %d card(s)" % n)
```

Replace the `"select_cards"` branch in `_route_card_effect` (currently):

```gdscript
		"select_cards":
			_select.show_selection(spec.cards, spec.min_n, spec.max_n, spec.title)
```

with:

```gdscript
		"select_cards":
			if _is_hand_pool(spec.cards):
				_hand_choice.start(hand_view, spec.cards, spec.min_n, spec.max_n, spec.title)
			else:
				_select.show_selection(spec.cards, spec.min_n, spec.max_n, spec.title)
```

Add this helper method (place it right after `_route_card_effect`):

```gdscript
# A selection uses the in-hand flow only when its whole source pool is the
# human player's current hand. Non-hand pools (discard pile, deck candidates)
# fall back to the CardSelectPanel overlay.
func _is_hand_pool(cards: Array) -> bool:
	if cards.is_empty():
		return false
	var hand_ids := {}
	for c in state.players[HUMAN].hand:
		hand_ids[c.instance_id] = true
	for c in cards:
		if not hand_ids.has(c.instance_id):
			return false
	return true
```

- [ ] **Step 3: Update `tests/test_pending_choice_routing.gd`**

Replace the existing `test_select_cards_choice_shows_card_select_panel` test (lines 25-31) with these three tests:

```gdscript
func test_hand_pool_select_cards_uses_hand_choice() -> void:
	var m: Node = _spawn()
	m.start_game(3, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	# Source list is the whole human hand -> in-hand flow.
	var spec := ChoiceSpec.select_cards(m.state.players[0].hand, 0, 1, "Pick")
	m.state.pending_choice = PendingChoice.new("card_effect", 0, {"spec": spec, "ui_shape": "select_cards"})
	m._route_pending_choice()
	assert_bool(m.get_node("HandChoice").visible).is_true()
	assert_bool(m.get_node("CardSelectPanel").visible).is_false()

func test_non_hand_pool_select_cards_uses_overlay() -> void:
	var m: Node = _spawn()
	m.start_game(3, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	# A card NOT in the hand (synthetic id) -> overlay path.
	var def: CardDefinition = m.state.players[0].hand[0].definition
	var outsider := CardInstance.new(999999, def)
	var spec := ChoiceSpec.select_cards([outsider], 0, 1, "Pick")
	m.state.pending_choice = PendingChoice.new("card_effect", 0, {"spec": spec, "ui_shape": "select_cards"})
	m._route_pending_choice()
	assert_bool(m.get_node("CardSelectPanel").visible).is_true()
	assert_bool(m.get_node("HandChoice").visible).is_false()

func test_discard_to_limit_resolves_through_hand_choice() -> void:
	var m: Node = _spawn()
	m.start_game(3, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	var hand: Array = m.state.players[0].hand
	var id0: int = hand[0].instance_id
	var id1: int = hand[1].instance_id
	m.state.pending_choice = PendingChoice.new("discard_to_limit", 0, {"count": 2})
	m._route_pending_choice()
	assert_bool(m.get_node("HandChoice").visible).is_true()
	m._hand_choice._on_card_clicked(id0)
	m._hand_choice._on_card_clicked(id1)
	m._hand_choice._confirm_pressed()
	assert_bool(m.state.pending_choice == null).is_true()
	var discard_ids: Array = []
	for c in m.state.players[0].discard:
		discard_ids.append(c.instance_id)
	assert_bool(discard_ids.has(id0)).is_true()
	assert_bool(discard_ids.has(id1)).is_true()
```

- [ ] **Step 4: Run the routing + controller suites**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_pending_choice_routing.gd
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_hand_choice.gd
```
Expected: PASS for both suites.

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/match.tscn src/ui/match/match.gd tests/test_pending_choice_routing.gd
git commit -m "feat: route hand-pool selections to HandChoice; keep overlay for non-hand pools"
```

---

## Task 5: Full-suite regression check

**Files:** none (verification only)

- [ ] **Step 1: Run the whole test directory**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```
Expected: exit code 0. Pay attention to `test_overlays.gd` (CardSelectPanel still used by non-hand pools — must stay green), `test_choice_system.gd`, `test_match_flow.gd`, `test_integration_ui_game.gd`, and the engine choice tests — none of these should regress since the engine still consumes `{"indices": [...]}` unchanged.

- [ ] **Step 2: If anything fails, fix and re-run**

Triage any failure against the cause. The most likely break is a test that previously assumed a hand-sourced `select_cards` opened `CardSelectPanel`; update such assertions to `HandChoice` (the in-hand path) as in Task 4 Step 3. Do not change engine resolution.

- [ ] **Step 3: Commit any fixes**

```bash
git add -A
git commit -m "test: reconcile selection tests with in-hand HandChoice flow"
```

---

## Notes for the implementer

- **Why `set_interactive(false)` + `gui_input` (not a custom drag lock):** A `CardView` only emits `clicked`/drag signals through its own handlers, which are gated by `_interactive`. Setting `_interactive = false` cleanly disables drag and hover-lift while the `gui_input` Control signal still fires, letting `HandChoice` detect plain clicks. This mirrors `mulligan_panel.gd` and `card_select_panel.gd`.
- **Coordinate space:** `hand_view` is effectively at the scene origin — `render` assigns `BoardLayout.slot(...).origin - CARD_PIVOT` straight to `CardView.position`. So staged-slot screen coordinates can be used directly as `hand_view`-local positions; no `to_local`/reparenting needed.
- **Staged card size:** never touch `scale` — staged cards keep `BoardLayout.CARD_SCALE` from the hand, satisfying the "same size as in hand" requirement.
- **Headless input:** tests drive selection by calling `_on_card_clicked(id)` / `_confirm_pressed()` directly (input events are not transported in headless), matching how `test_overlays.gd` calls `toggle_index`.
```
