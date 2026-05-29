# Game UI — Juice & Static Table (Phases 3–4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `CardView` Balatro-style tactile feel (hover tilt + scale/raise, dynamic shadow, drag wobble, dissolve-on-death) and the input signals later phases consume; then build the read-only table — hand fan, board rows, piles + leader slots, ticket tray, opponent backs — laid out from a seeded `GameState` with **no interaction yet**.

**Architecture:** The UI stays a pure view over `GameState`; nothing here mutates game state or sends `Action`s. Juice is encapsulated inside `CardView`. Table widgets are thin scripts over `CardView`s. The only piece with real logic is `board_layout.gd` — a pure `zone+index→Transform2D` function, fully unit-tested without a scene.

**Tech Stack:** Godot 4.6 (GL Compatibility), GDScript, GdUnit4 for tests.

**Spec:** `docs/superpowers/specs/2026-05-29-game-ui-design.md` (this plan covers spec §8 phases 3–4).

**Reference (juice):** `/home/jeremy/Development/Godot/godot_balatro_ui/scenes/balatro/` — `scripts/card.gd` (hover/drag/oscillator/dissolve), `card.tscn` (Shadow + shader material wiring), `scenes/shared/shaders/dissolve.gdshader` and `fake_3D.gdshader`. We adapt these from a `Button` to our `Control`-based `CardView`.

---

## Conventions used in every task

- **Canonical deck path:** `res://src/data/decks/<color>.csv` (`strike`, `raccoon`, `writing`, `audio`).
- **Run a single suite:**
  ```bash
  godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a <suite-path>
  ```
  Exit code `0` = all pass; `100` = failures. If a run reports `Could not find type "GdUnitTestCIRunner"`, build the class cache once with `godot --headless --path . --import`.
- **Headless reality:** animations/`Tween`s and `InputEvent` routing are unreliable headless. Tests here assert **state and contract** (signals exist, methods complete, layout math), **not** pixels or in-flight tween values. Visual tuning is explicit manual steps.
- **Commit** after each task (steps below specify exact files).

---

## File structure (this plan)

```
src/ui/assets/shaders/dissolve.gdshader      # CREATE: copied from reference
src/ui/assets/shaders/fake_3D.gdshader       # CREATE: copied from reference (hover tilt)
src/ui/assets/shadow.png                      # CREATE: soft shadow sprite (copied/placeholder)
src/ui/card/card_view.tscn                    # MODIFY: wrap visuals in CanvasGroup; add Shadow; materials
src/ui/card/card_view.gd                      # MODIFY: signals + hover/drag/shadow/dissolve juice
tests/test_card_view.gd                       # MODIFY: signal contract + dissolve smoke (binding tests stay green)

src/ui/table/board_layout.gd                  # CREATE: pure zone+index -> Transform2D
src/ui/table/hand_view.gd                     # CREATE: fans player's CardViews
src/ui/table/board_view.gd                    # CREATE: centered minion row
src/ui/table/pile_view.gd / .tscn             # CREATE: deck/discard stacks + count badge + leader slot
src/ui/table/ticket_tray.gd / .tscn           # CREATE: pips total vs tapped
src/ui/table/opponent_hand.gd                 # CREATE: N face-down backs
src/ui/table/table_view.tscn / .gd            # CREATE: debug scene that renders a seeded GameState
tests/test_board_layout.gd                    # CREATE: layout math unit tests
tests/test_table_view.gd                      # CREATE: counts match a seeded GameState
```

---

# Phase 3 — CardView juice

## Task 1: Import shaders + shadow asset

Bring the reference dissolve + fake-3D shaders and a shadow sprite into the project so the scene can reference them as `res://` resources.

**Files:**
- Create: `src/ui/assets/shaders/dissolve.gdshader`, `src/ui/assets/shaders/fake_3D.gdshader`
- Create: `src/ui/assets/shadow.png`

- [ ] **Step 1: Copy the shaders + a shadow sprite**

```bash
mkdir -p src/ui/assets/shaders
REF="/home/jeremy/Development/Godot/godot_balatro_ui/scenes/shared/shaders"
cp "$REF/dissolve.gdshader" src/ui/assets/shaders/dissolve.gdshader
cp "$REF/fake_3D.gdshader"  src/ui/assets/shaders/fake_3D.gdshader
# Reuse the card-back as a stand-in shadow sprite (tinted black + low alpha in-scene).
cp src/ui/assets/frames/back.png src/ui/assets/shadow.png
ls -1 src/ui/assets/shaders/ src/ui/assets/shadow.png
```
Expected: both `.gdshader` files and `shadow.png` listed.

