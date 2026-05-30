extends CardTestBase

func test_steals_top_of_opponent_discard_on_deck_attack() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var cactus := place_on_board(eng, me, strike_def(10))
	cactus.tapped = false
	eng.state.players[opp].deck.clear()
	eng.state.players[opp].reshuffles_remaining = 0
	var loot := eng.state.make_instance(strike_def(2))
	loot.zone = Enums.Zone.DISCARD
	eng.state.players[opp].discard.append(loot)
	eng.apply(Action.declare_attack(cactus.instance_id, {"deck": true}))
	assert_bool(eng.state.players[me].hand.has(loot)).is_true()
	assert_int(loot.vars["stolen_from"]).is_equal(opp)
