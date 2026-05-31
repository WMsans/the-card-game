class_name PriorityRaise
extends CardScript

func activated_abilities(card: CardInstance, ctx: EffectContext) -> Array:
	if card.tapped:
		return []
	var has_target := false
	for c in ctx.discard_pile(ctx.me()):
		if c.card_script != null and c.card_script.has_request():
			has_target = true
			break
	return [{"id": "raise", "label": "Move a REQUEST card to your Deck"}] if has_target else []

func activate(card: CardInstance, ability_id: String, ctx: EffectContext) -> void:
	if ability_id != "raise":
		return
	var candidates: Array = []
	for c in ctx.discard_pile(ctx.me()):
		if c.card_script != null and c.card_script.has_request():
			candidates.append(c)
	if candidates.is_empty():
		return
	card.tapped = true
	ctx.request_choice(card, ChoiceSpec.select_cards(candidates, 1, 1, "Move a REQUEST card to your Deck"), "raise")

func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "raise" and not result["cards"].is_empty():
		var c: CardInstance = result["cards"][0]
		ctx.gs().players[ctx.me()].discard.erase(c)
		c.zone = Enums.Zone.DECK
		ctx.gs().players[ctx.me()].deck.append(c)