- [ ] **Step 2: Import**

```bash
godot --headless --path . --import
```
Expected: completes with no shader compile errors mentioning `dissolve` / `fake_3D`.

- [ ] **Step 3: Commit**

```bash
git add src/ui/assets/shaders src/ui/assets/shadow.png
git commit -m "assets: import dissolve + fake_3D shaders and shadow sprite for card juice"
```

---

## Task 2: Restructure `card_view.tscn` for juice (CanvasGroup + Shadow + materials)

The dissolve shader must composite the **whole** card (frame + overlays) as one image, so all visual children move under a `CanvasGroup`. A `Shadow` sibling sits behind. The dissolve material lives on the `CanvasGroup`; the fake-3D tilt material lives on the `Frame` (it carries the art).

> `find_child(...)` in the existing tests is recursive, so re-parenting nodes under `Visuals` keeps every binding test green. Only the `@onready` paths in `card_view.gd` change (Task 3).

**Files:**
- Modify: `src/ui/card/card_view.tscn`

- [ ] **Step 1: Re-parent visuals under a CanvasGroup**

Open `src/ui/card/card_view.tscn` in the editor. Target tree:

```
CardView           (Control)        # root; custom_minimum_size 350 x 490; pivot_offset = (175, 245); mouse_filter = Stop
├── Shadow         (TextureRect)    # show_behind_parent = true; texture = shadow.png; modulate black; self_modulate a≈0.25; offset down ~24px
└── Visuals        (CanvasGroup)    # full rect; material = dissolve ShaderMaterial (local to scene)
    ├── Frame         (TextureRect)  # material = fake_3D ShaderMaterial (local to scene); existing texture/stretch
    ├── ArtTexture    (TextureRect)
    ├── NameLabel     (Label)
    ├── DamageLabel   (Label)
    ├── HealthLabel   (Label)
    ├── TicketLabel   (Label)
    ├── DiscardLabel  (Label)
    ├── AbilityText   (RichTextLabel / AutoSizeRichTextLabel)
    └── FlavorLabel   (Label)
```

Keep every overlay node's name and its calibrated offsets from the foundation plan. Move them (with offsets intact) under `Visuals`.

- [ ] **Step 2: Wire the materials**

- On `Visuals` (CanvasGroup): add a new `ShaderMaterial`, **Local to Scene = on**, shader = `res://src/ui/assets/shaders/dissolve.gdshader`. Set `dissolve_value = 1.0` (1 = fully visible), `burn_size = 0.03`, `burn_color = (1.5, 0.92, 0, 1)`, and a `NoiseTexture2D` (FastNoiseLite, frequency ≈ 0.0021) for `dissolve_texture`.
- On `Frame` (TextureRect): add a `ShaderMaterial`, **Local to Scene = on**, shader = `res://src/ui/assets/shaders/fake_3D.gdshader`. Set `rect_size` ≈ (350, 490), `fov = 90`, `cull_back = true`, `x_rot = 0`, `y_rot = 0`, `inset = 0`.

Set the root `CardView`'s `pivot_offset` to its center (175, 245) so hover scale/rotation pivots about the middle. Confirm `mouse_filter = Stop`.

- [ ] **Step 3: Verify the scene loads**

```bash
godot --headless --path . --import
```
Expected: completes; no errors mentioning `card_view.tscn`.

- [ ] **Step 4: Commit**

```bash
git add src/ui/card/card_view.tscn
git commit -m "feat: CardView scene wired for juice (CanvasGroup dissolve, fake-3D frame, shadow)"
```

---

## Task 3: `card_view.gd` — signals + hover/drag/shadow/dissolve

Adapt the reference `card.gd` to our `Control`. Add the input **signals** later phases consume and the juice behaviors, while keeping all existing data binding intact.

**Files:**
- Modify: `src/ui/card/card_view.gd`
- Test: `tests/test_card_view.gd`

- [ ] **Step 1: Update `@onready` paths and add the signal contract**

Change the existing `@onready` node paths to the new `Visuals/...` parents, and add the shadow + signals. At the top of `card_view.gd`, after the `STAT_*` consts:

