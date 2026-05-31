class_name Plop
extends CardScript

func on_cast(_card: CardInstance, ctx: EffectContext) -> void:
	ctx.harmonize()

func reacts_to() -> Array: return [Enums.EventType.HARMONIZE]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, _event: GameEvent, ctx: EffectContext) -> void:
	if card.vars.get("harmonized", false):
		return
	card.vars["harmonized"] = true
	ctx.deal_deck_damage(ctx.opponent(), 6)
