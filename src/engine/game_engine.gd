class_name GameEngine
extends RefCounted

const EffectContextClass = preload("res://src/cards/effect_context.gd")

var state: GameState
var _queue: Array = []
var _resolving: bool = false
var _suspended: bool = false

func _init(game_state: GameState) -> void:
	state = game_state

func emit(event: GameEvent) -> void:
	_queue.append({"kind": "event", "event": event})
	_pump()

func _push(item: Dictionary) -> void:
	_queue.append(item)

func _pump() -> void:
	if _resolving:
		return
	_resolving = true
	_drain()

func _drain() -> void:
	while not _queue.is_empty():
		if _suspended:
			_resolving = false
			return
		var item: Dictionary = _queue.pop_front()
		match item["kind"]:
			"event":
				state.bus.publish(item["event"])
				_dispatch_triggers(item["event"])
			"react":
				item["card"].card_script.react(item["card"], item["event"], _ctx_for(item["pidx"]))
			"call":
				item["fn"].call()
	_resolving = false

func _dispatch_triggers(event: GameEvent) -> void:
	var jobs: Array = []
	for pidx in [state.active_player, state.opponent()]:
		for card in _trigger_candidates(state.players[pidx]):
			var s: CardScript = card.card_script
			if s == null:
				continue
			if not s.reacts_to().has(event.type):
				continue
			if not s.active_zones().has(card.zone):
				continue
			jobs.append({"kind": "react", "card": card, "event": event, "pidx": pidx})
	for i in range(jobs.size() - 1, -1, -1):
		_queue.push_front(jobs[i])

func _trigger_candidates(ps: PlayerState) -> Array:
	var out: Array = []
	out.append_array(ps.board)
	out.append_array(ps.set_traps)
	out.append_array(ps.discard)
	out.append_array(ps.hand)
	return out

func _ctx_for(pidx: int):
	return EffectContextClass.new(self, pidx)

func effective_cost(card: CardInstance, player_idx: int) -> int:
	var base := card.definition.ticket_cost
	var modd := 0
	if card.card_script != null:
		modd = card.card_script.cost_modifier(card, _ctx_for(player_idx))
	var fee: int = card.vars.get("fee_modifier", 0)
	return max(0, base + modd + fee)

func _owner_of(unit: CardInstance) -> int:
	for i in range(state.players.size()):
		var ps := state.players[i]
		if ps.board.has(unit) or ps.discard.has(unit) or ps.hand.has(unit) \
				or ps.set_traps.has(unit) or ps.deck.has(unit):
			return i
	return -1

func _fire_trap(card: CardInstance) -> void:
	var owner := _owner_of(card)
	if owner < 0:
		return
	var ps := state.players[owner]
	if not ps.set_traps.has(card):
		return
	ps.set_traps.erase(card)
	card.zone = Enums.Zone.DISCARD
	ps.discard.append(card)
	emit(GameEvent.new(Enums.EventType.TRAP_FIRED, {"player": owner, "instance": card.instance_id}))

func _request_met(card: CardInstance) -> bool:
	var owner := _owner_of(card)
	if owner < 0:
		return false
	if state.players[owner].all_requests_met_this_turn:
		return true
	if card.card_script == null or not card.card_script.has_request():
		return false
	return card.card_script.condition_met(card, _ctx_for(owner))

func _request_choice(card: CardInstance, spec: ChoiceSpec, tag: String, asked_player: int) -> void:
	state.pending_choice = PendingChoice.new("card_effect", asked_player, {
		"spec": spec,
		"ui_shape": spec.ui_shape,
		"resume_card": card.instance_id,
		"resume_tag": tag,
		"resume_owner": _owner_of(card),
	})
	_suspended = true

func _find_anywhere(instance_id: int) -> CardInstance:
	for ps in state.players:
		for zone in [ps.board, ps.hand, ps.discard, ps.set_traps, ps.deck]:
			for c in zone:
				if c.instance_id == instance_id:
					return c
	return null