```gdscript
signal hovered(card_view: CardView)
signal unhovered(card_view: CardView)
signal drag_started(card_view: CardView)
signal drag_released(card_view: CardView, at: Vector2)
signal clicked(card_view: CardView)

@export var angle_max: float = 12.0          # hover tilt range (deg)
@export var hover_scale: float = 1.12
@export var spring: float = 150.0            # drag wobble oscillator
@export var damp: float = 10.0
@export var velocity_multiplier: float = 1.0

@onready var _visuals: CanvasGroup = $Visuals
@onready var _shadow: TextureRect = $Shadow
@onready var _frame: TextureRect = $Visuals/Frame
@onready var _art: TextureRect = $Visuals/ArtTexture
@onready var _name: Label = $Visuals/NameLabel
@onready var _damage: Label = $Visuals/DamageLabel
@onready var _health: Label = $Visuals/HealthLabel
@onready var _ticket: Label = $Visuals/TicketLabel
@onready var _discard: Label = $Visuals/DiscardLabel
@onready var _ability: RichTextLabel = $Visuals/AbilityText
@onready var _flavor: Label = $Visuals/FlavorLabel
```

(Keep `_instance` / `_face_down` and the whole `setup` / `set_face_down` / `_refresh` / `_set_overlays_visible` / `_stat_color` / `_bold_keywords` body unchanged.)

- [ ] **Step 2: Add hover, drag, shadow, and dissolve behavior**

Append to `card_view.gd`:

```gdscript
var _dragging: bool = false
var _displacement: float = 0.0
var _osc_velocity: float = 0.0
var _last_pos: Vector2
var _interactive: bool = true   # hand/board cards true; preview cards false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

func set_interactive(v: bool) -> void:
	_interactive = v

func _process(delta: float) -> void:
	_handle_shadow()
	if _dragging:
		_wobble(delta)

func _handle_shadow() -> void:
	var center := get_viewport_rect().size * 0.5
	var dist := global_position.x - center.x
	_shadow.position.x = lerp(0.0, -sign(dist) * 40.0, abs(dist / maxf(center.x, 1.0)))

func _wobble(delta: float) -> void:
	var velocity := (position - _last_pos) / maxf(delta, 0.0001)
	_last_pos = position
	_osc_velocity += velocity.normalized().x * velocity_multiplier
	var force := -spring * _displacement - damp * _osc_velocity
	_osc_velocity += force * delta
	_displacement += _osc_velocity * delta
	rotation = _displacement

func _on_mouse_entered() -> void:
	if not _interactive or _dragging:
		return
	hovered.emit(self)
	var t := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	t.tween_property(self, "scale", Vector2(hover_scale, hover_scale), 0.4)

func _on_mouse_exited() -> void:
	if not _interactive:
		return
	unhovered.emit(self)
	_frame.material.set_shader_parameter("x_rot", 0.0)
	_frame.material.set_shader_parameter("y_rot", 0.0)
	var t := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	t.tween_property(self, "scale", Vector2.ONE, 0.45)

func _on_gui_input(event: InputEvent) -> void:
	if not _interactive:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_last_pos = position
			_displacement = 0.0
			_osc_velocity = 0.0
			drag_started.emit(self)
		else:
			if _dragging:
				_dragging = false
				clicked.emit(self)
				drag_released.emit(self, get_global_mouse_position())
				var t := create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
				t.tween_property(self, "rotation", 0.0, 0.3)
	elif event is InputEventMouseMotion and not _dragging:
		var lx := remap(event.position.x, 0.0, size.x, 0.0, 1.0)
		var ly := remap(event.position.y, 0.0, size.y, 0.0, 1.0)
		_frame.material.set_shader_parameter("y_rot", rad_to_deg(lerp_angle(-deg_to_rad(angle_max), deg_to_rad(angle_max), lx)))
		_frame.material.set_shader_parameter("x_rot", rad_to_deg(lerp_angle(deg_to_rad(angle_max), -deg_to_rad(angle_max), ly)))

# Dissolve out; returns the Tween so callers can await it before freeing the node.
func dissolve() -> Tween:
	var t := create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(_visuals.material, "shader_parameter/dissolve_value", 0.0, 0.8).from(1.0)
	t.parallel().tween_property(_shadow, "self_modulate:a", 0.0, 0.8)
	return t
```

> Note: when a `CardView` is dragged it is reparented to a top-level layer by `hand_view` (Phase 4 / `Match`), so `position` here is meaningful for the wobble. Until then dragging just wobbles in place — acceptable for the milestone.

- [ ] **Step 3: Update tests — keep bindings green, add contract + dissolve smoke**

