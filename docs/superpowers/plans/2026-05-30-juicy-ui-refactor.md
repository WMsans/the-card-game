# Juicy UI Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the whole game a juicy, consistent, reusable cartoony UI — themed buttons with hover/press motion, a unified card-highlight system, board-based drag feedback with dashed drop zones, juicy ticket pips with a red cost preview, and a symmetric framed table layout.

**Architecture:** A shared `src/ui/theme/` backbone (a `UiPalette` color source of truth, a `game_theme.tres` applied at runtime via theme inheritance, a static `JuicyButton` retrofit helper, a `CardHighlight` glow overlay, and a `DropZoneOverlay`) layered on top of the existing scenes. Drag-feedback decision logic is pulled into a pure `DragClassifier` so it is unit-testable headless; tweens and drawing are verified manually.

**Tech Stack:** Godot 4.6 (GL Compatibility), GDScript, GdUnit4 for tests.

**Conventions:**
- One `class_name` per file, snake_case filenames, matching the existing `src/ui/` style.
- Run one suite headless:
  `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/<suite>.gd`
  Whole dir: `-a res://tests`. Exit code 0 = pass; reports land in `reports/report_N/`.
- Harmless headless noise to ignore: `ERROR: Required object "rp_font" is null` and the "InputEvents not transported in headless" notice.
- Commit after each task.

**Design deviation from spec (intentional):** `JuicyButton` is implemented as a **static retrofit helper** (`JuicyButton.apply(button)`) rather than a `Button` subclass. This juices existing buttons with one line in each screen's `_ready()` and needs zero `.tscn` surgery, which is both less error-prone and more reusable. Same applies to applying the theme — done in code (`root.theme = preload(...)`) so it also reaches the overlay panels, which sit under `CanvasLayer` nodes and therefore do not inherit a theme set on the match root.

---

## File Structure

**New files:**
- `src/ui/theme/ui_palette.gd` — `class_name UiPalette`: all canonical colors + a couple sizing constants. Single source of truth.
- `src/ui/theme/game_theme.tres` — Godot `Theme`: Button/Panel/Label StyleBoxes, font sizes, font colors.
- `src/ui/theme/juicy_button.gd` — `class_name JuicyButton`: static `apply(button)` wiring hover/press tweens.
- `src/ui/theme/card_highlight.gd` — `class_name CardHighlight extends Control`: glow-border overlay with named states.
- `src/ui/table/drop_zone_overlay.gd` — `class_name DropZoneOverlay extends Control`: dashed cartoony drop zones.
- `src/ui/match/drag_classifier.gd` — `class_name DragClassifier`: pure drag-state classification + zone advertising.
- Tests: `tests/test_ui_palette.gd`, `tests/test_game_theme.gd`, `tests/test_juicy_button.gd`, `tests/test_card_highlight.gd`, `tests/test_drag_classifier.gd`, `tests/test_drop_zone_overlay.gd`.

**Modified files:**
- `src/ui/card/card_view.tscn` / `card_view.gd` — add `Highlight` child + `set_highlight`; route `set_playable`/`set_attackable` through it.
- `src/ui/table/ticket_tray.gd` — store pip state, juicy pop on change, `preview_cost`/`clear_preview`, colors from palette.
- `src/ui/table/hand_view.gd` — emit `card_drag_started`.
- `src/ui/match/match.tscn` / `match.gd` — add `DropZoneLayer`, station/felt `Panel` frames, theme + button juice, drive drop zones + pip preview during drag.
- `src/ui/menu/main_menu.gd` — theme, button juice, selected-deck state.
- `src/ui/overlays/*.gd` (discard, mulligan, leader_cost_prompt, game_over, turn_banner) — theme + button juice; selection highlight via `CardHighlight`.
- `tests/test_ticket_tray.gd` — extend for preview + computed `filled_count`.

---

## Task 1: `UiPalette` color source of truth

**Files:**
- Create: `src/ui/theme/ui_palette.gd`
- Test: `tests/test_ui_palette.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_ui_palette.gd
extends GdUnitTestSuite

func test_core_colors_are_defined() -> void:
	assert_int(typeof(UiPalette.BTN_NORMAL)).is_equal(TYPE_COLOR)
	assert_int(typeof(UiPalette.HL_PLAYABLE)).is_equal(TYPE_COLOR)
	assert_int(typeof(UiPalette.PIP_COST)).is_equal(TYPE_COLOR)

func test_drag_zone_colors_are_translucent() -> void:
	assert_float(UiPalette.ZONE_ACCEPTABLE.a).is_less(1.0)
	assert_float(UiPalette.ZONE_UNAFFORDABLE.a).is_less(1.0)
	assert_float(UiPalette.ZONE_NEUTRAL.a).is_less(1.0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_ui_palette.gd`
Expected: FAIL (`UiPalette` not found).

- [ ] **Step 3: Create the palette**

```gdscript
# src/ui/theme/ui_palette.gd
class_name UiPalette
extends RefCounted

# Chrome
const BG := Color(0.17, 0.13, 0.20, 1.0)
const PANEL := Color(0.23, 0.18, 0.28, 0.96)
const PANEL_BORDER := Color(0.94, 0.89, 0.72, 1.0)
const ACCENT := Color(1.0, 0.70, 0.27, 1.0)
const TEXT := Color(0.99, 0.96, 0.89, 1.0)

# Buttons
const BTN_NORMAL := Color(0.91, 0.45, 0.23, 1.0)
const BTN_HOVER := Color(1.0, 0.58, 0.27, 1.0)
const BTN_PRESSED := Color(0.79, 0.35, 0.16, 1.0)
const BTN_DISABLED := Color(0.42, 0.36, 0.32, 1.0)

# Card highlight glows
const HL_PLAYABLE := Color(0.34, 0.78, 1.0, 1.0)
const HL_ATTACKABLE := Color(1.0, 0.70, 0.27, 1.0)
const HL_SELECTABLE := Color(0.34, 0.78, 1.0, 1.0)
const HL_SELECTED := Color(1.0, 0.82, 0.29, 1.0)

# Drop zones
const ZONE_NEUTRAL := Color(1.0, 1.0, 1.0, 0.12)
const ZONE_ACCEPTABLE := Color(0.36, 0.85, 0.45, 0.30)
const ZONE_UNAFFORDABLE := Color(0.95, 0.70, 0.25, 0.30)
const ZONE_OUTLINE := Color(0.98, 0.95, 0.85, 0.85)

# Ticket pips
const PIP_FILLED := Color(0.96, 0.80, 0.20, 1.0)
const PIP_EMPTY := Color(0.30, 0.30, 0.30, 1.0)
const PIP_COST := Color(0.91, 0.29, 0.23, 1.0)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_ui_palette.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/ui/theme/ui_palette.gd tests/test_ui_palette.gd
git commit -m "feat(ui): add UiPalette color source of truth"
```

