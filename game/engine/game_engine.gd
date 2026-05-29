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
