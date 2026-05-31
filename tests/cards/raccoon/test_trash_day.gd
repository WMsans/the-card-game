extends RaccoonTestBase

func test_trash_day_mills_then_damages_unit() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var ps := eng.state.players[me]
	var target := place_on_board(eng, opp, TestFactory.minion(1, 1, 5, 1))
	var spell := eng.state.make_instance(raccoon_def(12))
	ps.hand.append(spell)
	ps.tickets_total = 20
	var deck_before := ps.deck.size()
	eng.apply(Action.play_card(spell.instance_id))
	# choose how many to discard from own deck
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("choose_option")
	eng.apply(Action.resolve_choice({"option": 3}))  # discard 3
	assert_int(ps.deck.size()).is_equal(deck_before - 3)
	# now pick a unit to damage by 3
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_target")
	eng.apply(Action.resolve_choice({"target_ids": [target.instance_id]}))
	assert_int(target.current_health).is_equal(2)
