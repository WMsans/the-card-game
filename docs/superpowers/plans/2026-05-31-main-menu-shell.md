# Main Menu Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bare main menu with a Slay-the-Spire-style menu hub — a persistent `AppShell` that owns one animated background and swaps between a landing menu, a deck-select/Embark screen, a display-settings screen, the existing compendium, and the match itself.

**Architecture:** A single persistent root scene `AppShell` owns one `BalatroBg` (never freed) plus a `ContentLayer` that holds exactly one panel at a time. Panels (`LandingPanel`, `DeckSelectPanel`, `SettingsPanel`, reused `CardGallery`, refactored `Match`) are small, independently testable scenes that emit intent signals; the shell decides what to mount and crossfades between them. `BalatroBg` gains a parallaxed trauma-shake that all foreground subscribers inherit.

**Tech Stack:** Godot 4.6 (GL Compatibility), GDScript, GdUnit4 for tests, `ConfigFile` for settings persistence.

---

## Conventions for every task

**Test run command** (from `AGENTS.md` — import first so the worktree's `.godot/` cache exists):

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/<test_file>.gd
```

Run the **full** suite with `-a res://tests` (no single file) before the final commit of a task that touches shared code.

**TDD loop for every task:** write the failing test → run it, confirm it fails for the expected reason → write minimal implementation → run, confirm pass → commit. Use small commits.

---

## File Structure

**New**
- `src/ui/shell/app_shell.gd` / `app_shell.tscn` — persistent root: owns `BalatroBg` + `ContentLayer`, navigation, crossfades, `start_match`, settings load-on-ready.
- `src/ui/shell/landing_panel.gd` / `landing_panel.tscn` — the menu (Play/Compendium/Settings/Quit + Credits corner) and drifting cards.
- `src/ui/shell/deck_select_panel.gd` / `deck_select_panel.tscn` — leader showcase + deck/opponent tray + seed + Embark/Back.
- `src/ui/shell/settings_panel.gd` / `settings_panel.tscn` — fullscreen + vsync toggles + Back.
- `src/ui/shell/credits_panel.gd` / `credits_panel.tscn` — minimal credits + Back.
- `src/ui/shell/game_settings.gd` — `ConfigFile`-backed load/apply/save of display settings.

**Modified**
- `src/ui/match/balatro_bg.gd` — add `add_trauma()` + parallaxed shake.
- `src/ui/match/match.tscn` — remove the `BalatroBg` node + its ext_resource.
- `src/ui/match/match.gd` — injected/optional background via `attach_background()`; add a "Main Menu" path on game-over.
- `src/ui/overlays/game_over_panel.gd` / `.tscn` — add a "Main Menu" button + `main_menu` signal.
- `project.godot` — `run/main_scene` → `res://src/ui/shell/app_shell.tscn`.

**Removed**
- `src/ui/menu/main_menu.gd` / `.tscn` (+ stale `.uid`) — superseded.

**Tests (new/replaced)**
- `tests/test_balatro_bg_shake.gd`, `tests/test_match_background.gd`, `tests/test_landing_panel.gd`, `tests/test_deck_select_panel.gd`, `tests/test_settings_panel.gd`, `tests/test_game_settings.gd`, `tests/test_credits_panel.gd`, `tests/test_app_shell.gd`. Replace `tests/test_main_menu.gd`.

---

## Task 1: Parallaxed shake in BalatroBg

**Files:**
- Modify: `src/ui/match/balatro_bg.gd`
- Test: `tests/test_balatro_bg_shake.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_balatro_bg_shake.gd
extends GdUnitTestSuite

func _spawn() -> BalatroBg:
	var bg: BalatroBg = load("res://src/ui/match/balatro_bg.tscn").instantiate()
	add_child(bg)
	auto_free(bg)
	return bg

func test_trauma_starts_at_zero() -> void:
	var bg := _spawn()
	assert_float(bg.get_trauma()).is_equal_approx(0.0, 0.0001)

func test_add_trauma_is_clamped_to_one() -> void:
	var bg := _spawn()
	bg.add_trauma(5.0)
	assert_float(bg.get_trauma()).is_equal_approx(1.0, 0.0001)

func test_shake_emits_nonzero_foreground_offset() -> void:
	var bg := _spawn()
	bg.add_trauma(1.0)
	var captured := [Vector2.ZERO]
	bg.foreground_offset.connect(func(o: Vector2) -> void: captured[0] = o)
	bg._process(0.016)
	assert_vector(captured[0]).is_not_equal(Vector2.ZERO)

func test_trauma_decays_to_zero_over_time() -> void:
	var bg := _spawn()
	bg.add_trauma(1.0)
	for i in range(240):
		bg._process(0.016)
	assert_float(bg.get_trauma()).is_equal_approx(0.0, 0.0001)
```

- [ ] **Step 2: Run the test, confirm it fails**

Run the test file. Expected: FAIL — `get_trauma`/`add_trauma` do not exist.

- [ ] **Step 3: Implement the shake**

In `src/ui/match/balatro_bg.gd`, add exports + state near the top (after the existing `smoothing` export and `_fg_current`):

```gdscript
@export var trauma_decay: float = 1.5
@export var shake_max: Vector2 = Vector2(40, 30)

var _trauma: float = 0.0

func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

func get_trauma() -> float:
	return _trauma
```

Then replace the body of `_process` so the shake rides the existing parallax channels. The shake magnitude is `trauma²` (standard trauma curve), scaled per-layer by the same `bg_max_offset` / `fg_max_offset` ratios so the foreground shakes harder than the background:

```gdscript
func _process(delta: float) -> void:
	var center := get_viewport_rect().size / 2.0
	var dist := get_global_mouse_position() - center
	var normalized := dist / center

	var bg_target := Vector2(-bg_max_offset.x * normalized.x, -bg_max_offset.y * normalized.y)
	var fg_target := Vector2(-fg_max_offset.x * normalized.x, -fg_max_offset.y * normalized.y)

	_bg_current = _bg_current.lerp(bg_target, smoothing * delta)
	_fg_current = _fg_current.lerp(fg_target, smoothing * delta)

	_trauma = maxf(_trauma - trauma_decay * delta, 0.0)
	var shake := _trauma * _trauma
	var jolt := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake
	# parallaxed: background moves less than foreground, matching the parallax ratios
	var bg_jolt := jolt * shake_max * (bg_max_offset / fg_max_offset)
	var fg_jolt := jolt * shake_max

	position = _bg_current + bg_jolt
	foreground_offset.emit(_fg_current + fg_jolt)
```

- [ ] **Step 4: Run the test, confirm it passes**

Run `tests/test_balatro_bg_shake.gd`. Expected: PASS (4 tests).

- [ ] **Step 5: Run the existing match tests to confirm no regression**

Run `res://tests/test_match_flow.gd`. Expected: PASS (background still emits offsets as before, plus shake when trauma added).

- [ ] **Step 6: Commit**

```bash
git add src/ui/match/balatro_bg.gd tests/test_balatro_bg_shake.gd
git commit -m "feat: add parallaxed trauma shake to BalatroBg"
```

---

## Task 2: Make Match's background injectable (optional)

Match must no longer own a `BalatroBg`; the shell injects one. When none is injected (standalone / tests), Match runs without foreground parallax.

**Files:**
- Modify: `src/ui/match/match.tscn` (remove BalatroBg node + ext_resource)
- Modify: `src/ui/match/match.gd:51,84` (drop `@onready _bg`, add `attach_background`)
- Test: `tests/test_match_background.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_match_background.gd
extends GdUnitTestSuite

func _spawn() -> Control:
	var m: Control = load("res://src/ui/match/match.tscn").instantiate()
	add_child(m)
	auto_free(m)
	return m

func test_match_instantiates_without_a_background() -> void:
	var m := _spawn()
	assert_object(m).is_not_null()
	assert_bool(m.has_node("BalatroBg")).is_false()

func test_attach_background_wires_foreground_parallax() -> void:
	var m := _spawn()
	var bg: BalatroBg = load("res://src/ui/match/balatro_bg.tscn").instantiate()
	add_child(bg)
	auto_free(bg)
	m.attach_background(bg)
	var table: Control = m.get_node("Table")
	bg.foreground_offset.emit(Vector2(7, 9))
	assert_vector(table.position).is_equal(Vector2(7, 9))
```

- [ ] **Step 2: Run the test, confirm it fails**

Run `tests/test_match_background.gd`. Expected: FAIL — `BalatroBg` node still present (first test) and `attach_background` undefined (second).

- [ ] **Step 3: Remove the BalatroBg node from `match.tscn`**

Delete line 23 (the ext_resource) and line 34 (the node), leaving the rest intact:

```
# DELETE this ext_resource line:
[ext_resource type="PackedScene" path="res://src/ui/match/balatro_bg.tscn" id="21_bg"]

# DELETE this node line (line 34):
[node name="BalatroBg" parent="." instance=ExtResource("21_bg")]
```

- [ ] **Step 4: Update `match.gd`**

Remove the `@onready` background var at `match.gd:51`:

```gdscript
# DELETE:
@onready var _bg: BalatroBg = $BalatroBg
```

Add a nullable field near the other vars (e.g. after `var _tweens: Array[Tween] = []`):

```gdscript
var _bg: BalatroBg = null
```

Remove the connect line at `match.gd:84` from `_ready()`:

```gdscript
# DELETE from _ready():
	_bg.foreground_offset.connect(_on_foreground_offset)
```

Add the injection method (place it next to `start_game`):

```gdscript
func attach_background(bg: BalatroBg) -> void:
	_bg = bg
	if _bg != null and not _bg.foreground_offset.is_connected(_on_foreground_offset):
		_bg.foreground_offset.connect(_on_foreground_offset)
```

- [ ] **Step 5: Run the test, confirm it passes**

Run `tests/test_match_background.gd`. Expected: PASS (2 tests).

- [ ] **Step 6: Run the full match suite for regressions**

Run these and expect PASS: `res://tests/test_match_flow.gd`, `res://tests/test_match_transitions.gd`, `res://tests/test_integration_ui_game.gd`.

- [ ] **Step 7: Commit**

```bash
git add src/ui/match/match.tscn src/ui/match/match.gd tests/test_match_background.gd
git commit -m "refactor: inject Match background instead of owning it"
```

---

## Task 3: Game-over "Main Menu" return

Add a third game-over option that the shell will route back to the landing menu.

**Files:**
- Modify: `src/ui/overlays/game_over_panel.tscn` (add MainMenu button)
- Modify: `src/ui/overlays/game_over_panel.gd` (add `main_menu` signal)
- Modify: `src/ui/match/match.gd` (re-expose a `quit_to_menu` signal)
- Test: `tests/test_game_over_panel.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_game_over_panel.gd
extends GdUnitTestSuite

func _spawn() -> Node:
	var p: Node = load("res://src/ui/overlays/game_over_panel.tscn").instantiate()
	add_child(p)
	auto_free(p)
	return p

func test_main_menu_button_emits_main_menu_signal() -> void:
	var p := _spawn()
	var fired := [false]
	p.main_menu.connect(func() -> void: fired[0] = true)
	p.get_node("Panel/MainMenu").pressed.emit()
	assert_bool(fired[0]).is_true()
```

- [ ] **Step 2: Run, confirm it fails**

Expected: FAIL — no `Panel/MainMenu` node and no `main_menu` signal.

- [ ] **Step 3: Add the button to `game_over_panel.tscn`**

Append this node after the existing `Quit` node (mirrors its layout, shifted down):

```
[node name="MainMenu" type="Button" parent="Panel"]
layout_mode = 0
offset_left = 250.0
offset_top = 420.0
offset_right = 670.0
offset_bottom = 470.0
text = "Main Menu"
```

- [ ] **Step 4: Add the signal + wiring in `game_over_panel.gd`**

Add to the signals block:

```gdscript
signal main_menu
```

In `_ready()`, add (next to the other button connects):

```gdscript
	$Panel/MainMenu.pressed.connect(func(): main_menu.emit())
	JuicyButton.apply($Panel/MainMenu)
```

- [ ] **Step 5: Re-expose the choice from Match**

In `match.gd`, add a signal at the top (after `extends Control`):

```gdscript
signal quit_to_menu
```

In `_ready()`, connect the panel's new signal to re-emit it (next to the existing `_game_over.play_again.connect(...)`):

```gdscript
	_game_over.main_menu.connect(func(): quit_to_menu.emit())
```

- [ ] **Step 6: Run, confirm it passes**

Run `tests/test_game_over_panel.gd`. Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/ui/overlays/game_over_panel.tscn src/ui/overlays/game_over_panel.gd src/ui/match/match.gd tests/test_game_over_panel.gd
git commit -m "feat: add Main Menu return option to game over"
```

---

## Task 4: GameSettings (display settings persistence)

**Files:**
- Create: `src/ui/shell/game_settings.gd`
- Test: `tests/test_game_settings.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_game_settings.gd
extends GdUnitTestSuite

const PATH := "user://test_settings.cfg"

func before_test() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

func test_defaults_when_no_file() -> void:
	var s := GameSettings.new(PATH)
	s.load()
	assert_bool(s.fullscreen).is_false()
	assert_bool(s.vsync).is_true()

func test_save_then_load_round_trips() -> void:
	var s := GameSettings.new(PATH)
	s.fullscreen = true
	s.vsync = false
	s.save()
	var s2 := GameSettings.new(PATH)
	s2.load()
	assert_bool(s2.fullscreen).is_true()
	assert_bool(s2.vsync).is_false()
```

- [ ] **Step 2: Run, confirm it fails**

Expected: FAIL — `GameSettings` class does not exist.

- [ ] **Step 3: Implement `game_settings.gd`**

```gdscript
# src/ui/shell/game_settings.gd
class_name GameSettings
extends RefCounted

const SECTION := "display"
const DEFAULT_PATH := "user://settings.cfg"

var path: String
var fullscreen: bool = false
var vsync: bool = true

func _init(p: String = DEFAULT_PATH) -> void:
	path = p

func load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	fullscreen = cfg.get_value(SECTION, "fullscreen", fullscreen)
	vsync = cfg.get_value(SECTION, "vsync", vsync)

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "fullscreen", fullscreen)
	cfg.set_value(SECTION, "vsync", vsync)
	cfg.save(path)

