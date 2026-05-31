extends RaccoonTestBase

func test_trash_cannon_deals_two_deck_damage_per_rummage_instance() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	seed_discard(eng, me, 2)
	place_on_board(eng, me, raccoon_def(10))
	var opp_deck_before := eng.state.players[opp].deck.size()
	EffectContext.new(eng, me).rummage(1)
	assert_int(eng.state.players[opp].deck.size()).is_equal(opp_deck_before - 2)