The existing binding tests in `tests/test_card_view.gd` still pass unchanged (recursive `find_child`). Add:

```gdscript
func test_exposes_input_signals() -> void:
	var cv := _spawn()
	for sig in ["hovered", "unhovered", "drag_started", "drag_released", "clicked"]:
		assert_bool(cv.has_signal(sig)).override_failure_message("missing signal %s" % sig).is_true()

func test_dissolve_returns_tween_and_completes() -> void:
	var def: CardDefinition = _strike_defs()[0]
	var cv := _spawn()
	cv.setup(_make(def))
	var t := cv.dissolve()
	assert_object(t).is_not_null()
	# Drive the tween to completion without relying on frame timing.
	while t.is_valid() and t.is_running():
		t.custom_step(0.1)
	assert_float(cv.find_child("Visuals").material.get_shader_parameter("dissolve_value")).is_equal_approx(0.0, 0.01)
```

- [ ] **Step 4: Run the CardView suite**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_card_view.gd
```
Expected: PASS, exit `0`.

- [ ] **Step 5: Manual juice check (editor)**

Open `src/ui/card/card_gallery.tscn`, run (F6). Confirm: hovering a card scales it up + tilts toward the cursor; the shadow shifts with screen position; pressing+dragging wobbles and snaps rotation back on release. Tune `angle_max` / `hover_scale` / `spring` / `damp` to taste. No automated assertion — visual.

- [ ] **Step 6: Commit**

```bash
git add src/ui/card/card_view.gd tests/test_card_view.gd
git commit -m "feat: CardView juice (hover tilt/scale, shadow, drag wobble, dissolve) + input signals"
```

---

# Phase 4 — Static table

## Task 4: `board_layout.gd` — pure zone+index → Transform2D

The single piece of real logic in this plan: maps a card's `(zone, index, count, player)` to a target `Transform2D` (position + rotation). Fully unit-tested, no scene. Both `Match` (Phase 5 reconcile) and the static table (Task 9) use it.

**Files:**
- Create: `src/ui/table/board_layout.gd`
- Test: `tests/test_board_layout.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_board_layout.gd`:

```gdscript
extends GdUnitTestSuite

const CENTER_X := 960.0

func _x(t: Transform2D) -> float:
	return t.origin.x

func test_single_board_card_centered() -> void:
	var t := BoardLayout.slot(Enums.Zone.BOARD, 0, 1, 0)
	assert_float(_x(t)).is_equal_approx(CENTER_X, 1.0)

func test_two_board_cards_symmetric_about_center() -> void:
	var a := BoardLayout.slot(Enums.Zone.BOARD, 0, 2, 0)
	var b := BoardLayout.slot(Enums.Zone.BOARD, 1, 2, 0)
	assert_float(_x(a) + _x(b)).is_equal_approx(2.0 * CENTER_X, 1.0)
	assert_float(_x(a)).is_less(_x(b))

func test_player_board_below_opponent_board() -> void:
	var you := BoardLayout.slot(Enums.Zone.BOARD, 0, 1, 0)
	var opp := BoardLayout.slot(Enums.Zone.BOARD, 0, 1, 1)
	assert_float(you.origin.y).is_greater(opp.origin.y)

func test_tapped_board_card_is_rotated() -> void:
	var untapped := BoardLayout.slot(Enums.Zone.BOARD, 0, 1, 0, false)
	var tapped := BoardLayout.slot(Enums.Zone.BOARD, 0, 1, 0, true)
	assert_float(untapped.get_rotation()).is_equal_approx(0.0, 0.001)
	assert_float(absf(tapped.get_rotation())).is_greater(0.2)   # ~15deg

func test_hand_fan_is_ordered_and_centered() -> void:
	var left := BoardLayout.slot(Enums.Zone.HAND, 0, 5, 0)
	var right := BoardLayout.slot(Enums.Zone.HAND, 4, 5, 0)
	assert_float(_x(left)).is_less(_x(right))
	var mid := BoardLayout.slot(Enums.Zone.HAND, 2, 5, 0)
	assert_float(_x(mid)).is_equal_approx(CENTER_X, 40.0)
```

- [ ] **Step 2: Run to verify failure**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_board_layout.gd
```
Expected: FAIL — `BoardLayout` not declared, exit `100`.

- [ ] **Step 3: Implement**

Create `src/ui/table/board_layout.gd`:

