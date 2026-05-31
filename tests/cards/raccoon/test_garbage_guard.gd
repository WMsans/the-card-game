extends RaccoonTestBase

func test_garbage_guard_negates_deck_damage_and_rummages_that_many() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	seed_discard(eng, me, 5)
	var trap := eng.state.make_instance(raccoon_def(18))
	trap.zone = Enums.Zone.TRAP_SET
	ps.set_traps.append(trap)
	var deck_before := ps.deck.size()
	var disc_before := ps.discard.size()
	eng._deck_damage(me, 3)
	assert_str(eng.state.pending_choice.kind).is_equal("intercept")
	eng.apply(Action.resolve_choice({"option": 0}))
	assert_int(ps.deck.size()).is_equal(deck_before)
	assert_int(ps.discard.size()).is_equal(disc_before - 2)