---

## Task 2: `game_theme.tres` cartoony theme

**Files:**
- Create: `src/ui/theme/game_theme.tres`
- Test: `tests/test_game_theme.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_game_theme.gd
extends GdUnitTestSuite

const THEME := "res://src/ui/theme/game_theme.tres"

func test_theme_loads_and_styles_buttons() -> void:
	var theme: Theme = load(THEME)
	assert_object(theme).is_instanceof(Theme)
	assert_bool(theme.has_stylebox("normal", "Button")).is_true()
	assert_bool(theme.has_stylebox("hover", "Button")).is_true()
	assert_bool(theme.has_stylebox("pressed", "Button")).is_true()
	assert_bool(theme.has_stylebox("disabled", "Button")).is_true()

func test_theme_styles_panels() -> void:
	var theme: Theme = load(THEME)
	assert_bool(theme.has_stylebox("panel", "Panel")).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_game_theme.gd`
Expected: FAIL (resource missing).

- [ ] **Step 3: Create the theme resource**

```
# src/ui/theme/game_theme.tres
[gd_resource type="Theme" load_steps=6 format=3]

[sub_resource type="StyleBoxFlat" id="btn_normal"]
bg_color = Color(0.91, 0.45, 0.23, 1)
corner_radius_top_left = 14
corner_radius_top_right = 14
corner_radius_bottom_right = 14
corner_radius_bottom_left = 14
content_margin_left = 20.0
content_margin_top = 12.0
content_margin_right = 20.0
content_margin_bottom = 12.0
shadow_color = Color(0, 0, 0, 0.35)
shadow_size = 6

[sub_resource type="StyleBoxFlat" id="btn_hover"]
bg_color = Color(1, 0.58, 0.27, 1)
corner_radius_top_left = 14
corner_radius_top_right = 14
corner_radius_bottom_right = 14
corner_radius_bottom_left = 14
content_margin_left = 20.0
content_margin_top = 12.0
content_margin_right = 20.0
content_margin_bottom = 12.0
shadow_color = Color(0, 0, 0, 0.35)
shadow_size = 8

[sub_resource type="StyleBoxFlat" id="btn_pressed"]
bg_color = Color(0.79, 0.35, 0.16, 1)
corner_radius_top_left = 14
corner_radius_top_right = 14
corner_radius_bottom_right = 14
corner_radius_bottom_left = 14
content_margin_left = 20.0
content_margin_top = 12.0
content_margin_right = 20.0
content_margin_bottom = 12.0

[sub_resource type="StyleBoxFlat" id="btn_disabled"]
bg_color = Color(0.42, 0.36, 0.32, 1)
corner_radius_top_left = 14
corner_radius_top_right = 14
corner_radius_bottom_right = 14
corner_radius_bottom_left = 14
content_margin_left = 20.0
content_margin_top = 12.0
content_margin_right = 20.0
content_margin_bottom = 12.0

[sub_resource type="StyleBoxFlat" id="panel"]
bg_color = Color(0.23, 0.18, 0.28, 0.96)
border_width_left = 4
border_width_top = 4
border_width_right = 4
border_width_bottom = 4
border_color = Color(0.94, 0.89, 0.72, 1)
corner_radius_top_left = 18
corner_radius_top_right = 18
corner_radius_bottom_right = 18
corner_radius_bottom_left = 18
content_margin_left = 18.0
content_margin_top = 18.0
content_margin_right = 18.0
content_margin_bottom = 18.0
shadow_color = Color(0, 0, 0, 0.45)
shadow_size = 10

[resource]
Button/colors/font_color = Color(0.99, 0.96, 0.89, 1)
Button/colors/font_hover_color = Color(1, 1, 1, 1)
Button/colors/font_pressed_color = Color(1, 1, 1, 1)
Button/colors/font_disabled_color = Color(0.8, 0.78, 0.74, 1)
Button/font_sizes/font_size = 22
Button/styles/normal = SubResource("btn_normal")
Button/styles/hover = SubResource("btn_hover")
Button/styles/pressed = SubResource("btn_pressed")
Button/styles/disabled = SubResource("btn_disabled")
Button/styles/focus = SubResource("btn_normal")
Label/colors/font_color = Color(0.99, 0.96, 0.89, 1)
Label/font_sizes/font_size = 22
Panel/styles/panel = SubResource("panel")
PanelContainer/styles/panel = SubResource("panel")
```

Note: `load_steps` is only a hint; Godot recomputes it on first save. If the editor rewrites the value, that is expected and fine.

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_game_theme.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/ui/theme/game_theme.tres tests/test_game_theme.gd
git commit -m "feat(ui): add cartoony game theme resource"
```

---

## Task 3: `JuicyButton` retrofit helper

**Files:**
- Create: `src/ui/theme/juicy_button.gd`
- Test: `tests/test_juicy_button.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_juicy_button.gd
extends GdUnitTestSuite

func _btn() -> Button:
	var b := Button.new()
	b.size = Vector2(120, 40)
	add_child(b)
	auto_free(b)
	return b

func test_apply_recenters_pivot_and_connects_signals() -> void:
	var b := _btn()
	JuicyButton.apply(b)
	assert_vector(b.pivot_offset).is_equal(Vector2(60, 20))
	assert_int(b.mouse_entered.get_connections().size()).is_greater(0)
	assert_int(b.button_down.get_connections().size()).is_greater(0)

func test_disabled_button_does_not_scale_on_hover() -> void:
	var b := _btn()
	b.disabled = true
	JuicyButton.apply(b)
	b.mouse_entered.emit()
	assert_vector(b.scale).is_equal(Vector2.ONE)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_juicy_button.gd`
Expected: FAIL (`JuicyButton` not found).

- [ ] **Step 3: Implement the helper**

```gdscript
# src/ui/theme/juicy_button.gd
class_name JuicyButton
extends RefCounted

const HOVER_SCALE := 1.08
const PRESS_SCALE := 0.92
const TILT_DEG := 2.5
const HOVER_TIME := 0.25
const SETTLE_TIME := 0.4
const PRESS_TIME := 0.08