func _resolve_card_effect(params: Dictionary) -> void:
	var pc := state.pending_choice
	var data := pc.data
	var spec: ChoiceSpec = data["spec"]
	var card := _find_anywhere(data["resume_card"])
	var owner: int = data["resume_owner"]
	var result := _build_choice_result(spec, params)
	state.pending_choice = null
	_suspended = false
	if card != null and card.card_script != null:
		card.card_script.resume(card, data["resume_tag"], result, _ctx_for(owner))
	if not _suspended:
		_pump()

func _resolve_intercept(params: Dictionary) -> void:
	var d := state.pending_choice.data
	var option: int = params.get("option", 1)
	var trap := _find_anywhere(d["trap_id"])
	state.pending_choice = null
	_suspended = false
	match d["op"]:
		"deck_damage":
			if option == 0 and trap != null and trap.card_script != null:
				_fire_trap(trap)
				var remaining: int = trap.card_script.deck_damage_on_fire(
					trap, d["player"], d["amount"], _ctx_for(d["player"]))
				_apply_deck_damage(d["player"], remaining)
			else:
				_apply_deck_damage(d["player"], d["amount"])
		"kill":
			var unit := _find_anywhere(d["unit_id"])
			if option == 0 and trap != null and trap.card_script != null and unit != null:
				_fire_trap(trap)
				var prevented: bool = trap.card_script.kill_on_fire(
					trap, unit, _ctx_for(d["owner"]))
				if not prevented:
					_apply_kill(d["owner"], unit)
			elif unit != null:
				_apply_kill(d["owner"], unit)
	if not _suspended:
		_pump()

