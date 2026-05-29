class_name TestFactory
extends RefCounted

static func minion(cost: int, dmg: int, hp: int, id: int = 1) -> CardDefinition:
	var d := CardDefinition.new()
	d.id = id
	d.name = "M%d" % id
	d.type = Enums.CardType.MINION
	d.ticket_cost = cost
	d.base_damage = dmg
	d.base_health = hp
	d.deck_color = "Test"
	return d

static func leader(cost: int, dmg: int, hp: int, alt: int) -> CardDefinition:
	var d := CardDefinition.new()
	d.id = 0
	d.name = "Leader"
	d.type = Enums.CardType.LEADER
	d.ticket_cost = cost
	d.alt_discard_cost = alt
	d.base_damage = dmg
	d.base_health = hp
	d.deck_color = "Test"
	return d

static func spell(cost: int, id: int = 1) -> CardDefinition:
	var d := CardDefinition.new()
	d.id = id
	d.name = "S%d" % id
	d.type = Enums.CardType.SPELL
	d.ticket_cost = cost
	d.deck_color = "Test"
	return d

static func trap(cost: int, id: int = 1) -> CardDefinition:
	var d := CardDefinition.new()
	d.id = id
	d.name = "T%d" % id
	d.type = Enums.CardType.TRAP
	d.ticket_cost = cost
	d.deck_color = "Test"
	return d

static func simple_deck() -> Array[CardDefinition]:
	var defs: Array[CardDefinition] = []
	defs.append(leader(2, 2, 5, 4))
	for i in range(20):
		defs.append(minion(1, 1, 1, i + 100))
	return defs
