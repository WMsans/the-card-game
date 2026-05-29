extends Node2D

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")

var card_views: Dictionary = {}

func render(cards: Array, player: int) -> void:
	for c in get_children():
		c.queue_free()
	card_views.clear()
	var n := cards.size()
	for i in range(n):
		var inst: CardInstance = cards[i]
		var cv: CardView = CARD_VIEW.instantiate()
		add_child(cv)
		cv.setup(inst)
		var t := BoardLayout.slot(Enums.Zone.HAND, i, n, player)
		cv.position = t.origin
		cv.rotation = t.get_rotation()
		card_views[inst.instance_id] = cv
