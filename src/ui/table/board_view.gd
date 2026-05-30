extends Node2D

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")

var card_views: Dictionary = {}

func render(units: Array, player: int) -> void:
	for c in get_children():
		c.queue_free()
	card_views.clear()
	var n := units.size()
	for i in range(n):
		var inst: CardInstance = units[i]
		var cv: CardView = CARD_VIEW.instantiate()
		cv.set_interactive(player == 0)
		add_child(cv)
		cv.setup(inst)
		cv.set_base_scale(BoardLayout.CARD_SCALE)
		var t := BoardLayout.slot(Enums.Zone.BOARD, i, n, player, inst.tapped)
		cv.position = t.origin - BoardLayout.CARD_PIVOT
		cv.rotation = t.get_rotation()
		card_views[inst.instance_id] = cv
