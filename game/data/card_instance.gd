class_name CardInstance
extends RefCounted

var instance_id: int
var definition: CardDefinition
var zone: int = Enums.Zone.DECK
var tapped: bool = false
var current_damage: int
var current_health: int

func _init(id: int, def: CardDefinition) -> void:
	instance_id = id
	definition = def
	current_damage = def.base_damage
	current_health = def.base_health

func reset_stats() -> void:
	current_damage = definition.base_damage
	current_health = definition.base_health

func is_unit() -> bool:
	return definition.type == Enums.CardType.MINION or definition.type == Enums.CardType.LEADER
