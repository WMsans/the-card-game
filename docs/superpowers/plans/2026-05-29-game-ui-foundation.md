# Game UI — Foundation (Phases 1–2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add card art data to the model and build a reusable `CardView` that renders any card onto the provided blank frames, shown in a debug gallery — the foundation every later UI phase depends on.

**Architecture:** The UI is a pure view over `GameState`; it never mutates game state. This plan adds one additive data field (`CardDefinition.image`) and a self-contained `CardView` (`Control` scene + script) plus a stateless `CardArt` helper. No engine logic changes.

**Tech Stack:** Godot 4.6 (GL Compatibility), GDScript, GdUnit4 for tests.

**Spec:** `docs/superpowers/specs/2026-05-29-game-ui-design.md` (this plan covers spec §8 phases 1–2).

---

## Conventions used in every task

- **Canonical deck path:** `res://src/data/decks/<color>.csv` (`strike`, `raccoon`, `writing`, `audio`).
- **Run a single suite:**
  ```bash
  godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a <suite-path>
  ```
  Exit code `0` = all pass; `100` = failures. The script-class cache must exist; if a run reports `Could not find type "GdUnitTestCIRunner"`, build it once with `godot --headless --path . --import`.
- **Commit** after each task (steps below specify exact files).

---

## File structure (this plan)

```
src/data/card_definition.gd       # MODIFY: add `image` field
src/data/card_database.gd         # MODIFY: parse CSV column 8 into `image`
tests/test_card_database.gd       # MODIFY: fix deck path; add image-field test
src/ui/assets/frames/             # CREATE: minion/leader/spell/trap/back PNGs (+ .import)
src/ui/assets/art/                # CREATE: per-card art PNGs/JPGs (+ .import)
src/ui/card/card_art.gd           # CREATE: frame_path(type) + art_path(def) helper
src/ui/card/card_view.gd          # CREATE: renders one CardInstance onto a frame
src/ui/card/card_view.tscn        # CREATE: CardView scene (named overlay nodes)
src/ui/card/card_gallery.tscn     # CREATE: debug grid of all cards (visible milestone)
src/ui/card/card_gallery.gd       # CREATE: loads all decks, fills the grid
tests/test_card_art.gd            # CREATE: CardArt mapping tests
tests/test_card_view.gd           # CREATE: CardView data-binding tests
```

---

## Task 1: Restore green baseline (fix pre-existing deck path)

`tests/test_card_database.gd` loads `res://game/data/decks/…` which no longer exists; the CSVs are at `res://src/data/decks/…`. Fix the path so the suite is green before we build on it.

**Files:**
- Modify: `tests/test_card_database.gd` (lines 4, 11, 20, 25, 32)

- [ ] **Step 1: Run the suite to confirm it currently fails**

Run:
```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_card_database.gd
```
Expected: FAIL — `Assertion failed: Could not open res://game/data/decks/strike.csv`, exit code `100`.

- [ ] **Step 2: Replace every `game/data/decks` with `src/data/decks`**

In `tests/test_card_database.gd`, change all five occurrences of `res://game/data/decks/` to `res://src/data/decks/`. The resulting lines:

```gdscript
var defs := CardDatabase.load_deck("res://src/data/decks/strike.csv", "Strike")   # lines 4, 11
var defs := CardDatabase.load_deck("res://src/data/decks/audio.csv", "Audio")     # line 20
var defs := CardDatabase.load_deck("res://src/data/decks/raccoon.csv", "Raccoon") # line 25
var defs := CardDatabase.load_deck("res://src/data/decks/%s.csv" % path, path)     # line 32
```

- [ ] **Step 3: Run the suite to verify it passes**

Run:
```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_card_database.gd
```
Expected: PASS, exit code `0`.

- [ ] **Step 4: Commit**

```bash
git add tests/test_card_database.gd
git commit -m "fix: correct deck CSV path in card_database tests (game -> src)"
```

---

## Task 2: Add `image` field to the card model

The CSV has an `Image` column (index 8) currently ignored. Parse it into a new `CardDefinition.image` so the UI can locate art.

**Files:**
- Modify: `src/data/card_definition.gd`
- Modify: `src/data/card_database.gd:36` (inside `_parse_row`)
- Test: `tests/test_card_database.gd`

- [ ] **Step 1: Write the failing test**

Add to `tests/test_card_database.gd`:

