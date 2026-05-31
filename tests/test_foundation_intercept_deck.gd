extends CardTestBase

class RestStub extends CardScript:
	func active_zones() -> Array: return [Enums.Zone.TRAP_SET]
	func can_intercept_deck_damage(_card: CardInstance, _player: int, _amount: int, _ctx) -> bool:
		return true
	func deck_damage_on_fire(_card: CardInstance, _player: int, _amount: int, _ctx) -> int:
		return 0  # fully negate

func _set_trap(eng: GameEngine, p: int, script: CardScript) -> CardInstance:
	var t := eng.state.make_instance(TestFactory.trap(4, 20))
	t.card_script = script
	t.zone = Enums.Zone.TRAP_SET
	eng.state.players[p].set_traps.append(t)
	return t

func test_deck_damage_without_interceptor_mills_normally() -> void:
	var eng := fresh_engine()
	var opp := eng.state.opponent()
	var before := eng.state.players[opp].deck.size()
	eng._deck_damage(opp, 2)
	assert_int(eng.state.players[opp].deck.size()).is_equal(before - 2)
	assert_bool(eng.state.pending_choice == null).is_true()

func test_deck_damage_with_interceptor_suspends_then_fire_negates() -> void:
	var eng := fresh_engine()
	var opp := eng.state.opponent()
	_set_trap(eng, opp, RestStub.new())
	var before := eng.state.players[opp].deck.size()
	eng._deck_damage(opp, 6)
	# suspended, asking the defender (opp)
	assert_bool(eng.state.pending_choice != null).is_true()
	assert_str(eng.state.pending_choice.kind).is_equal("intercept")
	assert_int(eng.state.pending_choice.player).is_equal(opp)
	eng.apply(Action.resolve_choice({"option": 0}))  # Fire
	assert_int(eng.state.players[opp].deck.size()).is_equal(before)  # nothing milled
	assert_bool(eng.state.players[opp].set_traps.is_empty()).is_true()  # trap fired

func test_deck_damage_decline_applies_full_damage() -> void:
	var eng := fresh_engine()
	var opp := eng.state.opponent()
	_set_trap(eng, opp, RestStub.new())
	var before := eng.state.players[opp].deck.size()
	eng._deck_damage(opp, 3)
	eng.apply(Action.resolve_choice({"option": 1}))  # Decline
	assert_int(eng.state.players[opp].deck.size()).is_equal(before - 3)