# Retrofits hover/press tween motion onto an existing Button. State lives in a
# captured dictionary so each button gets its own tween without a subclass.
static func apply(btn: Button) -> void:
	btn.pivot_offset = btn.size * 0.5
	btn.resized.connect(func() -> void: btn.pivot_offset = btn.size * 0.5)
	var st := {"tween": null}
	var retween := func() -> Tween:
		if st["tween"] != null and st["tween"].is_running():
			st["tween"].kill()
		st["tween"] = btn.create_tween().set_ease(Tween.EASE_OUT)
		return st["tween"]
	btn.mouse_entered.connect(func() -> void:
		if btn.disabled: return
		var t: Tween = retween.call().set_trans(Tween.TRANS_BACK)
		t.tween_property(btn, "scale", Vector2.ONE * HOVER_SCALE, HOVER_TIME)
		t.parallel().tween_property(btn, "rotation", deg_to_rad(TILT_DEG), HOVER_TIME))
	btn.mouse_exited.connect(func() -> void:
		var t: Tween = retween.call().set_trans(Tween.TRANS_ELASTIC)
		t.tween_property(btn, "scale", Vector2.ONE, SETTLE_TIME)
		t.parallel().tween_property(btn, "rotation", 0.0, SETTLE_TIME))
	btn.button_down.connect(func() -> void:
		if btn.disabled: return
		var t: Tween = retween.call().set_trans(Tween.TRANS_BACK)
		t.tween_property(btn, "scale", Vector2.ONE * PRESS_SCALE, PRESS_TIME)
		t.parallel().tween_property(btn, "rotation", deg_to_rad(-TILT_DEG), PRESS_TIME))
	btn.button_up.connect(func() -> void:
		if btn.disabled: return
		var target := HOVER_SCALE if btn.is_hovered() else 1.0
		var t: Tween = retween.call().set_trans(Tween.TRANS_ELASTIC)
		t.tween_property(btn, "scale", Vector2.ONE * target, SETTLE_TIME)
		t.parallel().tween_property(btn, "rotation", 0.0, SETTLE_TIME))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_juicy_button.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/ui/theme/juicy_button.gd tests/test_juicy_button.gd
git commit -m "feat(ui): add JuicyButton hover/press motion helper"
```

---

## Task 4: `CardHighlight` glow overlay

**Files:**
- Create: `src/ui/theme/card_highlight.gd`
- Test: `tests/test_card_highlight.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_card_highlight.gd
extends GdUnitTestSuite

func _hl() -> CardHighlight:
	var h := CardHighlight.new()
	h.size = Vector2(350, 490)
	add_child(h)
	auto_free(h)
	return h

func test_starts_hidden() -> void:
	assert_bool(_hl().visible).is_false()

func test_set_state_toggles_visibility() -> void:
	var h := _hl()
	h.set_state(CardHighlight.State.PLAYABLE)
	assert_bool(h.visible).is_true()
	h.set_state(CardHighlight.State.NONE)
	assert_bool(h.visible).is_false()

func test_set_state_selects_color() -> void:
	var h := _hl()
	h.set_state(CardHighlight.State.SELECTED)
	assert_object(h.current_color()).is_equal(UiPalette.HL_SELECTED)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_highlight.gd`
Expected: FAIL (`CardHighlight` not found).

- [ ] **Step 3: Implement the overlay**

```gdscript
# src/ui/theme/card_highlight.gd
class_name CardHighlight
extends Control

enum State { NONE, PLAYABLE, ATTACKABLE, SELECTABLE, SELECTED }

const _COLORS := {
	State.PLAYABLE: UiPalette.HL_PLAYABLE,
	State.ATTACKABLE: UiPalette.HL_ATTACKABLE,
	State.SELECTABLE: UiPalette.HL_SELECTABLE,
	State.SELECTED: UiPalette.HL_SELECTED,
}

var _state: int = State.NONE
var _color: Color = Color.TRANSPARENT
var _pulse: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func set_state(state: int) -> void:
	_state = state
	visible = state != State.NONE
	if visible:
		_color = _COLORS[state]
	queue_redraw()

func current_color() -> Color:
	return _color

func _process(delta: float) -> void:
	if not visible:
		return
	_pulse = fmod(_pulse + delta * 3.0, TAU)
	queue_redraw()

func _draw() -> void:
	if _state == State.NONE:
		return
	var a := 0.55 + 0.35 * sin(_pulse)
	var border := Color(_color.r, _color.g, _color.b, a)
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, border, false, 6.0)
	draw_rect(rect.grow(-3.0), Color(_color.r, _color.g, _color.b, a * 0.15), true)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_highlight.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/ui/theme/card_highlight.gd tests/test_card_highlight.gd
git commit -m "feat(ui): add CardHighlight glow overlay"
```

---

## Task 5: Wire `CardHighlight` into `CardView`

**Files:**
- Modify: `src/ui/card/card_view.tscn` (add `Highlight` child node)
- Modify: `src/ui/card/card_view.gd` (add `set_highlight`, route `set_playable`/`set_attackable`)
- Test: `tests/test_card_view.gd` (add cases)

- [ ] **Step 1: Add the failing test cases**

Append to `tests/test_card_view.gd`:

```gdscript
func test_set_highlight_toggles_overlay() -> void:
	var cv := _spawn()
	cv.set_highlight(CardHighlight.State.PLAYABLE)
	assert_bool((cv.find_child("Highlight") as Control).visible).is_true()
	cv.set_highlight(CardHighlight.State.NONE)
	assert_bool((cv.find_child("Highlight") as Control).visible).is_false()

func test_set_playable_drives_highlight() -> void:
	var cv := _spawn()
	cv.set_playable(true)
	assert_bool((cv.find_child("Highlight") as Control).visible).is_true()
	cv.set_playable(false)
	assert_bool((cv.find_child("Highlight") as Control).visible).is_false()
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_view.gd`
Expected: FAIL (no `Highlight` node / `set_highlight` undefined).

- [ ] **Step 3: Add the `Highlight` node to `card_view.tscn`**

Add this ext_resource line alongside the others near the top of `src/ui/card/card_view.tscn`:

```
[ext_resource type="Script" path="res://src/ui/theme/card_highlight.gd" id="9_hl"]
```

Add this node at the **end** of the file (last child of the root `CardView`, so it draws above `CardSurface`):

```
[node name="Highlight" type="Control" parent="." unique_id=771100922]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
script = ExtResource("9_hl")
```

- [ ] **Step 4: Update `card_view.gd`**

Add the onready ref near the other `@onready` lines (after line 34):

```gdscript
@onready var _highlight: CardHighlight = $Highlight
```

Replace the existing `set_playable` and `set_attackable` (lines 134-138) with:

```gdscript
func set_highlight(state: int) -> void:
	_highlight.set_state(state)

