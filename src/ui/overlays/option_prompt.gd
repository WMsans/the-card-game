extends CanvasLayer

signal picked(option: int)
signal minimize_requested

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")

@onready var _box: HBoxContainer = $Center/Panel/Margin/VBox/Options
@onready var _label: Label = $Center/Panel/Margin/VBox/Body/Info/Label
@onready var _slot: Control = $Center/Panel/Margin/VBox/Body/CardSlot

func show_options(labels: Array, title: String, card: CardInstance = null) -> void:
	if not is_node_ready(): await ready
	_label.text = title
	for c in _slot.get_children(): c.queue_free()
	_slot.visible = card != null
	if card != null:
		var cv: CardView = CARD_VIEW.instantiate()
		cv.set_interactive(false)
		_slot.add_child(cv)
		cv.setup(card)
	for c in _box.get_children(): c.queue_free()
	for i in range(labels.size()):
		var b := Button.new()
		b.text = labels[i]
		var idx := i
		b.pressed.connect(func(): _emit(idx))
		_box.add_child(b)
		JuicyButton.apply(b)
	visible = true
	CardJuice.popup_in($Center/Panel)

func _ready() -> void:
	var _min_btn: Button = $Center/Panel/Margin/VBox/MinimizeButton
	JuicyButton.apply(_min_btn)
	_min_btn.pressed.connect(func(): minimize_requested.emit())

func _emit(i: int) -> void:
	visible = false
	picked.emit(i)

func get_animatable_nodes() -> Array[Node]:
	var nodes: Array[Node] = [_label, _box, $Center/Panel/Margin/VBox/MinimizeButton]
	if _slot.visible and _slot.get_child_count() > 0:
		nodes.push_front(_slot)
	return nodes

func get_dim_node() -> ColorRect:
	return $Dim
