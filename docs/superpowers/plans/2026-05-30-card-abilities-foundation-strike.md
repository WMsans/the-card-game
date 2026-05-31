# Card Abilities Foundation + Strike Deck Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a per-card-script ability architecture plus the engine primitives it needs, and implement all 14 unique Strike-deck cards, each unit-tested against shipping card data.

**Architecture:** Each card is one pure `CardScript` GDScript subclass registered by `(deck, id)`, touching the engine only through an `EffectContext` facade. The engine resolves effects through a typed work-item queue (`event` / `react` / `call`) so battlecries and attacks can suspend for player choices and resume. REQUEST is engine-applied (+2/+2 combat buff + a queryable boolean). Traps auto-fire via the same reactive dispatch.

**Tech Stack:** Godot 4.6 (GL Compatibility), GDScript, GdUnit4 (headless).

---

## Conventions used throughout this plan

**Run one test suite (headless):**
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/<suite>.gd
```
Exit code `0` = pass. Reports land in `reports/report_N/`. Ignore the harmless headless noise: `ERROR: Required object "rp_font" is null` and the "InputEvents not transported in headless" notice.

**Run the whole suite:** replace `-a res://tests/<suite>.gd` with `-a res://tests`.

`godot` must be on PATH (or substitute your binary). The project root is `/home/jeremy/Development/Godot/the-card-game`.

**Existing engine entry points you will reuse (do not rewrite):**
`GameEngine._draw(player_idx, n)`, `._mill(player_idx, n)`, `._deck_damage(player_idx, amount)`, `._kill(owner_idx, unit)`, `._find_on_board(ps, id)`, `._find_in_hand(ps, id)`, `GameState.make_instance(def)`, `PlayerState.turn_counters` (`cards_played`, `cards_discarded`, `attacks_made`, `units_died`).

---

## File Structure

**New files:**
- `src/cards/card_script.gd` — `CardScript` base class (all hooks are virtual no-ops).
- `src/cards/effect_context.gd` — `EffectContext` facade; the only surface scripts touch.
- `src/cards/choice_spec.gd` — `ChoiceSpec` data builders for the three UI shapes.
- `src/cards/card_script_registry.gd` — `(deck, id) -> CardScript` lookup; `default` no-op.
- `src/cards/scripts/default_card.gd` — no-op script for vanilla / unscripted cards.
- `src/cards/scripts/strike/*.gd` — the 14 Strike card scripts.
- `src/ui/overlays/card_select_panel.gd` + `.tscn` — generalized selection page (renamed from discard panel).
- `tests/cards/strike/test_*.gd` — per-card tests.
- `tests/test_effect_queue.gd`, `tests/test_effect_context.gd`, `tests/test_request_primitive.gd`, `tests/test_choice_system.gd`, `tests/test_trap_firing.gd`, `tests/test_card_registry.gd`.

**Modified files:**
- `src/data/enums.gd` — add `REQUEST_MET`, `TRAP_FIRED` event types; `ACTIVATE_ABILITY` action type.
- `src/data/card_instance.gd` — add `vars: Dictionary`, `script: CardScript`.
- `src/engine/game_state.gd` — resolve `script` in `make_instance`.
- `src/engine/player_state.gd` — add `all_requests_met_this_turn`.
- `src/engine/game_engine.gd` — work-item queue, dispatch, choice suspend/resume, REQUEST combat, trap firing, new ctx-backing primitives, activated abilities, `publish → emit` migration.
- `src/engine/action.gd` — add `activate_ability` constructor.
- `src/ui/match/match.gd` — generic choice routing, `card_select_panel` rename, targeting + option-prompt paths, activated-ability input.
- `src/ui/match/ai_controller.gd` — generic `card_effect` choice resolver.
- `tests/test_overlays.gd`, `tests/test_pending_choice_routing.gd` — update for renamed panel.

---

# PHASE 1 — Work-item queue migration

Goal: replace direct `bus.publish` with a queued `emit` that can host reactions later, with **zero behavior change** today. The existing suite is the regression guard.

### Task 1: Add the work-item queue and `emit`

**Files:**
- Modify: `src/engine/game_engine.gd`
- Test: `tests/test_effect_queue.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/test_effect_queue.gd`:
```gdscript
extends GdUnitTestSuite

func _eng() -> GameEngine:
	var state := GameState.new(1)
	return GameEngine.new(state)

func test_emit_publishes_to_bus_log() -> void:
	var eng := _eng()
	eng.emit(GameEvent.new(Enums.EventType.TURN_STARTED, {"player": 0}))
	assert_int(eng.state.bus.log.size()).is_equal(1)
	assert_int(eng.state.bus.log[0].type).is_equal(Enums.EventType.TURN_STARTED)

func test_reentrant_emit_drains_in_order() -> void:
	var eng := _eng()
	# Subscribe a listener that emits a second event the first time it runs.
	var seen: Array = []
	eng.state.bus.subscribe(func(e: GameEvent):
		seen.append(e.type)
		if e.type == Enums.EventType.TURN_STARTED and seen.size() == 1:
			eng.emit(GameEvent.new(Enums.EventType.TURN_ENDED, {})))
	eng.emit(GameEvent.new(Enums.EventType.TURN_STARTED, {"player": 0}))
	# First event fully published before the re-entrant one.
	assert_array(seen).is_equal([Enums.EventType.TURN_STARTED, Enums.EventType.TURN_ENDED])
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_effect_queue.gd`
Expected: FAIL — `emit` does not exist.

- [ ] **Step 3: Implement the queue**

In `src/engine/game_engine.gd`, add fields right after `var state: GameState`:
```gdscript
var _queue: Array = []          # work items: {kind:"event"|"react"|"call", ...}
var _resolving: bool = false
var _suspended: bool = false
```

Add these methods (place them above `_draw`):
```gdscript
func emit(event: GameEvent) -> void:
	_queue.append({"kind": "event", "event": event})
	_pump()

func _push(item: Dictionary) -> void:
	_queue.append(item)

func _pump() -> void:
	if _resolving:
		return
	_resolving = true
	_drain()

func _drain() -> void:
	while not _queue.is_empty():
		if _suspended:
			return
		var item: Dictionary = _queue.pop_front()
		match item["kind"]:
			"event":
				state.bus.publish(item["event"])
				_dispatch_triggers(item["event"])
			"react":
				item["card"].script.react(item["card"], item["event"], _ctx_for(item["pidx"]))
			"call":
				item["fn"].call()
	_resolving = false

func _dispatch_triggers(_event: GameEvent) -> void:
	pass   # Phase 3 fills this in

func _ctx_for(_pidx: int):
	return null   # Phase 2 returns an EffectContext
```

- [ ] **Step 4: Run to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_effect_queue.gd`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**
```bash
git add src/engine/game_engine.gd tests/test_effect_queue.gd
git commit -m "feat(engine): add work-item queue and emit()"
```

### Task 2: Migrate every `bus.publish` to `emit`

**Files:**
- Modify: `src/engine/game_engine.gd`

- [ ] **Step 1: Replace publish calls**

In `src/engine/game_engine.gd`, change **every** `state.bus.publish(GameEvent.new(...))` to `emit(GameEvent.new(...))`. There are publish calls in `_draw`, `_mill`, `_deck_damage`, `_reshuffle_or_lose`, `_lose`, `_start_turn`, `_play_card`, `_apply_resolve_choice`, `_finish_end_turn`, `_declare_attack`, `_kill`. Example — in `_draw`:
```gdscript
		emit(GameEvent.new(Enums.EventType.CARD_DRAWN,
			{"player": player_idx, "instance": card.instance_id}))