func set_playable(v: bool) -> void:
	set_highlight(CardHighlight.State.PLAYABLE if v else CardHighlight.State.NONE)

func set_attackable(v: bool) -> void:
	set_highlight(CardHighlight.State.ATTACKABLE if v else CardHighlight.State.NONE)
```

(Remove the old `modulate`-based bodies — the glow overlay replaces the flat tint.)

- [ ] **Step 5: Run card_view + reconcile suites to verify pass**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_view.gd`
Then: `... -a res://tests/test_match_reconcile.gd`
Expected: PASS both.

- [ ] **Step 6: Commit**

```bash
git add src/ui/card/card_view.tscn src/ui/card/card_view.gd tests/test_card_view.gd
git commit -m "feat(ui): route card playable/attackable through CardHighlight glow"
```

---

## Task 6: `DragClassifier` pure logic

**Files:**
- Create: `src/ui/match/drag_classifier.gd`
- Test: `tests/test_drag_classifier.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_drag_classifier.gd
extends GdUnitTestSuite

func _state_in_main(seed_value: int) -> Array:
	var st := GameState.new(seed_value)
	var en := GameEngine.new(st)
	en.setup(CardDatabase.load_deck("res://src/data/decks/strike.csv", "S"),
			 CardDatabase.load_deck("res://src/data/decks/raccoon.csv", "R"))
	while st.pending_choice != null:
		en.apply(Action.mulligan([0, 1]))
	return [st, en]

func test_legal_play_is_acceptable() -> void:
	var pair := _state_in_main(3)
	var st: GameState = pair[0]
	var en: GameEngine = pair[1]
	var legal := en.get_legal_actions()
	var plays := legal.filter(func(a): return a.type == Enums.ActionType.PLAY_CARD)
	if plays.is_empty():
		return
	var iid: int = plays[0].params["instance_id"]
	assert_int(DragClassifier.classify(st, legal, iid, 0)).is_equal(DragClassifier.State.ACCEPTABLE)

func test_card_not_in_hand_is_invalid() -> void:
	var pair := _state_in_main(3)
	var st: GameState = pair[0]
	var en: GameEngine = pair[1]
	assert_int(DragClassifier.classify(st, en.get_legal_actions(), 999999, 0)).is_equal(DragClassifier.State.INVALID)

func test_not_your_turn_is_invalid() -> void:
	var pair := _state_in_main(3)
	var st: GameState = pair[0]
	var en: GameEngine = pair[1]
	var iid: int = st.players[0].hand[0].instance_id
	st.active_player = 1
	assert_int(DragClassifier.classify(st, en.get_legal_actions(), iid, 0)).is_equal(DragClassifier.State.INVALID)

func test_too_few_tickets_is_unaffordable() -> void:
	var pair := _state_in_main(3)
	var st: GameState = pair[0]
	var en: GameEngine = pair[1]
	# Find a non-leader hand card that costs something, then zero out tickets.
	var iid := -1
	for c in st.players[0].hand:
		if c.definition.type != Enums.CardType.LEADER and c.definition.ticket_cost > 0:
			iid = c.instance_id
			break
	if iid == -1:
		return
	st.players[0].tickets_tapped = st.players[0].tickets_total
	assert_int(DragClassifier.classify(st, en.get_legal_actions(), iid, 0)).is_equal(DragClassifier.State.UNAFFORDABLE)

func test_advertises_zone_for_hand_card_on_turn() -> void:
	var pair := _state_in_main(3)
	var st: GameState = pair[0]
	var iid: int = st.players[0].hand[0].instance_id
	assert_bool(DragClassifier.advertises_zone(st, iid, 0)).is_true()
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_drag_classifier.gd`
Expected: FAIL (`DragClassifier` not found).

- [ ] **Step 3: Implement the classifier**

```gdscript
# src/ui/match/drag_classifier.gd
class_name DragClassifier
extends RefCounted

enum State { INVALID, UNAFFORDABLE, ACCEPTABLE }

# Classifies a dragged hand card. ACCEPTABLE iff the engine offers a legal
# PLAY_CARD for it; UNAFFORDABLE iff it is a playable-type hand card on your turn
# whose ticket cost exceeds available tickets; INVALID otherwise.
static func classify(state: GameState, legal: Array, instance_id: int, player: int) -> int:
	for a in legal:
		if a.type == Enums.ActionType.PLAY_CARD and a.params.get("instance_id") == instance_id:
			return State.ACCEPTABLE
	if state.active_player != player or state.pending_choice != null:
		return State.INVALID
	var inst := _find_in_hand(state.players[player].hand, instance_id)
	if inst == null:
		return State.INVALID
	if inst.definition.type == Enums.CardType.LEADER:
		return State.INVALID
	if inst.definition.ticket_cost > state.players[player].available_tickets():
		return State.UNAFFORDABLE
	return State.INVALID

# Whether to advertise drop zones for this card (placement legality, ignoring
# tickets): a non-leader hand card on your turn with no pending choice.
static func advertises_zone(state: GameState, instance_id: int, player: int) -> bool:
	if state.active_player != player or state.pending_choice != null:
		return false
	var inst := _find_in_hand(state.players[player].hand, instance_id)
	return inst != null and inst.definition.type != Enums.CardType.LEADER

static func _find_in_hand(hand: Array, instance_id: int) -> CardInstance:
	for c in hand:
		if c.instance_id == instance_id:
			return c
	return null
```

- [ ] **Step 4: Run to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_drag_classifier.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/drag_classifier.gd tests/test_drag_classifier.gd
git commit -m "feat(ui): add pure DragClassifier for drag-state feedback"
```

---

## Task 7: `DropZoneOverlay` dashed drop zones

**Files:**
- Create: `src/ui/table/drop_zone_overlay.gd`
- Test: `tests/test_drop_zone_overlay.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_drop_zone_overlay.gd
extends GdUnitTestSuite