# Applies the current values to the OS window. Guarded so headless runs are no-ops-safe.
func apply() -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
	var vmode := DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(vmode)
```

- [ ] **Step 4: Run, confirm it passes**

Run `tests/test_game_settings.gd`. Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/ui/shell/game_settings.gd tests/test_game_settings.gd
git commit -m "feat: add GameSettings config persistence"
```

---

## Task 5: SettingsPanel

**Files:**
- Create: `src/ui/shell/settings_panel.gd` / `settings_panel.tscn`
- Test: `tests/test_settings_panel.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_settings_panel.gd
extends GdUnitTestSuite

func _spawn() -> SettingsPanel:
	var p: SettingsPanel = load("res://src/ui/shell/settings_panel.tscn").instantiate()
	add_child(p)
	auto_free(p)
	return p

func test_back_button_emits_back_pressed() -> void:
	var p := _spawn()
	var fired := [false]
	p.back_pressed.connect(func() -> void: fired[0] = true)
	p.get_node("%Back").pressed.emit()
	assert_bool(fired[0]).is_true()

func test_toggles_reflect_initial_settings() -> void:
	var p := _spawn()
	var s := GameSettings.new("user://test_settings_panel.cfg")
	s.fullscreen = true
	s.vsync = false
	p.bind(s)
	assert_bool(p.get_node("%Fullscreen").button_pressed).is_true()
	assert_bool(p.get_node("%Vsync").button_pressed).is_false()

func test_toggling_fullscreen_updates_and_saves_settings() -> void:
	var p := _spawn()
	var s := GameSettings.new("user://test_settings_panel.cfg")
	p.bind(s)
	p.get_node("%Fullscreen").button_pressed = true
	p.get_node("%Fullscreen").toggled.emit(true)
	assert_bool(s.fullscreen).is_true()
	var reloaded := GameSettings.new("user://test_settings_panel.cfg")
	reloaded.load()
	assert_bool(reloaded.fullscreen).is_true()
```

