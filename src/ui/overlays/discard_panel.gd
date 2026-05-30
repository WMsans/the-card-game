extends CanvasLayer

signal confirmed(indices: Array)

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")

var _selected: Array = []
var _required: int = 0

@onready var _row: HBoxContainer = $Panel/CardRow
@onready var _confirm: Button = $Panel/ConfirmButton

func _ready() -> void:
	_confirm.pressed.connect(_confirm_pressed)

func show_hand(hand: Array, count: int) -> void:
	if not is_node_ready(): await ready
	_required = count
	_selected.clear()
	for c in _row.get_children(): c.queue_free()
	for i in range(hand.size()):
		var cv: CardView = CARD_VIEW.instantiate()
		cv.set_interactive(false)
		_row.add_child(cv)
		cv.setup(hand[i])
		var idx := i
		cv.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed: toggle_index(idx))
	visible = true
	_update()

func toggle_index(i: int) -> void:
	if _selected.has(i): _selected.erase(i)
	elif _selected.size() < _required: _selected.append(i)
	_update()

func can_confirm() -> bool: return _selected.size() == _required

func _confirm_pressed() -> void:
	if can_confirm():
		visible = false
		confirmed.emit(_selected.duplicate())

func _update() -> void: _confirm.disabled = not can_confirm()