```gdscript
class_name BoardLayout
extends RefCounted

const SCREEN := Vector2(1920, 1080)
const CENTER_X := 960.0

# Row Y bands (player = bottom).
const PLAYER_BOARD_Y := 620.0
const OPP_BOARD_Y := 320.0
const PLAYER_HAND_Y := 940.0
const OPP_HAND_Y := 90.0

const BOARD_SLOT_W := 200.0
const HAND_SLOT_W := 150.0
const TAP_ANGLE := deg_to_rad(15.0)
const FAN_ANGLE := deg_to_rad(4.0)   # per-card fan tilt in hand

# Centered evenly-spaced x for `index` of `count`, width `slot_w` per card.
static func _row_x(index: int, count: int, slot_w: float) -> float:
	var total := slot_w * float(count)
	var start := CENTER_X - total * 0.5 + slot_w * 0.5
	return start + slot_w * float(index)

static func slot(zone: int, index: int, count: int, player: int, tapped: bool = false) -> Transform2D:
	var pos := Vector2.ZERO
	var rot := 0.0
	match zone:
		Enums.Zone.BOARD:
			pos = Vector2(_row_x(index, count, BOARD_SLOT_W),
				PLAYER_BOARD_Y if player == 0 else OPP_BOARD_Y)
			rot = TAP_ANGLE if tapped else 0.0
		Enums.Zone.HAND:
			pos = Vector2(_row_x(index, count, HAND_SLOT_W),
				PLAYER_HAND_Y if player == 0 else OPP_HAND_Y)
			# Symmetric fan: tilt grows from the center outward.
			var mid := float(count - 1) * 0.5
			rot = (float(index) - mid) * FAN_ANGLE * (1.0 if player == 0 else -1.0)
		_:
			pos = Vector2(CENTER_X, SCREEN.y * 0.5)
	return Transform2D(rot, pos)
```

- [ ] **Step 4: Run to verify pass**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_board_layout.gd
```
Expected: PASS, exit `0`.

- [ ] **Step 5: Commit**

```bash
git add src/ui/table/board_layout.gd tests/test_board_layout.gd
git commit -m "feat: BoardLayout pure zone+index -> Transform2D (unit-tested)"
```

---

## Task 5: `ticket_tray` widget

Draws `tickets_total` pips with `tickets_tapped` filled. Pure render from two ints; affordability highlight derives from `available_tickets()`.

**Files:**
- Create: `src/ui/table/ticket_tray.tscn`, `src/ui/table/ticket_tray.gd`
- Test: `tests/test_ticket_tray.gd`

- [ ] **Step 1: Author the scene**

`ticket_tray.tscn`:
```
TicketTray  (HBoxContainer)   # attach ticket_tray.gd
```
Pips are created in code (ColorRect/TextureRect children), so the scene is just the container.

- [ ] **Step 2: Failing test**

Create `tests/test_ticket_tray.gd`:

```gdscript
extends GdUnitTestSuite

func _spawn() -> Node:
	var t := load("res://src/ui/table/ticket_tray.tscn").instantiate()
	add_child(t)
	auto_free(t)
	return t

func test_draws_total_pips_with_tapped_filled() -> void:
	var tray := _spawn()
	tray.set_tickets(3, 5)   # tapped, total
	assert_int(tray.get_child_count()).is_equal(5)
	assert_int(tray.filled_count()).is_equal(3)
```

- [ ] **Step 3: Implement**

`src/ui/table/ticket_tray.gd`:

```gdscript
extends HBoxContainer

const PIP_FILLED := Color(0.95, 0.8, 0.2)
const PIP_EMPTY := Color(0.3, 0.3, 0.3)

var _tapped: int = 0
var _total: int = 0

func set_tickets(tapped: int, total: int) -> void:
	_tapped = tapped
	_total = total
	for c in get_children():
		c.queue_free()
	for i in range(total):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(28, 28)
		pip.color = PIP_FILLED if i < (total - tapped) else PIP_EMPTY
		add_child(pip)

func filled_count() -> int:
	var n := 0
	for c in get_children():
		if c is ColorRect and c.color == PIP_FILLED:
			n += 1
	return n
```

> Pips show **available** tickets filled (`total - tapped`), matching `available_tickets()`.

- [ ] **Step 4: Run**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_ticket_tray.gd
```
Expected: PASS, exit `0`.

- [ ] **Step 5: Commit**

```bash
git add src/ui/table/ticket_tray.tscn src/ui/table/ticket_tray.gd tests/test_ticket_tray.gd
git commit -m "feat: ticket_tray widget (available pips filled)"
```