func _overlay() -> DropZoneOverlay:
	var o := DropZoneOverlay.new()
	o.size = Vector2(1920, 1080)
	add_child(o)
	auto_free(o)
	return o

func test_hidden_by_default() -> void:
	assert_bool(_overlay().is_hovering_zone()).is_false()

func test_hit_test_inside_and_outside() -> void:
	var o := _overlay()
	o.show_zones([Rect2(0, 0, 100, 100)])
	o.set_hover(Vector2(50, 50), DropZoneOverlay.ZoneState.ACCEPTABLE)
	assert_bool(o.is_hovering_zone()).is_true()
	o.set_hover(Vector2(500, 500), DropZoneOverlay.ZoneState.ACCEPTABLE)
	assert_bool(o.is_hovering_zone()).is_false()

func test_clear_resets() -> void:
	var o := _overlay()
	o.show_zones([Rect2(0, 0, 100, 100)])
	o.set_hover(Vector2(50, 50), DropZoneOverlay.ZoneState.ACCEPTABLE)
	o.clear()
	assert_bool(o.is_hovering_zone()).is_false()
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_drop_zone_overlay.gd`
Expected: FAIL (`DropZoneOverlay` not found).

- [ ] **Step 3: Implement the overlay**

```gdscript
# src/ui/table/drop_zone_overlay.gd
class_name DropZoneOverlay
extends Control

enum ZoneState { NEUTRAL, ACCEPTABLE, UNAFFORDABLE }

const DASH := 18.0
const GAP := 12.0

var _zones: Array[Rect2] = []
var _hovered: int = -1
var _state: int = ZoneState.NEUTRAL
var _bump: float = 0.0          # juicy emphasis on the hovered zone
var _bump_tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func show_zones(rects: Array) -> void:
	_zones.clear()
	for r in rects:
		_zones.append(r)
	_hovered = -1
	_state = ZoneState.NEUTRAL
	visible = not _zones.is_empty()
	queue_redraw()

func set_hover(point: Vector2, state: int) -> void:
	var idx := _zone_at(point)
	if idx != _hovered and idx != -1:
		_kick_bump()
	_hovered = idx
	_state = state
	queue_redraw()

func is_hovering_zone() -> bool:
	return _hovered != -1

func clear() -> void:
	_zones.clear()
	_hovered = -1
	visible = false
	queue_redraw()

func _zone_at(point: Vector2) -> int:
	for i in _zones.size():
		if _zones[i].has_point(point):
			return i
	return -1

func _kick_bump() -> void:
	if _bump_tween and _bump_tween.is_running():
		_bump_tween.kill()
	_bump = 1.0
	_bump_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	_bump_tween.tween_method(func(v: float) -> void:
		_bump = v
		queue_redraw(), 1.0, 0.0, 0.45)

func _draw() -> void:
	for i in _zones.size():
		var hovered := i == _hovered
		var rect := _zones[i]
		var fill := UiPalette.ZONE_NEUTRAL
		if hovered:
			rect = rect.grow(_bump * 8.0)
			match _state:
				ZoneState.ACCEPTABLE: fill = UiPalette.ZONE_ACCEPTABLE
				ZoneState.UNAFFORDABLE: fill = UiPalette.ZONE_UNAFFORDABLE
				_: fill = UiPalette.ZONE_NEUTRAL
		draw_rect(rect, fill, true)
		_draw_dashed_border(rect, UiPalette.ZONE_OUTLINE, 4.0 if hovered else 3.0)

func _draw_dashed_border(rect: Rect2, color: Color, width: float) -> void:
	var corners := [
		rect.position,
		rect.position + Vector2(rect.size.x, 0),
		rect.position + rect.size,
		rect.position + Vector2(0, rect.size.y),
	]
	for c in 4:
		_dashed_line(corners[c], corners[(c + 1) % 4], color, width)

func _dashed_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var length := from.distance_to(to)
	var dir := (to - from).normalized()
	var travelled := 0.0
	while travelled < length:
		var seg := minf(DASH, length - travelled)
		draw_line(from + dir * travelled, from + dir * (travelled + seg), color, width)
		travelled += DASH + GAP
```

- [ ] **Step 4: Run to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_drop_zone_overlay.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/ui/table/drop_zone_overlay.gd tests/test_drop_zone_overlay.gd
git commit -m "feat(ui): add dashed DropZoneOverlay with juicy hover bump"
```

---

## Task 8: Juicy ticket pips + red cost preview

**Files:**
- Modify: `src/ui/table/ticket_tray.gd`
- Test: `tests/test_ticket_tray.gd` (extend)

- [ ] **Step 1: Add the failing test cases**

Replace the contents of `tests/test_ticket_tray.gd` with:

```gdscript
extends GdUnitTestSuite

func _spawn() -> Node:
	var t: Node = load("res://src/ui/table/ticket_tray.tscn").instantiate()
	add_child(t)
	auto_free(t)
	return t

func test_draws_total_pips_with_tapped_filled() -> void:
	var tray := _spawn()
	tray.set_tickets(3, 5)
	assert_int(tray.get_child_count()).is_equal(5)
	assert_int(tray.filled_count()).is_equal(2)

func test_preview_cost_marks_spent_pips_red() -> void:
	var tray := _spawn()
	tray.set_tickets(0, 5)   # 5 available (indices 0..4 filled)
	tray.preview_cost(2)     # the last 2 available pips (3, 4) turn red
	assert_object((tray.get_child(4) as ColorRect).color).is_equal(UiPalette.PIP_COST)
	assert_object((tray.get_child(3) as ColorRect).color).is_equal(UiPalette.PIP_COST)
	assert_object((tray.get_child(2) as ColorRect).color).is_equal(UiPalette.PIP_FILLED)

func test_clear_preview_restores_filled() -> void:
	var tray := _spawn()
	tray.set_tickets(0, 5)
	tray.preview_cost(2)
	tray.clear_preview()
	assert_object((tray.get_child(4) as ColorRect).color).is_equal(UiPalette.PIP_FILLED)
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_ticket_tray.gd`
Expected: FAIL (`preview_cost`/`clear_preview` undefined).

- [ ] **Step 3: Rewrite `ticket_tray.gd`**

