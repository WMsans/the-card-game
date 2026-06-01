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
