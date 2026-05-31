extends Control

signal clicked

@onready var _back: TextureRect = $Back
@onready var _count: Label = $Count

var _n: int = 0
var _hover_tween: Tween

func _ready() -> void:
	_back.texture = load(CardArt.BACK)
	_back.mouse_filter = Control.MOUSE_FILTER_PASS
	pivot_offset = size * 0.5
	mouse_entered.connect(_on_pile_mouse_entered)
	mouse_exited.connect(_on_pile_mouse_exited)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
		accept_event()

func set_count(n: int) -> void:
	if not is_node_ready():
		await ready
	_n = n
	_count.text = str(n)
	_back.visible = n > 0

func _on_pile_mouse_entered() -> void:
	if _n <= 0:
		return
	if _hover_tween and _hover_tween.is_running():
		_hover_tween.kill()
	_hover_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	_hover_tween.tween_property(self, "scale", Vector2(1.08, 1.08), 0.4)
	_hover_tween.parallel().tween_property(self, "rotation", deg_to_rad(5.0), 0.4)

func _on_pile_mouse_exited() -> void:
	if _hover_tween and _hover_tween.is_running():
		_hover_tween.kill()
	_hover_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	_hover_tween.tween_property(self, "scale", Vector2.ONE, 0.45)
	_hover_tween.parallel().tween_property(self, "rotation", 0.0, 0.45)
