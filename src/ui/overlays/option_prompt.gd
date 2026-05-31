extends CanvasLayer

signal picked(option: int)

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

func _emit(i: int) -> void:
	visible = false
	picked.emit(i)
