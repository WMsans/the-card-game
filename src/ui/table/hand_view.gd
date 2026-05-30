extends Node2D

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")

signal card_drag_released(instance_id: int, at: Vector2)

var card_views: Dictionary = {}

func render(cards: Array, player: int) -> void:
	var n := cards.size()
	var seen := {}
	for i in range(n):
		var inst: CardInstance = cards[i]
		seen[inst.instance_id] = true
		var cv: CardView = card_views.get(inst.instance_id)
		if cv == null:
			cv = CARD_VIEW.instantiate()
			add_child(cv)
			card_views[inst.instance_id] = cv
			var iid := inst.instance_id
			cv.drag_released.connect(func(_cv: CardView, at: Vector2): card_drag_released.emit(iid, at))
		cv.setup(inst)
		cv.set_base_scale(BoardLayout.CARD_SCALE)
		var t := BoardLayout.slot(Enums.Zone.HAND, i, n, player)
		var tw := cv.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(cv, "position", t.origin - BoardLayout.CARD_PIVOT, 0.25)
		tw.parallel().tween_property(cv, "rotation", t.get_rotation(), 0.25)
	for iid in card_views.keys():
		if not seen.has(iid):
			card_views[iid].queue_free()
			card_views.erase(iid)
