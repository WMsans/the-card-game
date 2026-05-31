extends RaccoonTestBase

func test_rat_plays_free_when_rummaged() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	var rat := eng.state.make_instance(raccoon_def(2))
	rat.zone = Enums.Zone.DISCARD
	ps.discard.append(rat)
	EffectContext.new(eng, me).rummage(1)
	assert_bool(ps.board.has(rat)).is_true()
	assert_bool(ps.hand.has(rat)).is_false()
