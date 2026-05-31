class_name ClefCard
extends CardScript

func is_clef() -> bool: return true

func activated_abilities(card: CardInstance, ctx: EffectContext) -> Array:
	if card.zone != Enums.Zone.BOARD:
		return []
	if ctx.gs().players[ctx.me()].available_tickets() < 2:
		return []
	return [{"id": "clef_bounce", "label": "Return this Clef to your hand (2)"}]

func activate(card: CardInstance, ability_id: String, ctx: EffectContext) -> void:
	if ability_id != "clef_bounce":
		return
	var ps := ctx.gs().players[ctx.me()]
	ps.tickets_tapped += 2
	ps.board.erase(card)
	card.reset_stats()
	card.tapped = false
	card.zone = Enums.Zone.HAND
	ps.hand.append(card)
