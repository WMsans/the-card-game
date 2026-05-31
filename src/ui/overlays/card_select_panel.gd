extends CanvasLayer

signal confirmed(indices: Array)

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")

var _selected: Array = []
var _min: int = 0
var _max: int = 0

@onready var _row: HBoxContainer = $Center/Panel/Margin/VBox/CardRow
@onready var _confirm: Button = $Center/Panel/Margin/VBox/Buttons/ConfirmButton
@onready var _label: Label = $Center/Panel/Margin/VBox/Label

func _ready() -> void:
	_confirm.pressed.connect(_confirm_pressed)
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
		cv.select_only = true
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
