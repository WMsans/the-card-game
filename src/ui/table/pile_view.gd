extends Control

@onready var _back: TextureRect = $Back
@onready var _count: Label = $Count

func _ready() -> void:
	_back.texture = load(CardArt.BACK)

func set_count(n: int) -> void:
	if not is_node_ready():
		await ready
	_count.text = str(n)
	_back.visible = n > 0
