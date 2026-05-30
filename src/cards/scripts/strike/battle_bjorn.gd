class_name BattleBjorn
extends CardScript

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	ctx.gs().players[ctx.me()].all_requests_met_this_turn = true
