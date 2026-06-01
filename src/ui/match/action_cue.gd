class_name ActionCue
extends RefCounted

const COL_PLAYED := Color(0.45, 1.0, 0.55)
const COL_REQUEST := Color(1.0, 0.85, 0.25)
const COL_HARMONIZE := Color(0.55, 0.8, 1.0)
const COL_RUMMAGE := Color(1.0, 0.7, 0.35)
const COL_TRASH := Color(0.8, 0.8, 0.85)

var anim_speed: float = 1.0
var _last_end: float = -999.0

static func descriptors(events: Array) -> Array:
	var out: Array = []
	for e in events:
		match e.type:
			Enums.EventType.CARD_PLAYED:
				if e.data.get("card_type", -1) == Enums.CardType.MINION:
					out.append(_card("PLAYED", COL_PLAYED, e.data.get("instance", -1), e.data.get("player", -1)))
			Enums.EventType.REQUEST_MET:
				out.append(_card("REQUEST MET", COL_REQUEST, e.data.get("instance", -1), e.data.get("player", -1)))
			Enums.EventType.UNIT_TRASHED:
				out.append(_card("TRASHED", COL_TRASH, e.data.get("instance", -1), e.data.get("owner", -1)))
			Enums.EventType.HARMONIZE:
				out.append({"label": "HARMONIZE", "color": COL_HARMONIZE, "target_id": -1, "anchor": "board", "player": e.data.get("player", -1)})
			Enums.EventType.RUMMAGE_PERFORMED:
				var n: int = e.data.get("count", 0)
				out.append({"label": "RUMMAGE x%d" % n, "color": COL_RUMMAGE, "target_id": -1, "anchor": "discard", "player": e.data.get("player", -1)})
	return out

static func _card(label: String, color: Color, iid: int, player: int) -> Dictionary:
	return {"label": label, "color": color, "target_id": iid, "anchor": "card", "player": player}

func reset_ramp() -> void:
	anim_speed = 1.0

func play(m, events: Array) -> void:
	var ds := descriptors(events)
	if ds.is_empty():
		return
	for d in ds:
		anim_speed = FeedbackFx.next_speed(anim_speed, _now() - _last_end)
		var spd := anim_speed
		var at := _resolve_pos(m, d)
		var cv: CardView = _resolve_card(m, d["target_id"])
		if cv != null:
			cv.z_index = 150
			CardJuice.squash(cv, spd)
			CardJuice.spring_wiggle(cv, 8.0, spd)
			_tint(cv, d["color"], spd)
		_spawn_label(m, at, d["label"], d["color"])
		await m.get_tree().create_timer(FeedbackFx.HOLD_TIME / maxf(spd, 0.01)).timeout
		if cv != null:
			cv.z_index = 0
		_last_end = _now()

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _resolve_card(m, iid: int) -> CardView:
	if iid < 0:
		return null
	if m.player_board.card_views.has(iid):
		return m.player_board.card_views[iid]
	if m.opp_board.card_views.has(iid):
		return m.opp_board.card_views[iid]
	return null

func _resolve_pos(m, d: Dictionary) -> Vector2:
	match d["anchor"]:
		"card":
			var cv: CardView = _resolve_card(m, d["target_id"])
			if cv != null:
				return cv.global_position + cv.size * cv.scale * 0.5
			return Vector2(BoardLayout.CENTER_X, BoardLayout.SCREEN.y * 0.5)
		"discard":
			return FlightAnchors.of(Enums.Zone.DISCARD, d["player"], m)
		_: # "board"
			var y := BoardLayout.PLAYER_BOARD_Y if d["player"] == m.HUMAN else BoardLayout.OPP_BOARD_Y
			return Vector2(BoardLayout.CENTER_X, y)

func _tint(cv: CardView, color: Color, spd: float) -> void:
	var tw := cv.create_tween()
	tw.tween_property(cv, "modulate", color, 0.12 / maxf(spd, 0.01))
	tw.tween_property(cv, "modulate", Color.WHITE, (FeedbackFx.HOLD_TIME * 0.8) / maxf(spd, 0.01))

func _spawn_label(m, at: Vector2, text: String, color: Color) -> void:
	var fx: Node = m.get_node("FxLayer")
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = color
	lbl.z_index = 200
	fx.add_child(lbl)
	lbl.global_position = at - Vector2(0, 40)
	lbl.scale = Vector2(1.6, 1.6)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "global_position", lbl.global_position - Vector2(0, 30), FeedbackFx.HOLD_TIME)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.3)
	tw.tween_callback(lbl.queue_free)
