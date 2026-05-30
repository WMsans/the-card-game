class_name CardInput
extends RefCounted

static func _is_legal(candidate: Action, legal: Array) -> bool:
	for a in legal:
		if a.type != candidate.type:
			continue
		if a.params == candidate.params:
			return true
	return false

static func play_from_drop(instance_id: int, drop_zone: String, legal: Array, pay_by_discard: bool = false) -> Action:
	if drop_zone == "":
		return null
	var act := Action.play_card(instance_id, {"pay_by_discard": true} if pay_by_discard else {})
	return act if _is_legal(act, legal) else null

static func attack_from_target(attacker_id: int, target: Dictionary, legal: Array) -> Action:
	var act := Action.declare_attack(attacker_id, target)
	return act if _is_legal(act, legal) else null