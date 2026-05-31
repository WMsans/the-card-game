class_name BassClef
extends ClefCard

func doubles_all_damage() -> bool: return true

func reacts_to() -> Array: return [Enums.EventType.UNIT_DAMAGED]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	var target := ctx.engine._find_anywhere(int(event.data.get("target", -1)))
	if target == null:
		return
	if target.current_health <= 0:
		return
	var owner := ctx.engine._owner_of(target)
	if owner < 0 or not ctx.gs().players[owner].board.has(target):
		return
	ctx.harmonize()
