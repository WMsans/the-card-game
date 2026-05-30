extends Control

signal clicked

@onready var _back: TextureRect = $Back
@onready var _count: Label = $Count

func _ready() -> void:
	_back.texture = load(CardArt.BACK)
	_back.mouse_filter = Control.MOUSE_FILTER_PASS

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
		accept_event()

func set_count(n: int) -> void:
	if not is_node_ready():
		await ready
	_count.text = str(n)
	_back.visible = n > 0
