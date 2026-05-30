extends CanvasLayer

@onready var _label: Label = $Panel/Label

func show_turn(is_player: bool) -> void:
	if not is_node_ready():
		await ready
	_label.text = "Your Turn" if is_player else "Opponent's Turn"
	visible = true
	var t := create_tween()
	t.tween_interval(0.8)
	t.tween_callback(_hide)

func _hide() -> void:
	visible = false