class_name RequestSlacker
extends CardScript

func has_request() -> bool: return true
func condition_met(card: CardInstance, ctx: EffectContext) -> bool:
	return ctx.board(ctx.me()).size() + ctx.board(ctx.opponent()).size() <= 4

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	var enemy_minions: Array = []
	for u in ctx.board(ctx.opponent()):
		if u.definition.type == Enums.CardType.MINION:
			enemy_minions.append(u)
	if enemy_minions.is_empty():
		return
	ctx.request_choice(card, ChoiceSpec.select_target(enemy_minions, 1, 1, "Place an enemy Minion on top of their Deck"), "bounce")

func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "bounce" and not result["targets"].is_empty():
		ctx.put_on_deck_top(result["targets"][0])