---

## Task 6: `pile_view` widget (deck / discard / leader slot)

A small widget showing a stacked card-back with a count badge. Configurable as deck, discard, or leader slot. No interaction yet (click-to-peek arrives in Phase 6).

**Files:**
- Create: `src/ui/table/pile_view.tscn`, `src/ui/table/pile_view.gd`
- Test: `tests/test_pile_view.gd`

- [ ] **Step 1: Author the scene**

`pile_view.tscn`:
```
PileView   (Control)              # attach pile_view.gd; custom_minimum_size 150 x 210
├── Back    (TextureRect)         # frames/back.png; expand Keep Aspect; full rect
└── Count   (Label)               # bottom-right badge; bold
```

- [ ] **Step 2: Failing test**

Create `tests/test_pile_view.gd`:

```gdscript
extends GdUnitTestSuite

func _spawn() -> Node:
	var p := load("res://src/ui/table/pile_view.tscn").instantiate()
	add_child(p)
	auto_free(p)
	return p

func test_count_badge_reflects_size() -> void:
	var p := _spawn()
	p.set_count(17)
	assert_str(p.find_child("Count").text).is_equal("17")

func test_empty_pile_hides_back() -> void:
	var p := _spawn()
	p.set_count(0)
	assert_bool(p.find_child("Back").visible).is_false()
```

- [ ] **Step 3: Implement**

`src/ui/table/pile_view.gd`:

```gdscript
extends Control

@onready var _back: TextureRect = $Back
@onready var _count: Label = $Count

func _ready() -> void:
	_back.texture = load(CardArt.BACK)

func set_count(n: int) -> void:
	if not is_node_ready():
		await ready
	_count.text = str(n)
	_back.visible = n > 0
```

- [ ] **Step 4: Run**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_pile_view.gd
```
Expected: PASS, exit `0`.

- [ ] **Step 5: Commit**

```bash
git add src/ui/table/pile_view.tscn src/ui/table/pile_view.gd tests/test_pile_view.gd
git commit -m "feat: pile_view widget (card-back stack + count badge)"
```

---

## Task 7: `opponent_hand` widget (face-down backs)

Renders N face-down `CardView`s (count only) along the opponent's hand band.

**Files:**
- Create: `src/ui/table/opponent_hand.gd`
- Test: `tests/test_opponent_hand.gd`

- [ ] **Step 1: Failing test**

Create `tests/test_opponent_hand.gd`:

```gdscript
extends GdUnitTestSuite

func _spawn() -> Node:
	var n := Node2D.new()
	n.set_script(load("res://src/ui/table/opponent_hand.gd"))
	add_child(n)
	auto_free(n)
	return n

func test_renders_n_face_down_backs() -> void:
	var oh := _spawn()
	oh.set_count(4)
	assert_int(oh.get_child_count()).is_equal(4)
```

- [ ] **Step 2: Implement**

`src/ui/table/opponent_hand.gd`:

```gdscript
extends Node2D

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")

# A throwaway face-down definition (any def works; the back hides its data).
var _placeholder: CardDefinition

func _ready() -> void:
	_placeholder = CardDefinition.new()
	_placeholder.name = "?"

func set_count(n: int) -> void:
	for c in get_children():
		c.queue_free()
	for i in range(n):
		var cv: CardView = CARD_VIEW.instantiate()
		cv.set_interactive(false)
		add_child(cv)
		cv.setup(CardInstance.new(-1 - i, _placeholder))
		cv.set_face_down(true)
		var t := BoardLayout.slot(Enums.Zone.HAND, i, n, 1)
		cv.position = t.origin
		cv.rotation = t.get_rotation()
```

- [ ] **Step 3: Run**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_opponent_hand.gd
```
Expected: PASS, exit `0`.

- [ ] **Step 4: Commit**

```bash
git add src/ui/table/opponent_hand.gd tests/test_opponent_hand.gd
git commit -m "feat: opponent_hand widget (face-down backs by count)"
```

---

## Task 8: `hand_view` + `board_view` (CardView rows)

Two thin layout scripts that spawn `CardView`s for a player's hand / board and place each via `BoardLayout`. No drag pickup wiring yet (Phase 6); `hand_view` already spawns interactive `CardView`s so the signals are live for later.

**Files:**
- Create: `src/ui/table/hand_view.gd`, `src/ui/table/board_view.gd`
- Test: `tests/test_card_rows.gd`

- [ ] **Step 1: Failing test**

