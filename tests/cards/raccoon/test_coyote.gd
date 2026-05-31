extends RaccoonTestBase

func test_coyote_adds_one_extra_card_per_rummage() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	seed_discard(eng, me, 6)
	place_on_board(eng, me, raccoon_def(8))
	EffectContext.new(eng, me).rummage(2)  # 2 + 1 bonus = 3
	assert_int(eng.state.players[me].discard.size()).is_equal(3)