```gdscript
# src/ui/table/ticket_tray.gd
class_name TicketTray
extends HBoxContainer

var _tapped: int = 0
var _total: int = 0
var _pips: Array[ColorRect] = []

func set_tickets(tapped: int, total: int) -> void:
	var grew := total > _total
	_tapped = tapped
	_total = total
	for c in get_children():
		c.queue_free()
	_pips.clear()
	var available := total - tapped
	for i in range(total):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(28, 28)
		pip.pivot_offset = Vector2(14, 14)
		pip.color = UiPalette.PIP_FILLED if i < available else UiPalette.PIP_EMPTY
		add_child(pip)
		_pips.append(pip)
		_pop(pip, grew)

func filled_count() -> int:
	return _total - _tapped

# Light the last `n` available pips red to preview a play's cost.
func preview_cost(n: int) -> void:
	clear_preview()
	var available := _total - _tapped
	var k := mini(n, available)
	for i in range(available - k, available):
		if i >= 0 and i < _pips.size():
			_pips[i].color = UiPalette.PIP_COST
			_pop(_pips[i], true)

func clear_preview() -> void:
	var available := _total - _tapped
	for i in _pips.size():
		_pips[i].color = UiPalette.PIP_FILLED if i < available else UiPalette.PIP_EMPTY

func _pop(pip: ColorRect, grew: bool) -> void:
	if not is_inside_tree():
		return
	pip.scale = Vector2.ONE * (0.2 if grew else 0.8)
	var t := pip.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(pip, "scale", Vector2.ONE, 0.25)
```

Note: `filled_count()` is now computed from state (not pip color) so the red preview never skews it.

- [ ] **Step 4: Run to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_ticket_tray.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/ui/table/ticket_tray.gd tests/test_ticket_tray.gd
git commit -m "feat(ui): juicy ticket pips with red cost preview"
```

---

## Task 9: `hand_view` emits `card_drag_started`

**Files:**
- Modify: `src/ui/table/hand_view.gd`
- Test: covered by Task 10 integration; no new unit test (signal plumbing).

- [ ] **Step 1: Add the signal and connection**

In `src/ui/table/hand_view.gd`, add a signal after the existing `card_drag_released` (line 5):

```gdscript
signal card_drag_started(instance_id: int)
```

In `render()`, where the card is first created and `drag_released` is connected (after line 21), also connect `drag_started`:

```gdscript
			cv.drag_started.connect(func(_cv: CardView): card_drag_started.emit(iid))
```

(The `iid` local already exists in that block.)

- [ ] **Step 2: Verify table/hand suites still pass**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_table_view.gd`
Then: `... -a res://tests/test_card_rows.gd`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add src/ui/table/hand_view.gd
git commit -m "feat(ui): hand_view emits card_drag_started"
```

---

## Task 10: Wire drag feedback into `match`

**Files:**
- Modify: `src/ui/match/match.tscn` (add `DropZoneLayer`)
- Modify: `src/ui/match/match.gd` (drive zones + pip preview during drag)
- Test: `tests/test_match_flow.gd`, `tests/test_integration_ui_game.gd` must stay green.

- [ ] **Step 1: Add `DropZoneLayer` to `match.tscn`**

Add this ext_resource near the top of `src/ui/match/match.tscn` (with the other `ext_resource` lines):

```
[ext_resource type="Script" path="res://src/ui/table/drop_zone_overlay.gd" id="13_dropzone"]
```

Add this node after the `DragLayer` node (so it draws above the table but below `ArrowLayer`):

```
[node name="DropZoneLayer" type="Control" parent="." unique_id=884412001]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
script = ExtResource("13_dropzone")
```

- [ ] **Step 2: Wire it in `match.gd`**

Add the onready ref with the others (after line 27):

```gdscript
@onready var _drop_zones: DropZoneOverlay = $DropZoneLayer
```

Add a drag-tracking field near the top (after line 9 `var _deck1_path: String`):

```gdscript
var _dragging_id: int = -1
```

In `_ready()`, connect the new hand signal (after line 31):

```gdscript
	hand_view.card_drag_started.connect(_on_hand_card_drag_started)
```

Add these methods (place near `_on_hand_card_drag_released`, around line 208):

```gdscript
func _on_hand_card_drag_started(instance_id: int) -> void:
	_dragging_id = instance_id
	if DragClassifier.advertises_zone(state, instance_id, HUMAN):
		_drop_zones.show_zones(_zone_rects_for(instance_id))

func _zone_rects_for(instance_id: int) -> Array:
	var inst := _find_hand_inst(instance_id)
	if inst != null and inst.definition.type == Enums.CardType.MINION:
		return [Rect2(360, 520, 1200, 260)]   # player board row band
	return [Rect2(360, 360, 1200, 420)]       # general play zone

func _find_hand_inst(instance_id: int) -> CardInstance:
	for c in state.players[HUMAN].hand:
		if c.instance_id == instance_id:
			return c
	return null
```

Replace `_on_hand_card_drag_released` (lines 208-209) with:

```gdscript
func _on_hand_card_drag_released(instance_id: int, _at: Vector2) -> void:
	_dragging_id = -1
	_drop_zones.clear()
	_tickets.clear_preview()
	handle_drop(instance_id, "play_zone")
```

Extend `_process` (lines 211-213) to drive the live feedback:

```gdscript
func _process(_delta: float) -> void:
	if _selected_attacker != -1:
		_arrow.point_at(get_global_mouse_position())
	if _dragging_id != -1:
		_update_drag_feedback()

func _update_drag_feedback() -> void:
	var cls := DragClassifier.classify(state, engine.get_legal_actions(), _dragging_id, HUMAN)
	var zstate := DropZoneOverlay.ZoneState.NEUTRAL
	if cls == DragClassifier.State.ACCEPTABLE:
		zstate = DropZoneOverlay.ZoneState.ACCEPTABLE
	elif cls == DragClassifier.State.UNAFFORDABLE:
		zstate = DropZoneOverlay.ZoneState.UNAFFORDABLE
	_drop_zones.set_hover(get_global_mouse_position(), zstate)
	if cls == DragClassifier.State.ACCEPTABLE and _drop_zones.is_hovering_zone():
		var inst := _find_hand_inst(_dragging_id)
		if inst != null:
			_tickets.preview_cost(inst.definition.ticket_cost)
	else:
		_tickets.clear_preview()
```

- [ ] **Step 3: Run the match/integration suites**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_match_flow.gd`
Then: `... -a res://tests/test_integration_ui_game.gd`
Expected: PASS (drag feedback is inert when no drag is active; `_dragging_id` guards it).

- [ ] **Step 4: Manual verification**

