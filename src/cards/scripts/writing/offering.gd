class_name Offering
extends CardScript

func active_zones() -> Array: return [Enums.Zone.TRAP_SET]

func can_intercept_deck_damage(_card: CardInstance, _player: int, _amount: int, _ctx) -> bool:
	return true

func deck_damage_on_fire(_card: CardInstance, _player: int, _amount: int, ctx: EffectContext) -> int:
	ctx.gain_orange(ctx.opponent())
	return 0
