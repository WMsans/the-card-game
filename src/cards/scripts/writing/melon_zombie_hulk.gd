class_name MelonZombieHulk
extends CardScript

func reacts_to() -> Array: return [Enums.EventType.UNIT_ATTACKED]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("attacker", -1) != card.instance_id:
		return
	var allies: Array = ctx.board(ctx.me())
	if allies.is_empty():
		return
	ctx.request_choice(card,
		ChoiceSpec.select_target(allies.duplicate(), 1, 1, "TRASH a Unit"), "hulk")

func resume(_card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "hulk" and not result["targets"].is_empty():
		ctx.trash(result["targets"][0])
