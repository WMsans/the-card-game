extends RaccoonTestBase

func test_rummages_two_at_turn_start_while_in_discard() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	seed_discard(eng, me, 4)
	var leader := eng.state.make_instance(raccoon_def(1))
	leader.zone = Enums.Zone.DISCARD
	ps.discard.append(leader)
	var disc_before := ps.discard.size()
	eng.emit(GameEvent.new(Enums.EventType.TURN_STARTED, {"player": me}))
	assert_int(ps.discard.size()).is_equal(disc_before - 2)

func test_activated_ability_discards_to_damage_unit() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var ps := eng.state.players[me]
	var leader := place_on_board(eng, me, raccoon_def(1))
	var c1 := eng.state.make_instance(TestFactory.minion(1, 1, 1, 10))
	var c2 := eng.state.make_instance(TestFactory.minion(1, 1, 1, 11))
	c1.zone = Enums.Zone.HAND; c2.zone = Enums.Zone.HAND
	ps.hand.append(c1); ps.hand.append(c2)
	var target := place_on_board(eng, opp, TestFactory.minion(1, 1, 5, 1))
	eng.apply(Action.activate_ability(leader.instance_id, "raccoon_throw"))
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_cards")
	eng.apply(Action.resolve_choice({"indices": [ps.hand.find(c1), ps.hand.find(c2)]}))
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_target")
	eng.apply(Action.resolve_choice({"target_ids": [target.instance_id]}))
	assert_int(target.current_health).is_equal(3)