Create `tests/test_card_rows.gd`:

```gdscript
extends GdUnitTestSuite

func _strike_defs() -> Array:
	return CardDatabase.load_deck("res://src/data/decks/strike.csv", "Strike")

func _instances(n: int) -> Array[CardInstance]:
	var defs := _strike_defs()
	var out: Array[CardInstance] = []
	for i in range(n):
		out.append(CardInstance.new(i + 1, defs[i % defs.size()]))
	return out

func _row(path: String) -> Node2D:
	var n := Node2D.new()
	n.set_script(load(path))
	add_child(n)
	auto_free(n)
	return n

func test_hand_view_spawns_one_cardview_per_card() -> void:
	var hv := _row("res://src/ui/table/hand_view.gd")
	hv.render(_instances(5), 0)
	assert_int(hv.get_child_count()).is_equal(5)

func test_board_view_spawns_one_cardview_per_unit() -> void:
	var bv := _row("res://src/ui/table/board_view.gd")
	bv.render(_instances(3), 0)
	assert_int(bv.get_child_count()).is_equal(3)
```

- [ ] **Step 2: Implement `hand_view.gd`**

```gdscript
extends Node2D

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")

var card_views: Dictionary = {}   # instance_id -> CardView

func render(cards: Array, player: int) -> void:
	for c in get_children():
		c.queue_free()
	card_views.clear()
	var n := cards.size()
	for i in range(n):
		var inst: CardInstance = cards[i]
		var cv: CardView = CARD_VIEW.instantiate()
		add_child(cv)
		cv.setup(inst)
		var t := BoardLayout.slot(Enums.Zone.HAND, i, n, player)
		cv.position = t.origin
		cv.rotation = t.get_rotation()
		card_views[inst.instance_id] = cv
```

- [ ] **Step 3: Implement `board_view.gd`**

Identical shape with `Enums.Zone.BOARD` and passing each unit's `tapped`:

```gdscript
extends Node2D

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")

var card_views: Dictionary = {}

func render(units: Array, player: int) -> void:
	for c in get_children():
		c.queue_free()
	card_views.clear()
	var n := units.size()
	for i in range(n):
		var inst: CardInstance = units[i]
		var cv: CardView = CARD_VIEW.instantiate()
		cv.set_interactive(player == 0)
		add_child(cv)
		cv.setup(inst)
		var t := BoardLayout.slot(Enums.Zone.BOARD, i, n, player, inst.tapped)
		cv.position = t.origin
		cv.rotation = t.get_rotation()
		card_views[inst.instance_id] = cv
```

- [ ] **Step 4: Run**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_card_rows.gd
```
Expected: PASS, exit `0`.

- [ ] **Step 5: Commit**

```bash
git add src/ui/table/hand_view.gd src/ui/table/board_view.gd tests/test_card_rows.gd
git commit -m "feat: hand_view + board_view CardView row layouts"
```

---

## Task 9: `table_view` — render a seeded GameState (visible milestone)

A debug scene that builds a `GameState` from a fixed seed via `GameEngine.setup(...)` and renders both sides with the widgets above — the visible milestone for Phase 4. **No interaction.** (To bypass the opening mulligan for rendering, resolve it with a fixed pair of indices, since `setup` leaves `pending_choice = "mulligan"`.)

**Files:**
- Create: `src/ui/table/table_view.tscn`, `src/ui/table/table_view.gd`
- Test: `tests/test_table_view.gd`

- [ ] **Step 1: Author the scene**

`table_view.tscn` (1920×1080, `canvas_items` stretch):
```
TableView   (Control)                 # full rect; attach table_view.gd
├── OppBoard     (board_view.gd Node2D)
├── PlayerBoard  (board_view.gd Node2D)
├── PlayerHand   (hand_view.gd Node2D)
├── OppHand      (opponent_hand.gd Node2D)
├── PlayerDeck   (pile_view)          # bottom-left cluster
├── PlayerDiscard(pile_view)
├── PlayerLeader (pile_view)          # leader slot
├── OppDeck      (pile_view)          # top cluster
├── OppDiscard   (pile_view)
├── OppLeader    (pile_view)
└── PlayerTickets(ticket_tray)
```
Position the pile clusters per the spec ASCII (player bottom-left, opponent top). Use instances of `pile_view.tscn` / `ticket_tray.tscn`.

- [ ] **Step 2: Failing test**

Create `tests/test_table_view.gd`:

```gdscript
extends GdUnitTestSuite