- [ ] **Step 2: Run, confirm it fails**

Expected: FAIL — scene/class does not exist.

- [ ] **Step 3: Create `settings_panel.tscn`**

Build a `Control` root named `SettingsPanel` filling the screen, with a centered `VBoxContainer`. Set `unique_name_in_owner = true` on the three interactive nodes so `%Back`, `%Fullscreen`, `%Vsync` resolve.

```
[gd_scene format=3 uid="uid://csettings001"]

[ext_resource type="Script" path="res://src/ui/shell/settings_panel.gd" id="1_set"]

[node name="SettingsPanel" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_set")

[node name="VBox" type="VBoxContainer" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -200.0
offset_top = -150.0
offset_right = 200.0
offset_bottom = 150.0
grow_horizontal = 2
grow_vertical = 2

[node name="Title" type="Label" parent="VBox"]
layout_mode = 2
text = "Settings"
horizontal_alignment = 1

[node name="Fullscreen" type="CheckButton" parent="VBox"]
unique_name_in_owner = true
layout_mode = 2
text = "Fullscreen"

[node name="Vsync" type="CheckButton" parent="VBox"]
unique_name_in_owner = true
layout_mode = 2
text = "VSync"

[node name="Back" type="Button" parent="VBox"]
unique_name_in_owner = true
layout_mode = 2
text = "Back"
```

