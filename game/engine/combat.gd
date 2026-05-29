class_name Combat
extends RefCounted

static func compute(attacker: CardInstance, defender: CardInstance) -> Dictionary:
	return {
		"dmg_to_def": attacker.current_damage,
		"dmg_to_atk": defender.current_damage,
		"def_dies": attacker.current_damage >= defender.current_health,
		"atk_dies": defender.current_damage >= attacker.current_health,
	}
