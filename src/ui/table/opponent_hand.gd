extends Node2D

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")

var _placeholder: CardDefinition

func _ready() -> void:
	_placeholder = CardDefinition.new()
	_placeholder.name = "?"

func set_count(n: int) -> void:
	for c in get_children():
		c.queue_free()
	for i in range(n):
		var cv: CardView = CARD_VIEW.instantiate()
		cv.set_interactive(false)
		add_child(cv)
		cv.setup(CardInstance.new(-1 - i, _placeholder))
		cv.set_face_down(true)
		var t := BoardLayout.slot(Enums.Zone.HAND, i, n, 1)
		cv.position = t.origin
		cv.rotation = t.get_rotation()
