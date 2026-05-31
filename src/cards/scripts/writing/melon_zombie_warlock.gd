class_name MelonZombieWarlock
extends CardScript

func trash_replacement_for(card: CardInstance, target: CardInstance, _ctx) -> String:
	if card == target:
		return ""
	if card.zone != Enums.Zone.BOARD:
		return ""
	if target.definition.type != Enums.CardType.MINION:
		return ""
	return "Replay for cost +1"

func apply_trash_replacement(_card: CardInstance, target: CardInstance, ctx: EffectContext) -> void:
	var ps := ctx.gs().players[ctx.me()]
	ps.tickets_tapped += target.definition.ticket_cost + 1
	target.reset_stats()