func _build_choice_result(spec: ChoiceSpec, params: Dictionary) -> Dictionary:
	match spec.ui_shape:
		"select_cards":
			var picked: Array = []
			for i in params.get("indices", []):
				picked.append(spec.cards[i])
			return {"cards": picked}
		"select_target":
			var targets: Array = []
			for id in params.get("target_ids", []):
				for u in spec.cards:
					if u.instance_id == id:
						targets.append(u)
			return {"targets": targets}
		"choose_option":
			return {"option": params.get("option", 0)}
		_:
			return {}

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
		emit(GameEvent.new(Enums.EventType.CARD_DRAWN,
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
		emit(GameEvent.new(Enums.EventType.CARD_DISCARDED,
			{"player": player_idx, "instance": card.instance_id}))

func _deck_damage(player_idx: int, amount: int) -> void:
	_push({"kind": "call", "fn": func(): _begin_deck_damage(player_idx, amount)})
	_pump()

func _begin_deck_damage(player_idx: int, amount: int) -> void:
	var ps := state.players[player_idx]
	for trap in ps.set_traps:
		if trap.card_script != null and trap.card_script.can_intercept_deck_damage(
				trap, player_idx, amount, _ctx_for(player_idx)):
			state.pending_choice = PendingChoice.new("intercept", player_idx, {
				"op": "deck_damage", "trap_id": trap.instance_id,
				"player": player_idx, "amount": amount,
				"spec": ChoiceSpec.intercept(trap,
					"Your Deck will take %d damage" % amount, ["Fire", "Decline"]),
				"ui_shape": "intercept",
			})
			_suspended = true
			return
	_apply_deck_damage(player_idx, amount)

func _apply_deck_damage(player_idx: int, amount: int) -> void:
	if amount > 0:
		_mill(player_idx, amount)
	emit(GameEvent.new(Enums.EventType.DECK_DAMAGED,
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
	emit(GameEvent.new(Enums.EventType.DECK_RESHUFFLED,
		{"player": player_idx, "remaining": ps.reshuffles_remaining}))
	if ps.deck.is_empty():
		_lose(player_idx)
		return false
	return true

func _harmonize(player_idx: int) -> void:
	emit(GameEvent.new(Enums.EventType.HARMONIZE, {"player": player_idx}))

func _lose(player_idx: int) -> void:
	state.winner = 1 - player_idx
	state.phase = Enums.Phase.GAME_OVER
	emit(GameEvent.new(Enums.EventType.GAME_OVER, {"winner": state.winner}))

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
		var ci: CardInstance = ps.hand[i]
		if ci.definition.type == Enums.CardType.LEADER:
			continue
		to_discard.append(ci)
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
	for p in state.players:
		for u in p.board:
			u.vars.erase("immortal_this_turn")
			u.vars.erase("opt_used_this_turn")
	emit(GameEvent.new(Enums.EventType.TURN_STARTED, {"player": state.active_player}))
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
		Enums.ActionType.ACTIVATE_ABILITY:
			_activate_ability(action.params["instance_id"], action.params["ability_id"])
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
		ps.tickets_tapped += effective_cost(card, state.active_player)
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
	emit(GameEvent.new(Enums.EventType.CARD_PLAYED,
		{"player": state.active_player, "instance": instance_id, "card_type": def.type}))
	if def.type != Enums.CardType.TRAP and card.card_script != null:
		_push({"kind": "call", "fn": func(): card.card_script.on_cast(card, _ctx_for(state.active_player))})
		_pump()

func _find_in_hand(ps: PlayerState, instance_id: int) -> CardInstance:
	for c in ps.hand:
		if c.instance_id == instance_id:
			return c
	return null

func _end_turn() -> void:
	state.phase = Enums.Phase.END
	var ps := state.active()
	if ps.hand.size() > _hand_limit(ps):
		state.pending_choice = PendingChoice.new(
			"discard_to_limit", state.active_player, {"count": ps.hand.size() - _hand_limit(ps)})
		return
	_finish_end_turn()

func _gain_orange(player_idx: int) -> void:
	var ps := state.players[player_idx]
	var held := 0
	for c in ps.hand:
		if OrangeToken.is_orange(c):
			held += 1
	if held >= OrangeToken.MAX_HELD:
		return
	var ci := state.make_instance(OrangeToken.DEF)
	ci.zone = Enums.Zone.HAND
	ps.hand.append(ci)

func _hand_limit(ps: PlayerState) -> int:
	var oranges := 0
	for c in ps.hand:
		if OrangeToken.is_orange(c):
			oranges += 1
	return 5 + oranges

func _apply_resolve_choice(params: Dictionary) -> void:
	var pc := state.pending_choice
	if pc.kind == "intercept":
		_resolve_intercept(params)
		return
	if pc.kind == "card_effect":
		_resolve_card_effect(params)
		return
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
			emit(GameEvent.new(Enums.EventType.CARD_DISCARDED,
				{"player": pc.player, "instance": c.instance_id}))
		state.pending_choice = null
		_finish_end_turn()

func _finish_end_turn() -> void:
	for p in state.players:
		for u in p.board:
			u.reset_stats()
	emit(GameEvent.new(Enums.EventType.TURN_ENDED, {"player": state.active_player}))
	if state.phase == Enums.Phase.GAME_OVER:
		return
	state.active_player = state.opponent()
	_start_turn()

func _declare_attack(attacker_id: int, target: Dictionary) -> void:
	var ap := state.active()
	var attacker: CardInstance = _find_on_board(ap, attacker_id)
	attacker.tapped = true
	ap.turn_counters["attacks_made"] += 1
	emit(GameEvent.new(Enums.EventType.UNIT_ATTACKED,
		{"attacker": attacker_id, "player": state.active_player, "target_unit": target.get("unit", -1)}))
	if _request_met(attacker):
		emit(GameEvent.new(Enums.EventType.REQUEST_MET,
			{"player": state.active_player, "instance": attacker_id}))
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
	emit(GameEvent.new(Enums.EventType.UNIT_DAMAGED,
		{"target": defender.instance_id, "amount": r["dmg_to_def"]}))
	emit(GameEvent.new(Enums.EventType.UNIT_DAMAGED,
		{"target": attacker.instance_id, "amount": r["dmg_to_atk"]}))
	if r["def_dies"]:
		_kill(state.opponent(), defender, "battle")
	if r["atk_dies"]:
		_kill(state.active_player, attacker, "battle")

func _kill(owner_idx: int, unit: CardInstance, reason: String = "effect") -> void:
	_push({"kind": "call", "fn": func(): _begin_kill(owner_idx, unit, reason)})
	_pump()

func _begin_kill(owner_idx: int, unit: CardInstance, reason: String) -> void:
	if unit.vars.get("immortal_this_turn", false):
		return
	if not state.players[owner_idx].board.has(unit):
		return
	for trap in state.players[owner_idx].set_traps:
		if trap.card_script != null and trap.card_script.can_intercept_kill(
				trap, unit, reason, _ctx_for(owner_idx)):
			state.pending_choice = PendingChoice.new("intercept", owner_idx, {
				"op": "kill", "trap_id": trap.instance_id,
				"owner": owner_idx, "unit_id": unit.instance_id,
				"spec": ChoiceSpec.intercept(trap,
					"%s would be killed" % unit.definition.name, ["Fire", "Decline"]),
				"ui_shape": "intercept",
			})
			_suspended = true
			return
	_apply_kill(owner_idx, unit)

func _apply_kill(owner_idx: int, unit: CardInstance) -> void:
	var owner := state.players[owner_idx]
	if not owner.board.has(unit):
		return
	owner.board.erase(unit)
	unit.zone = Enums.Zone.DISCARD
	unit.reset_stats()
	if unit.vars.get("discard_to_bottom", false):
		unit.vars.erase("discard_to_bottom")
		owner.discard.push_front(unit)
	else:
		owner.discard.append(unit)
	owner.turn_counters["units_died"] += 1
	emit(GameEvent.new(Enums.EventType.UNIT_DIED,
		{"owner": owner_idx, "instance": unit.instance_id}))

func _damage_unit(unit: CardInstance, n: int) -> void:
	unit.current_health -= n
	emit(GameEvent.new(Enums.EventType.UNIT_DAMAGED, {"target": unit.instance_id, "amount": n}))
	if unit.current_health <= 0:
		_kill_unit(unit)

func _kill_unit(unit: CardInstance) -> void:
	var owner := _owner_of(unit)
	if owner >= 0 and state.players[owner].board.has(unit):
		_kill(owner, unit)

func _discard_from_hand(card: CardInstance) -> void:
	var owner := _owner_of(card)
	if owner < 0:
		return
	var ps := state.players[owner]
	if not ps.hand.has(card):
		return
	ps.hand.erase(card)
	card.zone = Enums.Zone.DISCARD
	ps.discard.append(card)
	ps.turn_counters["cards_discarded"] += 1
	emit(GameEvent.new(Enums.EventType.CARD_DISCARDED, {"player": owner, "instance": card.instance_id}))

func _search_deck(pidx: int, pred: Callable) -> CardInstance:
	for c in state.players[pidx].deck:
		if pred.call(c):
			return c
	return null

func _draw_specific(pidx: int, card: CardInstance) -> void:
	var ps := state.players[pidx]
	if not ps.deck.has(card):
		return
	ps.deck.erase(card)
	card.zone = Enums.Zone.HAND
	ps.hand.append(card)
	emit(GameEvent.new(Enums.EventType.CARD_DRAWN, {"player": pidx, "instance": card.instance_id}))

func _summon_free(pidx: int, card: CardInstance) -> void:
	var ps := state.players[pidx]
	if ps.hand.has(card):
		ps.hand.erase(card)
	card.zone = Enums.Zone.BOARD
	card.tapped = true
	ps.board.append(card)
	emit(GameEvent.new(Enums.EventType.CARD_PLAYED,
		{"player": pidx, "instance": card.instance_id, "card_type": card.definition.type}))

func _put_on_deck_top(unit: CardInstance) -> void:
	var owner := _owner_of(unit)
	if owner < 0:
		return
	var ps := state.players[owner]
	ps.board.erase(unit)
	unit.reset_stats()
	unit.zone = Enums.Zone.DECK
	ps.deck.push_front(unit)

func _rummage(player_idx: int, n: int) -> void:
	var ps := state.players[player_idx]
	var bonus := 0
	for u in ps.board:
		if u.card_script != null:
			bonus += u.card_script.rummage_bonus(u, _ctx_for(player_idx))
	var total := n + bonus
	ps.turn_counters["rummages_made"] += 1
	emit(GameEvent.new(Enums.EventType.RUMMAGE_PERFORMED,
		{"player": player_idx, "count": total}))
	for i in range(total):
		if ps.discard.is_empty():
			break
		var card: CardInstance = ps.discard.pop_front()
		card.zone = Enums.Zone.HAND
		ps.hand.append(card)
		emit(GameEvent.new(Enums.EventType.CARD_RUMMAGED,
			{"player": player_idx, "instance": card.instance_id}))

func _to_deck_bottom(card: CardInstance) -> void:
	var owner := _owner_of(card)
	if owner < 0:
		return
	var ps := state.players[owner]
	ps.board.erase(card)
	ps.hand.erase(card)
	ps.discard.erase(card)
	card.reset_stats()
	card.zone = Enums.Zone.DECK
	ps.deck.append(card)

func _steal_top_discard(thief: int, victim: int) -> CardInstance:
	var vps := state.players[victim]
	if vps.discard.is_empty():
		return null
	var card: CardInstance = vps.discard.pop_back()
	card.vars["stolen_from"] = victim
	card.zone = Enums.Zone.HAND
	state.players[thief].hand.append(card)
	return card

func _find_on_board(ps: PlayerState, instance_id: int) -> CardInstance:
	for c in ps.board:
		if c.instance_id == instance_id:
			return c
	return null

func _activate_ability(instance_id: int, ability_id: String) -> void:
	var ps := state.active()
	var card := _find_on_board(ps, instance_id)
	if card == null or card.card_script == null:
		return
	_push({"kind": "call", "fn": func(): card.card_script.activate(card, ability_id, _ctx_for(state.active_player))})
	_pump()

func _check_traps(event: GameEvent) -> void:
	var defender_idx := state.opponent()
	for trap in state.players[defender_idx].set_traps:
		if _trap_condition_met(trap, event):
			pass

func _trap_condition_met(_trap: CardInstance, _event: GameEvent) -> bool:
	return false

func _taunt_units(player_idx: int) -> Array:
	var out: Array = []
	for u in state.players[player_idx].board:
		if u.vars.get("taunt", false):
			out.append(u)
	return out

func _has_clef_on_board(player_idx: int) -> bool:
	for u in state.players[player_idx].board:
		if u.card_script != null and u.card_script.is_clef():
			return true
	return false

func get_legal_actions() -> Array:
	var out: Array = []
	if state.phase == Enums.Phase.GAME_OVER:
		return out
	if state.pending_choice != null:
		return out
	if state.phase != Enums.Phase.MAIN:
		return out
	var ps := state.active()
	for c in ps.hand:
		var def := c.definition
		var is_clef := c.card_script != null and c.card_script.is_clef()
		if is_clef and _has_clef_on_board(state.active_player):
			continue
		if ps.available_tickets() >= effective_cost(c, state.active_player):
			out.append(Action.play_card(c.instance_id))
		if def.type == Enums.CardType.LEADER \
				and ps.deck.size() + ps.discard.size() >= def.alt_discard_cost:
			out.append(Action.play_card(c.instance_id, {"pay_by_discard": true}))
	var opp := state.players[state.opponent()]
	var taunts := _taunt_units(state.opponent())
	for u in ps.board:
		if u.tapped or not u.is_unit():
			continue
		if taunts.is_empty():
			out.append(Action.declare_attack(u.instance_id, {"deck": true}))
			for d in opp.board:
				out.append(Action.declare_attack(u.instance_id, {"unit": d.instance_id}))
		else:
			for d in taunts:
				out.append(Action.declare_attack(u.instance_id, {"unit": d.instance_id}))
	for u in ps.board:
		if u.card_script == null:
			continue
		for ab in u.card_script.activated_abilities(u, _ctx_for(state.active_player)):
			out.append(Action.activate_ability(u.instance_id, ab["id"]))
	out.append(Action.end_turn())
	return out
