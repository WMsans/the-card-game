class_name MelonZombie
extends CardScript

func trash_replacement_for(card: CardInstance, target: CardInstance, _ctx) -> String:
	return "Return to hand" if card == target else ""

func apply_trash_replacement(_card: CardInstance, target: CardInstance, ctx: EffectContext) -> void:
	var ps := ctx.gs().players[ctx.me()]
	ps.board.erase(target)
	target.reset_stats()
	target.zone = Enums.Zone.HAND
	ps.hand.append(target)
