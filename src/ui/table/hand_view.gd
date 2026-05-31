extends Node2D

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")

signal card_drag_released(instance_id: int, at: Vector2)
signal card_drag_started(instance_id: int)
signal card_departed(card_view: CardView, to_pos: Vector2)

var card_views: Dictionary = {}

func render(cards: Array, player: int, plan: Array = []) -> void:
	var n := cards.size()
	var seen := {}
	var fly_i := 0
	for i in range(n):
		var inst: CardInstance = cards[i]
		seen[inst.instance_id] = true
		var cv: CardView = card_views.get(inst.instance_id)
		var is_new := cv == null
		if is_new:
			cv = CARD_VIEW.instantiate()
			add_child(cv)
			card_views[inst.instance_id] = cv
			var iid := inst.instance_id
			cv.drag_released.connect(func(_cv: CardView, at: Vector2): card_drag_released.emit(iid, at))
			cv.drag_started.connect(func(_cv: CardView): card_drag_started.emit(iid))
		cv.setup(inst)
		cv.lift_on_hover = true
		cv.set_base_scale(BoardLayout.CARD_SCALE)
		var t := BoardLayout.slot(Enums.Zone.HAND, i, n, player)
		var rest_pos := t.origin - BoardLayout.CARD_PIVOT
		cv.set_rest(rest_pos, t.get_rotation())
		var entry := _fly_in_entry(inst.instance_id, plan)
		if is_new and not entry.is_empty():
			cv.rotation = t.get_rotation()
			var delay := float(fly_i) * CardFlight.STAGGER
			if entry["from"] == Enums.Zone.DECK:
				cv.set_face_down(true)
				_schedule_flip(cv, delay)
			CardFlight.fly_in(cv, entry["from_pos"], delay)
			fly_i += 1
		else:
			var tw := cv.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(cv, "position", rest_pos, 0.25)
			tw.parallel().tween_property(cv, "rotation", t.get_rotation(), 0.25)
	for iid in card_views.keys():
		if not seen.has(iid):
			var leaver: CardView = card_views[iid]
			var dest = _pile_dest(iid, plan)
			card_views.erase(iid)
			if dest != null:
				card_departed.emit(leaver, dest)
			else:
				leaver.queue_free()

func _fly_in_entry(iid: int, plan: Array) -> Dictionary:
	for e in plan:
		if e["instance_id"] == iid and e["to"] == Enums.Zone.HAND \
				and (e["from"] == Enums.Zone.DECK or e["from"] == Enums.Zone.DISCARD):
			return e
	return {}

func _pile_dest(iid: int, plan: Array):
	for e in plan:
		if e["instance_id"] == iid and (e["to"] == Enums.Zone.DISCARD or e["to"] == Enums.Zone.DECK):
			return e.get("to_pos", null)
	return null

func _schedule_flip(cv: CardView, delay: float) -> void:
	var timer := get_tree().create_timer(delay + CardFlight.FLY_TIME * 0.6)
	timer.timeout.connect(cv.flip_to_face_up, CONNECT_ONE_SHOT)
