class_name MulliganPanel
extends CanvasLayer

signal confirmed(indices: Array)

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")
const REQUIRED := 2

var _selected: Array = []
var _discardable: Array = []

@onready var _row: HBoxContainer = $Panel/CardRow
@onready var _confirm: Button = $Panel/ConfirmButton

func _ready() -> void:
	_confirm.pressed.connect(confirm)

func show_hand(hand: Array) -> void:
	if not is_node_ready():
		await ready
	_selected.clear()
	_discardable.clear()
	for c in _row.get_children():
		c.queue_free()
	for i in range(hand.size()):
		var inst: CardInstance = hand[i]
		var cv: CardView = CARD_VIEW.instantiate()
		cv.set_interactive(false)
		_row.add_child(cv)
		cv.setup(inst)
		if inst.definition.type != Enums.CardType.LEADER:
			_discardable.append(i)
			var idx := i
			cv.gui_input.connect(func(e):
				if e is InputEventMouseButton and e.pressed:
					toggle_index(idx))
	visible = true
	_update()

func toggle_index(i: int) -> void:
	if _selected.has(i):
		_selected.erase(i)
	else:
		_selected.append(i)
	_update()

func can_confirm() -> bool:
	return _selected.size() == REQUIRED

func confirm() -> void:
	if can_confirm():
		visible = false
		confirmed.emit(_selected.duplicate())

func _update() -> void:
	_confirm.disabled = not can_confirm()