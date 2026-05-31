extends RaccoonTestBase

func test_trashalanche_damages_all_units_by_discard_size() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	seed_discard(eng, me, 3)  # discard size 3
	var a := place_on_board(eng, me, TestFactory.minion(1, 1, 5, 1))
	var b := place_on_board(eng, opp, TestFactory.minion(1, 1, 5, 2))
	var spell := eng.state.make_instance(raccoon_def(16))
	eng.state.players[me].hand.append(spell)
	eng.state.players[me].tickets_total = 20
	eng.apply(Action.play_card(spell.instance_id))
	assert_int(a.current_health).is_equal(2)
	assert_int(b.current_health).is_equal(2)