Launch the game, start a match, and drag a hand card. Confirm: dashed shaded zone appears over the board when you pick up a playable card; the zone turns green when affordable / amber when not; the matching ticket pips glow red while green; everything clears on release.
Run: `godot --path . res://src/ui/menu/main_menu.tscn`

- [ ] **Step 5: Commit**

```bash
git add src/ui/match/match.tscn src/ui/match/match.gd
git commit -m "feat(ui): board drop-zone + ticket cost-preview drag feedback"
```

---

## Task 11: Discard & mulligan selection highlight

**Files:**
- Modify: `src/ui/overlays/discard_panel.gd`
- Modify: `src/ui/overlays/mulligan_panel.gd`
- Test: `tests/test_overlays.gd` (extend), `tests/test_mulligan_panel.gd` stays green.

- [ ] **Step 1: Add a failing test**

Append to `tests/test_overlays.gd`:

```gdscript
func test_discard_selection_highlights_card() -> void:
	var p = _inst("res://src/ui/overlays/discard_panel.tscn")
	p.show_hand(_hand(7), 2)
	p.toggle_index(0)
	var row := p.find_child("CardRow")
	var first_card: CardView = row.get_child(0)
	assert_bool((first_card.find_child("Highlight") as Control).visible).is_true()
	p.toggle_index(0)
	assert_bool((first_card.find_child("Highlight") as Control).visible).is_false()
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_overlays.gd`
Expected: FAIL (selected card highlight not shown).

- [ ] **Step 3: Drive the highlight in `discard_panel.gd`**

In `show_hand` (the loop that builds cards), mark every selectable card and keep the card refs. After `cv.setup(hand[i])` and before the `gui_input` connection, add:

```gdscript
		cv.set_highlight(CardHighlight.State.SELECTABLE)
```

Replace `_update()` (the last function) with a version that repaints selection state:

```gdscript
func _update() -> void:
	_confirm.disabled = not can_confirm()
	for i in _row.get_child_count():
		var cv: CardView = _row.get_child(i)
		cv.set_highlight(CardHighlight.State.SELECTED if _selected.has(i) else CardHighlight.State.SELECTABLE)
```

- [ ] **Step 4: Mirror it in `mulligan_panel.gd`**

In `show_hand`, for discardable cards set `SELECTABLE`; non-discardable (the leader) stay `NONE`. After `cv.setup(inst)`:

```gdscript
		if inst.definition.type != Enums.CardType.LEADER:
			cv.set_highlight(CardHighlight.State.SELECTABLE)
```

Replace `_update()`:

```gdscript
func _update() -> void:
	_confirm.disabled = not can_confirm()
	for i in _row.get_child_count():
		var cv: CardView = _row.get_child(i)
		if not _discardable.has(i):
			continue
		cv.set_highlight(CardHighlight.State.SELECTED if _selected.has(i) else CardHighlight.State.SELECTABLE)
```

- [ ] **Step 5: Run overlays + mulligan suites**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_overlays.gd`
Then: `... -a res://tests/test_mulligan_panel.gd`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/ui/overlays/discard_panel.gd src/ui/overlays/mulligan_panel.gd tests/test_overlays.gd
git commit -m "feat(ui): discard/mulligan selection highlight via CardHighlight"
```

---

## Task 12: Theme + button juice rollout (match, menu, overlays)

**Files:**
- Modify: `src/ui/match/match.gd`, `src/ui/menu/main_menu.gd`, `src/ui/overlays/{discard_panel,mulligan_panel,leader_cost_prompt,game_over_panel,turn_banner}.gd`
- Test: existing `tests/test_main_menu.gd`, `tests/test_overlays.gd`, `tests/test_turn_banner.gd`, `tests/test_match_flow.gd` must stay green.

- [ ] **Step 1: Add a const + helper usage in `match.gd`**

At the top of `src/ui/match/match.gd` (after `const HUMAN := 0`):

```gdscript
const THEME := preload("res://src/ui/theme/game_theme.tres")
```

At the **end** of `_ready()`:

```gdscript
	theme = THEME
	JuicyButton.apply(_end_turn)
```

- [ ] **Step 2: Theme + juice the main menu**

In `src/ui/menu/main_menu.gd` `_ready()`, after the existing setup:

```gdscript
	theme = preload("res://src/ui/theme/game_theme.tres")
	JuicyButton.apply(_play)
	JuicyButton.apply($QuitButton)
	for c in COLORS:
		JuicyButton.apply($DeckButtons.get_node(c.capitalize()))
	_refresh_deck_selection()
```

Replace `select_deck` and add the refresh helper:

```gdscript
func select_deck(color: String) -> void:
	chosen_deck = color
	_refresh_deck_selection()

func _refresh_deck_selection() -> void:
	for c in COLORS:
		var btn: Button = $DeckButtons.get_node(c.capitalize())
		btn.modulate = UiPalette.ACCENT if c == chosen_deck else Color.WHITE
```

- [ ] **Step 3: Theme + juice the overlays**

Each overlay is a `CanvasLayer` with a `Panel` child, so set the theme on the `Panel` (theme does not cross `CanvasLayer`). Add to each overlay's `_ready()`:

`discard_panel.gd`:
```gdscript
	$Panel.theme = preload("res://src/ui/theme/game_theme.tres")
	JuicyButton.apply(_confirm)
```

`mulligan_panel.gd`:
```gdscript
	$Panel.theme = preload("res://src/ui/theme/game_theme.tres")
	JuicyButton.apply(_confirm)
```

`leader_cost_prompt.gd`:
```gdscript
	$Panel.theme = preload("res://src/ui/theme/game_theme.tres")
	JuicyButton.apply(_tickets_btn)
	JuicyButton.apply(_discard_btn)
```

`game_over_panel.gd`:
```gdscript
	$Panel.theme = preload("res://src/ui/theme/game_theme.tres")
	JuicyButton.apply($Panel/PlayAgain)
	JuicyButton.apply($Panel/Quit)
```

`turn_banner.gd`: add at the end of `_ready()` (create one if absent), setting the theme on the banner's root `Control`/`Panel` node if it has one:
```gdscript
	if has_node("Panel"):
		$Panel.theme = preload("res://src/ui/theme/game_theme.tres")
```

- [ ] **Step 4: Run the affected suites**

Run each:
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_main_menu.gd
... -a res://tests/test_overlays.gd
... -a res://tests/test_turn_banner.gd
... -a res://tests/test_match_flow.gd
```
Expected: PASS all.

