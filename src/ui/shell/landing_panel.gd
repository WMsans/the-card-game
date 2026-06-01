# src/ui/shell/landing_panel.gd
class_name LandingPanel
extends Control

signal play_pressed
signal compendium_pressed
signal settings_pressed
signal quit_pressed
signal credits_pressed

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")
const DRIFT_CARD_COUNT := 7
const DRIFT_X_MIN := 880.0
const DRIFT_X_MAX := 1680.0
const DRIFT_Y_TOP := -550.0
const DRIFT_Y_BOTTOM := 1150.0
const SPEED_MIN := 22.0
const SPEED_MAX := 42.0
const SCALE_MIN := 0.8
const SCALE_MAX := 1.2
const SETTLE_MSEC := 400

@onready var _drift: Node2D = $DriftingCards

var _card_pool: Array[CardView] = []
var _def_queue: Array[CardDefinition] = []
var _queue_index: int = 0
var _drift_data: Array[Dictionary] = []
var _dragging: Array[bool] = []
var _settling_until: Dictionary = {}
var _drag_start_pos: Dictionary = {}

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
	_load_deck_definitions()
	_spawn_drifting_cards()

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	for i in range(_card_pool.size()):
		if _dragging[i]:
			continue
		if now < _settling_until.get(i, 0):
			continue
		var cv := _card_pool[i]
		var d := _drift_data[i]
		cv.position.y += d.speed * delta
		cv.position.x = d.base_x + sin(d.phase + now * 0.0006 * d.sway_speed) * d.sway_amplitude
		if cv.position.y > DRIFT_Y_BOTTOM:
			_recycle_card(i)

func _load_deck_definitions() -> void:
	var all: Array[CardDefinition] = []
	for pair in [
		["res://src/data/decks/strike.csv", "strike"],
		["res://src/data/decks/raccoon.csv", "raccoon"],
		["res://src/data/decks/writing.csv", "writing"],
		["res://src/data/decks/audio.csv", "audio"],
	]:
		all.append_array(CardDatabase.load_deck(pair[0], pair[1]))
	_def_queue = all.duplicate()
	_def_queue.shuffle()

func _next_definition() -> CardDefinition:
	if _queue_index >= _def_queue.size():
		_def_queue.shuffle()
		_queue_index = 0
	var def := _def_queue[_queue_index]
	_queue_index += 1
	return def

func _spawn_drifting_cards() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()

	for i in range(DRIFT_CARD_COUNT):
		var cv: CardView = CARD_VIEW.instantiate()
		cv.lift_on_hover = false
		cv.drag_started.connect(_on_drag_started.bind(i))
		cv.drag_released.connect(_on_drag_released.bind(i))
		_drift.add_child(cv)

		var def := _next_definition()
		cv.setup(CardInstance.new(0, def))

		var s := rng.randf_range(SCALE_MIN, SCALE_MAX)
		cv.scale = Vector2(s, s)
		cv.base_scale = s

		var x := rng.randf_range(DRIFT_X_MIN, DRIFT_X_MAX)
		var span := DRIFT_Y_BOTTOM - DRIFT_Y_TOP
		var y := DRIFT_Y_TOP + span * float(i) / float(DRIFT_CARD_COUNT - 1)
		cv.position = Vector2(x, y)
		cv.rotation = rng.randf_range(-0.1, 0.1)

		var z := DRIFT_CARD_COUNT - i
		cv.z_index = z

		_card_pool.append(cv)
		_drift_data.append({
			base_x = x,
			speed = rng.randf_range(SPEED_MIN, SPEED_MAX),
			sway_amplitude = rng.randf_range(8.0, 22.0),
			sway_speed = rng.randf_range(0.6, 1.4),
			phase = rng.randf_range(0.0, TAU),
		})
		_dragging.append(false)

func _recycle_card(index: int) -> void:
	if _dragging[index]:
		return
	var cv := _card_pool[index]
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()

	var new_def := _next_definition()
	cv.setup(CardInstance.new(0, new_def))

	var x := rng.randf_range(DRIFT_X_MIN, DRIFT_X_MAX)
	cv.position = Vector2(x, DRIFT_Y_TOP)
	cv.rotation = rng.randf_range(-0.1, 0.1)
	cv.z_index = 0

	_drift_data[index] = {
		base_x = x,
		speed = rng.randf_range(SPEED_MIN, SPEED_MAX),
		sway_amplitude = rng.randf_range(8.0, 22.0),
		sway_speed = rng.randf_range(0.6, 1.4),
		phase = rng.randf_range(0.0, TAU),
	}

func _on_drag_started(cv: CardView, index: int) -> void:
	_dragging[index] = true
	_drag_start_pos[index] = cv.position
	cv.set_rest(cv.position, cv.rotation)

func _on_drag_released(_cv: CardView, _at: Vector2, index: int) -> void:
	_dragging[index] = false
	_settling_until[index] = Time.get_ticks_msec() + SETTLE_MSEC
	var rest := _drag_start_pos.get(index, _cv.position) as Vector2
	_drift_data[index].base_x = rest.x
	_drift_data[index].phase = 0.0

func on_foreground_offset(offset: Vector2) -> void:
	position = offset
