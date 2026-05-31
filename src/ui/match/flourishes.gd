class_name Flourishes
extends RefCounted

static func play(match_node, events: Array, attack: bool = false) -> void:
	for e in events:
		match e.type:
			Enums.EventType.UNIT_DAMAGED:
				if not attack:
					_damage_number(match_node, e.data.get("target", -1), e.data.get("amount", 0))
			Enums.EventType.DECK_DAMAGED:
				_mill_burst(match_node, e.data.get("player", -1))

static func _find_card_view(match_node, iid: int) -> CardView:
	for row in [match_node.player_board, match_node.opp_board]:
		if row.card_views.has(iid):
			return row.card_views[iid]
	return null

static func _damage_number(match_node, iid: int, amount: int) -> void:
	if amount <= 0:
		return
	var cv := _find_card_view(match_node, iid)
	var at := Vector2(960, 540)
	if cv != null:
		at = cv.global_position + cv.size * cv.scale * 0.5
	DamageNumber.spawn(match_node.get_node("FxLayer"), at, amount, amount >= 4)

static func _mill_burst(match_node, player: int) -> void:
	var pile = match_node._opp_discard if player == (1 - match_node.HUMAN) else match_node._player_discard
	var lbl := Label.new()
	lbl.text = "MILL"
	lbl.position = pile.position
	match_node.get_node("FxLayer").add_child(lbl)
	var t := lbl.create_tween()
	t.tween_property(lbl, "modulate:a", 0.0, 0.7)
	t.tween_callback(lbl.queue_free)
