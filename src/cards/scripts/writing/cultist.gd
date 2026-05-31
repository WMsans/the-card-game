class_name Cultist
extends CardScript

func reacts_to() -> Array: return [Enums.EventType.UNIT_ATTACKED]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("attacker", -1) != card.instance_id:
		return
	if event.data.get("target_unit", -1) != -1:
		return
	var disc := ctx.discard_pile(ctx.me())
	if disc.is_empty():
		return
	ctx.request_choice(card,
		ChoiceSpec.select_cards(disc.duplicate(), 0, 1, "Trash Cultist to return a card?"),
		"cultist")

func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "cultist" and not result["cards"].is_empty():
		var c: CardInstance = result["cards"][0]
		ctx.gs().players[ctx.me()].discard.erase(c)
		c.zone = Enums.Zone.HAND
		ctx.gs().players[ctx.me()].hand.append(c)
		ctx.trash(card)
