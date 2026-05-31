# Minimize Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a minimize button to all choice overlays that shrinks the overlay content into a small bottom tab, revealing the board (non-interactive), with a bouncy juiced expand animation to restore it.

**Architecture:** A single `MinimizeBar` CanvasLayer lives in the Match scene and coordinates with overlays. Each overlay adds a minimize button and emits `minimize_requested`. Match.gd manages the animation: on minimize, it saves each overlay's animatable node transforms, tweens them toward the tab position while scaling to zero (staggered), and fades the dim; on expand, it reverses from scale zero at the tab to the saved transforms. The MinimizeBar tab handles expand clicks and blocks board interaction via a near-transparent input-eating ColorRect.

**Tech Stack:** Godot 4.6 (GL Compatibility), GDScript, GdUnit4 for tests.

---

## Background the implementer needs

- **Tests use GdUnit4.** Suites `extends GdUnitTestSuite`, run headless:
  ```bash
  godot --headless --path . --import && \
  godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_overlays.gd
  ```
  Exit code `0` = pass. Harmless headless noise: `ERROR: Required object "rp_font" is null` and "InputEvents not transported in headless".
- **All overlays are CanvasLayer nodes** with `visible = false` initially. They set `visible = true` when shown and `visible = false` when dismissed. Most have a full-screen `Dim` child (ColorRect with `Color(0,0,0,0.55)`) for visual dimming and input blocking.
- **JuicyButton** (`src/ui/theme/juicy_button.gd`): `class_name JuicyButton extends RefCounted`. Static method `JuicyButton.apply(btn: Button)` wires hover/press animations. Apply it to any new buttons.
- **Animation style reference:** `src/ui/match/card_juice.gd` uses `TRANS_BACK` for overshoot, `TRANS_ELASTIC` for springy settle, `TRANS_QUAD`/`TRANS_CUBIC` for smooth motion. `CardFlight.STAGGER` (0.06s) is the per-card stagger delay. Consistent with the game's bouncy feel.
- **MinimizeBar node paths:** When adding MinimizeBar to `match.tscn`, follow the existing pattern of instance nodes (like `$CardSelectPanel`, `$MulliganPanel`, etc.). The internal MinimizeBar paths need `is_node_ready()` guards in `_ready` since signals are wired by Match.
- **Overlay dim references:**
  - CardSelectPanel: `$Dim` (ColorRect, `Color(0,0,0,0.55)`)
  - OptionPrompt: `$Dim`
  - TrapRevealOverlay: `$Dim`
  - LeaderCostPrompt: `$Panel` (the Panel itself is full-screen and acts as background; it's a `Panel` type, not a ColorRect — needs separate `modulate.a` tween approach)
  - MulliganPanel: `$Panel` (same — Panel is full-screen background)
  - HandChoice: Has NO dim — no background node to fade. HandChoice sits on top of the hand directly.

## File structure

New files:

| File | Responsibility |
|---|---|
| `src/ui/overlays/minimize_bar.gd` | `MinimizeBar` script — manages tab UI and `expand_pressed` signal |
| `src/ui/overlays/minimize_bar.tscn` | MinimizeBar scene — CanvasLayer with InputBlocker + Tab |
| `tests/test_minimize_bar.gd` | Tests for MinimizeBar show/hide and signal emission |

Modified files:

| File | Change |
|---|---|
| `src/ui/match/match.tscn` | Add MinimizeBar child node instance |
| `src/ui/match/match.gd` | Add `_minimize_bar`, `_minimized_overlay`, `_active_overlay`, signal wiring, minimize/expand animation methods |
| `src/ui/overlays/card_select_panel.tscn` | Add MinimizeButton to VBox |
| `src/ui/overlays/card_select_panel.gd` | Add `minimize_requested` signal, `get_animatable_nodes()`, minimize button wiring |
| `src/ui/match/hand_choice.tscn` | Add MinimizeButton |
| `src/ui/match/hand_choice.gd` | Add `minimize_requested` signal, `get_animatable_nodes()`, minimize button wiring |
| `src/ui/overlays/option_prompt.tscn` | Add MinimizeButton |
| `src/ui/overlays/option_prompt.gd` | Add `minimize_requested` signal, `get_animatable_nodes()`, minimize button wiring |
| `src/ui/overlays/trap_reveal_overlay.tscn` | Add MinimizeButton |
| `src/ui/overlays/trap_reveal_overlay.gd` | Add `minimize_requested` signal, `get_animatable_nodes()`, minimize button wiring |
| `src/ui/overlays/leader_cost_prompt.tscn` | Add MinimizeButton |
| `src/ui/overlays/leader_cost_prompt.gd` | Add `minimize_requested` signal, `get_animatable_nodes()`, minimize button wiring |
| `src/ui/overlays/mulligan_panel.tscn` | Add MinimizeButton |
| `src/ui/overlays/mulligan_panel.gd` | Add `minimize_requested` signal, `get_animatable_nodes()`, minimize button wiring |
| `tests/test_overlays.gd` | Add tests for `minimize_requested` signal and `get_animatable_nodes()` on each overlay |

---

### Task 1: Create MinimizeBar scene and script

**Files:**
- Create: `src/ui/overlays/minimize_bar.gd`
- Create: `src/ui/overlays/minimize_bar.tscn`

- [ ] **Step 1: Create minimize_bar.gd**

```gdscript
extends CanvasLayer

signal expand_pressed

@onready var _tab: HBoxContainer = $Tab
@onready var _title: Label = $Tab/Title
@onready var _expand_btn: Button = $Tab/ExpandButton

func _ready() -> void:
	_tab.scale = Vector2.ZERO
	_tab.visible = false
	_expand_btn.pressed.connect(func(): expand_pressed.emit())
	JuicyButton.apply(_expand_btn)

func show_bar(title_text: String) -> void:
	_title.text = title_text
	_tab.visible = true
	var tw := _tab.create_tween()
	_tab.scale = Vector2.ZERO
	tw.tween_property(_tab, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func hide_bar() -> void:
	var tw := _tab.create_tween()
	tw.tween_property(_tab, "scale", Vector2.ZERO, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): _tab.visible = false)
```

- [ ] **Step 2: Create minimize_bar.tscn**

Save as `src/ui/overlays/minimize_bar.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/ui/overlays/minimize_bar.gd" id="1_script"]

[node name="MinimizeBar" type="CanvasLayer"]
visible = false
script = ExtResource("1_script")

[node name="InputBlocker" type="ColorRect" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(0, 0, 0, 0.15)

[node name="Tab" type="HBoxContainer" parent="."]
anchors_preset = 7
anchor_left = 0.5
anchor_top = 1.0
anchor_right = 0.5
anchor_bottom = 1.0
offset_left = -160.0
offset_top = -60.0
offset_right = 160.0
offset_bottom = -10.0
grow_horizontal = 2
grow_vertical = 0
alignment = 1

[node name="Title" type="Label" parent="Tab"]
layout_mode = 2
theme_override_font_sizes/font_size = 20
text = "Select cards"

[node name="ExpandButton" type="Button" parent="Tab"]
layout_mode = 2
text = "^"
```

- [ ] **Step 3: Run the project to verify MinimizeBar scene loads without errors**

Run: `godot --headless --path . --import && godot --headless --path . --script res://src/ui/overlays/minimize_bar.gd --quit`
This will fail because we can't test a scene this way directly. Instead, verify the `.tscn` parses by checking Godot can import it:

Run: `godot --headless --path . --import`
Expected: no import errors related to minimize_bar.

- [ ] **Step 4: Write test for MinimizeBar show/hide and signal**

Create `tests/test_minimize_bar.gd`:

```gdscript
extends GdUnitTestSuite

func _inst() -> Node:
	var p = load("res://src/ui/overlays/minimize_bar.tscn").instantiate()
	add_child(p)
	auto_free(p)
	return p

func test_show_bar_sets_title() -> void:
	var bar = _inst()
	bar.show_bar("Choose 2 cards")
	assert_str(bar.find_child("Title").text).is_equal("Choose 2 cards")

func test_expand_pressed_signal() -> void:
	var bar = _inst()
	var emitted := false
	bar.expand_pressed.connect(func(): emitted = true)
	bar.find_child("ExpandButton").emit_signal("pressed")
	assert_bool(emitted).is_true()
```

- [ ] **Step 5: Run the test**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_minimize_bar.gd`
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add src/ui/overlays/minimize_bar.gd src/ui/overlays/minimize_bar.tscn tests/test_minimize_bar.gd
git commit -m "feat: add MinimizeBar scene and script with expand signal"
```

---

### Task 2: Add minimize_requested signal and get_animatable_nodes to all overlays

Each overlay gets a `minimize_requested` signal, a minimize button in its scene, and a `get_animatable_nodes()` method. This task modifies all 6 overlays.

**Files:**
- Modify: `src/ui/overlays/card_select_panel.gd` and `.tscn`
- Modify: `src/ui/match/hand_choice.gd` and `.tscn`
- Modify: `src/ui/overlays/option_prompt.gd` and `.tscn`
- Modify: `src/ui/overlays/trap_reveal_overlay.gd` and `.tscn`
- Modify: `src/ui/overlays/leader_cost_prompt.gd` and `.tscn`
- Modify: `src/ui/overlays/mulligan_panel.gd` and `.tscn`
- Modify: `tests/test_overlays.gd`

- [ ] **Step 1: Add minimize_requested and get_animatable_nodes to card_select_panel.gd**

Add after `signal confirmed(indices: Array)`:

```gdscript
signal minimize_requested
```

Add at the end of the file:

```gdscript
func get_animatable_nodes() -> Array[Node]:
	return [_label, _row, $Center/Panel/Margin/VBox/Buttons]
```

In `_ready()`, after `JuicyButton.apply(_confirm)`, add:

```gdscript
	var _min_btn: Button = $Center/Panel/Margin/VBox/MinimizeButton
	JuicyButton.apply(_min_btn)
	_min_btn.pressed.connect(func(): minimize_requested.emit())
```

- [ ] **Step 2: Add MinimizeButton to card_select_panel.tscn**

Add before the Buttons node in VBox, or at the end of VBox. The minimize button should sit in the layout alongside the title. The cleanest placement is right after the Label, before CardRow.

Actually — to keep the layout clean, add the MinimizeButton inside the Buttons row alongside ConfirmButton. Insert in the `.tscn`:

After `[node name="ConfirmButton" ...]` add:

```
[node name="MinimizeButton" type="Button" parent="Center/Panel/Margin/VBox/Buttons"]
layout_mode = 2
text = "−"
```

- [ ] **Step 3: Add minimize_requested and get_animatable_nodes to hand_choice.gd**

Add after `signal confirmed(indices: Array)`:

```gdscript
signal minimize_requested
```

Add at end of file:

```gdscript
func get_animatable_nodes() -> Array[Node]:
	return [_title, _confirm]
```

In `_ready()`, after `JuicyButton.apply(_confirm)`, add:

```gdscript
	var _min_btn: Button = $MinimizeButton
	JuicyButton.apply(_min_btn)
	_min_btn.pressed.connect(func(): minimize_requested.emit())
```

- [ ] **Step 4: Add MinimizeButton to hand_choice.tscn**

After the Confirm button node, add:

```
[node name="MinimizeButton" type="Button" parent="."]
offset_left = 1080.0
offset_top = 680.0
offset_right = 1160.0
offset_bottom = 730.0
text = "−"
```

- [ ] **Step 5: Add minimize_requested and get_animatable_nodes to option_prompt.gd**

Add after `signal picked(option: int)`:

```gdscript
signal minimize_requested
```

Add at end of file:

```gdscript
func get_animatable_nodes() -> Array[Node]:
	var nodes: Array[Node] = [_label, _box]
	if _slot.visible and _slot.get_child_count() > 0:
		nodes.push_front(_slot)
	return nodes
```

Note: `_slot` is `_Center/Panel/Margin/VBox/Body/CardSlot`. The dynamically created option buttons are all in `_box` (the HBoxContainer), so animating the whole `_box` animates all buttons at once.

In `show_options()`, after the loop that creates buttons, add:

```gdscript
	var _min_btn: Button = $Center/Panel/Margin/VBox/MinimizeButton
	JuicyButton.apply(_min_btn)
	if not _min_btn.pressed.is_connected(func(): minimize_requested.emit()):
		_min_btn.pressed.connect(func(): minimize_requested.emit())
```

Actually, the minimize button should be wired once in `_ready`, not re-wired each call. But `_ready` runs before `show_options`. Add the wiring in `_ready`:

Actually, `option_prompt.gd` doesn't have `_ready`. Add one:

```gdscript
func _ready() -> void:
	var _min_btn: Button = $Center/Panel/Margin/VBox/MinimizeButton
	JuicyButton.apply(_min_btn)
	_min_btn.pressed.connect(func(): minimize_requested.emit())
```

Wait — the `_box` (Options HBoxContainer) children are dynamically created each call, and `_slot` (CardSlot) child is also dynamically created. The `get_animatable_nodes` must be called *after* `show_options` populates these, not at `_ready` time. The method itself queries live children, so it works as long as it's called after `show_options`. The minimize button is static. Put the wiring in `_ready`.

But `_ready` currently doesn't exist in `option_prompt.gd`. Add it:

```gdscript
func _ready() -> void:
	var _min_btn: Button = $Center/Panel/Margin/VBox/MinimizeButton
	JuicyButton.apply(_min_btn)
	_min_btn.pressed.connect(func(): minimize_requested.emit())
```

- [ ] **Step 6: Add MinimizeButton to option_prompt.tscn**

Add after the Options HBoxContainer:

```
[node name="MinimizeButton" type="Button" parent="Center/Panel/Margin/VBox"]
layout_mode = 2
text = "−"
```

- [ ] **Step 7: Add minimize_requested and get_animatable_nodes to trap_reveal_overlay.gd**

Add after `signal picked(option: int)`:

```gdscript
signal minimize_requested
```

Add at end of file:

```gdscript
func get_animatable_nodes() -> Array[Node]:
	return [_name, $Center/Panel/Margin/VBox/Body, _buttons]
```

In `_ready()` — currently there's no `_ready`. Add one:

Actually, the buttons are created dynamically in `show_reveal`. The `_buttons` HBoxContainer itself is the animatable node. Add wiring when the overlay first appears. Since there's no `_ready`, add one:

```gdscript
func _ready() -> void:
	var _min_btn: Button = $Center/Panel/Margin/VBox/MinimizeButton
	JuicyButton.apply(_min_btn)
	_min_btn.pressed.connect(func(): minimize_requested.emit())
```

Wait — the trap reveal can be shown as read-only (for AI intercept) where the buttons are hidden. In that case, the minimize button should still work — the player can minimize even a read-only intercept display. Actually, during AI turns the player shouldn't need to minimize since the AI resolves instantly. But for interactive mode, they should be able to. The minimize button should be visible whenever the overlay is visible.

- [ ] **Step 8: Add MinimizeButton to trap_reveal_overlay.tscn**

Add after the Buttons HBoxContainer:

```
[node name="MinimizeButton" type="Button" parent="Center/Panel/Margin/VBox"]
layout_mode = 2
text = "−"
```

- [ ] **Step 9: Add minimize_requested and get_animatable_nodes to leader_cost_prompt.gd**

Add after `signal chosen(by_discard: bool)`:

```gdscript
signal minimize_requested
```

Add at end of file:

```gdscript
func get_animatable_nodes() -> Array[Node]:
	return [$Panel/PromptLabel, _tickets_btn, _discard_btn]
```

The LeaderCostPrompt has no Dim node — its `Panel` node is the full-screen background. For dim animation purposes, the Panel itself needs its `modulate.a` tweened. Record `_dim_node` as the background panel:

```gdscript
var _dim_node: Control = null

func get_dim_node() -> Control:
	return $Panel
```

Wait, let me think about this more carefully. The design says the dim fades from 55% to 0%. CardSelectPanel, OptionPrompt, and TrapRevealOverlay have a `Dim` ColorRect child. LeaderCostPrompt and MulliganPanel use their full-screen `Panel` node as the background. The code needs to know which node is the "dim" for each overlay. Let me add a `get_dim_node()` method to all overlays.

Actually, to keep it simple — Match.gd will handle the dim animation. It needs to know which node is the dim/background for each overlay. The cleanest approach: add `get_dim_node() -> Control` to each overlay.

For CardSelectPanel: `return $Dim`
For HandChoice: `return null` (no dim — the InputBlocker on MinimizeBar replaces it)
For OptionPrompt: `return $Dim`
For TrapRevealOverlay: `return $Dim`
For LeaderCostPrompt: `return $Panel`
For MulliganPanel: `return $Panel`

Add this method alongside `get_animatable_nodes()`.

In `_ready()` of leader_cost_prompt.gd, add minimize button wiring:

```gdscript
	var _min_btn: Button = $Panel/MinimizeButton
	JuicyButton.apply(_min_btn)
	_min_btn.pressed.connect(func(): minimize_requested.emit())
```

- [ ] **Step 10: Add MinimizeButton to leader_cost_prompt.tscn**

Add inside the Panel, after PayDiscard:

```
[node name="MinimizeButton" type="Button" parent="Panel"]
layout_mode = 0
offset_left = 420.0
offset_top = 110.0
offset_right = 480.0
offset_bottom = 160.0
text = "−"
```

- [ ] **Step 11: Add minimize_requested and get_animatable_nodes to mulligan_panel.gd**

Add after `signal confirmed(indices: Array)`:

```gdscript
signal minimize_requested
```

Add at end of file:

```gdscript
func get_animatable_nodes() -> Array[Node]:
	return [$Panel/Label, _row, _confirm]

func get_dim_node() -> Control:
	return $Panel
```

In `_ready()`, after the existing code, add:

```gdscript
	var _min_btn: Button = $Panel/MinimizeButton
	JuicyButton.apply(_min_btn)
	_min_btn.pressed.connect(func(): minimize_requested.emit())
```

- [ ] **Step 12: Add MinimizeButton to mulligan_panel.tscn**

Add inside Panel, after ConfirmButton:

```
[node name="MinimizeButton" type="Button" parent="Panel"]
layout_mode = 0
offset_left = 720.0
offset_top = 580.0
offset_right = 780.0
offset_bottom = 630.0
text = "−"
```

- [ ] **Step 13: Add get_dim_node to the other overlays**

For each overlay that already has a Dim node, add `get_dim_node()`:

**card_select_panel.gd** — add:
```gdscript
func get_dim_node() -> ColorRect:
	return $Dim
```

**hand_choice.gd** — add:
```gdscript
func get_dim_node() -> Control:
	return null
```

**option_prompt.gd** — add:
```gdscript
func get_dim_node() -> ColorRect:
	return $Dim
```

**trap_reveal_overlay.gd** — add:
```gdscript
func get_dim_node() -> ColorRect:
	return $Dim
```

**leader_cost_prompt.gd** — add:
```gdscript
func get_dim_node() -> Control:
	return $Panel
```

- [ ] **Step 14: Add overlay minimize/get_animatable tests to test_overlays.gd**

Append to `tests/test_overlays.gd`:

```gdscript
func test_card_select_emits_minimize_requested() -> void:
	var p = _inst("res://src/ui/overlays/card_select_panel.tscn")
	p.show_selection(_hand(3), 0, 1, "Pick")
	var emitted := false
	p.minimize_requested.connect(func(): emitted = true)
	p.find_child("MinimizeButton").emit_signal("pressed")
	assert_bool(emitted).is_true()

func test_card_select_animatable_nodes() -> void:
	var p = _inst("res://src/ui/overlays/card_select_panel.tscn")
	p.show_selection(_hand(3), 0, 1, "Pick")
	var nodes := p.get_animatable_nodes()
	assert_int(nodes.size()).is_equal(3)

func test_hand_choice_animatable_nodes() -> void:
	var p = _inst("res://src/ui/match/hand_choice.tscn")
	var nodes := p.get_animatable_nodes()
	assert_int(nodes.size()).is_equal(2)

func test_option_prompt_animatable_nodes() -> void:
	var p = _inst("res://src/ui/overlays/option_prompt.tscn")
	p.show_options(["A", "B"], "Choose", null)
	var nodes := p.get_animatable_nodes()
	assert_int(nodes.size()).is_greater_equal(2)

func test_trap_reveal_animatable_nodes() -> void:
	var p = _inst("res://src/ui/overlays/trap_reveal_overlay.tscn")
	var nodes := p.get_animatable_nodes()
	assert_int(nodes.size()).is_equal(3)
```

- [ ] **Step 15: Run all overlay tests**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_overlays.gd`
Expected: all tests PASS (existing + new).

- [ ] **Step 16: Commit**

```bash
git add src/ui/overlays/card_select_panel.gd src/ui/overlays/card_select_panel.tscn src/ui/match/hand_choice.gd src/ui/match/hand_choice.tscn src/ui/overlays/option_prompt.gd src/ui/overlays/option_prompt.tscn src/ui/overlays/trap_reveal_overlay.gd src/ui/overlays/trap_reveal_overlay.tscn src/ui/overlays/leader_cost_prompt.gd src/ui/overlays/leader_cost_prompt.tscn src/ui/overlays/mulligan_panel.gd src/ui/overlays/mulligan_panel.tscn tests/test_overlays.gd
git commit -m "feat: add minimize_requested signal and get_animatable_nodes to all overlays"
```

---

### Task 3: Wire MinimizeBar into Match.gd with animation logic

This is the core coordination task. Match.gd gains minimize/expand methods that orchestrate the shrink/expand animations.

**Files:**
- Modify: `src/ui/match/match.gd`
- Modify: `src/ui/match/match.tscn`

- [ ] **Step 1: Add MinimizeBar instance to match.tscn**

Add to `match.tscn` after the HandChoice instance node:

```
[node name="MinimizeBar" parent="." instance=ExtResource("19_minbar")]
```

Add the ext_resource at the top of the file:

```
[ext_resource type="PackedScene" path="res://src/ui/overlays/minimize_bar.tscn" id="19_minbar"]
```

- [ ] **Step 2: Add Match.gd state variables and references**

At the top of `match.gd`, after `var _anim_busy: bool = false`, add:

```gdscript
var _minimized_overlay: CanvasLayer = null
var _active_overlay: CanvasLayer = null
```

After `@onready var _hand_choice = $HandChoice`, add:

```gdscript
@onready var _minimize_bar = $MinimizeBar
```

- [ ] **Step 3: Wire minimize_requested signals in _ready()**

In `_ready()`, add after the existing signal connections:

```gdscript
	_select.minimize_requested.connect(_on_overlay_minimize.bind(_select))
	_hand_choice.minimize_requested.connect(_on_overlay_minimize.bind(_hand_choice))
	_option_prompt.minimize_requested.connect(_on_overlay_minimize.bind(_option_prompt))
	_trap_reveal.minimize_requested.connect(_on_overlay_minimize.bind(_trap_reveal))
	_leader_prompt.minimize_requested.connect(_on_overlay_minimize.bind(_leader_prompt))
	_mulligan.minimize_requested.connect(_on_overlay_minimize.bind(_mulligan))
	_minimize_bar.expand_pressed.connect(_on_overlay_expand)
```

- [ ] **Step 4: Track _active_overlay when overlays are shown**

In `_route_pending_choice()`, each overlay is shown. We need to track which overlay is currently active. Add `_active_overlay` assignments at each point where an overlay is shown:

In the `"mulligan"` branch, after `_hand_choice.start(...)`, add:
```gdscript
	_active_overlay = _hand_choice
```

In `"discard_to_limit"`, after `_hand_choice.start(...)`, add:
```gdscript
	_active_overlay = _hand_choice
```

In `"intercept"`, after `_trap_reveal.show_reveal(...)`, add:
```gdshader
	_active_overlay = _trap_reveal
```

In `"trash_choice"`, after `_option_prompt.show_options(...)`, add:
```gdscript
	_active_overlay = _option_prompt
```

In `_route_card_effect`, `"select_cards"` with hand pool, after `_hand_choice.start(...)`, add:
```gdscript
	_active_overlay = _hand_choice
```

In `"select_cards"` without hand pool, after `_select.show_selection(...)`, add:
```gdscript
	_active_overlay = _select
```

In `"choose_option"`, after `_option_prompt.show_options(...)`, add:
```gdscript
	_active_overlay = _option_prompt
```

In `"select_target"`, after `_begin_target_selection(spec)`, add:
```gdscript
	_active_overlay = null  # targeting is inline on board, no overlay
```

In `handle_drop`, where `_leader_prompt.show_prompt()` is called, add after it:
```gdscript
	_active_overlay = _leader_prompt
```

In `_show_game_over`, after `_game_over.show_result(...)`, add:
```gdscript
	_active_overlay = _game_over
```

Clear `_active_overlay` in the signal handlers that resolve choices. After each `apply_action(...)` call in the signal callbacks, add:
```gdscript
	_active_overlay = null
```

This includes: `_on_hand_choice_confirmed`, all the `func(i): apply_action(...)` lambdas for `_option_prompt.picked`, `_trap_reveal.picked`, and `_mulligan.confirmed`. Also `_select.confirmed`.

For `_select.confirmed`:
```gdscript
	_select.confirmed.connect(func(idx): _active_overlay = null; apply_action(Action.resolve_choice({"indices": idx})))
```

For `_option_prompt.picked`:
```gdscript
	_option_prompt.picked.connect(func(i): _active_overlay = null; apply_action(Action.resolve_choice({"option": i})))
```

For `_trap_reveal.picked`:
```gdscript
	_trap_reveal.picked.connect(func(i): _active_overlay = null; apply_action(Action.resolve_choice({"option": i})))
```

For `_hand_choice.confirmed`:
In `_on_hand_choice_confirmed`:
```gdscript
func _on_hand_choice_confirmed(indices: Array) -> void:
	_active_overlay = null
	match state.pending_choice.kind:
		"mulligan":
			apply_action(Action.mulligan(indices))
		_:
			apply_action(Action.resolve_choice({"indices": indices}))
```

For `_mulligan.confirmed`:
```gdscript
	_mulligan.confirmed.connect(func(idx): _active_overlay = null; apply_action(Action.mulligan(idx)))
```

For `_leader_prompt`:
```gdscript
	var handler := func(by_disc):
		_active_overlay = null
		if by_disc:
			apply_action(by_discard)
		else:
			apply_action(by_tickets)
```

Also clear `_active_overlay` in `_on_play_again`.

- [ ] **Step 5: Add minimize/expand animation methods**

Add after `_show_game_over()` in `match.gd`:

```gdscript
const MINIMIZE_STAGGER := 0.05
const MINIMIZE_DURATION := 0.25
const EXPAND_DURATION := 0.35
const DIM_FADE_DURATION := 0.3

func _on_overlay_minimize(overlay: CanvasLayer) -> void:
	_minimized_overlay = overlay
	var dim: Control = overlay.get_dim_node()
	var tab_pos := _minimize_bar.find_child("Tab").global_position
	var nodes := overlay.get_animatable_nodes()
	for i in range(nodes.size()):
		var node: Node = nodes[i]
		if node == null:
			continue
		var tw := node.create_tween()
		tw.tween_interval(MINIMIZE_STAGGER * float(nodes.size() - 1 - i))
		tw.parallel().tween_property(node, "global_position", tab_pos, MINIMIZE_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(node, "scale", Vector2.ZERO, MINIMIZE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if dim != null:
		var tw := dim.create_tween()
		var orig_color: Color = dim.color if dim is ColorRect else dim.modulate
		var target_alpha := 0.0 if dim is ColorRect else 0.0
		if dim is ColorRect:
			tw.tween_property(dim, "color:a", target_alpha, DIM_FADE_DURATION).set_trans(Tween.TRANS_CUBIC)
		else:
			tw.tween_property(dim, "modulate:a", target_alpha, DIM_FADE_DURATION).set_trans(Tween.TRANS_CUBIC)
	var final_tw := create_tween()
	final_tw.tween_interval(MINIMIZE_DURATION + MINIMIZE_STAGGER * float(nodes.size()))
	final_tw.tween_callback(func():
		for node in nodes:
			if node != null:
				node.visible = false
		if dim != null:
			dim.visible = false
		_minimize_bar.show_bar(_overlay_title(overlay))
	)

func _on_overlay_expand() -> void:
	var overlay := _minimized_overlay
	if overlay == null:
		return
	_minimize_bar.hide_bar()
	var dim: Control = overlay.get_dim_node()
	var nodes := overlay.get_animatable_nodes()
	var tab_pos := _minimize_bar.find_child("Tab").global_position
	if dim != null:
		dim.visible = true
		var tw := dim.create_tween()
		if dim is ColorRect:
			var orig := Color(0, 0, 0, 0.55)
			dim.color = Color(0, 0, 0, 0.0)
			tw.tween_property(dim, "color:a", orig.a, DIM_FADE_DURATION).set_trans(Tween.TRANS_CUBIC)
		else:
			dim.modulate = Color(1, 1, 1, 0.0)
			tw.tween_property(dim, "modulate:a", 1.0, DIM_FADE_DURATION).set_trans(Tween.TRANS_CUBIC)
	for i in range(nodes.size()):
		var node: Node = nodes[i]
		if node == null:
			continue
		node.visible = true
		node.global_position = tab_pos
		node.scale = Vector2.ZERO
		var tw := node.create_tween()
		tw.tween_interval(MINIMIZE_STAGGER * float(i))
		tw.parallel().tween_property(node, "global_position", node.get_meta("rest_pos", node.global_position), EXPAND_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(node, "scale", Vector2.ONE, EXPAND_DURATION).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_minimized_overlay = null

func _overlay_title(overlay: CanvasLayer) -> String:
	if overlay == _select:
		return _select._label.text
	elif overlay == _hand_choice:
		return _hand_choice._title.text
	elif overlay == _option_prompt:
		return _option_prompt._label.text
	elif overlay == _trap_reveal:
		return _trap_reveal._name.text
	elif overlay == _leader_prompt:
		return "Pay leader cost"
	elif overlay == _mulligan:
		return "Select 2 cards to discard"
	return "Choose"
```

Wait — there's a problem with saving and restoring positions. When we minimize, we animate nodes from their current position toward the tab. On expand, we need to animate them back. But after the minimize animation, the nodes' positions have changed to the tab position. We need to save their "rest" positions before the minimize animation starts.

Let me revise the approach. Before minimizing, save each node's rest position and scale. On expand, restore from those saved values.

Add a dictionary to store rest transforms:

```gdscript
var _rest_transforms: Dictionary = {}
```

In `_on_overlay_minimize`, before starting tweens, save each node's rest position and scale:

```gdscript
func _on_overlay_minimize(overlay: CanvasLayer) -> void:
	_minimized_overlay = overlay
	var dim: Control = overlay.get_dim_node()
	var tab_pos := _minimize_bar.find_child("Tab").global_position
	var nodes := overlay.get_animatable_nodes()
	_rest_transforms.clear()
	for node in nodes:
		if node == null:
			continue
		_rest_transforms[node.get_instance_id()] = {
			"position": node.global_position,
			"scale": node.scale
		}
	for i in range(nodes.size()):
		var node: Node = nodes[i]
		if node == null:
			continue
		var tw := node.create_tween()
		tw.tween_interval(MINIMIZE_STAGGER * float(nodes.size() - 1 - i))
		tw.parallel().tween_property(node, "global_position", tab_pos, MINIMIZE_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(node, "scale", Vector2.ZERO, MINIMIZE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if dim != null:
		var tw := dim.create_tween()
		if dim is ColorRect:
			tw.tween_property(dim, "color:a", 0.0, DIM_FADE_DURATION).set_trans(Tween.TRANS_CUBIC)
		else:
			tw.tween_property(dim, "modulate:a", 0.0, DIM_FADE_DURATION).set_trans(Tween.TRANS_CUBIC)
	var final_tw := create_tween()
	final_tw.tween_interval(MINIMIZE_DURATION + MINIMIZE_STAGGER * float(nodes.size()))
	final_tw.tween_callback(func():
		for node in nodes:
			if node != null:
				node.visible = false
		if dim != null:
			dim.visible = false
		_minimize_bar.show_bar(_overlay_title(overlay))
	)
```

In `_on_overlay_expand`, read from `_rest_transforms`:

```gdscript
func _on_overlay_expand() -> void:
	var overlay := _minimized_overlay
	if overlay == null:
		return
	_minimize_bar.hide_bar()
	var dim: Control = overlay.get_dim_node()
	var nodes := overlay.get_animatable_nodes()
	var tab_pos := _minimize_bar.find_child("Tab").global_position
	if dim != null:
		dim.visible = true
		var tw := dim.create_tween()
		if dim is ColorRect:
			dim.color = Color(0, 0, 0, 0.0)
			tw.tween_property(dim, "color:a", 0.55, DIM_FADE_DURATION).set_trans(Tween.TRANS_CUBIC)
		else:
			dim.modulate = Color(1, 1, 1, 0.0)
			tw.tween_property(dim, "modulate:a", 1.0, DIM_FADE_DURATION).set_trans(Tween.TRANS_CUBIC)
	for i in range(nodes.size()):
		var node: Node = nodes[i]
		if node == null:
			continue
		var rest := _rest_transforms.get(node.get_instance_id(), {"position": node.global_position, "scale": Vector2.ONE})
		var rest_pos: Vector2 = rest["position"]
		var rest_scale: Vector2 = rest["scale"]
		node.visible = true
		node.global_position = tab_pos
		node.scale = Vector2.ZERO
		var tw := node.create_tween()
		tw.tween_interval(MINIMIZE_STAGGER * float(i))
		tw.parallel().tween_property(node, "global_position", rest_pos, EXPAND_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(node, "scale", rest_scale, EXPAND_DURATION).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_minimized_overlay = null
	_rest_transforms.clear()
```

- [ ] **Step 6: Handle HandChoice special case — dim replacement**

HandChoice has no dim node (returns null). When HandChoice is minimized, the MinimizeBar's InputBlocker already blocks all mouse input to the board, which is the desired behavior. The overlay's CanvasLayer stays visible during minimization (the nodes are just hidden/animated), so no additional dim is needed for HandChoice.

However, there's one important detail: HandChoice's `_title` and `_confirm` are Control nodes positioned in screen coordinates (not inside a layout container that auto-positions them). Their `global_position` changes during animation need to restore correctly. This should work fine since we're saving/restoring `global_position`.

For HandChoice specifically, when minimized, the staged cards (in the hand) stay visible. This is correct behavior — they're CardViews that belong to HandView, not to HandChoice's animatable nodes.

- [ ] **Step 7: Run the project and manually test minimize/expand**

Manual verification steps:
1. Start a game
2. When a choice overlay appears, click the minimize button
3. Verify: overlay content shrinks into the bottom tab, dim fades out, tab appears
4. Click the expand button on the tab
5. Verify: tab disappears, content bursts back out, dim fades in
6. Verify: board is not interactive while minimized
7. Test with each overlay type: CardSelectPanel, HandChoice, OptionPrompt, TrapRevealOverlay, LeaderCostPrompt, MulliganPanel

- [ ] **Step 8: Commit**

```bash
git add src/ui/match/match.gd src/ui/match/match.tscn
git commit -m "feat: wire MinimizeBar into Match with shrink/expand animations"
```

---

### Task 4: Test and polish

**Files:**
- Modify: `tests/test_overlays.gd`
- Possibly fix: `src/ui/match/match.gd`
- Possibly fix: overlay scripts if scene paths are wrong

- [ ] **Step 1: Add integration-level test for minimize/expand flow in test_overlays.gd**

Add tests verifying the MinimizeBar + overlay interaction:

```gdscript
func test_minimize_bar_show_sets_title() -> void:
	var bar = load("res://src/ui/overlays/minimize_bar.tscn").instantiate()
	add_child(bar)
	auto_free(bar)
	bar.show_bar("Pick a card")
	assert_str(bar.find_child("Title").text).is_equal("Pick a card")

func test_minimize_bar_expand_signal() -> void:
	var bar = load("res://src/ui/overlays/minimize_bar.tscn").instantiate()
	add_child(bar)
	auto_free(bar)
	var emitted := false
	bar.expand_pressed.connect(func(): emitted = true)
	bar.find_child("ExpandButton").emit_signal("pressed")
	assert_bool(emitted).is_true()
```

- [ ] **Step 2: Run all overlay tests**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_overlays.gd`
Expected: all tests PASS.

- [ ] **Step 3: Run the minimize bar tests**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_minimize_bar.gd`
Expected: all tests PASS.

- [ ] **Step 4: Run full test suite**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
Expected: all tests PASS.

- [ ] **Step 5: Manual playtest — minimize each overlay type**

Play through and trigger each overlay:
- **Mulligan/HandChoice**: Start a game, choose cards to discard
- **CardSelectPanel**: Play a card that triggers card selection
- **OptionPrompt**: Play a card that offers choices
- **TrapRevealOverlay**: Play against opponent's trap
- **LeaderCostPrompt**: Play a leader card
- **MulliganPanel**: Start a game (if still used)

For each, click the minimize button, verify the shrink animation, click expand, verify the expand animation, and confirm you can complete the choice afterwards.

- [ ] **Step 6: Commit any fixes**

```bash
git add -A
git commit -m "fix: polish minimize/expand animations and fix test issues"
```

---

## Self-review

### Spec coverage check

| Spec requirement | Covered by task |
|---|---|
| MinimizeBar CanvasLayer with InputBlocker + Tab | Task 1 |
| show(title) with TRANS_ELASTIC pop | Task 1 |
| hide() with shrink | Task 1 |
| expand_pressed signal | Task 1 |
| 15% dim InputBlocker, eats mouse events | Task 1 (ColorRect with mouse_filter) |
| Each overlay gets minimize button with JuicyButton | Task 2 |
| Each overlay emits minimize_requested | Task 2 |
| Each overlay has get_animatable_nodes() | Task 2 |
| Animatable nodes per overlay match spec table | Task 2 |
| Match coordination with _minimized_overlay, _active_overlay | Task 3 |
| Minimize animation: shrink nodes toward tab with stagger | Task 3 |
| Expand animation: burst from tab with TRANS_BACK + TRANS_ELASTIC | Task 3 |
| Dim lerp animation | Task 3 |
| HandChoice special handling (only Title + Confirm animate) | Task 2 (get_animatable_nodes returns only those) |
| EndTurnButton stays disabled | No change needed (spec confirmed) |
| Animation interruption handled | Task 3 (expand button only visible after minimize completes) |

### Placeholder scan

No TBDs, TODOs, or vague requirements. All code is concrete.

### Type consistency

- `get_animatable_nodes() -> Array[Node]` — consistent across all overlays
- `get_dim_node() -> Control` — returns ColorRect or Panel, both Control subclasses
- Signal `minimize_requested` — consistent name across all overlays
- `_rest_transforms` dictionary uses `node.get_instance_id()` as key — GDScript Dictionary, works correctly

### Potential issues

1. **global_position vs position**: Some overlay nodes (like those inside VBoxContainer/HBoxContainer) have their positions managed by the container. Animating `global_position` overrides the container's positioning. On expand, we restore to the saved rest position. But if the overlay is re-shown after a different `show_*` call that repopulates children (e.g., CardSelectPanel clears and refills CardRow), the saved positions may be stale. This is acceptable because the overlay won't be minimized during re-population — the minimize button is only available while the overlay is actively showing.

2. **CanvasLayer children and global_position**: Nodes inside a CanvasLayer use the canvas layer's transform. Since CanvasLayer has layer=0 by default, global_position should work. Need to verify in testing that `global_position` correctly references screen coordinates for these nodes. If not, may need to use `position` instead and account for the canvas layer offset. This should be verified in Task 4 during manual testing.

3. **LeaderCostPrompt uses layout_mode=0 (absolute positioning)** for its buttons, while other overlays use layout containers. The `global_position` animation for `PayTickets` and `PayDiscard` should work correctly for both layout modes since we're storing and restoring the actual rendered position.

4. **CardSelectPanel's CardRow children are dynamically created**: When `get_animatable_nodes()` returns `_row`, the entire HBoxContainer animates as a unit. This is correct — the individual cards inside move with their parent container.