- [ ] **Step 4: Create `settings_panel.gd`**

```gdscript
# src/ui/shell/settings_panel.gd
class_name SettingsPanel
extends Control

signal back_pressed

var _settings: GameSettings

@onready var _fullscreen: CheckButton = %Fullscreen
@onready var _vsync: CheckButton = %Vsync
@onready var _back: Button = %Back

func _ready() -> void:
	theme = preload("res://src/ui/theme/game_theme.tres")
	_back.pressed.connect(func() -> void: back_pressed.emit())
	_fullscreen.toggled.connect(_on_fullscreen_toggled)
	_vsync.toggled.connect(_on_vsync_toggled)
	JuicyButton.apply(_back)
	if _settings != null:
		_refresh()

# Binds the live settings object the panel reads from and writes to.
func bind(settings: GameSettings) -> void:
	_settings = settings
	if is_node_ready():
		_refresh()

func _refresh() -> void:
	_fullscreen.button_pressed = _settings.fullscreen
	_vsync.button_pressed = _settings.vsync

func _on_fullscreen_toggled(on: bool) -> void:
	if _settings == null: return
	_settings.fullscreen = on
	_settings.apply()
	_settings.save()

func _on_vsync_toggled(on: bool) -> void:
	if _settings == null: return
	_settings.vsync = on
	_settings.apply()
	_settings.save()
```

- [ ] **Step 5: Run, confirm it passes**

Run `tests/test_settings_panel.gd`. Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add src/ui/shell/settings_panel.gd src/ui/shell/settings_panel.tscn tests/test_settings_panel.gd
git commit -m "feat: add display SettingsPanel"
```

---

## Task 6: CreditsPanel (minimal)

**Files:**
- Create: `src/ui/shell/credits_panel.gd` / `credits_panel.tscn`
- Test: `tests/test_credits_panel.gd`

- [ ] **Step 1: Write the failing test**

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
```

- [ ] **Step 2: Run, confirm it fails**

Expected: FAIL — scene/class does not exist.

- [ ] **Step 3: Create `credits_panel.tscn`**

```
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

[node name="VBox" type="VBoxContainer" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -300.0
offset_top = -200.0
offset_right = 300.0
offset_bottom = 200.0
grow_horizontal = 2
grow_vertical = 2

[node name="Title" type="Label" parent="VBox"]
layout_mode = 2
text = "Credits"
horizontal_alignment = 1

[node name="Body" type="Label" parent="VBox"]
layout_mode = 2
text = "The Card Game
A WMsans project."
horizontal_alignment = 1

[node name="Back" type="Button" parent="VBox"]
unique_name_in_owner = true
layout_mode = 2
text = "Back"
```

- [ ] **Step 4: Create `credits_panel.gd`**

```gdscript
# src/ui/shell/credits_panel.gd
class_name CreditsPanel
extends Control

signal back_pressed

@onready var _back: Button = %Back

func _ready() -> void:
	theme = preload("res://src/ui/theme/game_theme.tres")
	_back.pressed.connect(func() -> void: back_pressed.emit())
	JuicyButton.apply(_back)
```

- [ ] **Step 5: Run, confirm it passes**

Run `tests/test_credits_panel.gd`. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/ui/shell/credits_panel.gd src/ui/shell/credits_panel.tscn tests/test_credits_panel.gd
git commit -m "feat: add minimal CreditsPanel"
```

---

## Task 7: LandingPanel (menu + drifting cards)

**Files:**
- Create: `src/ui/shell/landing_panel.gd` / `landing_panel.tscn`
- Test: `tests/test_landing_panel.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_landing_panel.gd
extends GdUnitTestSuite

func _spawn() -> LandingPanel:
	var p: LandingPanel = load("res://src/ui/shell/landing_panel.tscn").instantiate()
	add_child(p)
	auto_free(p)
	return p

func test_play_button_emits_play_pressed() -> void:
	var p := _spawn()
	var fired := [false]
	p.play_pressed.connect(func() -> void: fired[0] = true)
	p.get_node("%Play").pressed.emit()
	assert_bool(fired[0]).is_true()

func test_each_menu_button_emits_its_intent() -> void:
	var p := _spawn()
	var seen := {}
	p.compendium_pressed.connect(func() -> void: seen["c"] = true)
	p.settings_pressed.connect(func() -> void: seen["s"] = true)
	p.quit_pressed.connect(func() -> void: seen["q"] = true)
	p.credits_pressed.connect(func() -> void: seen["cr"] = true)
	p.get_node("%Compendium").pressed.emit()
	p.get_node("%Settings").pressed.emit()
	p.get_node("%Quit").pressed.emit()
	p.get_node("%Credits").pressed.emit()
	assert_bool(seen.has("c") and seen.has("s") and seen.has("q") and seen.has("cr")).is_true()

func test_creates_drifting_card_sprites() -> void:
	var p := _spawn()
	var cards: Node = p.get_node("DriftingCards")
	assert_int(cards.get_child_count()).is_equal(p.DRIFT_COUNT)

