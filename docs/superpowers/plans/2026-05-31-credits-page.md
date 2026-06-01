# Credits Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-scrolling movie-credits panel that reads artist names from a `.txt` file, populates a RichTextLabel, and scrolls it upward on a loop.

**Architecture:** A plaintext `credits.txt` file (one artist per line) is read at panel load. The existing `CreditsPanel` scene is stripped of its static VBox body and replaced with a RichTextLabel whose `position.y` is tweened from screen-bottom to above-screen-top (~15 s), looping forever. The Back button stays as-is so it's always accessible.

**Tech Stack:** Godot 4 GDScript, Control nodes, Tween, FileAccess, GdUnit4 for tests.

---

### Task 1: Create `credits.txt` data file

**Files:**
- Create: `src/data/credits.txt`

- [ ] **Step 1: Create `src/data/credits.txt`**

Write the file with the 5 deduplicated artists extracted from the deck CSVs:

```
Quin
Samuel Gines
Alexander C
henri
melina
```

- [ ] **Step 2: Commit**

```bash
git add src/data/credits.txt
git commit -m "feat: add credits.txt with artist names"
```

---

### Task 2: Update `credits_panel.tscn` scene

**Files:**
- Modify: `src/ui/shell/credits_panel.tscn`

Replace the static VBox body with a RichTextLabel for scrolling credits text. Keep the Back button.

- [ ] **Step 1: Replace `credits_panel.tscn`**

Write the full updated scene:

```ini
[gd_scene format=3 uid="uid://ccredits001"]

[ext_resource type="Script" path="res://src/ui/shell/credits_panel.gd" id="1_cr"]

[node name="CreditsPanel" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_cr")

[node name="CreditsLabel" type="RichTextLabel" parent="."]
layout_mode = 0
offset_left = 0.0
offset_right = 1920.0
offset_bottom = 100.0
text = ""
fit_content = true
scroll_active = false
bbcode_enabled = true

[node name="Back" type="Button" parent="."]
unique_name_in_owner = true
layout_mode = 0
offset_left = 40.0
offset_top = 40.0
offset_right = 140.0
offset_bottom = 80.0
text = "Back"
flat = true
```

Key changes from the old scene:
- VBox and its child nodes (Title, Body) are removed.
- `CreditsLabel` (RichTextLabel) is added — full width (1920), `fit_content = true` so it sizes to its content, `scroll_active = false` (we animate position ourselves), `bbcode_enabled = true`.
- `%Back` button stays but moves to top-left (`offset` 40,40) with `flat = true` so it floats over the scrolling text.

- [ ] **Step 2: Commit**

```bash
git add src/ui/shell/credits_panel.tscn
git commit -m "feat: replace credits panel body with RichTextLabel for scrolling"
```

---

### Task 3: Update tests

**Files:**
- Modify: `tests/test_credits_panel.gd`

- [ ] **Step 1: Write updated test file**

```gdscript
# tests/test_credits_panel.gd
extends GdUnitTestSuite

func _spawn() -> CreditsPanel:
	var p: CreditsPanel = load("res://src/ui/shell/credits_panel.tscn").instantiate()
	add_child(p)
	auto_free(p)
	return p

func test_back_button_emits_back_pressed() -> void:
	var p := _spawn()
	var fired := [false]
	p.back_pressed.connect(func() -> void: fired[0] = true)
	p.get_node("%Back").pressed.emit()
	assert_bool(fired[0]).is_true()

func test_credits_label_contains_artists_from_file() -> void:
	var p := _spawn()
	var label := p.get_node("CreditsLabel") as RichTextLabel
	assert_str(label.text).contains("Quin")
	assert_str(label.text).contains("Samuel Gines")
	assert_str(label.text).contains("Alexander C")
	assert_str(label.text).contains("henri")
	assert_str(label.text).contains("melina")

func test_credits_label_starts_below_viewport() -> void:
	var p := _spawn()
	var label := p.get_node("CreditsLabel") as Control
	var vp_height := p.get_viewport_rect().size.y
	assert_float(label.position.y).is_greater_equal(vp_height)
```

- [ ] **Step 2: Run the tests (expect FAIL on new tests)**

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_credits_panel.gd
```

Expected: `test_back_button_emits_back_pressed` passes; `test_credits_label_contains_artists_from_file` and `test_credits_label_starts_below_viewport` fail (label text is empty, position is 0).

- [ ] **Step 3: Commit**

```bash
git add tests/test_credits_panel.gd
git commit -m "test: add credits label content and scroll position tests"
```

---

### Task 4: Implement `credits_panel.gd`

**Files:**
- Modify: `src/ui/shell/credits_panel.gd`

- [ ] **Step 1: Write the updated script**

```gdscript
# src/ui/shell/credits_panel.gd
class_name CreditsPanel
extends Control

signal back_pressed

const CREDITS_PATH := "res://src/data/credits.txt"
const SCROLL_DURATION := 15.0

@onready var _back: Button = %Back
@onready var _label: RichTextLabel = $CreditsLabel

func _ready() -> void:
	theme = preload("res://src/ui/theme/game_theme.tres")
	_back.pressed.connect(func() -> void: back_pressed.emit())
	JuicyButton.apply(_back)
	_populate_label()
	_scroll_loop()

func _populate_label() -> void:
	var f := FileAccess.open(CREDITS_PATH, FileAccess.READ)
	assert(f != null, "Could not open %s" % CREDITS_PATH)
	var body := ""
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line != "":
			body += line + "\n"
	f.close()
	_label.text = "[center][font_size=48]Artists[/font_size]\n\n" + body + "[/center]"

func _scroll_loop() -> void:
	var viewport_height := get_viewport_rect().size.y
	_label.position.y = viewport_height
	var end_y := -_label.size.y - 100.0
	var tw := create_tween().set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_label, "position:y", end_y, SCROLL_DURATION)
	tw.tween_callback(_scroll_loop)
```

- [ ] **Step 2: Run the tests (expect PASS)**

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_credits_panel.gd
```

Expected: all 3 tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/ui/shell/credits_panel.gd
git commit -m "feat: implement auto-scrolling credits panel"
```

---

### Task 5: Final verification

- [ ] **Step 1: Run all shell panel tests together**

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_credits_panel.gd -a res://tests/test_landing_panel.gd -a res://tests/test_app_shell.gd
```

Expected: all tests pass.

- [ ] **Step 2: Inspect git status**

```bash
git status
git diff
```