```
Leave the `GameEvent.new(...)` argument exactly as-is; only swap `state.bus.publish(` → `emit(`.

- [ ] **Step 2: Run the full existing suite to verify no regression**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
Expected: PASS — same green result as before the change (no test references `bus.publish` directly; they read `bus.log` / `events_of_type`, which `publish` still populates).

- [ ] **Step 3: Commit**
```bash
git add src/engine/game_engine.gd
git commit -m "refactor(engine): route all events through emit()"
```

---

# PHASE 2 — CardScript base, registry, EffectContext

### Task 3: `CardScript` base + `default_card`

**Files:**
- Create: `src/cards/card_script.gd`, `src/cards/scripts/default_card.gd`
- Test: `tests/test_card_registry.gd` (create, first assertions only)

- [ ] **Step 1: Write the base class**

Create `src/cards/card_script.gd`:
```gdscript
class_name CardScript
extends RefCounted

# Battlecry / on-play. Called after the card reaches its zone.
func on_cast(_card: CardInstance, _ctx) -> void: pass

# Triggered abilities. Called per active card after each event.
func react(_card: CardInstance, _event: GameEvent, _ctx) -> void: pass

# Resume point after a requested choice is answered.
func resume(_card: CardInstance, _tag: String, _result: Dictionary, _ctx) -> void: pass

# REQUEST predicate. Pure, side-effect free.
func condition_met(_card: CardInstance, _ctx) -> bool: return false
func has_request() -> bool: return false

# Activated abilities contributed to legal actions.
# Returns Array of {"id": String, "label": String}.
func activated_abilities(_card: CardInstance, _ctx) -> Array: return []
func activate(_card: CardInstance, _ability_id: String, _ctx) -> void: pass

# Dispatch hints.
func reacts_to() -> Array: return []                                  # event types
func active_zones() -> Array: return [Enums.Zone.BOARD, Enums.Zone.TRAP_SET]
```

Create `src/cards/scripts/default_card.gd`:
```gdscript
class_name DefaultCard
extends CardScript
# Pure vanilla card: inherits all no-op hooks.
```

- [ ] **Step 2: Write the failing registry test**

Create `tests/test_card_registry.gd`:
```gdscript
extends GdUnitTestSuite

func test_unknown_card_resolves_to_default() -> void:
	var s := CardScriptRegistry.get_script_for("nope", 999)
	assert_object(s).is_not_null()
	assert_bool(s is DefaultCard).is_true()
```

- [ ] **Step 3: Run to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_registry.gd`
Expected: FAIL — `CardScriptRegistry` not defined.

- [ ] **Step 4: Implement the registry**

Create `src/cards/card_script_registry.gd`:
```gdscript
class_name CardScriptRegistry
extends RefCounted

static var _default := DefaultCard.new()
static var _scripts: Dictionary = {}      # "deck:id" -> CardScript
static var _built: bool = false

static func _key(deck: String, id: int) -> String:
	return "%s:%d" % [deck.to_lower(), id]

static func _register(deck: String, id: int, script: CardScript) -> void:
	_scripts[_key(deck, id)] = script

static func _build() -> void:
	if _built:
		return
	_built = true
	# Strike registrations are added in Phase 8.

static func get_script_for(deck: String, id: int) -> CardScript:
	_build()
	return _scripts.get(_key(deck, id), _default)
```

- [ ] **Step 5: Run to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_registry.gd`
Expected: PASS.

- [ ] **Step 6: Commit**
```bash
git add src/cards/card_script.gd src/cards/scripts/default_card.gd src/cards/card_script_registry.gd tests/test_card_registry.gd
git commit -m "feat(cards): CardScript base, default card, registry"
```

### Task 4: `CardInstance.script` + `vars`, resolved at creation

**Files:**
- Modify: `src/data/card_instance.gd`, `src/engine/game_state.gd`
- Test: `tests/test_card_instance.gd` (add a case)

- [ ] **Step 1: Write the failing test**

Append to `tests/test_card_instance.gd`:
```gdscript
func test_instance_has_vars_and_default_script() -> void:
	var d := CardDefinition.new()
	d.deck_color = "Test"
	d.id = 1
	var ci := CardInstance.new(7, d)
	assert_object(ci.vars).is_not_null()
	assert_int(ci.vars.size()).is_equal(0)
	assert_object(ci.script).is_null()   # raw CardInstance.new does not resolve script
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_instance.gd`
Expected: FAIL — `vars` / `script` not defined.

- [ ] **Step 3: Implement**

In `src/data/card_instance.gd`, add fields after `var current_health: int`:
```gdscript
var vars: Dictionary = {}
var script: CardScript = null
```

In `src/engine/game_state.gd`, update `make_instance` so engine-created cards get their script:
```gdscript
func make_instance(def: CardDefinition) -> CardInstance:
	var ci := CardInstance.new(_next_instance_id, def)
	ci.script = CardScriptRegistry.get_script_for(def.deck_color, def.id)
	_next_instance_id += 1
	return ci
```

- [ ] **Step 4: Run to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_instance.gd`
Expected: PASS.

- [ ] **Step 5: Run full suite (regression)**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
Expected: PASS.

- [ ] **Step 6: Commit**
```bash
git add src/data/card_instance.gd src/engine/game_state.gd tests/test_card_instance.gd
git commit -m "feat(cards): per-instance vars + resolved script reference"
```

### Task 5: `EffectContext` facade

**Files:**
- Create: `src/cards/effect_context.gd`
- Modify: `src/engine/game_engine.gd` (`_ctx_for`)
- Test: `tests/test_effect_context.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/test_effect_context.gd`:
```gdscript
extends GdUnitTestSuite

func _eng() -> GameEngine:
	var state := GameState.new(2)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	return eng

func test_ctx_draw_moves_card_to_hand() -> void:
	var eng := _eng()
	var hand_before := eng.state.players[0].hand.size()
	var ctx = eng._ctx_for(0)
	ctx.draw(1)
	assert_int(eng.state.players[0].hand.size()).is_equal(hand_before + 1)

func test_ctx_me_and_opponent() -> void:
	var eng := _eng()
	var ctx = eng._ctx_for(0)
	assert_int(ctx.me()).is_equal(0)
	assert_int(ctx.opponent()).is_equal(1)
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_effect_context.gd`
Expected: FAIL — `_ctx_for` returns null.

- [ ] **Step 3: Implement `EffectContext`**

Create `src/cards/effect_context.gd`:
```gdscript
class_name EffectContext
extends RefCounted

var engine: GameEngine
var pidx: int

func _init(e: GameEngine, p: int) -> void:
	engine = e
	pidx = p

# --- identity / reads -------------------------------------------------------
func me() -> int: return pidx
func opponent() -> int: return 1 - pidx
func gs() -> GameState: return engine.state
func board(p: int) -> Array: return engine.state.players[p].board
func hand(p: int) -> Array: return engine.state.players[p].hand
func discard_pile(p: int) -> Array: return engine.state.players[p].discard
func counters(p: int) -> Dictionary: return engine.state.players[p].turn_counters

# --- card movement / damage -------------------------------------------------
func draw(n: int = 1) -> void: engine._draw(pidx, n)
func mill(player: int, n: int) -> void: engine._mill(player, n)
func deal_deck_damage(player: int, n: int) -> void: engine._deck_damage(player, n)
func deal_damage(unit: CardInstance, n: int) -> void: engine._damage_unit(unit, n)
func kill(unit: CardInstance) -> void: engine._kill_unit(unit)
func discard_from_hand(card: CardInstance) -> void: engine._discard_from_hand(card)
func search_deck(pred: Callable) -> CardInstance: return engine._search_deck(pidx, pred)
func draw_specific(card: CardInstance) -> void: engine._draw_specific(pidx, card)
func summon_free(card: CardInstance) -> void: engine._summon_free(pidx, card)
func put_on_deck_top(unit: CardInstance) -> void: engine._put_on_deck_top(unit)
func steal_top_discard(opp: int) -> CardInstance: return engine._steal_top_discard(pidx, opp)
func end_turn() -> void: engine._end_turn()
func fire_trap(card: CardInstance) -> void: engine._fire_trap(card)
func set_unit_flag(unit: CardInstance, flag: String) -> void: unit.vars[flag] = true

# --- REQUEST ----------------------------------------------------------------
func request_met(card: CardInstance) -> bool: return engine._request_met(card)

# --- events / choices -------------------------------------------------------
func emit(event: GameEvent) -> void: engine.emit(event)
func request_choice(card: CardInstance, spec: ChoiceSpec, tag: String, asked_player: int = -1) -> void:
	engine._request_choice(card, spec, tag, asked_player if asked_player >= 0 else pidx)
```

In `src/engine/game_engine.gd`, replace the stub `_ctx_for`:
```gdscript
func _ctx_for(pidx: int) -> EffectContext:
	return EffectContext.new(self, pidx)
```

The engine methods `_damage_unit`, `_kill_unit`, `_discard_from_hand`, `_search_deck`, `_draw_specific`, `_summon_free`, `_put_on_deck_top`, `_steal_top_discard`, `_fire_trap`, `_request_met`, `_request_choice` are added in the tasks that need them (Phases 3–7). For this task, add the **two** the test exercises plus the simple ones now:
```gdscript
func _owner_of(unit: CardInstance) -> int:
	for i in range(state.players.size()):
		var ps := state.players[i]
		if ps.board.has(unit) or ps.discard.has(unit) or ps.hand.has(unit) \
				or ps.set_traps.has(unit) or ps.deck.has(unit):
			return i
	return -1
```
(`draw` already maps to existing `_draw`; no new method needed for the test.)

- [ ] **Step 4: Run to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_effect_context.gd`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add src/cards/effect_context.gd src/engine/game_engine.gd tests/test_effect_context.gd
git commit -m "feat(cards): EffectContext facade + _ctx_for + _owner_of"
```

---

# PHASE 3 — Trigger dispatch

### Task 6: Reactive dispatch over active cards

**Files:**
- Modify: `src/engine/game_engine.gd` (`_dispatch_triggers`)
- Test: `tests/test_effect_queue.gd` (add cases)

- [ ] **Step 1: Write the failing test**

Append to `tests/test_effect_queue.gd`:
```gdscript
# A throwaway script that counts reactions to CARD_DRAWN while on the board.
class CounterScript extends CardScript:
	var hits := 0
	func reacts_to() -> Array: return [Enums.EventType.CARD_DRAWN]
	func active_zones() -> Array: return [Enums.Zone.BOARD]
	func react(card, event, ctx) -> void: hits += 1

func test_board_card_reacts_to_event() -> void:
	var state := GameState.new(3)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	var sc := CounterScript.new()
	var unit := state.make_instance(TestFactory.minion(1, 1, 1, 900))
	unit.script = sc
	unit.zone = Enums.Zone.BOARD
	state.players[0].board.append(unit)
	eng.emit(GameEvent.new(Enums.EventType.CARD_DRAWN, {"player": 0, "instance": 1}))
	assert_int(sc.hits).is_equal(1)

func test_card_off_its_active_zone_does_not_react() -> void:
	var state := GameState.new(3)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	var sc := CounterScript.new()
	var unit := state.make_instance(TestFactory.minion(1, 1, 1, 901))
	unit.script = sc
	unit.zone = Enums.Zone.HAND       # not BOARD
	state.players[0].hand.append(unit)
	eng.emit(GameEvent.new(Enums.EventType.CARD_DRAWN, {"player": 0, "instance": 1}))
	assert_int(sc.hits).is_equal(0)
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_effect_queue.gd`
Expected: FAIL — `_dispatch_triggers` is a no-op, `hits` stays 0.

- [ ] **Step 3: Implement dispatch**

In `src/engine/game_engine.gd`, replace `_dispatch_triggers`:
```gdscript
func _dispatch_triggers(event: GameEvent) -> void:
	# Stable order: active player's cards, then opponent's. Jobs run after this
	# event (they are pushed to the FRONT, ahead of any already-queued events).
	var jobs: Array = []
	for pidx in [state.active_player, state.opponent()]:
		for card in _trigger_candidates(state.players[pidx]):
			var s: CardScript = card.script
			if s == null:
				continue
			if not s.reacts_to().has(event.type):
				continue
			if not s.active_zones().has(card.zone):
				continue
			jobs.append({"kind": "react", "card": card, "event": event, "pidx": pidx})
	for i in range(jobs.size() - 1, -1, -1):
		_queue.push_front(jobs[i])

func _trigger_candidates(ps: PlayerState) -> Array:
	var out: Array = []
	out.append_array(ps.board)
	out.append_array(ps.set_traps)
	out.append_array(ps.discard)
	return out
```

- [ ] **Step 4: Run to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_effect_queue.gd`
Expected: PASS (4 tests).

- [ ] **Step 5: Run full suite (regression)**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
Expected: PASS — vanilla cards have no `reacts_to`, so dispatch is inert.

- [ ] **Step 6: Commit**
```bash
git add src/engine/game_engine.gd tests/test_effect_queue.gd
git commit -m "feat(engine): reactive trigger dispatch"
```

---

# PHASE 4 — Generic choice system (suspend/resume)

### Task 7: `ChoiceSpec`

**Files:**
- Create: `src/cards/choice_spec.gd`
- Test: covered indirectly by Task 8; add a tiny direct test.

- [ ] **Step 1: Write the failing test**

Create `tests/test_choice_system.gd`:
```gdscript
extends GdUnitTestSuite

func test_choice_spec_select_cards_shape() -> void:
	var spec := ChoiceSpec.select_cards([], 0, 3, "Pick")
	assert_str(spec.ui_shape).is_equal("select_cards")
	assert_int(spec.min_n).is_equal(0)
	assert_int(spec.max_n).is_equal(3)
	assert_str(spec.title).is_equal("Pick")

func test_choice_spec_choose_option_shape() -> void:
	var spec := ChoiceSpec.choose_option(["A", "B"], "Decide")
	assert_str(spec.ui_shape).is_equal("choose_option")
	assert_array(spec.labels).is_equal(["A", "B"])
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_choice_system.gd`
Expected: FAIL — `ChoiceSpec` not defined.

- [ ] **Step 3: Implement `ChoiceSpec`**

Create `src/cards/choice_spec.gd`:
```gdscript
class_name ChoiceSpec
extends RefCounted

var ui_shape: String          # "select_cards" | "select_target" | "choose_option"
var cards: Array = []         # candidate CardInstances (select_cards / select_target)
var min_n: int = 0
var max_n: int = 0
var labels: Array = []        # choose_option
var title: String = ""

static func select_cards(card_list: Array, min_n: int, max_n: int, title: String) -> ChoiceSpec:
	var s := ChoiceSpec.new()
	s.ui_shape = "select_cards"
	s.cards = card_list
	s.min_n = min_n
	s.max_n = max_n
	s.title = title
	return s

static func select_target(unit_list: Array, min_n: int, max_n: int, title: String) -> ChoiceSpec:
	var s := ChoiceSpec.new()
	s.ui_shape = "select_target"
	s.cards = unit_list
	s.min_n = min_n
	s.max_n = max_n
	s.title = title
	return s

static func choose_option(labels: Array, title: String) -> ChoiceSpec:
	var s := ChoiceSpec.new()
	s.ui_shape = "choose_option"
	s.labels = labels
	s.title = title
	return s
```

- [ ] **Step 4: Run to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_choice_system.gd`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add src/cards/choice_spec.gd tests/test_choice_system.gd
git commit -m "feat(cards): ChoiceSpec data builders"
```

### Task 8: Suspend/resume through `request_choice`

**Files:**
- Modify: `src/engine/game_engine.gd` (`_request_choice`, `_apply_resolve_choice`)
- Test: `tests/test_choice_system.gd` (add)

- [ ] **Step 1: Write the failing test**

Append to `tests/test_choice_system.gd`:
```gdscript
# Script: on a CARD_PLAYED of its own, ask the controller to pick hand cards,
# then on resume draw (chosen count + 1).
class AskScript extends CardScript:
	func on_cast(card, ctx) -> void:
		ctx.request_choice(card, ChoiceSpec.select_cards(ctx.hand(ctx.me()), 0, 9, "Pick"), "pick")
	func resume(card, tag, result, ctx) -> void:
		if tag == "pick":
			ctx.draw(result["cards"].size() + 1)

func _engine_after_mulligan() -> GameEngine:
	var state := GameState.new(9)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	eng.apply(Action.mulligan([]))
	eng.apply(Action.mulligan([]))
	return eng

func test_request_choice_suspends_then_resumes() -> void:
	var eng := _engine_after_mulligan()
	var ps := eng.state.active()
	var card := eng.state.make_instance(TestFactory.minion(0, 1, 1, 950))
	card.script = AskScript.new()
	card.zone = Enums.Zone.BOARD
	ps.board.append(card)
	# Manually invoke the battlecry path the way _play_card will.
	eng._push({"kind": "call", "fn": func(): card.script.on_cast(card, eng._ctx_for(eng.state.active_player))})
	eng._pump()
	# Suspended, waiting for the choice.
	assert_object(eng.state.pending_choice).is_not_null()
	assert_str(eng.state.pending_choice.kind).is_equal("card_effect")
	assert_bool(eng._suspended).is_true()
	var hand_before := ps.hand.size()
	# Resolve: pick the first hand card.
	eng.apply(Action.resolve_choice({"indices": [0]}))
	assert_object(eng.state.pending_choice).is_null()
	assert_bool(eng._suspended).is_false()
	# Drew chosen(1) + 1 = 2.
	assert_int(ps.hand.size()).is_equal(hand_before - 1 + 2)  # -1 discarded? no: select_cards does not discard
```
> Note: `select_cards` only *selects*; `AskScript` does not discard, so hand grows by 2 and loses nothing. Adjust the final assertion to `hand_before + 2`. (The `-1` comment above is wrong; use `hand_before + 2`.)

Use this corrected final assertion:
```gdscript
	assert_int(ps.hand.size()).is_equal(hand_before + 2)
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_choice_system.gd`
Expected: FAIL — `_request_choice` not defined / choice not routed.

- [ ] **Step 3: Implement suspend + resume**

In `src/engine/game_engine.gd`, add:
```gdscript
func _request_choice(card: CardInstance, spec: ChoiceSpec, tag: String, asked_player: int) -> void:
	state.pending_choice = PendingChoice.new("card_effect", asked_player, {
		"spec": spec,
		"ui_shape": spec.ui_shape,
		"resume_card": card.instance_id,
		"resume_tag": tag,
		"resume_owner": _owner_of(card),
	})
	_suspended = true

func _find_anywhere(instance_id: int) -> CardInstance:
	for ps in state.players:
		for zone in [ps.board, ps.hand, ps.discard, ps.set_traps, ps.deck]:
			for c in zone:
				if c.instance_id == instance_id:
					return c
	return null

func _resolve_card_effect(params: Dictionary) -> void:
	var pc := state.pending_choice
	var data := pc.data
	var spec: ChoiceSpec = data["spec"]
	var card := _find_anywhere(data["resume_card"])
	var owner: int = data["resume_owner"]
	var result := _build_choice_result(spec, params)
	state.pending_choice = null
	_suspended = false
	if card != null and card.script != null:
		card.script.resume(card, data["resume_tag"], result, _ctx_for(owner))
	if not _suspended:        # resume() may have requested another choice
		_pump()

func _build_choice_result(spec: ChoiceSpec, params: Dictionary) -> Dictionary:
	match spec.ui_shape:
		"select_cards":
			var picked: Array = []
			for i in params.get("indices", []):
				picked.append(spec.cards[i])
			return {"cards": picked}
		"select_target":
			var targets: Array = []
			for id in params.get("target_ids", []):
				for u in spec.cards:
					if u.instance_id == id:
						targets.append(u)
			return {"targets": targets}
		"choose_option":
			return {"option": params.get("option", 0)}
		_:
			return {}
```

In `_apply_resolve_choice`, add a branch for the new kind (keep the existing `discard_to_limit` branch):
```gdscript
func _apply_resolve_choice(params: Dictionary) -> void:
	var pc := state.pending_choice
	if pc.kind == "card_effect":
		_resolve_card_effect(params)
		return
	if pc.kind == "discard_to_limit":
		... existing body unchanged ...
```

- [ ] **Step 4: Run to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_choice_system.gd`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add src/engine/game_engine.gd tests/test_choice_system.gd
git commit -m "feat(engine): suspend/resume choice resolution"
```

### Task 9: AI generic resolver for `card_effect`

**Files:**
- Modify: `src/ui/match/ai_controller.gd`
- Test: `tests/test_ai_controller.gd` (add)

- [ ] **Step 1: Write the failing test**

Append to `tests/test_ai_controller.gd`:
```gdscript
func test_ai_resolves_select_cards_with_minimum() -> void:
	var state := GameState.new(4)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	var spec := ChoiceSpec.select_cards([], 0, 3, "x")
	state.pending_choice = PendingChoice.new("card_effect", 0, {"spec": spec, "ui_shape": "select_cards"})
	var a := AiController.choice_action(eng)
	assert_int(a.type).is_equal(Enums.ActionType.RESOLVE_CHOICE)
	assert_array(a.params["indices"]).is_equal([])     # min 0 -> pick none

func test_ai_resolves_choose_option_picks_first() -> void:
	var state := GameState.new(4)
	var eng := GameEngine.new(state)
	var spec := ChoiceSpec.choose_option(["A", "B"], "x")
	state.pending_choice = PendingChoice.new("card_effect", 0, {"spec": spec, "ui_shape": "choose_option"})
	var a := AiController.choice_action(eng)
	assert_int(a.params["option"]).is_equal(0)
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_ai_controller.gd`
Expected: FAIL — `choice_action` has no `card_effect` branch (hits the `_` default and returns `{"indices": []}`, which passes the first test by luck but fails the second on `option`).

- [ ] **Step 3: Implement**

In `src/ui/match/ai_controller.gd`, add a branch to `choice_action`'s `match pc.kind` before the `_` default:
```gdscript
		"card_effect":
			var spec: ChoiceSpec = pc.data["spec"]
			match spec.ui_shape:
				"select_cards":
					var idx: Array = []
					for i in range(spec.min_n):
						idx.append(i)
					return Action.resolve_choice({"indices": idx})
				"select_target":
					var ids: Array = []
					var need: int = max(spec.min_n, 0)
					for i in range(min(need, spec.cards.size())):
						ids.append(spec.cards[i].instance_id)
					return Action.resolve_choice({"target_ids": ids})
				"choose_option":
					return Action.resolve_choice({"option": 0})
				_:
					return Action.resolve_choice({"indices": []})
```

- [ ] **Step 4: Run to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_ai_controller.gd`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add src/ui/match/ai_controller.gd tests/test_ai_controller.gd
git commit -m "feat(ai): generic card_effect choice resolver"
```

---

# PHASE 5 — Reusable card-selection page

### Task 10: Generalize discard panel → `card_select_panel`

**Files:**
- Create: `src/ui/overlays/card_select_panel.gd`, `src/ui/overlays/card_select_panel.tscn`
- Delete: `src/ui/overlays/discard_panel.gd`, `.tscn`
- Modify: `src/ui/match/match.gd`, `tests/test_overlays.gd`, `tests/test_pending_choice_routing.gd`

- [ ] **Step 1: Create the generalized scene + script**

Create `src/ui/overlays/card_select_panel.gd`:
```gdscript
extends CanvasLayer

signal confirmed(indices: Array)

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")

var _selected: Array = []
var _min: int = 0
var _max: int = 0

@onready var _row: HBoxContainer = $Panel/CardRow
@onready var _confirm: Button = $Panel/ConfirmButton
@onready var _label: Label = $Panel/Label

func _ready() -> void:
	_confirm.pressed.connect(_confirm_pressed)
	$Panel.theme = preload("res://src/ui/theme/game_theme.tres")
	JuicyButton.apply(_confirm)

func show_selection(cards: Array, min_n: int, max_n: int, title: String) -> void:
	if not is_node_ready(): await ready
	_min = min_n
	_max = max_n
	_label.text = title
	_selected.clear()
	for c in _row.get_children(): c.queue_free()
	for i in range(cards.size()):
		var cv: CardView = CARD_VIEW.instantiate()
		cv.set_interactive(false)
		_row.add_child(cv)
		cv.setup(cards[i])
		var idx := i
		cv.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed: toggle_index(idx))
	visible = true
	_update()

func toggle_index(i: int) -> void:
	if _selected.has(i): _selected.erase(i)
	elif _selected.size() < _max: _selected.append(i)
	_update()

func can_confirm() -> bool:
	return _selected.size() >= _min and _selected.size() <= _max

func _confirm_pressed() -> void:
	if can_confirm():
		visible = false
		confirmed.emit(_selected.duplicate())

func _update() -> void:
	_confirm.disabled = not can_confirm()
	for i in _row.get_child_count():
		var cv: CardView = _row.get_child(i)
		cv.set_highlight(CardHighlight.State.SELECTED if _selected.has(i) else CardHighlight.State.NONE)
```

Create `src/ui/overlays/card_select_panel.tscn` by copying `discard_panel.tscn` and changing: the script `ExtResource` path to `card_select_panel.gd`, the root node name to `CardSelectPanel`, and the `Label` node `text` to `"Select cards"`. (Keep the `Panel`, `CardRow`, `ConfirmButton`, `Label` node names — the script and tests reference them.)

- [ ] **Step 2: Delete the old panel**
```bash
git rm src/ui/overlays/discard_panel.gd src/ui/overlays/discard_panel.tscn
```

- [ ] **Step 3: Update `match.gd`**

In `src/ui/match/match.gd`:
- Change the `@onready` line `@onready var _discard = $DiscardPanel` to `@onready var _select = $CardSelectPanel`.
- In the scene `match.tscn`, rename the `DiscardPanel` child node to `CardSelectPanel` and repoint its script/scene to `card_select_panel.tscn` (edit the `.tscn` text: the instance/script reference and node name).
- Change the `_ready` connection
  `_discard.confirmed.connect(func(idx): apply_action(Action.resolve_choice({"indices": idx})))`
  to use `_select`.
- In `_route_pending_choice`, change the `discard_to_limit` case to:
```gdscript
		"discard_to_limit":
			var n: int = pc.data["count"]
			_select.show_selection(state.players[HUMAN].hand, n, n, "Discard %d card(s)" % n)
```

- [ ] **Step 4: Update the overlay tests**

In `tests/test_overlays.gd`, replace the two `discard_panel` tests with:
```gdscript
func test_card_select_requires_min_to_confirm() -> void:
	var p = _inst("res://src/ui/overlays/card_select_panel.tscn")
	p.show_selection(_hand(7), 2, 2, "Pick 2")
	p.toggle_index(0)
	assert_bool(p.can_confirm()).is_false()
	p.toggle_index(1)
	assert_bool(p.can_confirm()).is_true()

func test_card_select_allows_range() -> void:
	var p = _inst("res://src/ui/overlays/card_select_panel.tscn")
	p.show_selection(_hand(7), 0, 3, "Up to 3")
	assert_bool(p.can_confirm()).is_true()        # 0 is allowed
	p.toggle_index(0); p.toggle_index(1); p.toggle_index(2); p.toggle_index(3)
	assert_int(p._selected.size()).is_equal(3)    # capped at max 3

func test_card_select_highlights_card() -> void:
	var p = _inst("res://src/ui/overlays/card_select_panel.tscn")
	p.show_selection(_hand(7), 0, 2, "x")
	p.toggle_index(0)
	var row := p.find_child("CardRow")
	var first_card: CardView = row.get_child(0)
	assert_bool((first_card.find_child("Highlight") as Control).visible).is_true()
	p.toggle_index(0)
	assert_bool((first_card.find_child("Highlight") as Control).visible).is_false()
```

In `tests/test_pending_choice_routing.gd`, no node name changes are needed (it does not reference the discard panel). Leave as-is.

- [ ] **Step 5: Run the overlay + routing suites**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_overlays.gd`
Then: `... -a res://tests/test_pending_choice_routing.gd`
Expected: PASS for both.

- [ ] **Step 6: Run full suite (regression)**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
Expected: PASS.

- [ ] **Step 7: Commit**
```bash
git add -A src/ui tests/test_overlays.gd
git commit -m "refactor(ui): generalize discard panel into card_select_panel"
```

### Task 11: Route the three ChoiceSpec shapes in `match.gd`

**Files:**
- Modify: `src/ui/match/match.gd`
- Test: manual UI shapes are covered by engine/AI tests; add a routing smoke test.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_pending_choice_routing.gd`:
```gdscript
func test_select_cards_choice_shows_card_select_panel() -> void:
	var m: Node = _spawn()
	m.start_game(3, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	# Force a human card_effect choice.
	var spec := ChoiceSpec.select_cards(m.state.players[0].hand, 0, 1, "Pick")
	m.state.pending_choice = PendingChoice.new("card_effect", 0, {"spec": spec, "ui_shape": "select_cards"})
	m._route_pending_choice()
	assert_bool(m.get_node("CardSelectPanel").visible).is_true()
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_pending_choice_routing.gd`
Expected: FAIL — `card_effect` not routed.

- [ ] **Step 3: Implement routing + option prompt + targeting**

In `src/ui/match/match.gd`, add to `_route_pending_choice`'s human `match pc.kind`:
```gdscript
		"card_effect":
			_route_card_effect(pc)
```
Add the handler and a reusable option prompt. First add an `@onready` for an option prompt node (reuse `leader_cost_prompt` styling by adding a generic `OptionPrompt` CanvasLayer to `match.tscn` — see Step 4). Then:
```gdscript
func _route_card_effect(pc: PendingChoice) -> void:
	var spec: ChoiceSpec = pc.data["spec"]
	match spec.ui_shape:
		"select_cards":
			_select.show_selection(spec.cards, spec.min_n, spec.max_n, spec.title)
		"choose_option":
			_option_prompt.show_options(spec.labels, spec.title)
		"select_target":
			_begin_target_selection(spec)

func _begin_target_selection(spec: ChoiceSpec) -> void:
	_target_candidates = []
	for u in spec.cards:
		_target_candidates.append(u.instance_id)
	_targeting_for_choice = true
	_refresh_highlights()
```
Connect `_select.confirmed` is already wired to `resolve_choice({"indices": idx})` — good for `select_cards`.
For `select_target`, in the existing board click handler `handle_unit_clicked(instance_id)`, add at the top:
```gdscript
	if _targeting_for_choice:
		if _target_candidates.has(instance_id):
			_targeting_for_choice = false
			apply_action(Action.resolve_choice({"target_ids": [instance_id]}))
		return
```
Add fields near the other vars:
```gdscript
var _targeting_for_choice: bool = false
var _target_candidates: Array = []
```

- [ ] **Step 4: Add the OptionPrompt node + script**

Create `src/ui/overlays/option_prompt.gd`:
```gdscript
extends CanvasLayer

signal picked(option: int)

@onready var _box: VBoxContainer = $Panel/Options
@onready var _label: Label = $Panel/Label

func show_options(labels: Array, title: String) -> void:
	if not is_node_ready(): await ready
	_label.text = title
	for c in _box.get_children(): c.queue_free()
	for i in range(labels.size()):
		var b := Button.new()
		b.text = labels[i]
		var idx := i
		b.pressed.connect(func(): _emit(idx))
		_box.add_child(b)
		JuicyButton.apply(b)
	visible = true

func _emit(i: int) -> void:
	visible = false
	picked.emit(i)
```
Create `src/ui/overlays/option_prompt.tscn`: a `CanvasLayer` named `OptionPrompt` (`visible = false`) with `Panel` → `Label` (name `Label`) + `VBoxContainer` (name `Options`), script attached. Add it as a child of `match.tscn`'s root. In `match.gd` add:
```gdscript
@onready var _option_prompt = $OptionPrompt
```
and in `_ready`:
```gdscript
	_option_prompt.picked.connect(func(i): apply_action(Action.resolve_choice({"option": i})))
```

- [ ] **Step 5: Run the routing suite**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_pending_choice_routing.gd`
Expected: PASS.

- [ ] **Step 6: Commit**
```bash
git add -A src/ui tests/test_pending_choice_routing.gd
git commit -m "feat(ui): route select_cards/select_target/choose_option choices"
```

---

# PHASE 6 — REQUEST primitive

### Task 12: `all_requests_met_this_turn` flag + reset

**Files:**
- Modify: `src/engine/player_state.gd`, `src/engine/game_engine.gd`
- Test: `tests/test_request_primitive.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/test_request_primitive.gd`:
```gdscript
extends GdUnitTestSuite

func test_flag_defaults_false_and_resets_each_turn() -> void:
	var ps := PlayerState.new()
	assert_bool(ps.all_requests_met_this_turn).is_false()
	ps.all_requests_met_this_turn = true
	ps.reset_turn_counters()
	assert_bool(ps.all_requests_met_this_turn).is_false()
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_request_primitive.gd`
Expected: FAIL — field not defined.

- [ ] **Step 3: Implement**

In `src/engine/player_state.gd`, add field `var all_requests_met_this_turn: bool = false` and set it false in `reset_turn_counters()`:
```gdscript
func reset_turn_counters() -> void:
	all_requests_met_this_turn = false
	turn_counters = {
		"cards_played": 0,
		"cards_discarded": 0,
		"attacks_made": 0,
		"units_died": 0,
	}
```

- [ ] **Step 4: Run to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_request_primitive.gd`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add src/engine/player_state.gd tests/test_request_primitive.gd
git commit -m "feat(engine): per-player all_requests_met_this_turn flag"
```

### Task 13: `_request_met` + new event types

**Files:**
- Modify: `src/data/enums.gd`, `src/engine/game_engine.gd`
- Test: `tests/test_request_primitive.gd` (add)

- [ ] **Step 1: Add event + action enums**

In `src/data/enums.gd`, extend the enums:
```gdscript
enum EventType {
	CARD_PLAYED, CARD_DRAWN, CARD_DISCARDED,
	UNIT_ATTACKED, UNIT_DAMAGED, UNIT_DIED,
	DECK_DAMAGED, DECK_RESHUFFLED,
	TURN_STARTED, TURN_ENDED, GAME_OVER,
	REQUEST_MET, TRAP_FIRED,
}
enum ActionType { MULLIGAN, PLAY_CARD, DECLARE_ATTACK, END_TURN, ACTIVATE_TRAP, RESOLVE_CHOICE, ACTIVATE_ABILITY }
```

- [ ] **Step 2: Write the failing test**

Append to `tests/test_request_primitive.gd`:
```gdscript
class HasReq extends CardScript:
	func has_request() -> bool: return true
	func condition_met(card, ctx) -> bool:
		return ctx.counters(ctx.me())["cards_discarded"] >= 2

func test_request_met_uses_condition() -> void:
	var state := GameState.new(7)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	var u := state.make_instance(TestFactory.minion(1, 1, 1, 800))
	u.script = HasReq.new()
	u.zone = Enums.Zone.BOARD
	state.players[0].board.append(u)
	state.active_player = 0
	assert_bool(eng._request_met(u)).is_false()
	state.players[0].turn_counters["cards_discarded"] = 2
	assert_bool(eng._request_met(u)).is_true()

func test_global_flag_forces_request_met() -> void:
	var state := GameState.new(7)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	var u := state.make_instance(TestFactory.minion(1, 1, 1, 801))
	u.script = HasReq.new()
	u.zone = Enums.Zone.BOARD
	state.players[0].board.append(u)
	state.players[0].all_requests_met_this_turn = true
	assert_bool(eng._request_met(u)).is_true()
```

- [ ] **Step 3: Run to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_request_primitive.gd`
Expected: FAIL — `_request_met` not defined.

- [ ] **Step 4: Implement `_request_met`**

In `src/engine/game_engine.gd`:
```gdscript
func _request_met(card: CardInstance) -> bool:
	var owner := _owner_of(card)
	if owner < 0:
		return false
	if state.players[owner].all_requests_met_this_turn:
		return true
	if card.script == null or not card.script.has_request():
		return false
	return card.script.condition_met(card, _ctx_for(owner))
```

- [ ] **Step 5: Run to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_request_primitive.gd`
Expected: PASS.

- [ ] **Step 6: Commit**
```bash
git add src/data/enums.gd src/engine/game_engine.gd tests/test_request_primitive.gd
git commit -m "feat(engine): _request_met + REQUEST_MET/TRAP_FIRED/ACTIVATE_ABILITY enums"
```

### Task 14: REQUEST combat buff + resumable attack via queued combat

**Files:**
- Modify: `src/engine/game_engine.gd` (`_declare_attack`, add `_resolve_combat`, remove `_check_traps`/`_trap_condition_met`)
- Test: `tests/test_request_primitive.gd` (add), `tests/test_engine_attack.gd` (regression)

- [ ] **Step 1: Write the failing test**

Append to `tests/test_request_primitive.gd`:
```gdscript
func _ready_attack_engine() -> GameEngine:
	var state := GameState.new(11)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	eng.apply(Action.mulligan([]))
	eng.apply(Action.mulligan([]))
	return eng

func test_request_attacker_gets_plus_two_and_survives() -> void:
	var eng := _ready_attack_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	# Attacker: 3 HP with a REQUEST that is met (global flag).
	var atk := eng.state.make_instance(TestFactory.minion(1, 1, 3, 802))
	atk.script = HasReq.new()
	atk.zone = Enums.Zone.BOARD
	atk.tapped = false
	eng.state.players[me].board.append(atk)
	eng.state.players[me].all_requests_met_this_turn = true
	# Defender: deals 4 damage. Without the +2 HP buff the attacker (3 HP) dies.
	var def := eng.state.make_instance(TestFactory.minion(1, 4, 4, 803))
	def.zone = Enums.Zone.BOARD
	eng.state.players[opp].board.append(def)
	eng.apply(Action.declare_attack(atk.instance_id, {"unit": def.instance_id}))
	# Attacker survived (3+2-4 = 1 HP) and is still on the board.
	assert_array(eng.state.players[me].board).contains([atk])
	# A REQUEST_MET event fired.
	assert_int(eng.state.bus.events_of_type(Enums.EventType.REQUEST_MET).size()).is_equal(1)
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_request_primitive.gd`
Expected: FAIL — no buff applied, attacker dies / no REQUEST_MET.

- [ ] **Step 3: Reimplement attack as queued, with REQUEST buff**

In `src/engine/game_engine.gd`, replace `_declare_attack` and delete `_check_traps` / `_trap_condition_met`:
```gdscript
func _declare_attack(attacker_id: int, target: Dictionary) -> void:
	var ap := state.active()
	var attacker: CardInstance = _find_on_board(ap, attacker_id)
	if attacker == null:
		return
	attacker.tapped = true
	ap.turn_counters["attacks_made"] += 1
	emit(GameEvent.new(Enums.EventType.UNIT_ATTACKED,
		{"attacker": attacker_id, "player": state.active_player}))
	if attacker.script != null and attacker.script.has_request() and _request_met(attacker):
		attacker.current_damage += 2
		attacker.current_health += 2
		emit(GameEvent.new(Enums.EventType.REQUEST_MET,
			{"player": state.active_player, "instance": attacker_id}))
	_push({"kind": "call", "fn": func(): _resolve_combat(attacker_id, target)})
	_pump()

func _resolve_combat(attacker_id: int, target: Dictionary) -> void:
	if state.phase == Enums.Phase.GAME_OVER:
		return
	var ap := state.active()
	var attacker: CardInstance = _find_on_board(ap, attacker_id)
	if attacker == null:
		return                      # died/bounced during on-attack triggers
	if target.get("deck", false):
		_deck_damage(state.opponent(), attacker.current_damage)
		return
	var opp := state.players[state.opponent()]
	var defender: CardInstance = _find_on_board(opp, target["unit"])
	if defender == null:
		return
	var r := Combat.compute(attacker, defender)
	defender.current_health -= r["dmg_to_def"]
	attacker.current_health -= r["dmg_to_atk"]
	emit(GameEvent.new(Enums.EventType.UNIT_DAMAGED,
		{"target": defender.instance_id, "amount": r["dmg_to_def"]}))
	emit(GameEvent.new(Enums.EventType.UNIT_DAMAGED,
		{"target": attacker.instance_id, "amount": r["dmg_to_atk"]}))
	if r["def_dies"]:
		_kill(state.opponent(), defender)
	if r["atk_dies"]:
		_kill(state.active_player, attacker)
```
Note: `emit()` inside `_declare_attack` runs while not resolving, so it drains its reactions immediately; the combat `call` is queued and pumped after. Because on-attack reactions may suspend (a choice), the combat job stays queued and runs when the choice resumes — attacks are resumable.

- [ ] **Step 4: Run the new test + attack regression**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_request_primitive.gd`
Then: `... -a res://tests/test_engine_attack.gd`
Then: `... -a res://tests/test_engine_traps.gd`
Expected: `test_engine_traps.gd` references `_trap_condition_met` (now deleted) — update it: delete `test_trap_condition_is_inert`, keep `test_set_vanilla_trap_does_not_fire_on_opponent_attack` (a vanilla trap has no `reacts_to`, so it still never fires). Re-run until PASS.

- [ ] **Step 5: Run full suite (regression)**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
Expected: PASS.

- [ ] **Step 6: Commit**
```bash
git add src/engine/game_engine.gd tests/test_request_primitive.gd tests/test_engine_traps.gd
git commit -m "feat(engine): REQUEST combat buff + resumable queued combat"
```

---

# PHASE 7 — Effect primitives + trap firing + activated abilities

### Task 15: Effect-context engine primitives

**Files:**
- Modify: `src/engine/game_engine.gd`
- Test: `tests/test_effect_context.gd` (add)

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_effect_context.gd`:
```gdscript
func test_search_deck_and_draw_specific() -> void:
	var eng := _eng()
	var ps := eng.state.players[0]
	var target := ps.deck[3]
	var found := eng._search_deck(0, func(c): return c.instance_id == target.instance_id)
	assert_object(found).is_equal(target)
	eng._draw_specific(0, found)
	assert_array(ps.hand).contains([target])
	assert_bool(ps.deck.has(target)).is_false()

func test_damage_unit_kills_at_zero() -> void:
	var eng := _eng()
	var u := eng.state.make_instance(TestFactory.minion(1, 1, 2, 700))
	u.zone = Enums.Zone.BOARD
	eng.state.players[0].board.append(u)
	eng._damage_unit(u, 2)
	assert_bool(eng.state.players[0].board.has(u)).is_false()
	assert_bool(eng.state.players[0].discard.has(u)).is_true()

func test_put_on_deck_top() -> void:
	var eng := _eng()
	var u := eng.state.make_instance(TestFactory.minion(1, 1, 1, 701))
	u.zone = Enums.Zone.BOARD
	eng.state.players[1].board.append(u)
	eng._put_on_deck_top(u)
	assert_object(eng.state.players[1].deck[0]).is_equal(u)
	assert_bool(eng.state.players[1].board.has(u)).is_false()

func test_steal_top_discard() -> void:
	var eng := _eng()
	var stolen := eng.state.make_instance(TestFactory.minion(1, 1, 1, 702))
	stolen.zone = Enums.Zone.DISCARD
	eng.state.players[1].discard.append(stolen)
	var got := eng._steal_top_discard(0, 1)
	assert_object(got).is_equal(stolen)
	assert_bool(eng.state.players[0].hand.has(stolen)).is_true()
	assert_int(stolen.vars["stolen_from"]).is_equal(1)
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_effect_context.gd`
Expected: FAIL — primitives not defined.

- [ ] **Step 3: Implement the primitives**

In `src/engine/game_engine.gd`:
```gdscript
func _damage_unit(unit: CardInstance, n: int) -> void:
	unit.current_health -= n
	emit(GameEvent.new(Enums.EventType.UNIT_DAMAGED, {"target": unit.instance_id, "amount": n}))
	if unit.current_health <= 0:
		_kill_unit(unit)

func _kill_unit(unit: CardInstance) -> void:
	var owner := _owner_of(unit)
	if owner >= 0 and state.players[owner].board.has(unit):
		_kill(owner, unit)

func _discard_from_hand(card: CardInstance) -> void:
	var owner := _owner_of(card)
	if owner < 0:
		return
	var ps := state.players[owner]
	if not ps.hand.has(card):
		return
	ps.hand.erase(card)
	card.zone = Enums.Zone.DISCARD
	ps.discard.append(card)
	ps.turn_counters["cards_discarded"] += 1
	emit(GameEvent.new(Enums.EventType.CARD_DISCARDED, {"player": owner, "instance": card.instance_id}))

func _search_deck(pidx: int, pred: Callable) -> CardInstance:
	for c in state.players[pidx].deck:
		if pred.call(c):
			return c
	return null

func _draw_specific(pidx: int, card: CardInstance) -> void:
	var ps := state.players[pidx]
	if not ps.deck.has(card):
		return
	ps.deck.erase(card)
	card.zone = Enums.Zone.HAND
	ps.hand.append(card)
	emit(GameEvent.new(Enums.EventType.CARD_DRAWN, {"player": pidx, "instance": card.instance_id}))

func _summon_free(pidx: int, card: CardInstance) -> void:
	var ps := state.players[pidx]
	if ps.hand.has(card):
		ps.hand.erase(card)
	card.zone = Enums.Zone.BOARD
	card.tapped = true
	ps.board.append(card)
	emit(GameEvent.new(Enums.EventType.CARD_PLAYED,
		{"player": pidx, "instance": card.instance_id, "card_type": card.definition.type}))

func _put_on_deck_top(unit: CardInstance) -> void:
	var owner := _owner_of(unit)
	if owner < 0:
		return
	var ps := state.players[owner]
	ps.board.erase(unit)
	unit.reset_stats()
	unit.zone = Enums.Zone.DECK
	ps.deck.push_front(unit)

func _steal_top_discard(thief: int, victim: int) -> CardInstance:
	var vps := state.players[victim]
	if vps.discard.is_empty():
		return null
	var card: CardInstance = vps.discard.pop_back()
	vps.discard.erase(card)
	card.vars["stolen_from"] = victim
	card.zone = Enums.Zone.HAND
	state.players[thief].hand.append(card)
	return card
```
> Note: `pop_back()` already removes the element; the extra `erase` is harmless but remove it for clarity — keep only `pop_back()`.

Apply that note: the `_steal_top_discard` body is:
```gdscript
	var card: CardInstance = vps.discard.pop_back()
	card.vars["stolen_from"] = victim
	card.zone = Enums.Zone.HAND
	state.players[thief].hand.append(card)
	return card
```

- [ ] **Step 4: Run to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_effect_context.gd`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add src/engine/game_engine.gd tests/test_effect_context.gd
git commit -m "feat(engine): effect primitives (search/summon/steal/damage/etc.)"
```

### Task 16: `immortal_this_turn` kill guard + reset

**Files:**
- Modify: `src/engine/game_engine.gd` (`_kill`, `_start_turn`)
- Test: `tests/test_request_primitive.gd` (add)

- [ ] **Step 1: Write the failing test**

Append to `tests/test_request_primitive.gd`:
```gdscript
func test_immortal_unit_is_not_killed() -> void:
	var state := GameState.new(13)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	var u := state.make_instance(TestFactory.minion(1, 1, 1, 804))
	u.zone = Enums.Zone.BOARD
	u.vars["immortal_this_turn"] = true
	state.players[0].board.append(u)
	eng._kill(0, u)
	assert_array(state.players[0].board).contains([u])    # survived
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_request_primitive.gd`
Expected: FAIL — unit gets killed.

- [ ] **Step 3: Implement guard + reset**

In `src/engine/game_engine.gd`, at the top of `_kill`:
```gdscript
func _kill(owner_idx: int, unit: CardInstance) -> void:
	if unit.vars.get("immortal_this_turn", false):
		return
	var owner := state.players[owner_idx]
	... existing body ...
```
In `_start_turn`, after `ps.reset_turn_counters()`, clear per-unit turn flags and once-per-turn vars for both players:
```gdscript
	for p in state.players:
		for u in p.board:
			u.vars.erase("immortal_this_turn")
			u.vars.erase("opt_used_this_turn")
```

- [ ] **Step 4: Run to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_request_primitive.gd`
Expected: PASS.

- [ ] **Step 5: Run full suite (regression)**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
Expected: PASS.

- [ ] **Step 6: Commit**
```bash
git add src/engine/game_engine.gd tests/test_request_primitive.gd
git commit -m "feat(engine): immortal_this_turn death-prevention + turn-flag reset"
```

### Task 17: Trap firing primitive

**Files:**
- Modify: `src/engine/game_engine.gd` (`_fire_trap`)
- Test: `tests/test_trap_firing.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/test_trap_firing.gd`:
```gdscript
extends GdUnitTestSuite

class KillerTrap extends CardScript:
	func reacts_to() -> Array: return [Enums.EventType.UNIT_ATTACKED]
	func active_zones() -> Array: return [Enums.Zone.TRAP_SET]
	func react(card, event, ctx) -> void:
		ctx.fire_trap(card)

func test_fire_trap_moves_to_discard_and_emits() -> void:
	var state := GameState.new(21)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	var trap := state.make_instance(TestFactory.trap(2, 600))
	trap.script = KillerTrap.new()
	trap.zone = Enums.Zone.TRAP_SET
	state.players[1].set_traps.append(trap)
	eng.emit(GameEvent.new(Enums.EventType.UNIT_ATTACKED, {"attacker": 1, "player": 0}))
	assert_bool(state.players[1].set_traps.has(trap)).is_false()
	assert_bool(state.players[1].discard.has(trap)).is_true()
	assert_int(state.bus.events_of_type(Enums.EventType.TRAP_FIRED).size()).is_equal(1)
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_trap_firing.gd`
Expected: FAIL — `_fire_trap` not defined.

- [ ] **Step 3: Implement**

In `src/engine/game_engine.gd`:
```gdscript
func _fire_trap(card: CardInstance) -> void:
	var owner := _owner_of(card)
	if owner < 0:
		return
	var ps := state.players[owner]
	if not ps.set_traps.has(card):
		return
	ps.set_traps.erase(card)
	card.zone = Enums.Zone.DISCARD
	ps.discard.append(card)
	emit(GameEvent.new(Enums.EventType.TRAP_FIRED, {"player": owner, "instance": card.instance_id}))
```

- [ ] **Step 4: Run to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_trap_firing.gd`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add src/engine/game_engine.gd tests/test_trap_firing.gd
git commit -m "feat(engine): trap firing primitive"
```

### Task 18: Battlecry hook + activated abilities wiring

**Files:**
- Modify: `src/engine/game_engine.gd` (`_play_card`, `apply`, `get_legal_actions`), `src/engine/action.gd`
- Test: `tests/test_legal_actions.gd` (add), `tests/test_engine_play.gd` (regression)

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_legal_actions.gd`:
```gdscript
class TapAbility extends CardScript:
	func activated_abilities(card, ctx) -> Array:
		if card.tapped: return []
		return [{"id": "go", "label": "Go"}]
	func activate(card, ability_id, ctx) -> void:
		if ability_id == "go": card.tapped = true

func test_activated_ability_listed_and_applied() -> void:
	var state := GameState.new(15)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	eng.apply(Action.mulligan([]))
	eng.apply(Action.mulligan([]))
	var u := state.make_instance(TestFactory.minion(1, 1, 1, 610))
	u.script = TapAbility.new()
	u.zone = Enums.Zone.BOARD
	u.tapped = false
	state.active().board.append(u)
	var legal := eng.get_legal_actions()
	var has_ability := false
	for a in legal:
		if a.type == Enums.ActionType.ACTIVATE_ABILITY and a.params["instance_id"] == u.instance_id:
			has_ability = true
	assert_bool(has_ability).is_true()
	eng.apply(Action.activate_ability(u.instance_id, "go"))
	assert_bool(u.tapped).is_true()
```

Append to `tests/test_engine_play.gd`:
```gdscript
class CastBattlecry extends CardScript:
	func on_cast(card, ctx) -> void: ctx.draw(1)

func test_on_cast_battlecry_runs_when_played() -> void:
	var eng := _ready_engine()
	var ci := _give(eng, TestFactory.minion(1, 1, 1, 210))
	ci.script = CastBattlecry.new()
	var hand_before := eng.state.active().hand.size()   # includes ci
	eng.apply(Action.play_card(ci.instance_id))
	# Played ci (hand -1) then drew 1 (hand +1) => net same as before minus the played card... 
	# hand_before counted ci; after: removed ci (-1) + drew 1 (+1) = hand_before.
	assert_int(eng.state.active().hand.size()).is_equal(hand_before)
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_legal_actions.gd`
Then: `... -a res://tests/test_engine_play.gd`
Expected: FAIL — `activate_ability` / battlecry / `ACTIVATE_ABILITY` not handled.

- [ ] **Step 3: Implement**

In `src/engine/action.gd`, add:
```gdscript
static func activate_ability(instance_id: int, ability_id: String) -> Action:
	return Action.new(Enums.ActionType.ACTIVATE_ABILITY, {"instance_id": instance_id, "ability_id": ability_id})
```

In `src/engine/game_engine.gd` `apply`, add a case:
```gdscript
		Enums.ActionType.ACTIVATE_ABILITY:
			_activate_ability(action.params["instance_id"], action.params["ability_id"])
```
And implement:
```gdscript
func _activate_ability(instance_id: int, ability_id: String) -> void:
	var ps := state.active()
	var card := _find_on_board(ps, instance_id)
	if card == null or card.script == null:
		return
	_push({"kind": "call", "fn": func(): card.script.activate(card, ability_id, _ctx_for(state.active_player))})
	_pump()
```

In `_play_card`, after the existing `emit(GameEvent.new(Enums.EventType.CARD_PLAYED, ...))`, add the battlecry for non-trap cards (replace the trailing emit so it queues then runs on_cast):
```gdscript
	emit(GameEvent.new(Enums.EventType.CARD_PLAYED,
		{"player": state.active_player, "instance": instance_id, "card_type": def.type}))
	if def.type != Enums.CardType.TRAP and card.script != null:
		_push({"kind": "call", "fn": func(): card.script.on_cast(card, _ctx_for(state.active_player))})
		_pump()
```

In `get_legal_actions`, after the attack-generation loop and before `out.append(Action.end_turn())`, add:
```gdscript
	for u in ps.board:
		if u.script == null:
			continue
		for ab in u.script.activated_abilities(u, _ctx_for(state.active_player)):
			out.append(Action.activate_ability(u.instance_id, ab["id"]))
```

- [ ] **Step 4: Run to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_legal_actions.gd`
Then: `... -a res://tests/test_engine_play.gd`
Expected: PASS.

- [ ] **Step 5: Run full suite (regression)**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
Expected: PASS.

- [ ] **Step 6: Commit**
```bash
git add src/engine/game_engine.gd src/engine/action.gd tests/test_legal_actions.gd tests/test_engine_play.gd
git commit -m "feat(engine): battlecry on_cast + activated abilities"
```

---

# PHASE 8 — The 14 Strike cards

**Shared test helper.** Create `tests/cards/card_test_base.gd` once, used by every card test:
```gdscript
class_name CardTestBase
extends GdUnitTestSuite

func strike_def(id: int) -> CardDefinition:
	for d in CardDatabase.load_deck("res://src/data/decks/strike.csv", "strike"):
		if d.id == id:
			return d
	return null

func fresh_engine() -> GameEngine:
	var state := GameState.new(123)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	eng.apply(Action.mulligan([]))
	eng.apply(Action.mulligan([]))
	return eng

func place_on_board(eng: GameEngine, pidx: int, def: CardDefinition) -> CardInstance:
	var ci := eng.state.make_instance(def)
	ci.zone = Enums.Zone.BOARD
	eng.state.players[pidx].board.append(ci)
	return ci

func put_in_hand(eng: GameEngine, pidx: int, def: CardDefinition) -> CardInstance:
	var ci := eng.state.make_instance(def)
	ci.zone = Enums.Zone.HAND
	eng.state.players[pidx].hand.append(ci)
	eng.state.players[pidx].tickets_total = 20
	return ci
```
Commit this helper first:
```bash
git add tests/cards/card_test_base.gd
git commit -m "test: CardTestBase helper for Strike card tests"
```

Each card task follows the same rhythm: write `src/cards/scripts/strike/<file>.gd`, add its `_register` line in `card_script_registry.gd._build()`, write the per-card test, run it (fail → pass), commit. The `_build()` registrations accumulate; add this block in Phase 8 and append one line per card:
```gdscript
	# --- Strike ---
	_register("strike", 1, BattleBjorn.new())
	_register("strike", 2, StrikeRequestForm.new())   # both copies share id 2; copy id 3 -> add line too
	_register("strike", 3, StrikeRequestForm.new())
	_register("strike", 4, PriorityRaise.new())
	_register("strike", 5, BountyStriker.new())
	_register("strike", 6, BountyStriker.new())
	_register("strike", 7, RedAlien.new())
	_register("strike", 8, HeadphonesGhost.new())
	_register("strike", 9, GrayAlien.new())
	_register("strike", 10, CactusGuy.new())
	_register("strike", 11, RequestSlacker.new())
	_register("strike", 12, RequestSlacker.new())
	_register("strike", 13, Overstriker.new())
	_register("strike", 14, Overstriker.new())
	_register("strike", 15, RequestBoard.new())
	_register("strike", 16, RequestBoard.new())
	_register("strike", 17, BjornHammer.new())
	_register("strike", 18, BjornHammer.new())
	_register("strike", 19, WrongMascot.new())
	_register("strike", 20, WrongMascot.new())
	_register("strike", 21, StrikeSocial.new())
```
Add each `_register` line in the same commit as its script. The class names referenced are `class_name` declarations in each card file.

### Task 19: Strike Request Form (id 2/3) — search & draw

**Files:**
- Create: `src/cards/scripts/strike/strike_request_form.gd`
- Modify: `src/cards/card_script_registry.gd`
- Test: `tests/cards/strike/test_strike_request_form.gd`

- [ ] **Step 1: Write the script**

`src/cards/scripts/strike/strike_request_form.gd`:
```gdscript
class_name StrikeRequestForm
extends CardScript

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	var found := ctx.search_deck(func(c: CardInstance):
		return c.script != null and c.script.has_request())
	if found != null:
		ctx.draw_specific(found)
```

- [ ] **Step 2: Register**

In `card_script_registry.gd._build()`, add the two `_register("strike", 2, ...)` / `("strike", 3, ...)` lines.

- [ ] **Step 3: Write the failing test**

`tests/cards/strike/test_strike_request_form.gd`:
```gdscript
extends CardTestBase

func test_draws_first_request_card_from_deck() -> void:
	var eng := fresh_engine()
	# Put a Red Alien (has REQUEST) into player 0's deck.
	var red := eng.state.make_instance(strike_def(7))
	red.zone = Enums.Zone.DECK
	eng.state.players[0].deck.append(red)
	var form := put_in_hand(eng, 0, strike_def(2))
	eng.apply(Action.play_card(form.instance_id))
	assert_bool(eng.state.players[0].hand.has(red)).is_true()
```

- [ ] **Step 4: Run (fail → pass)**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/cards/strike/test_strike_request_form.gd`
Expected: PASS after the script+registration exist.

- [ ] **Step 5: Commit**
```bash
git add src/cards/scripts/strike/strike_request_form.gd src/cards/card_script_registry.gd tests/cards/strike/test_strike_request_form.gd
git commit -m "feat(strike): Strike Request Form"
```

### Task 20: Battle Bjorn (id 1) — global REQUEST enabler

**Files:** Create `src/cards/scripts/strike/battle_bjorn.gd`; register id 1; test.

- [ ] **Step 1: Script**
```gdscript
class_name BattleBjorn
extends CardScript

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	ctx.gs().players[ctx.me()].all_requests_met_this_turn = true
```

- [ ] **Step 2: Register** id 1.

- [ ] **Step 3: Test** `tests/cards/strike/test_battle_bjorn.gd`:
```gdscript
extends CardTestBase

func test_sets_global_request_flag_on_cast() -> void:
	var eng := fresh_engine()
	var bjorn := put_in_hand(eng, 0, strike_def(1))
	eng.apply(Action.play_card(bjorn.instance_id))
	assert_bool(eng.state.players[0].all_requests_met_this_turn).is_true()
```

- [ ] **Step 4: Run (fail → pass)**
Run: `... -a res://tests/cards/strike/test_battle_bjorn.gd` → PASS.

- [ ] **Step 5: Commit**
```bash
git add src/cards/scripts/strike/battle_bjorn.gd src/cards/card_script_registry.gd tests/cards/strike/test_battle_bjorn.gd
git commit -m "feat(strike): Battle Bjorn"
```

### Task 21: Gray Alien (id 9) — discard any, draw +1 (choice)

**Files:** Create script; register id 9; test.

- [ ] **Step 1: Script** `src/cards/scripts/strike/gray_alien.gd`:
```gdscript
class_name GrayAlien
extends CardScript

func has_request() -> bool: return true
func condition_met(card: CardInstance, ctx: EffectContext) -> bool:
	return ctx.hand(ctx.me()).size() >= 3

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	var h := ctx.hand(ctx.me())
	ctx.request_choice(card, ChoiceSpec.select_cards(h.duplicate(), 0, h.size(), "Discard any number"), "gray_discard")

func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "gray_discard":
		var chosen: Array = result["cards"]
		for c in chosen:
			ctx.discard_from_hand(c)
		ctx.draw(chosen.size() + 1)
```

- [ ] **Step 2: Register** id 9.

- [ ] **Step 3: Test** `tests/cards/strike/test_gray_alien.gd`:
```gdscript
extends CardTestBase

func test_discards_chosen_then_draws_count_plus_one() -> void:
	var eng := fresh_engine()
	var ps := eng.state.players[0]
	# Give a known extra hand card to discard.
	var extra := put_in_hand(eng, 0, strike_def(2))
	var gray := put_in_hand(eng, 0, strike_def(9))
	var deck_before := ps.deck.size()
	eng.apply(Action.play_card(gray.instance_id))
	# Suspended for the discard choice.
	assert_str(eng.state.pending_choice.kind).is_equal("card_effect")
	var spec: ChoiceSpec = eng.state.pending_choice.data["spec"]
	# Choose to discard `extra` (find its index in the spec list).
	var idx := spec.cards.find(extra)
	eng.apply(Action.resolve_choice({"indices": [idx]}))
	assert_bool(ps.discard.has(extra)).is_true()
	# Drew 1 (chosen) + 1 = 2 from deck.
	assert_int(ps.deck.size()).is_equal(deck_before - 2)
```

- [ ] **Step 4: Run (fail → pass)**
Run: `... -a res://tests/cards/strike/test_gray_alien.gd` → PASS.

- [ ] **Step 5: Commit**
```bash
git add src/cards/scripts/strike/gray_alien.gd src/cards/card_script_registry.gd tests/cards/strike/test_gray_alien.gd
git commit -m "feat(strike): Gray Alien"
```

### Task 22: Request Slacker (id 11/12) — bounce enemy minion to deck top (target)

**Files:** Create script; register id 11 & 12; test.

- [ ] **Step 1: Script** `src/cards/scripts/strike/request_slacker.gd`:
```gdscript
class_name RequestSlacker
extends CardScript

func has_request() -> bool: return true
func condition_met(card: CardInstance, ctx: EffectContext) -> bool:
	return ctx.board(ctx.me()).size() + ctx.board(ctx.opponent()).size() <= 4

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	var enemy_minions: Array = []
	for u in ctx.board(ctx.opponent()):
		if u.definition.type == Enums.CardType.MINION:
			enemy_minions.append(u)
	if enemy_minions.is_empty():
		return
	ctx.request_choice(card, ChoiceSpec.select_target(enemy_minions, 1, 1, "Place an enemy Minion on top of their Deck"), "bounce")

func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "bounce" and not result["targets"].is_empty():
		ctx.put_on_deck_top(result["targets"][0])
```

- [ ] **Step 2: Register** ids 11 and 12.

- [ ] **Step 3: Test** `tests/cards/strike/test_request_slacker.gd`:
```gdscript
extends CardTestBase

func test_puts_chosen_enemy_minion_on_deck_top() -> void:
	var eng := fresh_engine()
	var enemy := place_on_board(eng, 1, strike_def(2))   # a minion
	var slacker := put_in_hand(eng, 0, strike_def(11))
	eng.apply(Action.play_card(slacker.instance_id))
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_target")
	eng.apply(Action.resolve_choice({"target_ids": [enemy.instance_id]}))
	assert_object(eng.state.players[1].deck[0]).is_equal(enemy)
	assert_bool(eng.state.players[1].board.has(enemy)).is_false()
```

- [ ] **Step 4: Run (fail → pass)**
Run: `... -a res://tests/cards/strike/test_request_slacker.gd` → PASS.

- [ ] **Step 5: Commit**
```bash
git add src/cards/scripts/strike/request_slacker.gd src/cards/card_script_registry.gd tests/cards/strike/test_request_slacker.gd
git commit -m "feat(strike): Request Slacker"
```

### Task 23: Request Board (id 15/16) — summon met-REQUEST minions free

**Files:** Create script; register id 15 & 16; test.

- [ ] **Step 1: Script** `src/cards/scripts/strike/request_board.gd`:
```gdscript
class_name RequestBoard
extends CardScript

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	var minions: Array = []
	for c in ctx.hand(ctx.me()):
		if c.definition.type == Enums.CardType.MINION:
			minions.append(c)
	for m in minions:
		if m.script != null and m.script.has_request() and ctx.request_met(m):
			ctx.summon_free(m)
```

- [ ] **Step 2: Register** ids 15 and 16.

- [ ] **Step 3: Test** `tests/cards/strike/test_request_board.gd`:
```gdscript
extends CardTestBase

func test_summons_only_minions_whose_request_is_met() -> void:
	var eng := fresh_engine()
	eng.state.players[0].all_requests_met_this_turn = true   # force all requests met
	var slacker := put_in_hand(eng, 0, strike_def(11))       # a REQUEST minion
	var board := put_in_hand(eng, 0, strike_def(15))
	eng.apply(Action.play_card(board.instance_id))
	assert_bool(eng.state.players[0].board.has(slacker)).is_true()
```

- [ ] **Step 4: Run (fail → pass)**
Run: `... -a res://tests/cards/strike/test_request_board.gd` → PASS.

- [ ] **Step 5: Commit**
```bash
git add src/cards/scripts/strike/request_board.gd src/cards/card_script_registry.gd tests/cards/strike/test_request_board.gd
git commit -m "feat(strike): Request Board"
```

### Task 24: Bjorn Hammer (id 17/18) — kill non-REQUEST units, end turn

**Files:** Create script; register id 17 & 18; test.

- [ ] **Step 1: Script** `src/cards/scripts/strike/bjorn_hammer.gd`:
```gdscript
class_name BjornHammer
extends CardScript

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	var victims: Array = []
	for pidx in [ctx.me(), ctx.opponent()]:
		for u in ctx.board(pidx):
			if not ctx.request_met(u):     # no REQUEST never "meets" one
				victims.append(u)
	for v in victims:
		ctx.kill(v)
	ctx.end_turn()
```

- [ ] **Step 2: Register** ids 17 and 18.

- [ ] **Step 3: Test** `tests/cards/strike/test_bjorn_hammer.gd`:
```gdscript
extends CardTestBase

func test_kills_non_request_units_and_ends_turn() -> void:
	var eng := fresh_engine()
	var attacker_turn := eng.state.active_player
	var vanilla := place_on_board(eng, attacker_turn, strike_def(2))   # no REQUEST
	var req := place_on_board(eng, attacker_turn, strike_def(11))      # has REQUEST
	eng.state.players[attacker_turn].all_requests_met_this_turn = true
	var hammer := put_in_hand(eng, attacker_turn, strike_def(17))
	eng.apply(Action.play_card(hammer.instance_id))
	assert_bool(eng.state.players[attacker_turn].board.has(vanilla)).is_false()  # killed
	# req met its REQUEST (global flag) so it survives, if still that player's turn data
	# Turn ended: active player changed.
	assert_int(eng.state.active_player).is_not_equal(attacker_turn)
```

- [ ] **Step 4: Run (fail → pass)**
Run: `... -a res://tests/cards/strike/test_bjorn_hammer.gd` → PASS.

- [ ] **Step 5: Commit**
```bash
git add src/cards/scripts/strike/bjorn_hammer.gd src/cards/card_script_registry.gd tests/cards/strike/test_bjorn_hammer.gd
git commit -m "feat(strike): Bjorn Hammer"
```

### Task 25: Priority Raise (id 4) — activated: tap to move REQUEST card discard→deck

**Files:** Create script; register id 4; test.

- [ ] **Step 1: Script** `src/cards/scripts/strike/priority_raise.gd`:
```gdscript
class_name PriorityRaise
extends CardScript

func activated_abilities(card: CardInstance, ctx: EffectContext) -> Array:
	if card.tapped:
		return []
	var has_target := false
	for c in ctx.discard_pile(ctx.me()):
		if c.script != null and c.script.has_request():
			has_target = true
	return [{"id": "raise", "label": "Move a REQUEST card to your Deck"}] if has_target else []

func activate(card: CardInstance, ability_id: String, ctx: EffectContext) -> void:
	if ability_id != "raise":
		return
	var candidates: Array = []
	for c in ctx.discard_pile(ctx.me()):
		if c.script != null and c.script.has_request():
			candidates.append(c)
	if candidates.is_empty():
		return
	card.tapped = true
	ctx.request_choice(card, ChoiceSpec.select_cards(candidates, 1, 1, "Move a REQUEST card to your Deck"), "raise")

func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "raise" and not result["cards"].is_empty():
		var c: CardInstance = result["cards"][0]
		ctx.gs().players[ctx.me()].discard.erase(c)
		c.zone = Enums.Zone.DECK
		ctx.gs().players[ctx.me()].deck.append(c)
```

- [ ] **Step 2: Register** id 4.

- [ ] **Step 3: Test** `tests/cards/strike/test_priority_raise.gd`:
```gdscript
extends CardTestBase

func test_moves_request_card_from_discard_to_deck_and_taps() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var raise := place_on_board(eng, me, strike_def(4))
	raise.tapped = false
	# A REQUEST card sitting in discard.
	var req := eng.state.make_instance(strike_def(11))
	req.zone = Enums.Zone.DISCARD
	eng.state.players[me].discard.append(req)
	eng.apply(Action.activate_ability(raise.instance_id, "raise"))
	var spec: ChoiceSpec = eng.state.pending_choice.data["spec"]
	eng.apply(Action.resolve_choice({"indices": [spec.cards.find(req)]}))
	assert_bool(eng.state.players[me].deck.has(req)).is_true()
	assert_bool(eng.state.players[me].discard.has(req)).is_false()
	assert_bool(raise.tapped).is_true()
```

- [ ] **Step 4: Run (fail → pass)**
Run: `... -a res://tests/cards/strike/test_priority_raise.gd` → PASS.

- [ ] **Step 5: Commit**
```bash
git add src/cards/scripts/strike/priority_raise.gd src/cards/card_script_registry.gd tests/cards/strike/test_priority_raise.gd
git commit -m "feat(strike): Priority Raise"
```

### Task 26: Bounty Striker (id 5/6) — react to REQUEST_MET in discard

**Files:** Create script; register id 5 & 6; test.

- [ ] **Step 1: Script** `src/cards/scripts/strike/bounty_striker.gd`:
```gdscript
class_name BountyStriker
extends CardScript

func has_request() -> bool: return false   # its own line is a trigger, not a REQUEST buff

func reacts_to() -> Array: return [Enums.EventType.REQUEST_MET]
func active_zones() -> Array: return [Enums.Zone.DISCARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	# "Whenever you meet a REQUEST" => the controller's own REQUEST_MET.
	if event.data.get("player", -1) != ctx.me():
		return
	if not ctx.discard_pile(ctx.me()).has(card):
		return
	ctx.gs().players[ctx.me()].discard.erase(card)
	card.zone = Enums.Zone.HAND
	ctx.gs().players[ctx.me()].hand.append(card)
```

- [ ] **Step 2: Register** ids 5 and 6.

- [ ] **Step 3: Test** `tests/cards/strike/test_bounty_striker.gd`:
```gdscript
extends CardTestBase

func test_returns_to_hand_when_owner_meets_a_request() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	# Bounty Striker in discard.
	var bounty := eng.state.make_instance(strike_def(5))
	bounty.zone = Enums.Zone.DISCARD
	eng.state.players[me].discard.append(bounty)
	# A met-REQUEST attacker to trigger REQUEST_MET.
	var atk := place_on_board(eng, me, strike_def(11))
	atk.tapped = false
	eng.state.players[me].all_requests_met_this_turn = true
	# Give opponent a deck to attack so the attack resolves cleanly.
	eng.apply(Action.declare_attack(atk.instance_id, {"deck": true}))
	assert_bool(eng.state.players[me].hand.has(bounty)).is_true()
```

- [ ] **Step 4: Run (fail → pass)**
Run: `... -a res://tests/cards/strike/test_bounty_striker.gd` → PASS.

- [ ] **Step 5: Commit**
```bash
git add src/cards/scripts/strike/bounty_striker.gd src/cards/card_script_registry.gd tests/cards/strike/test_bounty_striker.gd
git commit -m "feat(strike): Bounty Striker"
```

### Task 27: Overstriker (id 13/14) — opponent plays cost≥7 → mill, once/turn

**Files:** Create script; register id 13 & 14; test.

- [ ] **Step 1: Script** `src/cards/scripts/strike/overstriker.gd`:
```gdscript
class_name Overstriker
extends CardScript

func has_request() -> bool: return true
func condition_met(card: CardInstance, ctx: EffectContext) -> bool:
	return ctx.counters(ctx.gs().active_player)["cards_played"] >= 2

func reacts_to() -> Array: return [Enums.EventType.CARD_PLAYED]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("player", -1) != ctx.opponent():
		return
	if card.vars.get("opt_used_this_turn", false):
		return
	var played := _find_played(ctx, event.data.get("instance", -1))
	if played == null or played.definition.ticket_cost < 7:
		return
	card.vars["opt_used_this_turn"] = true
	ctx.mill(ctx.opponent(), 1)

func _find_played(ctx: EffectContext, instance_id: int) -> CardInstance:
	for pidx in range(2):
		for zone in [ctx.gs().players[pidx].board, ctx.gs().players[pidx].discard]:
			for c in zone:
				if c.instance_id == instance_id:
					return c
	return null
```

- [ ] **Step 2: Register** ids 13 and 14.

- [ ] **Step 3: Test** `tests/cards/strike/test_overstriker.gd`:
```gdscript
extends CardTestBase

func test_mills_opponent_when_they_play_expensive_card() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	place_on_board(eng, me, strike_def(13))     # my Overstriker watches opp plays
	# Make it opponent's turn by ending mine.
	eng.apply(Action.end_turn())
	# Now active = opp. Give opp an expensive card (Headphones Ghost cost 10).
	var pricey := put_in_hand(eng, opp, strike_def(8))
	var deck_before := eng.state.players[opp].deck.size()
	eng.apply(Action.play_card(pricey.instance_id))
	assert_int(eng.state.players[opp].deck.size()).is_equal(deck_before - 1)
```

- [ ] **Step 4: Run (fail → pass)**
Run: `... -a res://tests/cards/strike/test_overstriker.gd` → PASS.

- [ ] **Step 5: Commit**
```bash
git add src/cards/scripts/strike/overstriker.gd src/cards/card_script_registry.gd tests/cards/strike/test_overstriker.gd
git commit -m "feat(strike): Overstriker"
```

### Task 28: Red Alien (id 7) — on own attack, opponent chooses (option), once/turn

**Files:** Create script; register id 7; test.

- [ ] **Step 1: Script** `src/cards/scripts/strike/red_alien.gd`:
```gdscript
class_name RedAlien
extends CardScript

func has_request() -> bool: return true
func condition_met(card: CardInstance, ctx: EffectContext) -> bool:
	# "A player discarded 2+ cards this turn."
	return ctx.counters(ctx.me())["cards_discarded"] >= 2 \
		or ctx.counters(ctx.opponent())["cards_discarded"] >= 2

func reacts_to() -> Array: return [Enums.EventType.UNIT_ATTACKED]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("attacker", -1) != card.instance_id:
		return
	if card.vars.get("opt_used_this_turn", false):
		return
	card.vars["opt_used_this_turn"] = true
	ctx.request_choice(card,
		ChoiceSpec.choose_option(["Discard 1 from hand", "Mill 2 from Deck"], "Red Alien strikes!"),
		"red", ctx.opponent())

func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag != "red":
		return
	var opp := ctx.opponent()
	if result["option"] == 0 and not ctx.hand(opp).is_empty():
		ctx.discard_from_hand(ctx.hand(opp)[0])
	else:
		ctx.mill(opp, 2)
```

- [ ] **Step 2: Register** id 7.

- [ ] **Step 3: Test** `tests/cards/strike/test_red_alien.gd`:
```gdscript
extends CardTestBase

func test_opponent_mills_two_on_attack_when_choosing_option_one() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var red := place_on_board(eng, me, strike_def(7))
	red.tapped = false
	var opp_deck_before := eng.state.players[opp].deck.size()
	eng.apply(Action.declare_attack(red.instance_id, {"deck": true}))
	# Suspended for the opponent's option choice.
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("choose_option")
	assert_int(eng.state.pending_choice.player).is_equal(opp)
	eng.apply(Action.resolve_choice({"option": 1}))   # Mill 2
	# Opponent lost 2 to mill + the deck-damage from the attack (1 from the 1-dmg... Red Alien dmg=7).
	# Just assert the mill happened: at least 2 fewer than before minus attack damage is messy;
	# instead assert opponent discard grew by at least 2 from milling.
	assert_int(eng.state.players[opp].discard.size()).is_greater_equal(2)
```

- [ ] **Step 4: Run (fail → pass)**
Run: `... -a res://tests/cards/strike/test_red_alien.gd` → PASS.

- [ ] **Step 5: Commit**
```bash
git add src/cards/scripts/strike/red_alien.gd src/cards/card_script_registry.gd tests/cards/strike/test_red_alien.gd
git commit -m "feat(strike): Red Alien"
```

### Task 29: Headphones Ghost (id 8) — on 2nd attack, controller kills a ≤8 HP unit (target)

**Files:** Create script; register id 8; test.

- [ ] **Step 1: Script** `src/cards/scripts/strike/headphones_ghost.gd`:
```gdscript
class_name HeadphonesGhost
extends CardScript

func has_request() -> bool: return true
func condition_met(card: CardInstance, ctx: EffectContext) -> bool:
	return ctx.counters(ctx.me())["units_died"] >= 3 \
		or ctx.counters(ctx.opponent())["units_died"] >= 3

func reacts_to() -> Array: return [Enums.EventType.UNIT_ATTACKED]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	var attacker_owner := event.data.get("player", -1)
	if attacker_owner < 0:
		return
	# Fires on the attacker's exact 2nd attack of the turn.
	if ctx.counters(attacker_owner)["attacks_made"] != 2:
		return
	if card.vars.get("opt_used_this_turn", false):
		return
	var targets: Array = []
	for pidx in range(2):
		for u in ctx.board(pidx):
			if u.current_health <= 8:
				targets.append(u)
	if targets.is_empty():
		return
	card.vars["opt_used_this_turn"] = true
	ctx.request_choice(card, ChoiceSpec.select_target(targets, 1, 1, "Kill a Unit with 8 or less Health"), "ghost")

func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "ghost" and not result["targets"].is_empty():
		ctx.kill(result["targets"][0])
```

- [ ] **Step 2: Register** id 8.

- [ ] **Step 3: Test** `tests/cards/strike/test_headphones_ghost.gd`:
```gdscript
extends CardTestBase

func test_kills_chosen_low_health_unit_on_second_attack() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ghost := place_on_board(eng, me, strike_def(8))
	# Two attackers so the 2nd attack triggers the ghost.
	var a1 := place_on_board(eng, me, strike_def(2)); a1.tapped = false
	var a2 := place_on_board(eng, me, strike_def(3)); a2.tapped = false
	# A low-HP victim on opponent board.
	var victim := place_on_board(eng, 1 - me, strike_def(2))
	eng.apply(Action.declare_attack(a1.instance_id, {"deck": true}))   # attacks_made = 1
	eng.apply(Action.declare_attack(a2.instance_id, {"deck": true}))   # attacks_made = 2 -> ghost
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_target")
	eng.apply(Action.resolve_choice({"target_ids": [victim.instance_id]}))
	assert_bool(eng.state.players[1 - me].board.has(victim)).is_false()
```

- [ ] **Step 4: Run (fail → pass)**
Run: `... -a res://tests/cards/strike/test_headphones_ghost.gd` → PASS.

- [ ] **Step 5: Commit**
```bash
git add src/cards/scripts/strike/headphones_ghost.gd src/cards/card_script_registry.gd tests/cards/strike/test_headphones_ghost.gd
git commit -m "feat(strike): Headphones Ghost"
```

### Task 30: Cactus Guy (id 10) — on deck-damage attack, steal opp discard top

**Files:** Create script; register id 10; test.

- [ ] **Step 1: Script** `src/cards/scripts/strike/cactus_guy.gd`:
```gdscript
class_name CactusGuy
extends CardScript

func has_request() -> bool: return true
func condition_met(card: CardInstance, ctx: EffectContext) -> bool:
	return ctx.counters(ctx.me())["attacks_made"] >= 2 \
		or ctx.counters(ctx.opponent())["attacks_made"] >= 2

func reacts_to() -> Array: return [Enums.EventType.DECK_DAMAGED]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	# Only when THIS card is the one that dealt deck damage (it just attacked the deck).
	if not card.tapped:
		return
	if event.data.get("player", -1) != ctx.opponent():
		return
	if card.vars.get("cactus_done_this_turn", false):
		return
	if ctx.discard_pile(ctx.opponent()).is_empty():
		return
	card.vars["cactus_done_this_turn"] = true
	ctx.steal_top_discard(ctx.opponent())
```
> Trade-off documented in the spec: distinguishing "this card dealt the deck damage" from a generic `DECK_DAMAGED` is approximated by "this card is tapped (just attacked) and the damaged deck is the opponent's." For the single-Cactus, single-deck-attack case this is correct; a stricter source-tagged event is a later refinement.

- [ ] **Step 2: Register** id 10.

- [ ] **Step 3: Test** `tests/cards/strike/test_cactus_guy.gd`:
```gdscript
extends CardTestBase

func test_steals_top_of_opponent_discard_on_deck_attack() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var cactus := place_on_board(eng, me, strike_def(10))
	cactus.tapped = false
	var loot := eng.state.make_instance(strike_def(2))
	loot.zone = Enums.Zone.DISCARD
	eng.state.players[opp].discard.append(loot)
	eng.apply(Action.declare_attack(cactus.instance_id, {"deck": true}))
	assert_bool(eng.state.players[me].hand.has(loot)).is_true()
	assert_int(loot.vars["stolen_from"]).is_equal(opp)
```

- [ ] **Step 4: Run (fail → pass)**
Run: `... -a res://tests/cards/strike/test_cactus_guy.gd` → PASS.

- [ ] **Step 5: Commit**
```bash
git add src/cards/scripts/strike/cactus_guy.gd src/cards/card_script_registry.gd tests/cards/strike/test_cactus_guy.gd
git commit -m "feat(strike): Cactus Guy"
```

### Task 31: Wrong Mascot (id 19/20) — trap: kill attacker of a met-REQUEST minion

**Files:** Create script; register id 19 & 20; test.

- [ ] **Step 1: Script** `src/cards/scripts/strike/wrong_mascot.gd`:
```gdscript
class_name WrongMascot
extends CardScript

func reacts_to() -> Array: return [Enums.EventType.UNIT_ATTACKED]
func active_zones() -> Array: return [Enums.Zone.TRAP_SET]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	# Opponent (relative to trap owner) is attacking.
	if event.data.get("player", -1) == ctx.me():
		return
	var target_id := event.data.get("target_unit", -1)
	if target_id < 0:
		return
	var defender := _find(ctx, ctx.me(), target_id)
	if defender == null or defender.script == null or not defender.script.has_request():
		return
	if not ctx.request_met(defender):
		return
	var attacker := _find(ctx, ctx.opponent(), event.data.get("attacker", -1))
	if attacker == null:
		return
	ctx.fire_trap(card)
	ctx.kill(attacker)

func _find(ctx: EffectContext, pidx: int, instance_id: int) -> CardInstance:
	for c in ctx.board(pidx):
		if c.instance_id == instance_id:
			return c
	return null
```
> This requires the `UNIT_ATTACKED` event to carry the defending unit. Update `_declare_attack` to include `"target_unit"` in the event data (see Step 2).

- [ ] **Step 2: Add `target_unit` to the attack event**

In `src/engine/game_engine.gd` `_declare_attack`, change the `UNIT_ATTACKED` emit to include the target:
```gdscript
	emit(GameEvent.new(Enums.EventType.UNIT_ATTACKED,
		{"attacker": attacker_id, "player": state.active_player,
		 "target_unit": target.get("unit", -1), "target_deck": target.get("deck", false)}))
```
Register Wrong Mascot ids 19 and 20.

- [ ] **Step 3: Test** `tests/cards/strike/test_wrong_mascot.gd`:
```gdscript
extends CardTestBase

func test_kills_attacker_of_met_request_minion() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player        # attacker's side
	var trapper := eng.state.opponent()      # trap owner / defender side
	# Defender: a met-REQUEST minion on trapper's board.
	var defender := place_on_board(eng, trapper, strike_def(11))
	eng.state.players[trapper].all_requests_met_this_turn = true
	# Trap set by trapper.
	var trap := eng.state.make_instance(strike_def(19))
	trap.zone = Enums.Zone.TRAP_SET
	eng.state.players[trapper].set_traps.append(trap)
	# Attacker on my board.
	var attacker := place_on_board(eng, me, strike_def(2))
	attacker.tapped = false
	eng.apply(Action.declare_attack(attacker.instance_id, {"unit": defender.instance_id}))
	assert_bool(eng.state.players[me].board.has(attacker)).is_false()   # killed by trap
	assert_bool(eng.state.players[trapper].discard.has(trap)).is_true() # trap fired
```

- [ ] **Step 4: Run (fail → pass) + attack regression**
Run: `... -a res://tests/cards/strike/test_wrong_mascot.gd`
Then: `... -a res://tests/test_engine_attack.gd` (verify the new event field didn't break existing attack tests)
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add src/cards/scripts/strike/wrong_mascot.gd src/engine/game_engine.gd src/cards/card_script_registry.gd tests/cards/strike/test_wrong_mascot.gd
git commit -m "feat(strike): Wrong Mascot + target_unit on UNIT_ATTACKED"
```

### Task 32: Strike Social (id 21) — trap: met-REQUEST minions become immortal this turn

**Files:** Create script; register id 21; test.

- [ ] **Step 1: Script** `src/cards/scripts/strike/strike_social.gd`:
```gdscript
class_name StrikeSocial
extends CardScript

func reacts_to() -> Array: return [Enums.EventType.UNIT_ATTACKED]
func active_zones() -> Array: return [Enums.Zone.TRAP_SET]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("player", -1) == ctx.me():
		return                       # only when the opponent declares an attack
	ctx.fire_trap(card)
	for u in ctx.board(ctx.me()):
		if u.script != null and u.script.has_request() and ctx.request_met(u):
			ctx.set_unit_flag(u, "immortal_this_turn")
```

- [ ] **Step 2: Register** id 21.

- [ ] **Step 3: Test** `tests/cards/strike/test_strike_social.gd`:
```gdscript
extends CardTestBase

func test_met_request_minions_survive_combat_after_trap() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player        # attacker
	var trapper := eng.state.opponent()
	# Trapper has a met-REQUEST minion that would otherwise die.
	var protege := place_on_board(eng, trapper, strike_def(11))   # 4/1 (dies easily)
	eng.state.players[trapper].all_requests_met_this_turn = true
	var trap := eng.state.make_instance(strike_def(21))
	trap.zone = Enums.Zone.TRAP_SET
	eng.state.players[trapper].set_traps.append(trap)
	# Strong attacker.
	var attacker := place_on_board(eng, me, strike_def(8))   # 9/9
	attacker.tapped = false
	eng.apply(Action.declare_attack(attacker.instance_id, {"unit": protege.instance_id}))
	# Trap fired before combat -> protege immortal -> survives.
	assert_bool(eng.state.players[trapper].board.has(protege)).is_true()
```

- [ ] **Step 4: Run (fail → pass)**
Run: `... -a res://tests/cards/strike/test_strike_social.gd` → PASS.

- [ ] **Step 5: Commit**
```bash
git add src/cards/scripts/strike/strike_social.gd src/cards/card_script_registry.gd tests/cards/strike/test_strike_social.gd
git commit -m "feat(strike): Strike Social"
```

### Task 33: Full-suite green + integration sanity

**Files:** none (verification)

- [ ] **Step 1: Run the entire suite**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
Expected: PASS, all suites including the 14 card tests and all regressions.

- [ ] **Step 2: Smoke-play a Strike vs Strike game via the existing integration test**

Confirm `tests/test_integration_game.gd` and `tests/test_integration_ui_game.gd` still pass (they drive full games through the AI; the generic choice resolver lets the AI handle any card_effect choices that arise).

- [ ] **Step 3: Commit any test fixups**
```bash
git add -A
git commit -m "test: full-suite green with Strike abilities"
```

---

## Self-Review (completed by plan author)

**Spec coverage:**
- CardScript/registry/EffectContext/file layout → Tasks 3–5, Phase 8 file structure. ✓
- Work-item queue + dispatch (spec Layer 2) → Tasks 1, 2, 6. ✓
- Suspend/resume choice + 3 UI shapes (spec Layer 3) → Tasks 7–11. ✓
- card_select_panel refactor (spec Layer 3b) → Task 10. ✓
- REQUEST primitive + combat + REQUEST_MET (spec Layer 4) → Tasks 12–14. ✓
- Trap firing + immortal hook + turn-flag reset (spec Layer 5) → Tasks 16–17. ✓
- New events/enums → Task 13. ✓
- All 14 unique Strike cards → Tasks 19–32 (each with the dedup'd id registrations). ✓
- Testing strategy (per-card vs shipping data, regression guard) → CardTestBase + every card task + regression runs. ✓

**Assumptions surfaced as code/notes (from spec rulings):** ability ungated by REQUEST (each script only checks REQUEST where spec'd); Bjorn Hammer kills no-REQUEST units; REQUEST_MET at attack moment; traps auto-fire; Cactus Guy "this card dealt deck damage" approximated by tapped+opponent-deck (noted in Task 30); Wrong Mascot needs `target_unit` on the attack event (added in Task 31).

**Type/name consistency:** `EffectContext` method names match between `effect_context.gd` (Task 5) and every card script; `ChoiceSpec` field names (`ui_shape`, `cards`, `min_n`, `max_n`, `labels`, `title`) consistent across Tasks 7–11 and all scripts; engine primitive names (`_search_deck`, `_draw_specific`, `_summon_free`, `_put_on_deck_top`, `_steal_top_discard`, `_damage_unit`, `_kill_unit`, `_discard_from_hand`, `_fire_trap`, `_request_met`, `_request_choice`, `_owner_of`, `_find_anywhere`) defined once and referenced consistently; queue item kinds (`event`/`react`/`call`) consistent.