func test_renders_counts_from_seeded_state() -> void:
	var tv := load("res://src/ui/table/table_view.tscn").instantiate()
	add_child(tv)
	auto_free(tv)
	tv.build(12345)   # fixed seed; resolves opening mulligan internally
	# Each player drew 5, mulliganed 2 -> hand 3 (+ leader if it sat in the opening hand).
	var hand := tv.find_child("PlayerHand")
	assert_int(hand.get_child_count()).is_equal(tv.state.players[0].hand.size())
	var opp := tv.find_child("OppHand")
	assert_int(opp.get_child_count()).is_equal(tv.state.players[1].hand.size())
```

- [ ] **Step 3: Implement `table_view.gd`**

```gdscript
extends Control

const STRIKE := "res://src/data/decks/strike.csv"
const RACCOON := "res://src/data/decks/raccoon.csv"

var state: GameState
var engine: GameEngine

func build(seed_value: int) -> void:
	state = GameState.new(seed_value)
	engine = GameEngine.new(state)
	var d0: Array[CardDefinition] = CardDatabase.load_deck(STRIKE, "Strike")
	var d1: Array[CardDefinition] = CardDatabase.load_deck(RACCOON, "Raccoon")
	engine.setup(d0, d1)
	# Resolve the opening mulligans so the table renders a clean MAIN state.
	engine.apply(Action.mulligan([0, 1]))   # player 0
	engine.apply(Action.mulligan([0, 1]))   # player 1
	render()

func render() -> void:
	var you := state.players[0]
	var opp := state.players[1]
	($PlayerBoard as Node2D).render(you.board, 0)
	($OppBoard as Node2D).render(opp.board, 1)
	($PlayerHand as Node2D).render(you.hand, 0)
	($OppHand as Node2D).set_count(opp.hand.size())
	($PlayerDeck as Node).set_count(you.deck.size())
	($PlayerDiscard as Node).set_count(you.discard.size())
	($OppDeck as Node).set_count(opp.deck.size())
	($OppDiscard as Node).set_count(opp.discard.size())
	($PlayerTickets as Node).set_tickets(you.tickets_tapped, you.tickets_total)
	# Leader slots: render the leader CardView if it left the hand, else show its pile placeholder.
```

> The leader starts in hand, so on a fresh state the leader slot is empty; it is exercised once cards are played in later phases. Rendering the leader CardView when `players[i].leader.zone == BOARD` is a small follow-up; not required for this milestone.

- [ ] **Step 4: Run**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_table_view.gd
```
Expected: PASS, exit `0`.

- [ ] **Step 5: Manual layout calibration (editor)**

Open `table_view.tscn`, run (F6). Confirm both boards, hands, piles, and the ticket tray sit in their bands without overlap at 1920×1080. Nudge the cluster positions and `BoardLayout` Y constants until it reads like the spec ASCII. Visual only.

- [ ] **Step 6: Commit**

```bash
git add src/ui/table/table_view.tscn src/ui/table/table_view.gd tests/test_table_view.gd
git commit -m "feat: static table_view rendered from a seeded GameState (Phase 4 milestone)"
```

---

## Self-review notes

- **Phase 3 coverage:** signals `hovered/unhovered/drag_started/drag_released/clicked` (Task 3) ✓; hover tilt+scale, dynamic shadow, drag wobble, dissolve (Tasks 2–3) ✓; reference `card.gd`/`dissolve.gdshader`/`fake_3D.gdshader` adapted to `Control` ✓.
- **Phase 4 coverage:** `board_layout.gd` pure + unit-tested (Task 4) ✓; `ticket_tray` (5), `pile_view`/leader slot (6), `opponent_hand` (7), `hand_view`/`board_view` (8), rendered from a seeded `GameState`, no interaction (Task 9) ✓.
- **Boundaries honored:** no `Action` is sent and no state mutated outside the engine's own `setup`/`mulligan`; `table_view` reads state only. `Match` wiring + reconcile/flourish are deliberately deferred to Plan 3.
- **Headless honesty:** tween/InputEvent behavior is verified manually; automated tests assert contract + layout math + counts.

---

## Next plan

**Plan 3 — Match + Player Input (Phases 5–6):** `match.gd` apply→reconcile→flourish cycle reusing `BoardLayout`, event flourishes, turn banner; then drag-to-play, click-target attacks (`targeting_arrow`), end turn, leader cost prompt, and `get_legal_actions()`-driven highlights — with input→`Action` mapping unit-tested.
