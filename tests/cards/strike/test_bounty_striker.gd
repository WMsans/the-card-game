extends CardTestBase

func test_returns_to_hand_when_owner_meets_a_request() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var bounty := eng.state.make_instance(strike_def(5))
	bounty.zone = Enums.Zone.DISCARD
	eng.state.players[me].discard.append(bounty)
	var atk := place_on_board(eng, me, strike_def(11))
	atk.tapped = false
	eng.state.players[me].all_requests_met_this_turn = true
	eng.apply(Action.declare_attack(atk.instance_id, {"deck": true}))
	assert_bool(eng.state.players[me].hand.has(bounty)).is_true()
