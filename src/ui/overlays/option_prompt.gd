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