```gdscript
func test_image_path_parsed_from_csv() -> void:
	var defs := CardDatabase.load_deck("res://src/data/decks/strike.csv", "Strike")
	var bjorn: CardDefinition = defs.filter(func(d): return d.name == "Battle Bjorn")[0]
	assert_str(bjorn.image).is_equal("docs/design_docs/Card List/images/strike_battle-bjorn.png")
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_card_database.gd
```
Expected: FAIL — `image` is empty (property exists on `RefCounted` default `""` vs expected path) → assertion mismatch, exit `100`.

- [ ] **Step 3: Add the field**

In `src/data/card_definition.gd`, add after the `flavor` line:

```gdscript
var flavor: String = ""
var image: String = ""
var keywords: Array[String] = []
```

- [ ] **Step 4: Parse column 8**

In `src/data/card_database.gd`, inside `_parse_row`, add after `d.flavor = row[7].strip_edges()`:

```gdscript
	d.flavor = row[7].strip_edges()
	d.image = row[8].strip_edges() if row.size() > 8 else ""
```

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_card_database.gd
```
Expected: PASS, exit `0`.

- [ ] **Step 6: Commit**

```bash
git add src/data/card_definition.gd src/data/card_database.gd tests/test_card_database.gd
git commit -m "feat: parse card image path from CSV into CardDefinition"
```

---

## Task 3: Import blank frame assets

Copy the five frame PNGs into the project and let Godot import them as textures.

**Files:**
- Create: `src/ui/assets/frames/minion.png`, `leader.png`, `spell.png`, `trap.png`, `back.png` (+ generated `.import`)
- Test: `tests/test_frames_load.gd`

- [ ] **Step 1: Copy the frame files**

```bash
mkdir -p src/ui/assets/frames
FRAMEDIR="docs/design_docs/Card List/Design & UI_UX MEGA COLLAB Cards"
cp "$FRAMEDIR/No text/Minion Card-1.png" src/ui/assets/frames/minion.png
cp "$FRAMEDIR/No text/Leader Card.png"   src/ui/assets/frames/leader.png
cp "$FRAMEDIR/No text/Spell Card.png"    src/ui/assets/frames/spell.png
cp "$FRAMEDIR/No text/Trap Card.png"     src/ui/assets/frames/trap.png
cp "$FRAMEDIR/Card Back.png"             src/ui/assets/frames/back.png
ls -1 src/ui/assets/frames/
```
Expected: five `.png` files listed.

- [ ] **Step 2: Import the new textures**

Run:
```bash
godot --headless --path . --import
```
Expected: completes; `src/ui/assets/frames/*.png.import` files now exist (verify with `ls src/ui/assets/frames/*.import`).

- [ ] **Step 3: Write a test that all frames load as textures**

Create `tests/test_frames_load.gd`:

```gdscript
extends GdUnitTestSuite

func test_all_frames_load_as_texture() -> void:
	for name in ["minion", "leader", "spell", "trap", "back"]:
		var path := "res://src/ui/assets/frames/%s.png" % name
		assert_bool(ResourceLoader.exists(path)).override_failure_message(
			"Missing frame: %s" % path).is_true()
		var tex := load(path)
		assert_object(tex).is_instanceof(Texture2D)
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_frames_load.gd
```
Expected: PASS, exit `0`.

- [ ] **Step 5: Commit**

```bash
git add src/ui/assets/frames tests/test_frames_load.gd
git commit -m "assets: import blank card frames (minion/leader/spell/trap/back)"
```

---

## Task 4: Import per-card art assets

Copy the card art images so `CardArt` can resolve them by filename.

**Files:**
- Create: `src/ui/assets/art/*` (copied from `docs/.../images/`) + generated `.import`

- [ ] **Step 1: Copy the art files**

```bash
mkdir -p src/ui/assets/art
cp "docs/design_docs/Card List/images/"*.png "docs/design_docs/Card List/images/"*.jpg src/ui/assets/art/ 2>/dev/null
ls -1 src/ui/assets/art/ | grep -vc import
```
Expected: a positive count (the art files copied; `.import` files not yet present).

- [ ] **Step 2: Import the textures**

Run:
```bash
godot --headless --path . --import
```
Expected: completes; `ls src/ui/assets/art/*.import` lists `.import` files.

- [ ] **Step 3: Commit**

```bash
git add src/ui/assets/art
git commit -m "assets: import per-card art images"
```

---

## Task 5: `CardArt` helper — frame & art path resolution

A stateless helper mapping a card to its frame texture and (optional) art texture. Pure logic, fully unit-tested.

**Files:**
- Create: `src/ui/card/card_art.gd`
- Test: `tests/test_card_art.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_card_art.gd`:

```gdscript
extends GdUnitTestSuite

func test_frame_path_per_type() -> void:
	assert_str(CardArt.frame_path(Enums.CardType.MINION)).is_equal("res://src/ui/assets/frames/minion.png")
	assert_str(CardArt.frame_path(Enums.CardType.LEADER)).is_equal("res://src/ui/assets/frames/leader.png")
	assert_str(CardArt.frame_path(Enums.CardType.SPELL)).is_equal("res://src/ui/assets/frames/spell.png")
	assert_str(CardArt.frame_path(Enums.CardType.TRAP)).is_equal("res://src/ui/assets/frames/trap.png")

func test_art_path_resolves_existing_file_by_basename() -> void:
	var def := CardDefinition.new()
	def.image = "docs/design_docs/Card List/images/strike_battle-bjorn.png"
	assert_str(CardArt.art_path(def)).is_equal("res://src/ui/assets/art/strike_battle-bjorn.png")

func test_art_path_empty_when_missing() -> void:
	var def := CardDefinition.new()
	def.image = "docs/design_docs/Card List/images/does-not-exist.png"
	assert_str(CardArt.art_path(def)).is_equal("")

func test_art_path_empty_when_no_image() -> void:
	var def := CardDefinition.new()
	def.image = ""
	assert_str(CardArt.art_path(def)).is_equal("")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_card_art.gd
```
Expected: FAIL — `CardArt` does not exist (parse error / identifier not declared), exit `100`.

- [ ] **Step 3: Implement `CardArt`**

Create `src/ui/card/card_art.gd`:

```gdscript
class_name CardArt
extends RefCounted

const FRAME_DIR := "res://src/ui/assets/frames/"
const ART_DIR := "res://src/ui/assets/art/"
const BACK := "res://src/ui/assets/frames/back.png"

const _FRAME := {
	Enums.CardType.MINION: "minion.png",
	Enums.CardType.LEADER: "leader.png",
	Enums.CardType.SPELL: "spell.png",
	Enums.CardType.TRAP: "trap.png",
}

static func frame_path(type: int) -> String:
	return FRAME_DIR + _FRAME.get(type, "minion.png")

# Returns a res:// path to the card art if it exists under ART_DIR, else "".
static func art_path(def: CardDefinition) -> String:
	if def.image == "":
		return ""
	var candidate := ART_DIR + def.image.get_file()
	return candidate if ResourceLoader.exists(candidate) else ""
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_card_art.gd
```
Expected: PASS, exit `0`.

- [ ] **Step 5: Commit**

```bash
git add src/ui/card/card_art.gd tests/test_card_art.gd
git commit -m "feat: CardArt frame/art path resolution helper"
```

---

## Task 6: `CardView` scene skeleton (named overlay nodes)

Build the scene with the exact node names `card_view.gd` will bind to. Positions are placeholder now and calibrated to the 750×1050 frame in Task 8.

**Files:**
- Create: `src/ui/card/card_view.tscn`

- [ ] **Step 1: Author the scene in the editor**

Create `src/ui/card/card_view.tscn` with this node tree (exact names matter — the script binds by `$Name`). Draw order is sibling order: later siblings render on top.

```
CardView            (Control)          # root; size 250 x 350 (frame aspect 5:7)
├── Frame           (TextureRect)      # expand=Ignore Size, stretch=Keep Aspect; full rect
├── ArtTexture      (TextureRect)      # stretch=Keep Aspect Covered; over the art box
├── NameLabel       (Label)            # over the colored name bar; autowrap on, clip text
├── DamageLabel     (Label)            # over the ⭐ (top-left), centered
├── HealthLabel     (Label)            # over the ❤️ (top-right), centered
├── TicketLabel     (Label)            # over the 🎟️ (bottom-left), centered
├── DiscardLabel    (Label)            # over the 🗑️ (bottom-right), centered
├── AbilityText     (RichTextLabel)    # over the ability box; BBCode enabled, fit content
└── FlavorLabel     (Label)            # over the gray flavor box; italic, autowrap
```

Set the root `CardView` node's script in Task 7 (after the script exists). For now leave it scriptless. Save the scene.

- [ ] **Step 2: Verify the scene loads**

Run:
```bash
godot --headless --path . --import
```
Expected: completes with no parse/scene errors mentioning `card_view.tscn`.

- [ ] **Step 3: Commit**

```bash
git add src/ui/card/card_view.tscn
git commit -m "feat: CardView scene skeleton with named overlay nodes"
```

---

## Task 7: `CardView` script — data binding

Bind a `CardInstance` (or `CardDefinition` preview) onto the named nodes, with face-down support, base-vs-current stats, stat tinting, and keyword bolding.

**Files:**
- Create: `src/ui/card/card_view.gd`
- Modify: `src/ui/card/card_view.tscn` (attach the script to the root)
- Test: `tests/test_card_view.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_card_view.gd`:

```gdscript
extends GdUnitTestSuite

const CARD_VIEW := "res://src/ui/card/card_view.tscn"

func _strike_defs() -> Array:
	return CardDatabase.load_deck("res://src/data/decks/strike.csv", "Strike")

func _make(def: CardDefinition) -> CardInstance:
	return CardInstance.new(1, def)

func _spawn() -> CardView:
	var cv: CardView = load(CARD_VIEW).instantiate()
	add_child(cv)
	auto_free(cv)
	return cv

func test_minion_renders_name_stats_and_frame() -> void:
	var def: CardDefinition = _strike_defs().filter(func(d): return d.type == Enums.CardType.MINION)[0]
	var cv := _spawn()
	cv.setup(_make(def))
	assert_str(cv.find_child("NameLabel").text).is_equal(def.name)
	assert_str(cv.find_child("DamageLabel").text).is_equal(str(def.base_damage))
	assert_str(cv.find_child("HealthLabel").text).is_equal(str(def.base_health))
	assert_str(cv.find_child("TicketLabel").text).is_equal(str(def.ticket_cost))
	assert_str((cv.find_child("Frame") as TextureRect).texture.resource_path).is_equal(CardArt.frame_path(Enums.CardType.MINION))

func test_spell_hides_unit_stats_and_discard() -> void:
	var def: CardDefinition = _strike_defs().filter(func(d): return d.type == Enums.CardType.SPELL)[0]
	var cv := _spawn()
	cv.setup(_make(def))
	assert_bool(cv.find_child("DamageLabel").visible).is_false()
	assert_bool(cv.find_child("HealthLabel").visible).is_false()
	assert_bool(cv.find_child("DiscardLabel").visible).is_false()

func test_leader_shows_discard_cost() -> void:
	var def: CardDefinition = _strike_defs().filter(func(d): return d.type == Enums.CardType.LEADER)[0]
	var cv := _spawn()
	cv.setup(_make(def))
	assert_bool(cv.find_child("DiscardLabel").visible).is_true()
	assert_str(cv.find_child("DiscardLabel").text).is_equal(str(def.alt_discard_cost))

func test_face_down_shows_back_and_hides_text() -> void:
	var def: CardDefinition = _strike_defs()[0]
	var cv := _spawn()
	cv.setup(_make(def))
	cv.set_face_down(true)
	assert_str((cv.find_child("Frame") as TextureRect).texture.resource_path).is_equal(CardArt.BACK)
	assert_bool(cv.find_child("NameLabel").visible).is_false()

func test_damaged_health_tints_red() -> void:
	var def: CardDefinition = _strike_defs().filter(func(d): return d.type == Enums.CardType.MINION)[0]
	var inst := _make(def)
	inst.current_health = def.base_health - 1
	var cv := _spawn()
	cv.setup(inst)
	assert_object(cv.find_child("HealthLabel").modulate).is_equal(CardView.STAT_DAMAGED)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_card_view.gd
```
Expected: FAIL — `CardView` class / `setup` not found, exit `100`.

- [ ] **Step 3: Implement the script**

Create `src/ui/card/card_view.gd`:

```gdscript
class_name CardView
extends Control

const STAT_NORMAL := Color.WHITE
const STAT_BUFFED := Color(0.4, 1.0, 0.4)
const STAT_DAMAGED := Color(1.0, 0.4, 0.4)

@onready var _frame: TextureRect = $Frame
@onready var _art: TextureRect = $ArtTexture
@onready var _name: Label = $NameLabel
@onready var _damage: Label = $DamageLabel
@onready var _health: Label = $HealthLabel
@onready var _ticket: Label = $TicketLabel
@onready var _discard: Label = $DiscardLabel
@onready var _ability: RichTextLabel = $AbilityText
@onready var _flavor: Label = $FlavorLabel

var _instance: CardInstance
var _face_down: bool = false

# Render a live card instance (board/hand). Call after the node is in the tree.
func setup(instance: CardInstance) -> void:
	_instance = instance
	_face_down = false
	_refresh()

func set_face_down(value: bool) -> void:
	_face_down = value
	_refresh()

func _refresh() -> void:
	if _instance == null:
		return
	if _face_down:
		_frame.texture = load(CardArt.BACK)
		_set_overlays_visible(false)
		return
	var def := _instance.definition
	_frame.texture = load(CardArt.frame_path(def.type))
	_set_overlays_visible(true)

	_name.text = def.name
	_ticket.text = str(def.ticket_cost)

	var art := CardArt.art_path(def)
	_art.visible = art != ""
	if art != "":
		_art.texture = load(art)

	var is_unit := def.type == Enums.CardType.MINION or def.type == Enums.CardType.LEADER
	_damage.visible = is_unit
	_health.visible = is_unit
	_damage.text = str(_instance.current_damage)
	_health.text = str(_instance.current_health)
	_damage.modulate = _stat_color(_instance.current_damage, def.base_damage)
	_health.modulate = _stat_color(_instance.current_health, def.base_health)

	_discard.visible = def.type == Enums.CardType.LEADER
	_discard.text = str(def.alt_discard_cost)

	_ability.text = _bold_keywords(def.ability_text, def.keywords)
	_flavor.text = def.flavor

func _set_overlays_visible(v: bool) -> void:
	for n in [_art, _name, _damage, _health, _ticket, _discard, _ability, _flavor]:
		n.visible = v

func _stat_color(current: int, base: int) -> Color:
	if current > base:
		return STAT_BUFFED
	if current < base:
		return STAT_DAMAGED
	return STAT_NORMAL

func _bold_keywords(text: String, keywords: Array[String]) -> String:
	var out := text
	for kw in keywords:
		out = out.replace(kw, "[b]%s[/b]" % kw)
	return out
```

- [ ] **Step 4: Attach the script and enable BBCode**

In `src/ui/card/card_view.tscn`: select the root `CardView` node and attach `res://src/ui/card/card_view.gd`. Select `AbilityText` and enable `bbcode_enabled = true`. Save.

- [ ] **Step 5: Run the tests to verify they pass**

Run:
```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_card_view.gd
```
Expected: PASS, exit `0`.

- [ ] **Step 6: Commit**

```bash
git add src/ui/card/card_view.gd src/ui/card/card_view.tscn tests/test_card_view.gd
git commit -m "feat: CardView data binding (stats, frame, face-down, keyword bolding)"
```

---

## Task 8: Card gallery — visible milestone + layout calibration

A debug scene that loads all four decks and lays every card out in a grid, so the overlay regions can be calibrated against the real frame art and the whole pipeline is seen working.

**Files:**
- Create: `src/ui/card/card_gallery.tscn`
- Create: `src/ui/card/card_gallery.gd`
- Test: `tests/test_card_gallery.gd`

- [ ] **Step 1: Write the failing smoke test**

Create `tests/test_card_gallery.gd`:

```gdscript
extends GdUnitTestSuite

func test_gallery_populates_a_card_for_every_definition() -> void:
	var gallery := load("res://src/ui/card/card_gallery.tscn").instantiate()
	add_child(gallery)
	auto_free(gallery)
	var expected := 0
	for color in ["strike", "raccoon", "writing", "audio"]:
		expected += CardDatabase.load_deck("res://src/data/decks/%s.csv" % color, color).size()
	var grid := gallery.find_child("Grid")
	assert_int(grid.get_child_count()).is_equal(expected)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_card_gallery.gd
```
Expected: FAIL — scene does not exist, exit `100`.

- [ ] **Step 3: Author the gallery scene**

Create `src/ui/card/card_gallery.tscn`:

```
CardGallery   (Control)            # full rect; attach card_gallery.gd
└── Scroll     (ScrollContainer)   # full rect
    └── Grid   (GridContainer)     # columns = 6
```

Save. (Run `godot --headless --path . --import` to register it.)

- [ ] **Step 4: Implement the gallery script**

Create `src/ui/card/card_gallery.gd`:

```gdscript
extends Control

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")
const DECKS := ["strike", "raccoon", "writing", "audio"]

@onready var _grid: GridContainer = $Scroll/Grid

func _ready() -> void:
	for color in DECKS:
		var defs := CardDatabase.load_deck("res://src/data/decks/%s.csv" % color, color)
		for def in defs:
			var cv: CardView = CARD_VIEW.instantiate()
			cv.custom_minimum_size = Vector2(250, 350)
			_grid.add_child(cv)
			cv.setup(CardInstance.new(0, def))
```

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/test_card_gallery.gd
```
Expected: PASS, exit `0`.

- [ ] **Step 6: Calibrate overlay regions against the frame (manual, in editor)**

Open `src/ui/card/card_gallery.tscn` in the Godot editor and run it (F6). Using a real card as reference, adjust the anchor/offset of each overlay node in `card_view.tscn` so labels sit inside their frame regions:
- `NameLabel` centered in the colored name bar.
- `DamageLabel` / `HealthLabel` centered in the ⭐ / ❤️.
- `TicketLabel` / `DiscardLabel` centered in the 🎟️ / 🗑️.
- `ArtTexture` filling the upper art box.
- `AbilityText` inside the lower box; `FlavorLabel` inside the gray box.

Use anchor presets expressed as ratios of the 750×1050 frame so they scale with `CardView` size. Re-run the gallery until all card types read cleanly. (No automated assertion — this is visual calibration.)

- [ ] **Step 7: Commit**

```bash
git add src/ui/card/card_gallery.tscn src/ui/card/card_gallery.gd src/ui/card/card_view.tscn tests/test_card_gallery.gd
git commit -m "feat: card gallery debug scene + calibrated CardView overlay regions"
```

---

## Self-review notes

- **Spec coverage (phases 1–2):** image field + CSV parse (Task 2) ✓; frame import (Task 3) ✓; art import (Task 4) ✓; frame/art mapping with missing-art fallback (Task 5) ✓; `CardView` render with name/damage/health/cost labels, correct frame per type, face-down back, current-vs-base stats, keyword bolding (Tasks 6–7) ✓; visible "debug grid showing all cards" milestone (Task 8) ✓.
- **Type consistency:** `CardArt.frame_path`/`art_path`/`BACK`, `CardView.setup`/`set_face_down`/`STAT_DAMAGED`, node names (`Frame`, `NameLabel`, `DamageLabel`, `HealthLabel`, `TicketLabel`, `DiscardLabel`, `AbilityText`, `FlavorLabel`, `ArtTexture`, `Grid`) are used identically across scene, script, and tests.
- **No placeholders:** every code step contains full code; the only non-code step is the explicitly-scoped visual calibration in Task 8 Step 6.

---

## Roadmap — remaining phases (separate plans, written as each lands)

These depend on `CardView`'s final shape (signals, drop API) and involve `.tscn`/interaction work that is calibrated against the running foundation, so each gets its own plan after the prior phase merges:

- **Plan 2 — Phase 3 (Juice):** hover tilt + scale/raise, dynamic shadow, drag wobble (spring/oscillator), dissolve shader on death; encapsulated in `CardView`; signals `hovered/unhovered/drag_started/drag_released/clicked`.
- **Plan 3 — Phase 4 (Static table):** `hand_view`, `board_view`, `pile_view`/leader slot, `ticket_tray`, `opponent_hand`, `board_layout.gd` (pure zone+index→transform, unit-tested); rendered from a seeded `GameState`, no interaction.
- **Plan 4 — Phase 5 (Match + reconciliation + flourishes):** `match.gd` apply→reconcile→flourish cycle; event flourishes (damage numbers, dissolve, mill burst, shake); turn banner.
- **Plan 5 — Phase 6 (Player input):** drag-to-play, click-target attacks (`targeting_arrow`), end turn, leader cost prompt; highlights from `get_legal_actions()`; input→`Action` mapping unit-tested (no headless InputEvent reliance).
- **Plan 6 — Phase 7 (Overlays):** mulligan, discard-to-limit, game-over panels.
- **Plan 7 — Phase 8 (AI + flow + menu):** `ai_controller.gd`, deck selection main menu, play-again; full vs-AI loop + manual smoke.
