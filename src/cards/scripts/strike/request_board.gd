class_name RequestBoard
extends CardScript

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	var minions: Array = []
	for c in ctx.hand(ctx.me()):
		if c.definition.type == Enums.CardType.MINION:
			minions.append(c)
	for m in minions:
		if m.card_script != null and m.card_script.has_request() and ctx.request_met(m):
			ctx.summon_free(m)
