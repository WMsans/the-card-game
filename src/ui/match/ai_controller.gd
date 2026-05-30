class_name AiController
extends RefCounted

static func choose_action(engine: GameEngine) -> Action:
	var legal := engine.get_legal_actions()
	if legal.is_empty():
		return Action.end_turn()
	var plays := legal.filter(func(a): return a.type == Enums.ActionType.PLAY_CARD)
	if not plays.is_empty():
		return plays[0]
	var attacks := legal.filter(func(a): return a.type == Enums.ActionType.DECLARE_ATTACK)
	if not attacks.is_empty():
		var deck_hits := attacks.filter(func(a): return a.params["target"].get("deck", false))
		return deck_hits[0] if not deck_hits.is_empty() else attacks[0]
	return Action.end_turn()

static func choice_action(engine: GameEngine) -> Action:
	var pc := engine.state.pending_choice
	match pc.kind:
		"mulligan":
			return Action.mulligan(_first_two_non_leader(engine.state.players[pc.player]))
		"discard_to_limit":
			var n: int = pc.data["count"]
			var idx: Array = []
			for i in range(n):
				idx.append(i)
			return Action.resolve_choice({"indices": idx})
		_:
			return Action.resolve_choice({"indices": []})

static func _first_two_non_leader(ps: PlayerState) -> Array:
	var out: Array = []
	for i in range(ps.hand.size()):
		if ps.hand[i].definition.type != Enums.CardType.LEADER:
			out.append(i)
		if out.size() == 2:
			break
	return out