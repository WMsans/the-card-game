class_name CombatDirector
extends RefCounted

const CHAIN_GAP := 0.6
const RAMP_STEP := 0.35
const MAX_SPEED := 2.5

var anim_speed: float = 1.0

static func has_attack(events: Array) -> bool:
	for e in events:
		if e.type == Enums.EventType.UNIT_ATTACKED:
			return true
	return false

static func parse_cluster(events: Array) -> Dictionary:
	var c := {
		"attacker": -1, "target_unit": -1, "player": -1,
		"deck_amount": 0, "damaged": [], "died": [],
	}
	for e in events:
		match e.type:
			Enums.EventType.UNIT_ATTACKED:
				c["attacker"] = e.data.get("attacker", -1)
				c["target_unit"] = e.data.get("target_unit", -1)
				c["player"] = e.data.get("player", -1)
			Enums.EventType.UNIT_DAMAGED:
				c["damaged"].append({"id": e.data.get("target", -1), "amount": e.data.get("amount", 0)})
			Enums.EventType.UNIT_DIED:
				c["died"].append(e.data.get("instance", -1))
			Enums.EventType.DECK_DAMAGED:
				c["deck_amount"] = e.data.get("amount", 0)
	return c

static func next_speed(current: float, gap: float) -> float:
	if gap <= CHAIN_GAP:
		return minf(current + RAMP_STEP, MAX_SPEED)
	return 1.0

func reset_ramp() -> void:
	anim_speed = 1.0
