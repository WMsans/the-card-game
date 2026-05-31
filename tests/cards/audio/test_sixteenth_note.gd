extends AudioTestBase

func test_costs_one_less_per_note_on_board() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	# two notes on board
	place_on_board(eng, me, audio_def(2))
	place_on_board(eng, me, audio_def(6))
	var sixteenth := eng.state.make_instance(audio_def(8))
	# base cost 10 - 2 notes = 8
	assert_int(eng.effective_cost(sixteenth, me)).is_equal(8)

func test_sixteenth_deals_four_deck_damage_on_harmonize() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	place_on_board(eng, me, audio_def(8))
	var before := eng.state.players[opp].deck.size()
	EffectContext.new(eng, me).harmonize()
	assert_int(eng.state.players[opp].deck.size()).is_equal(before - 4)
