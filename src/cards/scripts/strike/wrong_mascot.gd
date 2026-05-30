class_name WrongMascot
extends CardScript

func reacts_to() -> Array: return [Enums.EventType.UNIT_ATTACKED]
func active_zones() -> Array: return [Enums.Zone.TRAP_SET]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("player", -1) == ctx.me():
		return
	var target_id: int = event.data.get("target_unit", -1)
	if target_id < 0:
		return
	var defender := _find(ctx, ctx.me(), target_id)
	if defender == null or defender.card_script == null or not defender.card_script.has_request():
		return
	if not ctx.request_met(defender):
		return
	var attacker := _find(ctx, ctx.opponent(), event.data.get("attacker", -1))
	if attacker == null:
		return
	ctx.fire_trap(card)
	ctx.kill(attacker)

func _find(ctx: EffectContext, pidx: int, instance_id: int) -> CardInstance:
	for c in ctx.board(pidx):
		if c.instance_id == instance_id:
			return c
	return null
