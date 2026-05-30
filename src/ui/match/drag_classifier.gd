class_name DragClassifier
extends RefCounted

enum State { INVALID, UNAFFORDABLE, ACCEPTABLE }

static func classify(state: GameState, legal: Array, instance_id: int, player: int) -> int:
	for a in legal:
		if a.type == Enums.ActionType.PLAY_CARD and a.params.get("instance_id") == instance_id:
			return State.ACCEPTABLE
	if state.active_player != player or state.pending_choice != null:
		return State.INVALID
	var inst := _find_in_hand(state.players[player].hand, instance_id)
	if inst == null:
		return State.INVALID
	if inst.definition.type == Enums.CardType.LEADER:
		return State.INVALID
	if inst.definition.ticket_cost > state.players[player].available_tickets():
		return State.UNAFFORDABLE
	return State.INVALID

static func advertises_zone(state: GameState, instance_id: int, player: int) -> bool:
	if state.active_player != player or state.pending_choice != null:
		return false
	var inst := _find_in_hand(state.players[player].hand, instance_id)
	return inst != null and inst.definition.type != Enums.CardType.LEADER

static func _find_in_hand(hand: Array, instance_id: int) -> CardInstance:
	for c in hand:
		if c.instance_id == instance_id:
			return c
	return null