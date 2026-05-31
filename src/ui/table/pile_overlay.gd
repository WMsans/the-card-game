class_name PileOverlay
extends Control

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")
const CARD_SIZE := Vector2(350, 490)
const MAX_FLY_WINDOW := 1.0

@onready var _backdrop: ColorRect = $Backdrop
@onready var _title: Label = $Title
@onready var _close: Button = $CloseButton
@onready var _grid: GridContainer = $Scroll/Grid

var _open: bool = false
var _cards: Array[CardView] = []

func _ready() -> void:
	visible = false
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_input)
	_close.pressed.connect(close)

func is_open() -> bool:
	return _open

func open(cards: Array[CardInstance], from_pos: Vector2, title: String) -> void:
	if _open or cards.is_empty():
		return
	_open = true
	visible = true
	modulate.a = 1.0
	_title.text = title
	for inst in PileSort.sorted(cards):
		var cv: CardView = CARD_VIEW.instantiate()
		cv.custom_minimum_size = CARD_SIZE
		cv.select_only = true
		cv.modulate.a = 0.0
		_grid.add_child(cv)
		cv.setup(inst)
		cv.set_face_down(true)
		_cards.append(cv)
	await get_tree().process_frame
	_animate_in(from_pos)

func close() -> void:
	if not _open:
		return
	_open = false
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.15)
	await t.finished
	for cv in _cards:
		cv.queue_free()
	_cards.clear()
	visible = false
	modulate.a = 1.0

func _animate_in(from_pos: Vector2) -> void:
	var n := _cards.size()
	var stagger := minf(CardFlight.STAGGER, MAX_FLY_WINDOW / float(maxi(n, 1)))
	var from_local := (from_pos - _grid.global_position) - CARD_SIZE * 0.5
	for i in n:
		var cv := _cards[i]
		cv.set_rest(cv.position, 0.0)
		cv.modulate.a = 1.0
		var delay := float(i) * stagger
		CardFlight.fly_in(cv, from_local, delay)
		_schedule_flip(cv, delay + CardFlight.FLY_TIME * 0.6)

func _schedule_flip(cv: CardView, at: float) -> void:
	var t := cv.create_tween()
	t.tween_interval(at)
	t.tween_callback(cv.flip_to_face_up)

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()

func _unhandled_input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
