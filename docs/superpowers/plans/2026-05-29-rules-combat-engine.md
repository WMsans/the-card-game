# Rules/Combat Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a headless, deterministic, test-driven rules/combat engine for VGDC: The Card Game that can play a full two-player game of stat-only ("vanilla") cards from setup to a deck-out win.

**Architecture:** Pure-data engine (`RefCounted` classes, no `Node`/`SceneTree`). The engine advances only through discrete `Action` objects; it exposes `get_legal_actions()` and `apply(action)`. State mutations publish `GameEvent`s onto an `EventBus`; a reaction-window mechanism for traps is wired in but inert for vanilla cards. RNG is seeded and injected for determinism.

**Tech Stack:** Godot 4.6.3, GDScript, GdUnit4 test framework.

**Spec:** `docs/superpowers/specs/2026-05-29-rules-combat-engine-design.md`

---

## File Structure

```
the-card-game/
  project.godot                     # Task 0
  addons/gdUnit4/                   # Task 0 (vendored test plugin)
  game/
    data/
      enums.gd                      # Task 1  (class_name Enums)
      card_definition.gd            # Task 2  (class_name CardDefinition)
      card_instance.gd              # Task 2  (class_name CardInstance)
      card_database.gd              # Task 3  (class_name CardDatabase)
      decks/                        # Task 3  (the four CSVs copied in)
    engine/
      seeded_rng.gd                 # Task 1  (class_name SeededRng)
      game_event.gd                 # Task 4  (class_name GameEvent)
      event_bus.gd                  # Task 4  (class_name EventBus)
      pending_choice.gd             # Task 5  (class_name PendingChoice)
      player_state.gd               # Task 5  (class_name PlayerState)
      game_state.gd                 # Task 5  (class_name GameState)
      action.gd                     # Task 6  (class_name Action)
      combat.gd                     # Task 11 (class_name Combat)
      game_engine.gd                # Tasks 7-13 (class_name GameEngine)
  tests/
    test_factory.gd                 # Task 7  (class_name TestFactory)
    test_*.gd                       # one GdUnit4 suite per task
```

**Responsibilities:**
- `enums.gd` — all engine enums in one place (Zone, Phase, CardType, EventType, ActionType).
- `card_definition.gd` / `card_instance.gd` — static card data vs. runtime card state.
- `card_database.gd` — parse CSV files into `CardDefinition`s.
- `seeded_rng.gd` — deterministic shuffle/range.
- `game_event.gd` / `event_bus.gd` — event objects + publish/subscribe log.
- `pending_choice.gd` / `player_state.gd` / `game_state.gd` — game data containers.
- `action.gd` — the single command type with static constructors.
- `combat.gd` — pure combat math (no side effects).
- `game_engine.gd` — all action processing, turn flow, legality, orchestration.
- `tests/test_factory.gd` — helper to build vanilla card definitions/decks without CSVs.

---

## Conventions used in every test task

**Run a single suite:**
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/<file>.gd
```
A passing run prints a summary with `0 failed` and exits `0`; a failure exits non-zero. (Defined and verified in Task 0.)

Every GdUnit4 suite is a script that `extends GdUnitTestSuite`; test methods are named `test_*`. Assertions: `assert_int(x).is_equal(n)`, `assert_bool(x).is_true()/.is_false()`, `assert_array(a).has_size(n)/.contains([...])`, `assert_object(o).is_null()/.is_not_null()`, `assert_str(s).is_equal("...")`.

---

## Task 0: Project bootstrap + GdUnit4

**Files:**
- Create: `project.godot`
- Create: `addons/gdUnit4/` (vendored)
- Create: `tests/test_smoke.gd`

- [ ] **Step 1: Create the Godot project file**

Create `project.godot`:
```ini
config_version=5

[application]
config/name="VGDC The Card Game"
config/features=PackedStringArray("4.6", "GL Compatibility")

[editor_plugins]
enabled=PackedStringArray("res://addons/gdUnit4/plugin.cfg")
```

- [ ] **Step 2: Vendor the GdUnit4 plugin**

Run:
```bash
git clone --depth 1 https://github.com/MikeSchulze/gdUnit4.git /tmp/gdunit4 \
  && mkdir -p addons \
  && cp -r /tmp/gdunit4/addons/gdUnit4 addons/ \
  && rm -rf /tmp/gdunit4
```
Expected: `addons/gdUnit4/plugin.cfg` and `addons/gdUnit4/bin/GdUnitCmdTool.gd` now exist.

- [ ] **Step 3: Import the project once (registers GdUnit4 `class_name`s)**

Run:
```bash
godot --headless --path "$PWD" --import
```
Expected: exits without fatal errors; a `.godot/` cache directory is created. (Harmless warnings are fine.)

- [ ] **Step 4: Write a smoke test**

Create `tests/test_smoke.gd`:
```gdscript
extends GdUnitTestSuite

func test_arithmetic() -> void:
	assert_int(2 + 2).is_equal(4)
```

- [ ] **Step 5: Run the smoke test and verify it passes**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_smoke.gd
```
Expected: summary shows 1 test, `0 failed`, exit code `0`. If `GdUnitTestSuite` is "not found", re-run Step 3 then retry.

- [ ] **Step 6: Add a .gitignore entry for the Godot cache**

Append to `.gitignore` (create if missing) a line:
```
.godot/
```

- [ ] **Step 7: Commit**

```bash
git add project.godot addons/gdUnit4 tests/test_smoke.gd .gitignore
git commit -m "chore: bootstrap Godot project with GdUnit4 and smoke test"
```

---

## Task 1: Enums and SeededRng

**Files:**
- Create: `game/data/enums.gd`
- Create: `game/engine/seeded_rng.gd`
- Test: `tests/test_seeded_rng.gd`

- [ ] **Step 1: Create the enums file**

Create `game/data/enums.gd`:
```gdscript
class_name Enums
extends RefCounted

enum Zone { DECK, HAND, BOARD, DISCARD, TRAP_SET, LEADER_SLOT }
enum Phase { SETUP, START, MAIN, END, GAME_OVER }
enum CardType { MINION, SPELL, TRAP, LEADER }
enum EventType {
	CARD_PLAYED, CARD_DRAWN, CARD_DISCARDED,
	UNIT_ATTACKED, UNIT_DAMAGED, UNIT_DIED,
	DECK_DAMAGED, DECK_RESHUFFLED,
	TURN_STARTED, TURN_ENDED, GAME_OVER,
}
enum ActionType { MULLIGAN, PLAY_CARD, DECLARE_ATTACK, END_TURN, ACTIVATE_TRAP, RESOLVE_CHOICE }
```

- [ ] **Step 2: Write the failing SeededRng test**

Create `tests/test_seeded_rng.gd`:
```gdscript
extends GdUnitTestSuite

func test_same_seed_shuffles_identically() -> void:
	var a := [1, 2, 3, 4, 5, 6, 7, 8]
	var b := [1, 2, 3, 4, 5, 6, 7, 8]
	SeededRng.new(42).shuffle(a)
	SeededRng.new(42).shuffle(b)
	assert_array(a).is_equal(b)

func test_different_seed_shuffles_differently() -> void:
	var a := [1, 2, 3, 4, 5, 6, 7, 8]
	var b := [1, 2, 3, 4, 5, 6, 7, 8]
	SeededRng.new(1).shuffle(a)
	SeededRng.new(2).shuffle(b)
	assert_array(a).is_not_equal(b)
```

- [ ] **Step 3: Run to verify it fails**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_seeded_rng.gd
```
Expected: FAIL — `SeededRng` is not a known class.

- [ ] **Step 4: Implement SeededRng**

Create `game/engine/seeded_rng.gd`:
```gdscript
class_name SeededRng
extends RefCounted

var _rng := RandomNumberGenerator.new()

func _init(seed_value: int) -> void:
	_rng.seed = seed_value

func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)

func shuffle(arr: Array) -> void:
	# Deterministic Fisher-Yates using the seeded generator.
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
```

- [ ] **Step 5: Run to verify it passes**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_seeded_rng.gd
```
Expected: 2 tests, `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add game/data/enums.gd game/engine/seeded_rng.gd tests/test_seeded_rng.gd
git commit -m "feat: add enums and deterministic seeded RNG"
```

---

## Task 2: CardDefinition and CardInstance

**Files:**
- Create: `game/data/card_definition.gd`
- Create: `game/data/card_instance.gd`
- Test: `tests/test_card_instance.gd`