- [ ] **Step 5: Manual verification**

Launch the menu. Confirm: buttons have the cartoony rounded look, scale/tilt on hover, punch on click; the selected deck button is tinted; overlays use the themed panel + juicy buttons.
Run: `godot --path . res://src/ui/menu/main_menu.tscn`

- [ ] **Step 6: Commit**

```bash
git add src/ui/match/match.gd src/ui/menu/main_menu.gd src/ui/overlays/*.gd
git commit -m "feat(ui): roll theme + JuicyButton across match, menu, overlays"
```

---

## Task 13: Framed station layout

**Files:**
- Modify: `src/ui/match/match.tscn` (add felt + station `Panel` frames, reposition piles/tickets/end-turn symmetrically)
- Test: `tests/test_board_layout.gd` must stay green (board/hand math unchanged).

The board-row and hand fan math in `board_layout.gd` is already symmetric and centered and is left untouched. This task adds purely-visual framing and tidies the peripheral furniture into mirrored stations.

- [ ] **Step 1: Add a felt play-field frame**

In `src/ui/match/match.tscn`, add a `Panel` as the **first** child of `Table` (so it renders behind the boards) covering the central play field. Add the theme ext_resource if not present:

```
[ext_resource type="Theme" path="res://src/ui/theme/game_theme.tres" id="14_theme"]
```

```
[node name="FeltFrame" type="Panel" parent="Table" unique_id=512000001]
layout_mode = 0
offset_left = 300.0
offset_top = 220.0
offset_right = 1620.0
offset_bottom = 800.0
mouse_filter = 2
theme = ExtResource("14_theme")
```

- [ ] **Step 2: Add four mirrored station frames**

Add these `Panel` nodes to `Table` (after `FeltFrame`, before the boards so cards draw on top). They group the existing piles into tidy stations: leader bottom-left / deck+discard bottom-right for the player, mirrored at the top for the opponent.

```
[node name="PlayerLeaderStation" type="Panel" parent="Table" unique_id=512000002]
layout_mode = 0
offset_left = 90.0
offset_top = 730.0
offset_right = 290.0
offset_bottom = 1040.0
mouse_filter = 2
theme = ExtResource("14_theme")

[node name="PlayerPileStation" type="Panel" parent="Table" unique_id=512000003]
layout_mode = 0
offset_left = 1630.0
offset_top = 510.0
offset_right = 1840.0
offset_bottom = 980.0
mouse_filter = 2
theme = ExtResource("14_theme")

[node name="OppLeaderStation" type="Panel" parent="Table" unique_id=512000004]
layout_mode = 0
offset_left = 90.0
offset_top = 40.0
offset_right = 290.0
offset_bottom = 350.0
mouse_filter = 2
theme = ExtResource("14_theme")

[node name="OppPileStation" type="Panel" parent="Table" unique_id=512000005]
layout_mode = 0
offset_left = 1630.0
offset_top = 40.0
offset_right = 1840.0
offset_bottom = 510.0
mouse_filter = 2
theme = ExtResource("14_theme")
```

These wrap the existing `PlayerLeader`, `PlayerDeck`/`PlayerDiscard`, `OppLeader`, `OppDeck`/`OppDiscard` pile positions already defined in the scene (no pile offsets need to change — the stations are sized to frame them). `PlayerTickets` already sits at `offset_top = 980` directly under the leader station. Keep `mouse_filter = 2` on every frame so they never eat card input.

- [ ] **Step 3: Reposition the End-Turn button into the player pile station**

The `EndTurnButton` node already sits at `offset_left = 1700, offset_top = 900` — inside the `PlayerPileStation` band. Leave its offsets as-is; it now reads as part of the station. (No change required, but verify it visually overlaps the station, not the hand.)

- [ ] **Step 4: Run layout + match suites**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_board_layout.gd`
Then: `... -a res://tests/test_match_flow.gd`
Expected: PASS (no math changed).

- [ ] **Step 5: Manual verification**

Launch a match. Confirm the central felt frame sits behind both board rows, the four corner stations frame the leader/deck/discard piles symmetrically, the ticket pips sit under the player leader, and the End-Turn button reads as part of the bottom-right station. Cards still drag freely (frames don't block input).
Run: `godot --path . res://src/ui/menu/main_menu.tscn`

- [ ] **Step 6: Commit**

```bash
git add src/ui/match/match.tscn
git commit -m "feat(ui): framed symmetric station layout for the match table"
```

---

## Task 14: Full-suite verification

**Files:** none (verification only).

- [ ] **Step 1: Run the entire test directory**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
Expected: exit code 0, all suites pass. (Ignore the known `rp_font is null` and headless-input notices.)

- [ ] **Step 2: Full manual playthrough**

Launch the game and play a full match against the AI. Verify each must-have:
- Buttons tween rotation + scale on hover and click (menu, end-turn, overlays).
- Discard/mulligan selection highlights selected cards.
- Dragging a card shows dashed board drop zones; the hovered zone is green (acceptable) / amber (unaffordable); invalid cards show no zone.
- Ticket pips that would be spent glow red while a valid drop is hovered; pips pop on spend/gain.
- The table layout reads as symmetric framed stations.

Run: `godot --path . res://src/ui/menu/main_menu.tscn`

- [ ] **Step 3: Final commit (if any manual-tuning tweaks were made)**

```bash
git add -A
git commit -m "chore(ui): final juice tuning after playthrough"
```

---

## Self-Review Notes (for the implementer)

- **Spec coverage:** button motion (Task 3, 12), discard selection highlight (Task 11), drag invalid/unaffordable/acceptable feedback (Tasks 6, 7, 10 — on the board per the revised spec), red cost preview on the pips (Task 8, 10), cartoony dashed juicy zones (Task 7), whole-game theme + layout (Tasks 2, 12, 13). The ticket *number* counter was explicitly dropped during brainstorming and is intentionally absent.
- **Type consistency:** `CardHighlight.State`, `DragClassifier.State`, and `DropZoneOverlay.ZoneState` are the three distinct enums; `CardView.set_highlight(int)` takes a `CardHighlight.State`. `JuicyButton.apply(Button)` is static. `TicketTray.preview_cost(int)` / `clear_preview()` pair with `filled_count()` (now computed).
- **Font:** the theme ships font-less (uses Godot's default) to stay unblocked; drop a rounded TTF into `src/ui/theme/fonts/` and add `default_font = ...` to `game_theme.tres` later if desired.
