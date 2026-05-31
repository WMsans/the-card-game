class_name MulliganPanel
extends CanvasLayer

signal confirmed(indices: Array)
signal minimize_requested

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")
const REQUIRED := 2

var _selected: Array = []
var _discardable: Array = []

@onready var _row: HBoxContainer = $Panel/CardRow
@onready var _confirm: Button = $Panel/ConfirmButton

func _ready() -> void:
	_confirm.pressed.connect(confirm)
	$Panel.theme = preload("res://src/ui/theme/game_theme.tres")
	JuicyButton.apply(_confirm)
	var _min_btn: Button = $Panel/MinimizeButton
	JuicyButton.apply(_min_btn)
	_min_btn.pressed.connect(func(): minimize_requested.emit())

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
	for i in _row.get_child_count():
		var cv: CardView = _row.get_child(i)
		if not _discardable.has(i):
			continue
		cv.set_highlight(CardHighlight.State.SELECTED if _selected.has(i) else CardHighlight.State.NONE)

func get_animatable_nodes() -> Array[Node]:
	return [$Panel/Label, _row, _confirm, $Panel/MinimizeButton]

func get_dim_node() -> Control:
	return $Panel