- [ ] **Step 1: Create CardDefinition**

Create `game/data/card_definition.gd`:
```gdscript
class_name CardDefinition
extends RefCounted

var id: int = 0
var deck_color: String = ""
var type: int = Enums.CardType.MINION
var name: String = ""
var ticket_cost: int = 0
var alt_discard_cost: int = 0
var base_damage: int = 0
var base_health: int = 0
var ability_text: String = ""
var flavor: String = ""
var keywords: Array[String] = []
```

- [ ] **Step 2: Write the failing CardInstance test**

Create `tests/test_card_instance.gd`:
```gdscript
extends GdUnitTestSuite

func _make_def() -> CardDefinition:
	var d := CardDefinition.new()
	d.type = Enums.CardType.MINION
	d.base_damage = 3
	d.base_health = 2
	return d

func test_instance_copies_base_stats() -> void:
	var inst := CardInstance.new(7, _make_def())
	assert_int(inst.instance_id).is_equal(7)
	assert_int(inst.current_damage).is_equal(3)
	assert_int(inst.current_health).is_equal(2)
	assert_bool(inst.tapped).is_false()

func test_reset_stats_restores_base() -> void:
	var inst := CardInstance.new(1, _make_def())
	inst.current_health = 0
	inst.reset_stats()
	assert_int(inst.current_health).is_equal(2)

func test_is_unit() -> void:
	var inst := CardInstance.new(1, _make_def())
	assert_bool(inst.is_unit()).is_true()
```

- [ ] **Step 3: Run to verify it fails**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_card_instance.gd
```
Expected: FAIL — `CardInstance` not found.

- [ ] **Step 4: Implement CardInstance**

Create `game/data/card_instance.gd`:
```gdscript
class_name CardInstance
extends RefCounted

var instance_id: int
var definition: CardDefinition
var zone: int = Enums.Zone.DECK
var tapped: bool = false
var current_damage: int
var current_health: int

func _init(id: int, def: CardDefinition) -> void:
	instance_id = id
	definition = def
	current_damage = def.base_damage
	current_health = def.base_health

func reset_stats() -> void:
	current_damage = definition.base_damage
	current_health = definition.base_health

func is_unit() -> bool:
	return definition.type == Enums.CardType.MINION or definition.type == Enums.CardType.LEADER
```

- [ ] **Step 5: Run to verify it passes**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_card_instance.gd
```
Expected: 3 tests, `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add game/data/card_definition.gd game/data/card_instance.gd tests/test_card_instance.gd
git commit -m "feat: add CardDefinition and CardInstance data types"
```

---

## Task 3: CardDatabase CSV loader

**Files:**
- Create: `game/data/decks/{strike,raccoon,writing,audio}.csv` (copied)
- Create: `game/data/card_database.gd`
- Test: `tests/test_card_database.gd`

- [ ] **Step 1: Copy the CSVs into the project**

Run:
```bash
mkdir -p game/data/decks
cp "docs/design_docs/Card List/Strike Deck v2.csv" game/data/decks/strike.csv
cp "docs/design_docs/Card List/Raccoon Deck v2.csv" game/data/decks/raccoon.csv
cp "docs/design_docs/Card List/Writing Deck v2.csv" game/data/decks/writing.csv
cp "docs/design_docs/Card List/Audio Deck v2.csv" game/data/decks/audio.csv
```
Expected: four files now under `game/data/decks/`.

- [ ] **Step 2: Re-import so the new files are visible to `res://`**

Run:
```bash
godot --headless --path "$PWD" --import
```

- [ ] **Step 3: Write the failing CardDatabase test**

Create `tests/test_card_database.gd`:
```gdscript
extends GdUnitTestSuite

func test_strike_deck_has_one_leader_and_twenty_cards() -> void:
	var defs := CardDatabase.load_deck("res://game/data/decks/strike.csv", "Strike")
	var leaders := defs.filter(func(d): return d.type == Enums.CardType.LEADER)
	var non_leaders := defs.filter(func(d): return d.type != Enums.CardType.LEADER)
	assert_array(leaders).has_size(1)
	assert_array(non_leaders).has_size(20)

func test_leader_cost_and_discard_cost_parsed() -> void:
	# Strike row 1: "Battle Bjorn", cost "7 / Discard 4", 2 / 10
	var defs := CardDatabase.load_deck("res://game/data/decks/strike.csv", "Strike")
	var bjorn: CardDefinition = defs.filter(func(d): return d.type == Enums.CardType.LEADER)[0]
	assert_int(bjorn.ticket_cost).is_equal(7)
	assert_int(bjorn.alt_discard_cost).is_equal(4)
	assert_int(bjorn.base_damage).is_equal(2)
	assert_int(bjorn.base_health).is_equal(10)
	assert_str(bjorn.deck_color).is_equal("Strike")

func test_parenthetical_stat_takes_base_value() -> void:
	# Audio "Quarter Note": Damage "1 (3)" -> base 1
	var defs := CardDatabase.load_deck("res://game/data/decks/audio.csv", "Audio")
	var quarter: CardDefinition = defs.filter(func(d): return d.name == "Quarter Note")[0]
	assert_int(quarter.base_damage).is_equal(1)

func test_spell_has_zero_stats() -> void:
	# Spells have blank Damage/Health -> 0
	var defs := CardDatabase.load_deck("res://game/data/decks/raccoon.csv", "Raccoon")
	var spell: CardDefinition = defs.filter(func(d): return d.type == Enums.CardType.SPELL)[0]
	assert_int(spell.base_damage).is_equal(0)
	assert_int(spell.base_health).is_equal(0)

func test_all_four_decks_load_without_error() -> void:
	for path in ["strike", "raccoon", "writing", "audio"]:
		var defs := CardDatabase.load_deck("res://game/data/decks/%s.csv" % path, path)
		assert_array(defs).is_not_empty()
```

- [ ] **Step 4: Run to verify it fails**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_card_database.gd
```
Expected: FAIL — `CardDatabase` not found.

- [ ] **Step 5: Implement CardDatabase**

Create `game/data/card_database.gd`:
```gdscript
class_name CardDatabase
extends RefCounted

const KNOWN_KEYWORDS := [
	"REQUEST", "RUMMAGE", "TRASH", "ORANGE", "HARMONIZE", "CLEF",
	"TAUNT", "BOMB", "DETONATE", "DEFUSE", "CYCLE", "MILL",
	"SCRAPPED", "EMPOWERED", "OVERCHARGE", "RECYCLE", "HARMONIZED", "REMOVED",
]

# Column indices (0-based) common to all four CSVs:
# 0=id 1=Type 2=Name 3=Cost 4=Damage 5=Health 6=Ability 7=Flavor 8=Image
static func load_deck(path: String, deck_color: String) -> Array[CardDefinition]:
	var defs: Array[CardDefinition] = []
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "Could not open %s" % path)
	f.get_csv_line() # discard the header row
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 9:
			continue # blank or truncated line
		if row[1].strip_edges() == "":
			continue # no Type -> not a real card row
		defs.append(_parse_row(row, deck_color))
	f.close()
	return defs

static func _parse_row(row: PackedStringArray, deck_color: String) -> CardDefinition:
	var d := CardDefinition.new()
	d.deck_color = deck_color
	d.id = int(row[0].strip_edges())
	d.type = _parse_type(row[1])
	d.name = row[2].strip_edges()
	var cost := _parse_cost(row[3])
	d.ticket_cost = cost[0]
	d.alt_discard_cost = cost[1]
	d.base_damage = _parse_leading_int(row[4])
	d.base_health = _parse_leading_int(row[5])
	d.ability_text = row[6].strip_edges()
	d.flavor = row[7].strip_edges()
	d.keywords = _extract_keywords(d.ability_text)
	return d

static func _parse_type(s: String) -> int:
	match s.strip_edges().to_lower():
		"minion": return Enums.CardType.MINION
		"spell": return Enums.CardType.SPELL
		"trap": return Enums.CardType.TRAP
		"leader": return Enums.CardType.LEADER
		_: return Enums.CardType.MINION

# Returns [ticket_cost, alt_discard_cost].
# "7 / Discard 4" -> [7, 4];  "1" -> [1, 0]
static func _parse_cost(s: String) -> Array:
	var parts := s.split("/")
	var ticket := _parse_leading_int(parts[0])
	var discard := 0
	if parts.size() > 1:
		discard = _parse_leading_int(parts[1])
	return [ticket, discard]

