extends WritingTestBase

func test_offering_gives_opponent_orange_and_negates_deck_damage() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var ps := eng.state.players[me]
	var trap := eng.state.make_instance(writing_def(21))
	trap.zone = Enums.Zone.TRAP_SET
	ps.set_traps.append(trap)
	var before := ps.deck.size()
	var opp_oranges := oranges_in_hand(eng, opp)
	eng._deck_damage(me, 4)
	assert_str(eng.state.pending_choice.kind).is_equal("intercept")
	eng.apply(Action.resolve_choice({"option": 0}))
	assert_int(ps.deck.size()).is_equal(before)
	assert_int(oranges_in_hand(eng, opp)).is_equal(opp_oranges + 1)
