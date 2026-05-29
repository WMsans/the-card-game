class_name GameEngine
extends RefCounted

var state: GameState

func _init(game_state: GameState) -> void:
	state = game_state

func _draw(player_idx: int, n: int = 1) -> void:
	var ps := state.players[player_idx]
	for i in range(n):
		if ps.deck.is_empty() and not _reshuffle_or_lose(player_idx):
			return
		if ps.deck.is_empty():
			return
		var card: CardInstance = ps.deck.pop_front()
		card.zone = Enums.Zone.HAND
		ps.hand.append(card)
		state.bus.publish(GameEvent.new(Enums.EventType.CARD_DRAWN,
			{"player": player_idx, "instance": card.instance_id}))

func _mill(player_idx: int, n: int) -> void:
	var ps := state.players[player_idx]
	for i in range(n):
		if ps.deck.is_empty() and not _reshuffle_or_lose(player_idx):
			return
		if ps.deck.is_empty():
			return
		var card: CardInstance = ps.deck.pop_front()
		card.zone = Enums.Zone.DISCARD
		ps.discard.append(card)
		ps.turn_counters["cards_discarded"] += 1
		state.bus.publish(GameEvent.new(Enums.EventType.CARD_DISCARDED,
			{"player": player_idx, "instance": card.instance_id}))

func _deck_damage(player_idx: int, amount: int) -> void:
	_mill(player_idx, amount)
	state.bus.publish(GameEvent.new(Enums.EventType.DECK_DAMAGED,
		{"player": player_idx, "amount": amount}))

func _reshuffle_or_lose(player_idx: int) -> bool:
	var ps := state.players[player_idx]
	if ps.reshuffles_remaining <= 0:
		_lose(player_idx)
		return false
	ps.reshuffles_remaining -= 1
	ps.deck.append_array(ps.discard)
	ps.discard.clear()
	for c in ps.deck:
		c.zone = Enums.Zone.DECK
	state.rng.shuffle(ps.deck)
	state.bus.publish(GameEvent.new(Enums.EventType.DECK_RESHUFFLED,
		{"player": player_idx, "remaining": ps.reshuffles_remaining}))
	if ps.deck.is_empty():
		_lose(player_idx)
		return false
	return true

func _lose(player_idx: int) -> void:
	state.winner = 1 - player_idx
	state.phase = Enums.Phase.GAME_OVER
	state.bus.publish(GameEvent.new(Enums.EventType.GAME_OVER, {"winner": state.winner}))

# --- setup -----------------------------------------------------------------

func setup(deck0: Array[CardDefinition], deck1: Array[CardDefinition]) -> void:
	_build_player(0, deck0)
	_build_player(1, deck1)
	state.rng.shuffle(state.players[0].deck)
	state.rng.shuffle(state.players[1].deck)
	_draw(0, 5)
	_draw(1, 5)
	state.pending_choice = PendingChoice.new("mulligan", 0)

func _build_player(idx: int, defs: Array[CardDefinition]) -> void:
	var ps := state.players[idx]
	for def in defs:
		var ci := state.make_instance(def)
		if def.type == Enums.CardType.LEADER:
			ci.zone = Enums.Zone.HAND
			ps.leader = ci
			ps.hand.append(ci)
		else:
			ci.zone = Enums.Zone.DECK
			ps.deck.append(ci)

func _apply_mulligan(indices: Array) -> void:
	var p := state.pending_choice.player
	var ps := state.players[p]
	var to_discard: Array[CardInstance] = []
	for i in indices:
		to_discard.append(ps.hand[i])
	for c in to_discard:
		ps.hand.erase(c)
		c.zone = Enums.Zone.DISCARD
		ps.discard.append(c)
		ps.turn_counters["cards_discarded"] += 1
	if p == 0:
		state.pending_choice = PendingChoice.new("mulligan", 1)
	else:
		state.pending_choice = null
		state.first_player = state.rng.randi_range(0, 1)
		state.active_player = state.first_player
		_start_turn()

# --- turn flow -------------------------------------------------------------

func _start_turn() -> void:
	state.phase = Enums.Phase.START
	state.turn_number += 1
	var ps := state.active()
	for u in ps.board:
		u.tapped = false
	ps.tickets_tapped = 0
	if ps.turns_taken == 0:
		ps.tickets_total = 1 if state.active_player == state.first_player else 2
	else:
		ps.tickets_total = min(10, ps.tickets_total + 2)
	ps.turns_taken += 1
	ps.reset_turn_counters()
	state.bus.publish(GameEvent.new(Enums.EventType.TURN_STARTED, {"player": state.active_player}))
	_draw(state.active_player, 1)
	if state.phase == Enums.Phase.GAME_OVER:
		return
	state.phase = Enums.Phase.MAIN

# --- controller interface --------------------------------------------------

func apply(action: Action) -> void:
	match action.type:
		Enums.ActionType.MULLIGAN:
			_apply_mulligan(action.params["indices"])
		Enums.ActionType.PLAY_CARD:
			_play_card(action.params["instance_id"], action.params)
		Enums.ActionType.END_TURN:
			_end_turn()
		Enums.ActionType.RESOLVE_CHOICE:
			_apply_resolve_choice(action.params)
		Enums.ActionType.DECLARE_ATTACK:
			_declare_attack(action.params["attacker_id"], action.params["target"])
		Enums.ActionType.ACTIVATE_TRAP:
			pass
		_:
			push_error("Unhandled action type %d" % action.type)