func test_foreground_offset_moves_drifting_cards_container() -> void:
	var p := _spawn()
	p.on_foreground_offset(Vector2(11, 13))
	assert_vector(p.get_node("DriftingCards").position).is_equal(Vector2(11, 13))
```

- [ ] **Step 2: Run, confirm it fails**

Expected: FAIL — scene/class does not exist.

- [ ] **Step 3: Create `landing_panel.tscn`**

Bottom-left logo + vertical menu; an empty `DriftingCards` node the script fills. Mark interactive buttons unique.

```
[gd_scene format=3 uid="uid://clanding001"]

[ext_resource type="Script" path="res://src/ui/shell/landing_panel.gd" id="1_land"]

[node name="LandingPanel" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_land")

[node name="DriftingCards" type="Node2D" parent="."]

[node name="Logo" type="Label" parent="."]
layout_mode = 0
offset_left = 90.0
offset_top = 560.0
offset_right = 700.0
offset_bottom = 700.0
text = "THE CARD
GAME"
theme_override_font_sizes/font_size = 72

[node name="Menu" type="VBoxContainer" parent="."]
layout_mode = 0
offset_left = 96.0
offset_top = 720.0
offset_right = 396.0
offset_bottom = 980.0
theme_override_constants/separation = 12

[node name="Play" type="Button" parent="Menu"]
unique_name_in_owner = true
layout_mode = 2
text = "Play"

[node name="Compendium" type="Button" parent="Menu"]
unique_name_in_owner = true
layout_mode = 2
text = "Compendium"

[node name="Settings" type="Button" parent="Menu"]
unique_name_in_owner = true
layout_mode = 2
text = "Settings"

[node name="Quit" type="Button" parent="Menu"]
unique_name_in_owner = true
layout_mode = 2
text = "Quit"

[node name="Credits" type="Button" parent="."]
unique_name_in_owner = true
layout_mode = 0
offset_left = 1760.0
offset_top = 1020.0
offset_right = 1900.0
offset_bottom = 1060.0
text = "Credits"
flat = true
```

- [ ] **Step 4: Create `landing_panel.gd`**

Drifting cards are `Sprite2D` card-backs scattered in the right two-thirds, each slowly drifting via a looping tween; `on_foreground_offset` parallaxes the whole container (shake inherited for free).

```gdscript
# src/ui/shell/landing_panel.gd
class_name LandingPanel
extends Control

signal play_pressed
signal compendium_pressed
signal settings_pressed
signal quit_pressed
signal credits_pressed

const DRIFT_COUNT := 5
const CARD_BACK := preload("res://src/ui/assets/frames/back.png")

@onready var _drift: Node2D = $DriftingCards

func _ready() -> void:
	theme = preload("res://src/ui/theme/game_theme.tres")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	%Play.pressed.connect(func() -> void: play_pressed.emit())
	%Compendium.pressed.connect(func() -> void: compendium_pressed.emit())
	%Settings.pressed.connect(func() -> void: settings_pressed.emit())
	%Quit.pressed.connect(func() -> void: quit_pressed.emit())
	%Credits.pressed.connect(func() -> void: credits_pressed.emit())
	for b in [%Play, %Compendium, %Settings, %Quit, %Credits]:
		JuicyButton.apply(b)
	_spawn_drifting_cards()

func _spawn_drifting_cards() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260531
	for i in range(DRIFT_COUNT):
		var s := Sprite2D.new()
		s.texture = CARD_BACK
		s.scale = Vector2.ONE * rng.randf_range(0.5, 0.9)
		var base := Vector2(rng.randf_range(1000, 1750), rng.randf_range(150, 800))
		s.position = base
		s.rotation = rng.randf_range(-0.3, 0.3)
		_drift.add_child(s)
		var t := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		var dy := rng.randf_range(20, 60)
		t.tween_property(s, "position:y", base.y + dy, rng.randf_range(3.0, 6.0))
		t.tween_property(s, "position:y", base.y, rng.randf_range(3.0, 6.0))

# Called by the shell each frame with BalatroBg's foreground offset (parallax + shake).
func on_foreground_offset(offset: Vector2) -> void:
	_drift.position = offset
```

- [ ] **Step 5: Run, confirm it passes**

Run `tests/test_landing_panel.gd`. Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add src/ui/shell/landing_panel.gd src/ui/shell/landing_panel.tscn tests/test_landing_panel.gd
git commit -m "feat: add LandingPanel with drifting cards"
```

---

## Task 8: DeckSelectPanel (leader showcase + tray + seed)

**Files:**
- Create: `src/ui/shell/deck_select_panel.gd` / `deck_select_panel.tscn`
- Test: `tests/test_deck_select_panel.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_deck_select_panel.gd
extends GdUnitTestSuite

func _spawn() -> DeckSelectPanel:
	var p: DeckSelectPanel = load("res://src/ui/shell/deck_select_panel.tscn").instantiate()
	add_child(p)
	auto_free(p)
	return p

func test_deck_path_for_color() -> void:
	assert_str(DeckSelectPanel.deck_path("strike")).is_equal("res://src/data/decks/strike.csv")

func test_defaults_to_strike_vs_raccoon() -> void:
	var p := _spawn()
	assert_str(p.my_deck).is_equal("strike")
	assert_str(p.opp_deck).is_equal("raccoon")

func test_selecting_my_deck_updates_state_and_emits_change() -> void:
	var p := _spawn()
	var changed := [false]
	p.deck_changed.connect(func() -> void: changed[0] = true)
	p.select_my_deck("audio")
	assert_str(p.my_deck).is_equal("audio")
	assert_bool(changed[0]).is_true()

func test_showcase_shows_selected_leader_name() -> void:
	var p := _spawn()
	p.select_my_deck("raccoon")
	# Raccoon deck's leader (row 1 of raccoon.csv) is named "Raccoon".
	assert_str(p.get_node("%LeaderName").text).contains("Raccoon")

func test_blank_seed_is_randomized() -> void:
	var p := _spawn()
	p.get_node("%Seed").text = ""
	var v := p.seed_value()
	assert_int(v).is_greater_equal(0)

func test_explicit_seed_is_parsed() -> void:
	var p := _spawn()
	p.get_node("%Seed").text = "1234"
	assert_int(p.seed_value()).is_equal(1234)

func test_embark_emits_choices() -> void:
	var p := _spawn()
	p.select_my_deck("writing")
	p.select_opp_deck("audio")
	p.get_node("%Seed").text = "77"
	var got := {}
	p.embark.connect(func(seed: int, mine: String, opp: String) -> void:
		got = {"seed": seed, "mine": mine, "opp": opp})
	p.get_node("%Embark").pressed.emit()
	assert_int(got["seed"]).is_equal(77)
	assert_str(got["mine"]).is_equal("writing")
	assert_str(got["opp"]).is_equal("audio")

func test_back_emits_back_pressed() -> void:
	var p := _spawn()
	var fired := [false]
	p.back_pressed.connect(func() -> void: fired[0] = true)
	p.get_node("%Back").pressed.emit()
	assert_bool(fired[0]).is_true()
```

- [ ] **Step 2: Run, confirm it fails**

Expected: FAIL — scene/class does not exist.

- [ ] **Step 3: Create `deck_select_panel.tscn`**

Showcase on the left (leader image + name + text), tray on the right (4 my-deck buttons + opponent buttons), bottom bar (Back / Seed / Embark). Containers below build deck buttons at runtime so the scene stays small. Unique-name the nodes the script and tests touch.

```
[gd_scene format=3 uid="uid://cdeckselect01"]

[ext_resource type="Script" path="res://src/ui/shell/deck_select_panel.gd" id="1_ds"]

[node name="DeckSelectPanel" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_ds")

[node name="LeaderArt" type="TextureRect" parent="."]
unique_name_in_owner = true
layout_mode = 0
offset_left = 120.0
offset_top = 120.0
offset_right = 620.0
offset_bottom = 820.0
expand_mode = 1
stretch_mode = 5

[node name="LeaderName" type="Label" parent="."]
unique_name_in_owner = true
layout_mode = 0
offset_left = 120.0
offset_top = 60.0
offset_right = 620.0
offset_bottom = 110.0
theme_override_font_sizes/font_size = 40

[node name="LeaderText" type="Label" parent="."]
unique_name_in_owner = true
layout_mode = 0
offset_left = 120.0
offset_top = 830.0
offset_right = 760.0
offset_bottom = 980.0
autowrap_mode = 3

[node name="MyDeckLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 1300.0
offset_top = 120.0
offset_right = 1800.0
offset_bottom = 160.0
text = "Your Deck"

[node name="MyDeckRow" type="VBoxContainer" parent="."]
unique_name_in_owner = true
layout_mode = 0
offset_left = 1300.0
offset_top = 170.0
offset_right = 1800.0
offset_bottom = 470.0

[node name="OppLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 1300.0
offset_top = 500.0
offset_right = 1800.0
offset_bottom = 540.0
text = "Opponent"

[node name="OppRow" type="VBoxContainer" parent="."]
unique_name_in_owner = true
layout_mode = 0
offset_left = 1300.0
offset_top = 550.0
offset_right = 1800.0
offset_bottom = 850.0

[node name="Back" type="Button" parent="."]
unique_name_in_owner = true
layout_mode = 0
offset_left = 120.0
offset_top = 1000.0
offset_right = 320.0
offset_bottom = 1050.0
text = "Back"

[node name="Seed" type="LineEdit" parent="."]
unique_name_in_owner = true
layout_mode = 0
offset_left = 810.0
offset_top = 1000.0
offset_right = 1110.0
offset_bottom = 1050.0
placeholder_text = "Seed (optional)"

[node name="Embark" type="Button" parent="."]
unique_name_in_owner = true
layout_mode = 0
offset_left = 1600.0
offset_top = 1000.0
offset_right = 1800.0
offset_bottom = 1050.0
text = "Embark"
```

- [ ] **Step 4: Create `deck_select_panel.gd`**

```gdscript
# src/ui/shell/deck_select_panel.gd
class_name DeckSelectPanel
extends Control

signal back_pressed
signal embark(seed_value: int, my_deck: String, opp_deck: String)
signal deck_changed  # shell connects this to BalatroBg.add_trauma for the pick shake

const COLORS := ["strike", "raccoon", "writing", "audio"]

var my_deck: String = "strike"
var opp_deck: String = "raccoon"

var _my_buttons := {}
var _opp_buttons := {}

func _ready() -> void:
	theme = preload("res://src/ui/theme/game_theme.tres")
	for c in COLORS:
		_my_buttons[c] = _make_deck_button(%MyDeckRow, c, select_my_deck)
		_opp_buttons[c] = _make_deck_button(%OppRow, c, select_opp_deck)
	%Back.pressed.connect(func() -> void: back_pressed.emit())
	%Embark.pressed.connect(_on_embark)
	JuicyButton.apply(%Back)
	JuicyButton.apply(%Embark)
	_refresh()

static func deck_path(color: String) -> String:
	return "res://src/data/decks/%s.csv" % color

func _make_deck_button(row: VBoxContainer, color: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = color.capitalize()
	b.pressed.connect(cb.bind(color))
	row.add_child(b)
	JuicyButton.apply(b)
	return b

func select_my_deck(color: String) -> void:
	my_deck = color
	deck_changed.emit()
	_refresh()

func select_opp_deck(color: String) -> void:
	opp_deck = color
	deck_changed.emit()
	_refresh()

func _refresh() -> void:
	for c in COLORS:
		_my_buttons[c].modulate = UiPalette.ACCENT if c == my_deck else Color.WHITE
		_opp_buttons[c].modulate = UiPalette.ACCENT if c == opp_deck else Color.WHITE
	_refresh_showcase()

func _refresh_showcase() -> void:
	var art_path := CardArt.leader_art_path(my_deck)
	%LeaderArt.texture = load(art_path) if art_path != "" else null
	var leader := _leader_def(my_deck)
	%LeaderName.text = leader.name if leader != null else my_deck.capitalize()
	%LeaderText.text = leader.ability_text if leader != null else ""

func _leader_def(color: String) -> CardDefinition:
	for d in CardDatabase.load_deck(deck_path(color), color):
		if d.type == Enums.CardType.LEADER:
			return d
	return null

func seed_value() -> int:
	var txt: String = %Seed.text.strip_edges()
	return int(txt) if txt.is_valid_int() else randi()

func _on_embark() -> void:
	embark.emit(seed_value(), my_deck, opp_deck)
```

- [ ] **Step 5: Run, confirm it passes**

Run `tests/test_deck_select_panel.gd`. Expected: PASS (9 tests).

- [ ] **Step 6: Commit**

```bash
git add src/ui/shell/deck_select_panel.gd src/ui/shell/deck_select_panel.tscn tests/test_deck_select_panel.gd
git commit -m "feat: add DeckSelectPanel with leader showcase"
```

---

## Task 9: AppShell (background owner + navigation + match launch)

**Files:**
- Create: `src/ui/shell/app_shell.gd` / `app_shell.tscn`
- Test: `tests/test_app_shell.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_app_shell.gd
extends GdUnitTestSuite

func _spawn() -> AppShell:
	# add_child runs _ready synchronously, which mounts the landing panel
	# (mounting is synchronous via remove_child + add_child), so no await needed.
	var s: AppShell = load("res://src/ui/shell/app_shell.tscn").instantiate()
	add_child(s)
	auto_free(s)
	return s

func _content_child(s: AppShell) -> Node:
	var content: Node = s.get_node("ContentLayer")
	assert_int(content.get_child_count()).is_equal(1)
	return content.get_child(0)

func test_starts_on_landing_panel() -> void:
	var s := _spawn()
	assert_object(_content_child(s)).is_instanceof(LandingPanel)

func test_play_navigates_to_deck_select() -> void:
	var s := _spawn()
	(_content_child(s) as LandingPanel).play_pressed.emit()
	assert_object(_content_child(s)).is_instanceof(DeckSelectPanel)

func test_settings_navigates_to_settings_panel() -> void:
	var s := _spawn()
	(_content_child(s) as LandingPanel).settings_pressed.emit()
	assert_object(_content_child(s)).is_instanceof(SettingsPanel)

func test_compendium_navigates_to_card_gallery() -> void:
	var s := _spawn()
	(_content_child(s) as LandingPanel).compendium_pressed.emit()
	assert_object(_content_child(s)).is_instanceof(CardGallery)

func test_embark_mounts_match_with_injected_background() -> void:
	var s := _spawn()
	s.start_match(99, "strike", "raccoon")
	var m: Node = _content_child(s)
	assert_str(m.name).is_equal("Match")
	# Background is the shell's single BalatroBg, injected into the match.
	assert_object(m._bg).is_same(s.get_node("BalatroBg"))

func test_deck_change_adds_trauma_to_background() -> void:
	var s := _spawn()
	(_content_child(s) as LandingPanel).play_pressed.emit()
	var ds: DeckSelectPanel = _content_child(s)
	ds.select_my_deck("audio")
	assert_float((s.get_node("BalatroBg") as BalatroBg).get_trauma()).is_greater(0.0)
```

- [ ] **Step 2: Run, confirm it fails**

Expected: FAIL — scene/class does not exist.

- [ ] **Step 3: Create `app_shell.tscn`**

Root `Control` named `AppShell`, with the persistent `BalatroBg` behind a `ContentLayer`.

```
[gd_scene format=3 uid="uid://cappshell001"]

[ext_resource type="Script" path="res://src/ui/shell/app_shell.gd" id="1_shell"]
[ext_resource type="PackedScene" path="res://src/ui/match/balatro_bg.tscn" id="2_bg"]

[node name="AppShell" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_shell")

[node name="BalatroBg" parent="." instance=ExtResource("2_bg")]

[node name="ContentLayer" type="Control" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
```

- [ ] **Step 4: Create `app_shell.gd`**

The shell owns navigation. It mounts one panel at a time with a quick fade, wires each panel's intent signals, forwards `foreground_offset` to the landing panel's drifting cards, connects deck-pick shake, injects the background into Match, and applies persisted settings on ready.

```gdscript
# src/ui/shell/app_shell.gd
class_name AppShell
extends Control

const LANDING := preload("res://src/ui/shell/landing_panel.tscn")
const DECK_SELECT := preload("res://src/ui/shell/deck_select_panel.tscn")
const SETTINGS := preload("res://src/ui/shell/settings_panel.tscn")
const CREDITS := preload("res://src/ui/shell/credits_panel.tscn")
const COMPENDIUM := preload("res://src/ui/card/card_gallery.tscn")
const MATCH := preload("res://src/ui/match/match.tscn")

const DECK_PICK_TRAUMA := 0.8
const FADE_TIME := 0.2

@onready var _bg: BalatroBg = $BalatroBg
@onready var _content: Control = $ContentLayer

var _settings := GameSettings.new()

func _ready() -> void:
	theme = preload("res://src/ui/theme/game_theme.tres")
	_settings.load()
	_settings.apply()
	goto_landing()

# --- navigation -----------------------------------------------------------

func goto_landing() -> void:
	var p: LandingPanel = _mount(LANDING)
	p.play_pressed.connect(goto_deck_select)
	p.compendium_pressed.connect(goto_compendium)
	p.settings_pressed.connect(goto_settings)
	p.credits_pressed.connect(goto_credits)
	p.quit_pressed.connect(func() -> void: get_tree().quit())
	_bg.foreground_offset.connect(p.on_foreground_offset)

func goto_deck_select() -> void:
	var p: DeckSelectPanel = _mount(DECK_SELECT)
	p.back_pressed.connect(goto_landing)
	p.deck_changed.connect(func() -> void: _bg.add_trauma(DECK_PICK_TRAUMA))
	p.embark.connect(start_match)

func goto_settings() -> void:
	var p: SettingsPanel = _mount(SETTINGS)
	p.bind(_settings)
	p.back_pressed.connect(goto_landing)

func goto_credits() -> void:
	var p: CreditsPanel = _mount(CREDITS)
	p.back_pressed.connect(goto_landing)

func goto_compendium() -> void:
	var gallery: CardGallery = _mount(COMPENDIUM)
	# CardGallery has no back button of its own; add one so the user can return.
	var back := Button.new()
	back.text = "Back"
	back.position = Vector2(40, 40)
	back.pressed.connect(goto_landing)
	gallery.add_child(back)
	JuicyButton.apply(back)

func start_match(seed_value: int, my_deck: String, opp_deck: String) -> void:
	var m: Node = _mount(MATCH)
	m.attach_background(_bg)
	m.quit_to_menu.connect(goto_landing)
	m.start_game(seed_value, DeckSelectPanel.deck_path(my_deck), DeckSelectPanel.deck_path(opp_deck))

# --- internals ------------------------------------------------------------

# Frees the current panel and fades in the new one. Returns the new instance.
# Detaches synchronously (remove_child) before queue_free so the content layer
# holds exactly one child immediately — safe to call from a panel's own signal,
# since the freed panel is only detached (not destroyed) mid-emit.
func _mount(scene: PackedScene) -> Node:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	var inst: Node = scene.instantiate()
	_content.add_child(inst)
	if inst is CanvasItem:
		inst.modulate.a = 0.0
		create_tween().tween_property(inst, "modulate:a", 1.0, FADE_TIME)
	return inst
```

- [ ] **Step 5: Run, confirm it passes**

Run `tests/test_app_shell.gd`. Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

```bash
git add src/ui/shell/app_shell.gd src/ui/shell/app_shell.tscn tests/test_app_shell.gd
git commit -m "feat: add AppShell navigation hub with persistent background"
```

---

## Task 10: Make AppShell the main scene & remove the old menu

**Files:**
- Modify: `project.godot`
- Delete: `src/ui/menu/main_menu.gd`, `src/ui/menu/main_menu.tscn`, `src/ui/menu/main_menu.gd.uid`
- Delete: `tests/test_main_menu.gd` (its behaviour now lives in DeckSelectPanel tests)

- [ ] **Step 1: Repoint the main scene**

In `project.godot`, change the `[application]` line:

```
run/main_scene="res://src/ui/shell/app_shell.tscn"
```

- [ ] **Step 2: Delete the superseded menu files**

```bash
git rm src/ui/menu/main_menu.gd src/ui/menu/main_menu.tscn src/ui/menu/main_menu.gd.uid tests/test_main_menu.gd
```

- [ ] **Step 3: Confirm nothing else references the old menu**

Run:

```bash
grep -rn "main_menu\|MainMenu" src tests
```

Expected: no matches (the gallery/match no longer reference it). If any remain, update them to use `AppShell`/`DeckSelectPanel` equivalents before continuing.

- [ ] **Step 4: Re-import and run the FULL suite**

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: all suites PASS, including the new shell/panel suites and the unchanged engine/match suites.

- [ ] **Step 5: Commit**

```bash
git add project.godot
git commit -m "feat: make AppShell the main scene; remove legacy main menu"
```

---

## Self-Review (completed during planning)

**Spec coverage:**
- Persistent `AppShell` + swappable panels + single `BalatroBg` → Task 9.
- Match as a panel sharing the background → Tasks 2, 9.
- Parallaxed shake in `BalatroBg` → Task 1; triggered on deck pick → Tasks 8 (`deck_changed`) + 9 (`add_trauma`).
- Landing layout A (bottom-left menu + drifting parallaxing cards + Credits corner) → Task 7; Credits panel → Task 6.
- Deck-select layout B (leader image + name + text via `CardArt.leader_art_path`/CSV, deck + opponent + seed, Embark/Back) → Task 8.
- Settings (display-only, persisted to `user://settings.cfg`) → Tasks 4, 5; applied on shell ready → Task 9.
- Compendium reuse → Task 9 (`goto_compendium`).
- Game-over "Main Menu" return → Task 3 (signal) + Task 9 (`quit_to_menu` → `goto_landing`).
- `run/main_scene` repoint + legacy removal → Task 10.
- GdUnit4 tests for every unit → Tasks 1–9; full-suite gate → Task 10.

**Placeholder scan:** none — every code/test step contains full content.

**Type/name consistency:** `attach_background` (Tasks 2, 9), `add_trauma`/`get_trauma` (Tasks 1, 9), `deck_changed`/`select_my_deck`/`select_opp_deck`/`seed_value`/`deck_path`/`embark` (Tasks 8, 9), `quit_to_menu`/`main_menu` (Tasks 3, 9), `on_foreground_offset` (Tasks 7, 9), `bind` (Tasks 5, 9) all match across tasks.
```
