class_name CardDefinition
extends RefCounted

var id: int = 0
var deck_color: String = ""
var type: int = Enums.CardType.MINION
var name: String = ""
var ticket_cost: int = 0
var alt_discard_cost: int = 0
var base_damage: int = 0
var base_health: int = 0
var ability_text: String = ""
var flavor: String = ""
var image: String = ""
var keywords: Array[String] = []