func _play_card(instance_id: int, params: Dictionary) -> void:
	var ps := state.active()
	var card: CardInstance = _find_in_hand(ps, instance_id)
	var def := card.definition
	var pay_by_discard: bool = params.get("pay_by_discard", false)
	if def.type == Enums.CardType.LEADER and pay_by_discard:
		_mill(state.active_player, def.alt_discard_cost)
	else:
		ps.tickets_tapped += def.ticket_cost
	ps.hand.erase(card)
	ps.turn_counters["cards_played"] += 1
	match def.type:
		Enums.CardType.MINION, Enums.CardType.LEADER:
			card.zone = Enums.Zone.BOARD
			card.tapped = true
			ps.board.append(card)
		Enums.CardType.SPELL:
			card.zone = Enums.Zone.DISCARD
			ps.discard.append(card)
		Enums.CardType.TRAP:
			card.zone = Enums.Zone.TRAP_SET
			ps.set_traps.append(card)
	state.bus.publish(GameEvent.new(Enums.EventType.CARD_PLAYED,
		{"player": state.active_player, "instance": instance_id, "card_type": def.type}))

func _find_in_hand(ps: PlayerState, instance_id: int) -> CardInstance:
	for c in ps.hand:
		if c.instance_id == instance_id:
			return c
	return null

func _end_turn() -> void:
	state.phase = Enums.Phase.END
	var ps := state.active()
	if ps.hand.size() > 5:
		state.pending_choice = PendingChoice.new(
			"discard_to_limit", state.active_player, {"count": ps.hand.size() - 5})
		return
	_finish_end_turn()

func _apply_resolve_choice(params: Dictionary) -> void:
	var pc := state.pending_choice
	if pc.kind == "discard_to_limit":
		var ps := state.players[pc.player]
		var indices: Array = params["indices"].duplicate()
		indices.sort()
		indices.reverse()
		for i in indices:
			var c: CardInstance = ps.hand[i]
			ps.hand.erase(c)
			c.zone = Enums.Zone.DISCARD
			ps.discard.append(c)
			ps.turn_counters["cards_discarded"] += 1
			state.bus.publish(GameEvent.new(Enums.EventType.CARD_DISCARDED,
				{"player": pc.player, "instance": c.instance_id}))
		state.pending_choice = null
		_finish_end_turn()

func _finish_end_turn() -> void:
	for p in state.players:
		for u in p.board:
			u.reset_stats()
	state.bus.publish(GameEvent.new(Enums.EventType.TURN_ENDED, {"player": state.active_player}))
	if state.phase == Enums.Phase.GAME_OVER:
		return
	state.active_player = state.opponent()
	_start_turn()

func _declare_attack(attacker_id: int, target: Dictionary) -> void:
	var ap := state.active()
	var attacker: CardInstance = _find_on_board(ap, attacker_id)
	attacker.tapped = true
	ap.turn_counters["attacks_made"] += 1
	state.bus.publish(GameEvent.new(Enums.EventType.UNIT_ATTACKED,
		{"attacker": attacker_id, "player": state.active_player}))
	_check_traps(state.bus.log[-1])
	if state.phase == Enums.Phase.GAME_OVER:
		return
	if target.get("deck", false):
		_deck_damage(state.opponent(), attacker.current_damage)
		return
	var opp := state.players[state.opponent()]
	var defender: CardInstance = _find_on_board(opp, target["unit"])
	var r := Combat.compute(attacker, defender)
	defender.current_health -= r["dmg_to_def"]
	attacker.current_health -= r["dmg_to_atk"]
	state.bus.publish(GameEvent.new(Enums.EventType.UNIT_DAMAGED,
		{"target": defender.instance_id, "amount": r["dmg_to_def"]}))
	state.bus.publish(GameEvent.new(Enums.EventType.UNIT_DAMAGED,
		{"target": attacker.instance_id, "amount": r["dmg_to_atk"]}))
	if r["def_dies"]:
		_kill(state.opponent(), defender)
	if r["atk_dies"]:
		_kill(state.active_player, attacker)

func _kill(owner_idx: int, unit: CardInstance) -> void:
	var owner := state.players[owner_idx]
	owner.board.erase(unit)
	unit.zone = Enums.Zone.DISCARD
	unit.reset_stats()
	owner.discard.append(unit)
	owner.turn_counters["units_died"] += 1
	state.bus.publish(GameEvent.new(Enums.EventType.UNIT_DIED,
		{"owner": owner_idx, "instance": unit.instance_id}))

func _find_on_board(ps: PlayerState, instance_id: int) -> CardInstance:
	for c in ps.board:
		if c.instance_id == instance_id:
			return c
	return null

func _check_traps(event: GameEvent) -> void:
	var defender_idx := state.opponent()
	for trap in state.players[defender_idx].set_traps:
		if _trap_condition_met(trap, event):
			pass

func _trap_condition_met(_trap: CardInstance, _event: GameEvent) -> bool:
	return false
