class_name Flourishes
extends RefCounted

static func play(match_node, events: Array) -> void:
	for e in events:
		match e.type:
			Enums.EventType.UNIT_DAMAGED:
				_damage_number(match_node, e.data.get("target", -1), e.data.get("amount", 0))
				_shake(match_node, e.data.get("target", -1))
			Enums.EventType.DECK_DAMAGED:
				_mill_burst(match_node, e.data.get("player", -1))

static func _find_card_view(match_node, iid: int) -> CardView:
	for row in [match_node.player_board, match_node.opp_board]:
		if row.card_views.has(iid):
			return row.card_views[iid]
	return null

static func _damage_number(match_node, iid: int, amount: int) -> void:
	if amount <= 0: return
	var lbl := Label.new()
	lbl.text = "-%d" % amount
	lbl.modulate = Color(1, 0.3, 0.3)
	var cv := _find_card_view(match_node, iid)
	lbl.position = cv.position if cv else Vector2(960, 540)
	match_node.get_node("FxLayer").add_child(lbl)
	var t := lbl.create_tween()
	t.tween_property(lbl, "position:y", lbl.position.y - 60.0, 0.6)
	t.parallel().tween_property(lbl, "modulate:a", 0.0, 0.6)
	t.tween_callback(lbl.queue_free)

static func _shake(match_node, iid: int) -> void:
	var cv := _find_card_view(match_node, iid)
	if cv == null: return
	var base := cv.position
	var t := cv.create_tween()
	for i in range(3):
		t.tween_property(cv, "position", base + Vector2(randf_range(-6, 6), 0), 0.04)
	t.tween_property(cv, "position", base, 0.04)

static func _mill_burst(match_node, player: int) -> void:
	var pile = match_node._opp_discard if player == (1 - match_node.HUMAN) else match_node._player_discard
	var lbl := Label.new()
	lbl.text = "MILL"
	lbl.position = pile.position
	match_node.get_node("FxLayer").add_child(lbl)
	var t := lbl.create_tween()
	t.tween_property(lbl, "modulate:a", 0.0, 0.7)
	t.tween_callback(lbl.queue_free)