extends AudioTestBase

func test_rest_negates_next_deck_damage() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	var trap := eng.state.make_instance(audio_def(20))
	trap.zone = Enums.Zone.TRAP_SET
	ps.set_traps.append(trap)
	var before := ps.deck.size()
	eng._deck_damage(me, 5)
	assert_str(eng.state.pending_choice.kind).is_equal("intercept")
	eng.apply(Action.resolve_choice({"option": 0}))  # Fire
	assert_int(ps.deck.size()).is_equal(before)
	assert_bool(ps.set_traps.is_empty()).is_true()
