extends Node2D

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")

var card_views: Dictionary = {}

func render(units: Array, player: int) -> void:
	var n := units.size()
	var seen := {}
	for i in range(n):
		var inst: CardInstance = units[i]
		seen[inst.instance_id] = true
		var cv: CardView = card_views.get(inst.instance_id)
		if cv == null:
			cv = CARD_VIEW.instantiate()
			add_child(cv)
			card_views[inst.instance_id] = cv
		cv.setup(inst)
		cv.set_base_scale(BoardLayout.CARD_SCALE)
		cv.set_interactive(player == 0)
		var t := BoardLayout.slot(Enums.Zone.BOARD, i, n, player, inst.tapped)
		var tw := cv.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(cv, "position", t.origin - BoardLayout.CARD_PIVOT, 0.25)
		tw.parallel().tween_property(cv, "rotation", t.get_rotation(), 0.25)
	for iid in card_views.keys():
		if not seen.has(iid):
			var leaver: CardView = card_views[iid]
			card_views.erase(iid)
			leaver.dissolve()
			leaver.queue_free()
