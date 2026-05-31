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
		"card_effect":
			var spec: ChoiceSpec = pc.data["spec"]
			match spec.ui_shape:
				"select_cards":
					var idx: Array = []
					for i in range(spec.min_n):
						idx.append(i)
					return Action.resolve_choice({"indices": idx})
				"select_target":
					var ids: Array = []
					var need: int = max(spec.min_n, 0)
					for i in range(min(need, spec.cards.size())):
						ids.append(spec.cards[i].instance_id)
					return Action.resolve_choice({"target_ids": ids})
				"choose_option":
					return Action.resolve_choice({"option": 0})
				_:
					return Action.resolve_choice({"indices": []})
		"intercept":
			return Action.resolve_choice({"option": 1})
		"trash_choice":
			var spec: ChoiceSpec = pc.data["spec"]
			return Action.resolve_choice({"option": spec.labels.size() - 1})
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