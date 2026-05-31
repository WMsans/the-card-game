# tests/cards/writing/test_cultist.gd
extends WritingTestBase

func test_cultist_trashes_self_to_return_a_discard_card() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	var buried := eng.state.make_instance(TestFactory.minion(1, 1, 1, 50))
	buried.zone = Enums.Zone.DISCARD
	ps.discard.append(buried)
	var cultist := place_on_board(eng, me, writing_def(7))
	cultist.tapped = false
	eng.apply(Action.declare_attack(cultist.instance_id, {"deck": true}))
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_cards")
	eng.apply(Action.resolve_choice({"indices": [0]}))
	assert_bool(ps.hand.has(buried)).is_true()
	assert_bool(ps.discard.has(cultist)).is_true()
