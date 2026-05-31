extends AudioTestBase

func test_plop_harmonizes_on_cast_and_deals_six_deck_damage() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var ps := eng.state.players[me]
	var note := place_on_board(eng, me, audio_def(2))
	var bd := note.current_damage
	var plop := eng.state.make_instance(audio_def(1))
	plop.zone = Enums.Zone.HAND
	ps.hand.append(plop)
	ps.tickets_total = 20
	var opp_deck := eng.state.players[opp].deck.size()
	eng.apply(Action.play_card(plop.instance_id))
	assert_int(note.current_damage).is_equal(bd + 2)
	assert_int(eng.state.players[opp].deck.size()).is_equal(opp_deck - 6)
