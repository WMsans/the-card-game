# src/cards/orange_token.gd
class_name OrangeToken
extends RefCounted

const ID := 100
const MAX_HELD := 5

static var DEF: CardDefinition = _make_def()

static func _make_def() -> CardDefinition:
	var d := CardDefinition.new()
	d.id = ID
	d.deck_color = "writing"
	d.type = Enums.CardType.SPELL
	d.name = "Orange"
	d.ticket_cost = 0
	d.ability_text = "Reduce a card's fee by 1. While in hand, increase hand size by one. EXHAUSTED."
	d.keywords = ["EXHAUSTED"]
	return d

static func is_orange(card: CardInstance) -> bool:
	return card != null and card.definition == DEF
