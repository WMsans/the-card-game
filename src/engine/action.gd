class_name Action
extends RefCounted

var type: int
var params: Dictionary

func _init(t: int, p: Dictionary = {}) -> void:
	type = t
	params = p

static func mulligan(indices: Array) -> Action:
	return Action.new(Enums.ActionType.MULLIGAN, {"indices": indices})

static func play_card(instance_id: int, opts: Dictionary = {}) -> Action:
	var p := {"instance_id": instance_id}
	p.merge(opts)
	return Action.new(Enums.ActionType.PLAY_CARD, p)

static func declare_attack(attacker_id: int, target: Dictionary) -> Action:
	return Action.new(Enums.ActionType.DECLARE_ATTACK, {"attacker_id": attacker_id, "target": target})

static func end_turn() -> Action:
	return Action.new(Enums.ActionType.END_TURN)

static func activate_trap(instance_id: int) -> Action:
	return Action.new(Enums.ActionType.ACTIVATE_TRAP, {"instance_id": instance_id})

static func resolve_choice(data: Dictionary) -> Action:
	return Action.new(Enums.ActionType.RESOLVE_CHOICE, data)
