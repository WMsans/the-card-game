extends RaccoonTestBase

func test_safety_net_redirects_killed_ally_to_discard_bottom() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	var filler := eng.state.make_instance(TestFactory.minion(1, 1, 1, 99))
	filler.zone = Enums.Zone.DISCARD
	ps.discard.append(filler)
	var trap := eng.state.make_instance(raccoon_def(20))
	trap.zone = Enums.Zone.TRAP_SET
	ps.set_traps.append(trap)
	var u := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 1))
	eng._kill(me, u, "effect")
	assert_str(eng.state.pending_choice.kind).is_equal("intercept")
	eng.apply(Action.resolve_choice({"option": 0}))
	assert_object(ps.discard.front()).is_same(u)
