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
		_:
			push_error("Unhandled action type %d" % action.type)