# First signed integer in the string, else 0. "1 (3)" -> 1, "" -> 0.
static func _parse_leading_int(s: String) -> int:
	var re := RegEx.new()
	re.compile("-?\\d+")
	var m := re.search(s)
	return int(m.get_string()) if m != null else 0

static func _extract_keywords(text: String) -> Array[String]:
	var found: Array[String] = []
	var upper := text.to_upper()
	for kw in KNOWN_KEYWORDS:
		if upper.contains(kw) and not found.has(kw):
			found.append(kw)
	return found
```

- [ ] **Step 6: Run to verify it passes**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_card_database.gd
```
Expected: 5 tests, `0 failed`. (If a deck reports 21 non-leader rows due to a stray data row, inspect that CSV; the loader's `row[1]` empty-check should already skip blank lines.)

- [ ] **Step 7: Commit**

```bash
git add game/data/decks game/data/card_database.gd tests/test_card_database.gd
git commit -m "feat: parse deck CSVs into CardDefinitions"
```

---

## Task 4: GameEvent and EventBus

**Files:**
- Create: `game/engine/game_event.gd`
- Create: `game/engine/event_bus.gd`
- Test: `tests/test_event_bus.gd`

- [ ] **Step 1: Create GameEvent**

Create `game/engine/game_event.gd`:
```gdscript
class_name GameEvent
extends RefCounted

var type: int
var data: Dictionary

func _init(t: int, d: Dictionary = {}) -> void:
	type = t
	data = d
```

- [ ] **Step 2: Write the failing EventBus test**

Create `tests/test_event_bus.gd`:
```gdscript
extends GdUnitTestSuite

func test_publish_appends_to_log() -> void:
	var bus := EventBus.new()
	bus.publish(GameEvent.new(Enums.EventType.TURN_STARTED, {"player": 0}))
	assert_array(bus.log).has_size(1)
	assert_int(bus.log[0].type).is_equal(Enums.EventType.TURN_STARTED)

func test_subscribers_are_notified() -> void:
	var bus := EventBus.new()
	var seen := []
	bus.subscribe(func(e: GameEvent): seen.append(e.type))
	bus.publish(GameEvent.new(Enums.EventType.CARD_DRAWN))
	assert_array(seen).is_equal([Enums.EventType.CARD_DRAWN])

func test_events_of_type_filters() -> void:
	var bus := EventBus.new()
	bus.publish(GameEvent.new(Enums.EventType.CARD_DRAWN))
	bus.publish(GameEvent.new(Enums.EventType.TURN_ENDED))
	bus.publish(GameEvent.new(Enums.EventType.CARD_DRAWN))
	assert_array(bus.events_of_type(Enums.EventType.CARD_DRAWN)).has_size(2)
```

- [ ] **Step 3: Run to verify it fails**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_event_bus.gd
```
Expected: FAIL — `EventBus` not found.

- [ ] **Step 4: Implement EventBus**

Create `game/engine/event_bus.gd`:
```gdscript
class_name EventBus
extends RefCounted

var log: Array[GameEvent] = []
var _listeners: Array[Callable] = []

func subscribe(cb: Callable) -> void:
	_listeners.append(cb)

func publish(event: GameEvent) -> void:
	log.append(event)
	for cb in _listeners:
		cb.call(event)

func events_of_type(t: int) -> Array:
	return log.filter(func(e: GameEvent): return e.type == t)
```

- [ ] **Step 5: Run to verify it passes**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_event_bus.gd
```
Expected: 3 tests, `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add game/engine/game_event.gd game/engine/event_bus.gd tests/test_event_bus.gd
git commit -m "feat: add GameEvent and EventBus"
```

---

## Task 5: PendingChoice, PlayerState, GameState

**Files:**
- Create: `game/engine/pending_choice.gd`
- Create: `game/engine/player_state.gd`
- Create: `game/engine/game_state.gd`
- Test: `tests/test_game_state.gd`

- [ ] **Step 1: Create PendingChoice**

Create `game/engine/pending_choice.gd`:
```gdscript
class_name PendingChoice
extends RefCounted

var kind: String
var player: int
var data: Dictionary

func _init(k: String, p: int, d: Dictionary = {}) -> void:
	kind = k
	player = p
	data = d
```

- [ ] **Step 2: Create PlayerState**

Create `game/engine/player_state.gd`:
```gdscript
class_name PlayerState
extends RefCounted

var deck: Array[CardInstance] = []
var hand: Array[CardInstance] = []
var board: Array[CardInstance] = []
var discard: Array[CardInstance] = []
var set_traps: Array[CardInstance] = []
var leader: CardInstance = null
var tickets_total: int = 0
var tickets_tapped: int = 0
var reshuffles_remaining: int = 4
var turns_taken: int = 0
var turn_counters: Dictionary = {}

func _init() -> void:
	reset_turn_counters()

func available_tickets() -> int:
	return tickets_total - tickets_tapped

func reset_turn_counters() -> void:
	turn_counters = {
		"cards_played": 0,
		"cards_discarded": 0,
		"attacks_made": 0,
		"units_died": 0,
	}
```

- [ ] **Step 3: Write the failing GameState test**

Create `tests/test_game_state.gd`:
```gdscript
extends GdUnitTestSuite

func test_initial_state() -> void:
	var s := GameState.new(123)
	assert_array(s.players).has_size(2)
	assert_int(s.active_player).is_equal(0)
	assert_int(s.phase).is_equal(Enums.Phase.SETUP)
	assert_int(s.winner).is_equal(-1)
	assert_object(s.bus).is_not_null()
	assert_object(s.rng).is_not_null()

func test_opponent_and_active() -> void:
	var s := GameState.new(1)
	s.active_player = 1
	assert_int(s.opponent()).is_equal(0)
	assert_object(s.active()).is_same(s.players[1])

func test_make_instance_assigns_unique_ids() -> void:
	var s := GameState.new(1)
	var def := CardDefinition.new()
	var a := s.make_instance(def)
	var b := s.make_instance(def)
	assert_int(a.instance_id).is_not_equal(b.instance_id)

func test_player_defaults() -> void:
	var p := PlayerState.new()
	assert_int(p.reshuffles_remaining).is_equal(4)
	assert_int(p.available_tickets()).is_equal(0)
	assert_int(p.turn_counters["cards_played"]).is_equal(0)
```

- [ ] **Step 4: Run to verify it fails**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_game_state.gd
```
Expected: FAIL — `GameState` not found.

- [ ] **Step 5: Implement GameState**

Create `game/engine/game_state.gd`:
```gdscript
class_name GameState
extends RefCounted

var players: Array[PlayerState] = []
var active_player: int = 0
var first_player: int = 0
var turn_number: int = 0
var phase: int = Enums.Phase.SETUP
var rng: SeededRng
var bus: EventBus
var pending_choice: PendingChoice = null
var winner: int = -1
var _next_instance_id: int = 1

func _init(seed_value: int) -> void:
	rng = SeededRng.new(seed_value)
	bus = EventBus.new()
	players = [PlayerState.new(), PlayerState.new()]

func opponent() -> int:
	return 1 - active_player

func active() -> PlayerState:
	return players[active_player]

func make_instance(def: CardDefinition) -> CardInstance:
	var ci := CardInstance.new(_next_instance_id, def)
	_next_instance_id += 1
	return ci
```

- [ ] **Step 6: Run to verify it passes**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_game_state.gd
```
Expected: 4 tests, `0 failed`.

- [ ] **Step 7: Commit**

```bash
git add game/engine/pending_choice.gd game/engine/player_state.gd game/engine/game_state.gd tests/test_game_state.gd
git commit -m "feat: add PendingChoice, PlayerState, and GameState"
```

---

## Task 6: Action type

**Files:**
- Create: `game/engine/action.gd`
- Test: `tests/test_action.gd`

- [ ] **Step 1: Write the failing Action test**

Create `tests/test_action.gd`:
```gdscript
extends GdUnitTestSuite

func test_play_card_merges_options() -> void:
	var a := Action.play_card(5, {"pay_by_discard": true})
	assert_int(a.type).is_equal(Enums.ActionType.PLAY_CARD)
	assert_int(a.params["instance_id"]).is_equal(5)
	assert_bool(a.params["pay_by_discard"]).is_true()

func test_declare_attack_deck_target() -> void:
	var a := Action.declare_attack(9, {"deck": true})
	assert_int(a.type).is_equal(Enums.ActionType.DECLARE_ATTACK)
	assert_int(a.params["attacker_id"]).is_equal(9)
	assert_bool(a.params["target"]["deck"]).is_true()

func test_simple_constructors() -> void:
	assert_int(Action.end_turn().type).is_equal(Enums.ActionType.END_TURN)
	assert_int(Action.mulligan([0, 1]).type).is_equal(Enums.ActionType.MULLIGAN)
	assert_int(Action.resolve_choice({"indices": [0]}).type).is_equal(Enums.ActionType.RESOLVE_CHOICE)
```

- [ ] **Step 2: Run to verify it fails**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_action.gd
```
Expected: FAIL — `Action` not found.

- [ ] **Step 3: Implement Action**

Create `game/engine/action.gd`:
```gdscript
class_name Action
extends RefCounted

var type: int
var params: Dictionary

func _init(t: int, p: Dictionary = {}) -> void:
	type = t
	params = p

static func mulligan(indices: Array) -> Action:
	return Action.new(Enums.ActionType.MULLIGAN, {"indices": indices})

static func play_card(instance_id: int, opts: Dictionary = {}) -> Action:
	var p := {"instance_id": instance_id}
	p.merge(opts)
	return Action.new(Enums.ActionType.PLAY_CARD, p)

static func declare_attack(attacker_id: int, target: Dictionary) -> Action:
	return Action.new(Enums.ActionType.DECLARE_ATTACK, {"attacker_id": attacker_id, "target": target})

static func end_turn() -> Action:
	return Action.new(Enums.ActionType.END_TURN)

static func activate_trap(instance_id: int) -> Action:
	return Action.new(Enums.ActionType.ACTIVATE_TRAP, {"instance_id": instance_id})

static func resolve_choice(data: Dictionary) -> Action:
	return Action.new(Enums.ActionType.RESOLVE_CHOICE, data)
```

- [ ] **Step 4: Run to verify it passes**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_action.gd
```
Expected: 3 tests, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add game/engine/action.gd tests/test_action.gd
git commit -m "feat: add Action command type with static constructors"
```

---

## Task 7: GameEngine — deck operations (draw, mill, reshuffle, loss)

**Files:**
- Create: `tests/test_factory.gd`
- Create: `game/engine/game_engine.gd`
- Test: `tests/test_engine_deck_ops.gd`

- [ ] **Step 1: Create the test factory**

Create `tests/test_factory.gd`:
```gdscript
class_name TestFactory
extends RefCounted

static func minion(cost: int, dmg: int, hp: int, id: int = 1) -> CardDefinition:
	var d := CardDefinition.new()
	d.id = id
	d.name = "M%d" % id
	d.type = Enums.CardType.MINION
	d.ticket_cost = cost
	d.base_damage = dmg
	d.base_health = hp
	d.deck_color = "Test"
	return d

static func leader(cost: int, dmg: int, hp: int, alt: int) -> CardDefinition:
	var d := CardDefinition.new()
	d.id = 0
	d.name = "Leader"
	d.type = Enums.CardType.LEADER
	d.ticket_cost = cost
	d.alt_discard_cost = alt
	d.base_damage = dmg
	d.base_health = hp
	d.deck_color = "Test"
	return d

static func spell(cost: int, id: int = 1) -> CardDefinition:
	var d := CardDefinition.new()
	d.id = id
	d.name = "S%d" % id
	d.type = Enums.CardType.SPELL
	d.ticket_cost = cost
	d.deck_color = "Test"
	return d

static func trap(cost: int, id: int = 1) -> CardDefinition:
	var d := CardDefinition.new()
	d.id = id
	d.name = "T%d" % id
	d.type = Enums.CardType.TRAP
	d.ticket_cost = cost
	d.deck_color = "Test"
	return d

# 1 leader + 20 vanilla minions (cost 1, 1/1).
static func simple_deck() -> Array[CardDefinition]:
	var defs: Array[CardDefinition] = []
	defs.append(leader(2, 2, 5, 4))
	for i in range(20):
		defs.append(minion(1, 1, 1, i + 100))
	return defs
```

- [ ] **Step 2: Write the failing deck-ops test**

Create `tests/test_engine_deck_ops.gd`:
```gdscript
extends GdUnitTestSuite

func _engine_with_deck(n_cards: int) -> GameEngine:
	var state := GameState.new(1)
	var eng := GameEngine.new(state)
	for i in range(n_cards):
		var ci := state.make_instance(TestFactory.minion(1, 1, 1, i))
		ci.zone = Enums.Zone.DECK
		state.players[0].deck.append(ci)
	return eng

func test_draw_moves_card_to_hand() -> void:
	var eng := _engine_with_deck(5)
	eng._draw(0, 2)
	assert_array(eng.state.players[0].hand).has_size(2)
	assert_array(eng.state.players[0].deck).has_size(3)

func test_mill_moves_cards_to_discard() -> void:
	var eng := _engine_with_deck(5)
	eng._mill(0, 3)
	assert_array(eng.state.players[0].discard).has_size(3)
	assert_array(eng.state.players[0].deck).has_size(2)

func test_empty_deck_reshuffles_discard() -> void:
	var eng := _engine_with_deck(2)
	eng._mill(0, 2)            # deck now empty, 2 in discard
	eng._draw(0, 1)            # needs a card -> reshuffle, consume one
	var p := eng.state.players[0]
	assert_int(p.reshuffles_remaining).is_equal(3)
	assert_array(p.hand).has_size(1)

func test_running_out_of_reshuffles_loses() -> void:
	var eng := _engine_with_deck(1)
	var p := eng.state.players[0]
	p.reshuffles_remaining = 0
	eng._mill(0, 1)            # deck empty, 1 in discard
	eng._draw(0, 1)            # needs card, no reshuffles left -> lose
	assert_int(eng.state.phase).is_equal(Enums.Phase.GAME_OVER)
	assert_int(eng.state.winner).is_equal(1)
```

- [ ] **Step 3: Run to verify it fails**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_engine_deck_ops.gd
```
Expected: FAIL — `GameEngine` not found.

- [ ] **Step 4: Implement GameEngine deck operations**

Create `game/engine/game_engine.gd`:
```gdscript
class_name GameEngine
extends RefCounted

var state: GameState

func _init(game_state: GameState) -> void:
	state = game_state

# --- deck operations -------------------------------------------------------

func _draw(player_idx: int, n: int = 1) -> void:
	var ps := state.players[player_idx]
	for i in range(n):
		if ps.deck.is_empty() and not _reshuffle_or_lose(player_idx):
			return
		if ps.deck.is_empty():
			return
		var card: CardInstance = ps.deck.pop_front()
		card.zone = Enums.Zone.HAND
		ps.hand.append(card)
		state.bus.publish(GameEvent.new(Enums.EventType.CARD_DRAWN,
			{"player": player_idx, "instance": card.instance_id}))

# Move n cards off the top of the deck into discard (used by deck damage and
# the leader's discard-cost). Triggers reshuffle/loss when the deck empties.
func _mill(player_idx: int, n: int) -> void:
	var ps := state.players[player_idx]
	for i in range(n):
		if ps.deck.is_empty() and not _reshuffle_or_lose(player_idx):
			return
		if ps.deck.is_empty():
			return
		var card: CardInstance = ps.deck.pop_front()
		card.zone = Enums.Zone.DISCARD
		ps.discard.append(card)
		ps.turn_counters["cards_discarded"] += 1
		state.bus.publish(GameEvent.new(Enums.EventType.CARD_DISCARDED,
			{"player": player_idx, "instance": card.instance_id}))

func _deck_damage(player_idx: int, amount: int) -> void:
	_mill(player_idx, amount)
	state.bus.publish(GameEvent.new(Enums.EventType.DECK_DAMAGED,
		{"player": player_idx, "amount": amount}))

# Returns true if the player can continue, false if they have lost.
func _reshuffle_or_lose(player_idx: int) -> bool:
	var ps := state.players[player_idx]
	if ps.reshuffles_remaining <= 0:
		_lose(player_idx)
		return false
	ps.reshuffles_remaining -= 1
	ps.deck.append_array(ps.discard)
	ps.discard.clear()
	for c in ps.deck:
		c.zone = Enums.Zone.DECK
	state.rng.shuffle(ps.deck)
	state.bus.publish(GameEvent.new(Enums.EventType.DECK_RESHUFFLED,
		{"player": player_idx, "remaining": ps.reshuffles_remaining}))
	if ps.deck.is_empty():
		_lose(player_idx)
		return false
	return true

func _lose(player_idx: int) -> void:
	state.winner = 1 - player_idx
	state.phase = Enums.Phase.GAME_OVER
	state.bus.publish(GameEvent.new(Enums.EventType.GAME_OVER, {"winner": state.winner}))
```

- [ ] **Step 5: Run to verify it passes**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_engine_deck_ops.gd
```
Expected: 4 tests, `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add tests/test_factory.gd game/engine/game_engine.gd tests/test_engine_deck_ops.gd
git commit -m "feat: engine deck ops (draw, mill, reshuffle, loss)"
```

---

## Task 8: GameEngine — setup, mulligan, turn start, ticket ramp

**Files:**
- Modify: `game/engine/game_engine.gd`
- Test: `tests/test_engine_setup.gd`

- [ ] **Step 1: Write the failing setup/turn test**

Create `tests/test_engine_setup.gd`:
```gdscript
extends GdUnitTestSuite

func _started_engine(seed_value: int) -> GameEngine:
	var state := GameState.new(seed_value)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	# Resolve both mulligans (discard the first two non-leader cards).
	eng.apply(Action.mulligan([0, 1]))
	eng.apply(Action.mulligan([0, 1]))
	return eng

func test_setup_draws_leader_into_hand() -> void:
	var state := GameState.new(7)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	# Before mulligan: leader + 5 drawn = 6 cards in hand.
	assert_array(state.players[0].hand).has_size(6)
	assert_object(state.players[0].leader).is_not_null()

func test_pending_mulligan_is_set_for_player_zero_first() -> void:
	var state := GameState.new(7)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	assert_str(state.pending_choice.kind).is_equal("mulligan")
	assert_int(state.pending_choice.player).is_equal(0)

func test_after_both_mulligans_game_begins_in_main() -> void:
	var eng := _started_engine(7)
	assert_object(eng.state.pending_choice).is_null()
	assert_int(eng.state.phase).is_equal(Enums.Phase.MAIN)
	assert_int(eng.state.turn_number).is_equal(1)

func test_mulligan_reduces_hand_then_first_draw_restores() -> void:
	var eng := _started_engine(7)
	# leader + 3 kept + 1 drawn at turn start = 5
	assert_array(eng.state.players[0].hand).has_size(5)

func test_first_player_gets_one_ticket_second_gets_two() -> void:
	var eng := _started_engine(7)
	var first := eng.state.first_player
	var second := 1 - first
	assert_int(eng.state.players[first].tickets_total).is_equal(1)
	# Second player's tickets are still 0 until their turn starts.
	assert_int(eng.state.players[second].tickets_total).is_equal(0)

func test_ticket_ramp_caps_at_ten() -> void:
	var ps := PlayerState.new()
	ps.tickets_total = 9
	# simulate two ramps
	ps.tickets_total = min(10, ps.tickets_total + 2)
	ps.tickets_total = min(10, ps.tickets_total + 2)
	assert_int(ps.tickets_total).is_equal(10)
```

- [ ] **Step 2: Run to verify it fails**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_engine_setup.gd
```
Expected: FAIL — `setup` not defined.

- [ ] **Step 3: Implement setup, mulligan, turn start**

Add to `game/engine/game_engine.gd` (append these methods inside the class):
```gdscript
# --- setup -----------------------------------------------------------------

func setup(deck0: Array[CardDefinition], deck1: Array[CardDefinition]) -> void:
	_build_player(0, deck0)
	_build_player(1, deck1)
	state.rng.shuffle(state.players[0].deck)
	state.rng.shuffle(state.players[1].deck)
	_draw(0, 5)
	_draw(1, 5)
	state.pending_choice = PendingChoice.new("mulligan", 0)

func _build_player(idx: int, defs: Array[CardDefinition]) -> void:
	var ps := state.players[idx]
	for def in defs:
		var ci := state.make_instance(def)
		if def.type == Enums.CardType.LEADER:
			ci.zone = Enums.Zone.HAND
			ps.leader = ci
			ps.hand.append(ci)
		else:
			ci.zone = Enums.Zone.DECK
			ps.deck.append(ci)

func _apply_mulligan(indices: Array) -> void:
	var p := state.pending_choice.player
	var ps := state.players[p]
	var to_discard: Array[CardInstance] = []
	for i in indices:
		to_discard.append(ps.hand[i])
	for c in to_discard:
		ps.hand.erase(c)
		c.zone = Enums.Zone.DISCARD
		ps.discard.append(c)
		ps.turn_counters["cards_discarded"] += 1
	if p == 0:
		state.pending_choice = PendingChoice.new("mulligan", 1)
	else:
		state.pending_choice = null
		state.first_player = state.rng.randi_range(0, 1)
		state.active_player = state.first_player
		_start_turn()

# --- turn flow -------------------------------------------------------------

func _start_turn() -> void:
	state.phase = Enums.Phase.START
	state.turn_number += 1
	var ps := state.active()
	for u in ps.board:
		u.tapped = false
	ps.tickets_tapped = 0
	if ps.turns_taken == 0:
		ps.tickets_total = 1 if state.active_player == state.first_player else 2
	else:
		ps.tickets_total = min(10, ps.tickets_total + 2)
	ps.turns_taken += 1
	ps.reset_turn_counters()
	state.bus.publish(GameEvent.new(Enums.EventType.TURN_STARTED, {"player": state.active_player}))
	_draw(state.active_player, 1)
	if state.phase == Enums.Phase.GAME_OVER:
		return
	state.phase = Enums.Phase.MAIN
```

Also add the public `apply` dispatcher (it will grow in later tasks):
```gdscript
# --- controller interface --------------------------------------------------

func apply(action: Action) -> void:
	match action.type:
		Enums.ActionType.MULLIGAN:
			_apply_mulligan(action.params["indices"])
		_:
			push_error("Unhandled action type %d" % action.type)
```

- [ ] **Step 4: Run to verify it passes**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_engine_setup.gd
```
Expected: 6 tests, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add game/engine/game_engine.gd tests/test_engine_setup.gd
git commit -m "feat: engine setup, mulligan, turn start, ticket ramp"
```

---

## Task 9: GameEngine — playing cards

**Files:**
- Modify: `game/engine/game_engine.gd`
- Test: `tests/test_engine_play.gd`

- [ ] **Step 1: Write the failing play-card test**

Create `tests/test_engine_play.gd`:
```gdscript
extends GdUnitTestSuite

# Build an engine in MAIN phase with controlled hands.
func _ready_engine() -> GameEngine:
	var state := GameState.new(5)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	eng.apply(Action.mulligan([0, 1]))
	eng.apply(Action.mulligan([0, 1]))
	return eng

# Put a specific definition into the active player's hand, return its instance.
func _give(eng: GameEngine, def: CardDefinition) -> CardInstance:
	var ps := eng.state.active()
	var ci := eng.state.make_instance(def)
	ci.zone = Enums.Zone.HAND
	ps.hand.append(ci)
	ps.tickets_total = 10
	ps.tickets_tapped = 0
	return ci

func test_play_minion_enters_board_tapped_and_pays_tickets() -> void:
	var eng := _ready_engine()
	var ci := _give(eng, TestFactory.minion(3, 4, 4, 200))
	eng.apply(Action.play_card(ci.instance_id))
	var ps := eng.state.active()
	assert_array(ps.board).contains([ci])
	assert_bool(ci.tapped).is_true()
	assert_int(ps.tickets_tapped).is_equal(3)
	assert_int(ps.turn_counters["cards_played"]).is_equal(1)

func test_play_spell_goes_to_discard() -> void:
	var eng := _ready_engine()
	var ci := _give(eng, TestFactory.spell(2, 201))
	eng.apply(Action.play_card(ci.instance_id))
	assert_array(eng.state.active().discard).contains([ci])

func test_play_trap_is_set_face_down() -> void:
	var eng := _ready_engine()
	var ci := _give(eng, TestFactory.trap(2, 202))
	eng.apply(Action.play_card(ci.instance_id))
	assert_array(eng.state.active().set_traps).contains([ci])
	assert_int(ci.zone).is_equal(Enums.Zone.TRAP_SET)

func test_play_leader_by_discard_cost_mills_deck() -> void:
	var eng := _ready_engine()
	var ci := _give(eng, TestFactory.leader(7, 2, 5, 4))
	var deck_before := eng.state.active().deck.size()
	eng.apply(Action.play_card(ci.instance_id, {"pay_by_discard": true}))
	var ps := eng.state.active()
	assert_array(ps.board).contains([ci])
	assert_int(ps.tickets_tapped).is_equal(0)        # paid by discard, not tickets
	assert_int(ps.deck.size()).is_equal(deck_before - 4)
```

- [ ] **Step 2: Run to verify it fails**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_engine_play.gd
```
Expected: FAIL — play actions hit the `push_error` default branch / `_play_card` undefined.

- [ ] **Step 3: Implement card playing**

In `game/engine/game_engine.gd`, extend the `apply` match with the play branch:
```gdscript
		Enums.ActionType.PLAY_CARD:
			_play_card(action.params["instance_id"], action.params)
```

Add the method:
```gdscript
func _play_card(instance_id: int, params: Dictionary) -> void:
	var ps := state.active()
	var card: CardInstance = _find_in_hand(ps, instance_id)
	var def := card.definition
	var pay_by_discard: bool = params.get("pay_by_discard", false)
	if def.type == Enums.CardType.LEADER and pay_by_discard:
		_mill(state.active_player, def.alt_discard_cost)
	else:
		ps.tickets_tapped += def.ticket_cost
	ps.hand.erase(card)
	ps.turn_counters["cards_played"] += 1
	match def.type:
		Enums.CardType.MINION, Enums.CardType.LEADER:
			card.zone = Enums.Zone.BOARD
			card.tapped = true   # units played this turn start tapped
			ps.board.append(card)
		Enums.CardType.SPELL:
			card.zone = Enums.Zone.DISCARD
			ps.discard.append(card)
		Enums.CardType.TRAP:
			card.zone = Enums.Zone.TRAP_SET
			ps.set_traps.append(card)
	state.bus.publish(GameEvent.new(Enums.EventType.CARD_PLAYED,
		{"player": state.active_player, "instance": instance_id, "card_type": def.type}))

func _find_in_hand(ps: PlayerState, instance_id: int) -> CardInstance:
	for c in ps.hand:
		if c.instance_id == instance_id:
			return c
	return null
```

- [ ] **Step 4: Run to verify it passes**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_engine_play.gd
```
Expected: 4 tests, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add game/engine/game_engine.gd tests/test_engine_play.gd
git commit -m "feat: engine card playing (minion/spell/trap/leader)"
```

---

## Task 10: GameEngine — end turn (hand limit, full heal, pass)

**Files:**
- Modify: `game/engine/game_engine.gd`
- Test: `tests/test_engine_end_turn.gd`

- [ ] **Step 1: Write the failing end-turn test**

Create `tests/test_engine_end_turn.gd`:
```gdscript
extends GdUnitTestSuite

func _ready_engine() -> GameEngine:
	var state := GameState.new(11)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	eng.apply(Action.mulligan([0, 1]))
	eng.apply(Action.mulligan([0, 1]))
	return eng

func test_end_turn_passes_to_opponent_and_starts_their_turn() -> void:
	var eng := _ready_engine()
	var first := eng.state.active_player
	eng.apply(Action.end_turn())
	assert_int(eng.state.active_player).is_equal(1 - first)
	assert_int(eng.state.phase).is_equal(Enums.Phase.MAIN)

func test_end_turn_full_heals_damaged_units() -> void:
	var eng := _ready_engine()
	var ps := eng.state.active()
	var u := eng.state.make_instance(TestFactory.minion(1, 2, 5, 300))
	u.current_health = 1
	u.zone = Enums.Zone.BOARD
	ps.board.append(u)
	eng.apply(Action.end_turn())
	assert_int(u.current_health).is_equal(5)

func test_over_limit_hand_requires_discard_choice() -> void:
	var eng := _ready_engine()
	var ps := eng.state.active()
	# Force hand to 7 cards.
	while ps.hand.size() < 7:
		var c := eng.state.make_instance(TestFactory.minion(1, 1, 1, ps.hand.size()))
		c.zone = Enums.Zone.HAND
		ps.hand.append(c)
	eng.apply(Action.end_turn())
	assert_object(eng.state.pending_choice).is_not_null()
	assert_str(eng.state.pending_choice.kind).is_equal("discard_to_limit")
	assert_int(eng.state.pending_choice.data["count"]).is_equal(2)
	# Resolve the discard; turn should then pass.
	eng.apply(Action.resolve_choice({"indices": [0, 1]}))
	assert_int(ps.hand.size()).is_equal(5)
	assert_object(eng.state.pending_choice).is_null()
```

- [ ] **Step 2: Run to verify it fails**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_engine_end_turn.gd
```
Expected: FAIL — END_TURN/RESOLVE_CHOICE unhandled.

- [ ] **Step 3: Implement end turn + resolve choice**

In `game/engine/game_engine.gd`, extend the `apply` match:
```gdscript
		Enums.ActionType.END_TURN:
			_end_turn()
		Enums.ActionType.RESOLVE_CHOICE:
			_apply_resolve_choice(action.params)
```

Add the methods:
```gdscript
func _end_turn() -> void:
	state.phase = Enums.Phase.END
	var ps := state.active()
	if ps.hand.size() > 5:
		state.pending_choice = PendingChoice.new(
			"discard_to_limit", state.active_player, {"count": ps.hand.size() - 5})
		return
	_finish_end_turn()

func _apply_resolve_choice(params: Dictionary) -> void:
	var pc := state.pending_choice
	if pc.kind == "discard_to_limit":
		var ps := state.players[pc.player]
		var indices: Array = params["indices"].duplicate()
		indices.sort()
		indices.reverse()   # remove from the back so earlier indices stay valid
		for i in indices:
			var c: CardInstance = ps.hand[i]
			ps.hand.erase(c)
			c.zone = Enums.Zone.DISCARD
			ps.discard.append(c)
			ps.turn_counters["cards_discarded"] += 1
			state.bus.publish(GameEvent.new(Enums.EventType.CARD_DISCARDED,
				{"player": pc.player, "instance": c.instance_id}))
		state.pending_choice = null
		_finish_end_turn()

func _finish_end_turn() -> void:
	# Full-heal every unit on both boards.
	for p in state.players:
		for u in p.board:
			u.reset_stats()
	state.bus.publish(GameEvent.new(Enums.EventType.TURN_ENDED, {"player": state.active_player}))
	if state.phase == Enums.Phase.GAME_OVER:
		return
	state.active_player = state.opponent()
	_start_turn()
```

- [ ] **Step 4: Run to verify it passes**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_engine_end_turn.gd
```
Expected: 3 tests, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add game/engine/game_engine.gd tests/test_engine_end_turn.gd
git commit -m "feat: engine end-turn (hand limit, full heal, pass turn)"
```

---

## Task 11: Combat — pure math + DeclareAttack

**Files:**
- Create: `game/engine/combat.gd`
- Modify: `game/engine/game_engine.gd`
- Test: `tests/test_combat.gd`
- Test: `tests/test_engine_attack.gd`

- [ ] **Step 1: Write the failing Combat math test**

Create `tests/test_combat.gd`:
```gdscript
extends GdUnitTestSuite

func _unit(dmg: int, hp: int) -> CardInstance:
	return CardInstance.new(1, TestFactory.minion(1, dmg, hp))

func test_lethal_is_damage_equal_to_health() -> void:
	# 3-damage attacker vs 3-health defender: defender dies (>=).
	var atk := _unit(3, 2)
	var def := _unit(1, 3)
	var r := Combat.compute(atk, def)
	assert_bool(r["def_dies"]).is_true()
	assert_bool(r["atk_dies"]).is_false()
	assert_int(r["dmg_to_atk"]).is_equal(1)

func test_below_health_survives() -> void:
	var atk := _unit(2, 5)
	var def := _unit(1, 3)
	var r := Combat.compute(atk, def)
	assert_bool(r["def_dies"]).is_false()

func test_simultaneous_trade() -> void:
	var atk := _unit(3, 3)
	var def := _unit(3, 3)
	var r := Combat.compute(atk, def)
	assert_bool(r["def_dies"]).is_true()
	assert_bool(r["atk_dies"]).is_true()
```

- [ ] **Step 2: Run to verify it fails**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_combat.gd
```
Expected: FAIL — `Combat` not found.

- [ ] **Step 3: Implement Combat math**

Create `game/engine/combat.gd`:
```gdscript
class_name Combat
extends RefCounted

# Pure combat math: given attacker and defender, what happens?
# Death uses pre-combat health and the >= rule (incoming damage >= health).
static func compute(attacker: CardInstance, defender: CardInstance) -> Dictionary:
	return {
		"dmg_to_def": attacker.current_damage,
		"dmg_to_atk": defender.current_damage,
		"def_dies": attacker.current_damage >= defender.current_health,
		"atk_dies": defender.current_damage >= attacker.current_health,
	}
```

- [ ] **Step 4: Run to verify Combat passes**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_combat.gd
```
Expected: 3 tests, `0 failed`.

- [ ] **Step 5: Write the failing DeclareAttack test**

Create `tests/test_engine_attack.gd`:
```gdscript
extends GdUnitTestSuite

func _engine() -> GameEngine:
	var state := GameState.new(3)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	eng.apply(Action.mulligan([0, 1]))
	eng.apply(Action.mulligan([0, 1]))
	return eng

# Place an untapped unit on a player's board.
func _place(eng: GameEngine, owner: int, dmg: int, hp: int, id: int) -> CardInstance:
	var ci := eng.state.make_instance(TestFactory.minion(1, dmg, hp, id))
	ci.zone = Enums.Zone.BOARD
	ci.tapped = false
	eng.state.players[owner].board.append(ci)
	return ci

func test_attack_deck_mills_opponent_and_taps_attacker() -> void:
	var eng := _engine()
	var atk := _place(eng, eng.state.active_player, 3, 3, 400)
	var opp := eng.state.opponent()
	var deck_before := eng.state.players[opp].deck.size()
	eng.apply(Action.declare_attack(atk.instance_id, {"deck": true}))
	assert_int(eng.state.players[opp].deck.size()).is_equal(deck_before - 3)
	assert_bool(atk.tapped).is_true()
	assert_int(eng.state.active().turn_counters["attacks_made"]).is_equal(1)

func test_unit_vs_unit_lethal_kills_defender() -> void:
	var eng := _engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var atk := _place(eng, me, 3, 4, 401)
	var def := _place(eng, opp, 1, 3, 402)
	eng.apply(Action.declare_attack(atk.instance_id, {"unit": def.instance_id}))
	assert_array(eng.state.players[opp].board).not_contains([def])
	assert_array(eng.state.players[opp].discard).contains([def])
	# Attacker survived but took 1 damage.
	assert_int(atk.current_health).is_equal(3)

func test_unit_vs_unit_simultaneous_trade() -> void:
	var eng := _engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var atk := _place(eng, me, 3, 3, 403)
	var def := _place(eng, opp, 3, 3, 404)
	eng.apply(Action.declare_attack(atk.instance_id, {"unit": def.instance_id}))
	assert_array(eng.state.players[me].board).not_contains([atk])
	assert_array(eng.state.players[opp].board).not_contains([def])

func test_deck_attack_has_no_retaliation() -> void:
	var eng := _engine()
	var atk := _place(eng, eng.state.active_player, 1, 1, 405)
	eng.apply(Action.declare_attack(atk.instance_id, {"deck": true}))
	assert_int(atk.current_health).is_equal(1)  # undamaged
```

- [ ] **Step 6: Run to verify it fails**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_engine_attack.gd
```
Expected: FAIL — DECLARE_ATTACK unhandled.

- [ ] **Step 7: Implement DeclareAttack + kill**

In `game/engine/game_engine.gd`, extend the `apply` match:
```gdscript
		Enums.ActionType.DECLARE_ATTACK:
			_declare_attack(action.params["attacker_id"], action.params["target"])
```

Add the methods:
```gdscript
func _declare_attack(attacker_id: int, target: Dictionary) -> void:
	var ap := state.active()
	var attacker: CardInstance = _find_on_board(ap, attacker_id)
	attacker.tapped = true
	ap.turn_counters["attacks_made"] += 1
	state.bus.publish(GameEvent.new(Enums.EventType.UNIT_ATTACKED,
		{"attacker": attacker_id, "player": state.active_player}))
	_check_traps(state.bus.log[-1])   # reaction window (inert for vanilla)
	if state.phase == Enums.Phase.GAME_OVER:
		return
	if target.get("deck", false):
		_deck_damage(state.opponent(), attacker.current_damage)
		return
	var opp := state.players[state.opponent()]
	var defender: CardInstance = _find_on_board(opp, target["unit"])
	var r := Combat.compute(attacker, defender)
	defender.current_health -= r["dmg_to_def"]
	attacker.current_health -= r["dmg_to_atk"]
	state.bus.publish(GameEvent.new(Enums.EventType.UNIT_DAMAGED,
		{"target": defender.instance_id, "amount": r["dmg_to_def"]}))
	state.bus.publish(GameEvent.new(Enums.EventType.UNIT_DAMAGED,
		{"target": attacker.instance_id, "amount": r["dmg_to_atk"]}))
	if r["def_dies"]:
		_kill(state.opponent(), defender)
	if r["atk_dies"]:
		_kill(state.active_player, attacker)

func _kill(owner_idx: int, unit: CardInstance) -> void:
	var owner := state.players[owner_idx]
	owner.board.erase(unit)
	unit.zone = Enums.Zone.DISCARD
	unit.reset_stats()
	owner.discard.append(unit)
	owner.turn_counters["units_died"] += 1
	state.bus.publish(GameEvent.new(Enums.EventType.UNIT_DIED,
		{"owner": owner_idx, "instance": unit.instance_id}))

func _find_on_board(ps: PlayerState, instance_id: int) -> CardInstance:
	for c in ps.board:
		if c.instance_id == instance_id:
			return c
	return null
```

Also add a temporary stub for `_check_traps` so the code runs now (it gets its real body in Task 12):
```gdscript
func _check_traps(_event: GameEvent) -> void:
	pass
```

- [ ] **Step 8: Run to verify it passes**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_engine_attack.gd
```
Expected: 4 tests, `0 failed`.

- [ ] **Step 9: Commit**

```bash
git add game/engine/combat.gd game/engine/game_engine.gd tests/test_combat.gd tests/test_engine_attack.gd
git commit -m "feat: combat math and DeclareAttack resolution"
```

---

## Task 12: Reaction-window plumbing (traps)

**Files:**
- Modify: `game/engine/game_engine.gd`
- Test: `tests/test_engine_traps.gd`

- [ ] **Step 1: Write the failing trap-plumbing test**

Create `tests/test_engine_traps.gd`:
```gdscript
extends GdUnitTestSuite

func _engine() -> GameEngine:
	var state := GameState.new(8)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	eng.apply(Action.mulligan([0, 1]))
	eng.apply(Action.mulligan([0, 1]))
	return eng

func test_set_vanilla_trap_does_not_fire_on_opponent_attack() -> void:
	var eng := _engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	# Opponent (defender) sets a trap.
	var trap := eng.state.make_instance(TestFactory.trap(2, 500))
	trap.zone = Enums.Zone.TRAP_SET
	eng.state.players[opp].set_traps.append(trap)
	# Active player attacks the opponent's deck.
	var atk := eng.state.make_instance(TestFactory.minion(1, 1, 1, 501))
	atk.zone = Enums.Zone.BOARD
	atk.tapped = false
	eng.state.players[me].board.append(atk)
	eng.apply(Action.declare_attack(atk.instance_id, {"deck": true}))
	# Reaction window ran, but the vanilla trap stays set (no condition met).
	assert_array(eng.state.players[opp].set_traps).contains([trap])
	assert_object(eng.state.pending_choice).is_null()

func test_trap_condition_is_inert() -> void:
	var eng := _engine()
	var trap := eng.state.make_instance(TestFactory.trap(2, 502))
	assert_bool(eng._trap_condition_met(trap, GameEvent.new(Enums.EventType.UNIT_ATTACKED))).is_false()
```

- [ ] **Step 2: Run to verify it fails**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_engine_traps.gd
```
Expected: FAIL — `_trap_condition_met` not found.

- [ ] **Step 3: Implement the reaction-window plumbing**

In `game/engine/game_engine.gd`, replace the stub `_check_traps` with:
```gdscript
# Reaction-window plumbing. When an event opens a window, the defending
# player's set traps are checked. For vanilla cards no condition matches, so
# nothing fires. The future abilities slice replaces _trap_condition_met and
# adds activation handling without changing callers.
func _check_traps(event: GameEvent) -> void:
	var defender_idx := state.opponent()
	for trap in state.players[defender_idx].set_traps:
		if _trap_condition_met(trap, event):
			# Abilities slice: open an "activate_trap" PendingChoice here and
			# resolve the trap effect. Unreachable for vanilla cards.
			pass

func _trap_condition_met(_trap: CardInstance, _event: GameEvent) -> bool:
	return false
```

(Also extend the `apply` match so the `ACTIVATE_TRAP` action type does not fall into the error branch, even though it is never produced for vanilla cards:)
```gdscript
		Enums.ActionType.ACTIVATE_TRAP:
			pass  # plumbing only; no vanilla trap ever reaches activation
```

- [ ] **Step 4: Run to verify it passes**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_engine_traps.gd
```
Expected: 2 tests, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add game/engine/game_engine.gd tests/test_engine_traps.gd
git commit -m "feat: trap reaction-window plumbing (inert for vanilla)"
```

---

## Task 13: get_legal_actions

**Files:**
- Modify: `game/engine/game_engine.gd`
- Test: `tests/test_legal_actions.gd`

- [ ] **Step 1: Write the failing legal-actions test**

Create `tests/test_legal_actions.gd`:
```gdscript
extends GdUnitTestSuite

func _engine() -> GameEngine:
	var state := GameState.new(2)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	eng.apply(Action.mulligan([0, 1]))
	eng.apply(Action.mulligan([0, 1]))
	return eng

func _types(actions: Array) -> Array:
	return actions.map(func(a: Action): return a.type)

func test_pending_choice_yields_no_actions() -> void:
	var state := GameState.new(2)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	# Still in mulligan pending choice.
	assert_array(eng.get_legal_actions()).is_empty()

func test_main_phase_offers_end_turn() -> void:
	var eng := _engine()
	assert_array(_types(eng.get_legal_actions())).contains([Enums.ActionType.END_TURN])

func test_affordable_card_is_playable_unaffordable_is_not() -> void:
	var eng := _engine()
	var ps := eng.state.active()
	ps.hand.clear()
	ps.tickets_total = 2
	ps.tickets_tapped = 0
	var cheap := eng.state.make_instance(TestFactory.minion(2, 1, 1, 600))
	cheap.zone = Enums.Zone.HAND
	ps.hand.append(cheap)
	var pricey := eng.state.make_instance(TestFactory.minion(9, 1, 1, 601))
	pricey.zone = Enums.Zone.HAND
	ps.hand.append(pricey)
	var ids := eng.get_legal_actions() \
		.filter(func(a: Action): return a.type == Enums.ActionType.PLAY_CARD) \
		.map(func(a: Action): return a.params["instance_id"])
	assert_array(ids).contains([cheap.instance_id])
	assert_array(ids).not_contains([pricey.instance_id])

func test_untapped_unit_can_attack_deck_and_enemy_units() -> void:
	var eng := _engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var ps := eng.state.active()
	ps.hand.clear()
	var atk := eng.state.make_instance(TestFactory.minion(1, 1, 1, 602))
	atk.zone = Enums.Zone.BOARD
	atk.tapped = false
	ps.board.append(atk)
	var enemy := eng.state.make_instance(TestFactory.minion(1, 1, 1, 603))
	enemy.zone = Enums.Zone.BOARD
	eng.state.players[opp].board.append(enemy)
	var attacks := eng.get_legal_actions().filter(
		func(a: Action): return a.type == Enums.ActionType.DECLARE_ATTACK)
	assert_array(attacks).has_size(2)  # deck + the one enemy unit

func test_tapped_unit_cannot_attack() -> void:
	var eng := _engine()
	var ps := eng.state.active()
	ps.hand.clear()
	var atk := eng.state.make_instance(TestFactory.minion(1, 1, 1, 604))
	atk.zone = Enums.Zone.BOARD
	atk.tapped = true
	ps.board.append(atk)
	var attacks := eng.get_legal_actions().filter(
		func(a: Action): return a.type == Enums.ActionType.DECLARE_ATTACK)
	assert_array(attacks).is_empty()
```

- [ ] **Step 2: Run to verify it fails**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_legal_actions.gd
```
Expected: FAIL — `get_legal_actions` not found.

- [ ] **Step 3: Implement get_legal_actions**

Add to `game/engine/game_engine.gd`:
```gdscript
# Choices (mulligan, discard-to-limit) are resolved via state.pending_choice
# and are intentionally NOT enumerated here. When a choice is pending, no
# free actions are legal.
func get_legal_actions() -> Array:
	var out: Array = []
	if state.phase == Enums.Phase.GAME_OVER:
		return out
	if state.pending_choice != null:
		return out
	if state.phase != Enums.Phase.MAIN:
		return out
	var ps := state.active()
	for c in ps.hand:
		var def := c.definition
		if ps.available_tickets() >= def.ticket_cost:
			out.append(Action.play_card(c.instance_id))
		if def.type == Enums.CardType.LEADER \
				and ps.deck.size() + ps.discard.size() >= def.alt_discard_cost:
			out.append(Action.play_card(c.instance_id, {"pay_by_discard": true}))
	var opp := state.players[state.opponent()]
	for u in ps.board:
		if u.tapped or not u.is_unit():
			continue
		out.append(Action.declare_attack(u.instance_id, {"deck": true}))
		for d in opp.board:
			out.append(Action.declare_attack(u.instance_id, {"unit": d.instance_id}))
	out.append(Action.end_turn())
	return out
```

- [ ] **Step 4: Run to verify it passes**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_legal_actions.gd
```
Expected: 6 tests, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add game/engine/game_engine.gd tests/test_legal_actions.gd
git commit -m "feat: legal action generation"
```

---

## Task 14: Integration — full scripted game + determinism

**Files:**
- Test: `tests/test_integration_game.gd`

- [ ] **Step 1: Write the integration test**

Create `tests/test_integration_game.gd`:
```gdscript
extends GdUnitTestSuite

# A greedy auto-controller: develop board, then attack the enemy deck.
# Priority: attack deck > play a card > end turn.
func _play_to_end(eng: GameEngine, max_steps: int) -> void:
	var steps := 0
	while eng.state.phase != Enums.Phase.GAME_OVER and steps < max_steps:
		steps += 1
		var actions := eng.get_legal_actions()
		var chosen: Action = null
		for a in actions:
			if a.type == Enums.ActionType.DECLARE_ATTACK and a.params["target"].get("deck", false):
				chosen = a
				break
		if chosen == null:
			for a in actions:
				if a.type == Enums.ActionType.PLAY_CARD:
					chosen = a
					break
		if chosen == null:
			chosen = Action.end_turn()
		eng.apply(chosen)

func _new_started(seed_value: int) -> GameEngine:
	var state := GameState.new(seed_value)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	eng.apply(Action.mulligan([0, 1]))
	eng.apply(Action.mulligan([0, 1]))
	return eng

func test_full_vanilla_game_reaches_a_winner() -> void:
	var eng := _new_started(1234)
	_play_to_end(eng, 2000)
	assert_int(eng.state.phase).is_equal(Enums.Phase.GAME_OVER)
	assert_bool(eng.state.winner == 0 or eng.state.winner == 1).is_true()

func test_same_seed_same_script_is_deterministic() -> void:
	var a := _new_started(777)
	var b := _new_started(777)
	_play_to_end(a, 2000)
	_play_to_end(b, 2000)
	assert_int(a.state.winner).is_equal(b.state.winner)
	assert_int(a.state.turn_number).is_equal(b.state.turn_number)
	assert_int(a.state.bus.log.size()).is_equal(b.state.bus.log.size())
```

- [ ] **Step 2: Run to verify it passes**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_integration_game.gd
```
Expected: 2 tests, `0 failed`. If the game does not terminate within 2000 steps, that indicates a loss-condition bug (most likely in `_reshuffle_or_lose`); fix the engine, not the test cap.

- [ ] **Step 3: Run the entire suite**

Run:
```bash
godot --headless --path "$PWD" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests
```
Expected: every suite passes, `0 failed` overall.

- [ ] **Step 4: Commit**

```bash
git add tests/test_integration_game.gd
git commit -m "test: full scripted vanilla game and determinism"
```

---

## Done criteria

- All GdUnit4 suites pass via `-a res://tests` with `0 failed`.
- The engine plays a complete two-player vanilla game to a deck-out win through the action interface only.
- The event bus, reaction-window plumbing, and `PendingChoice` mechanism are in place for the abilities slice to build on, with no `Node`/`SceneTree` dependency anywhere in `game/`.
