extends RaccoonTestBase

func test_skunk_zeroes_opponent_damage_on_first_rummage() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	seed_discard(eng, me, 4)
	place_on_board(eng, me, raccoon_def(6))
	var victim := place_on_board(eng, opp, TestFactory.minion(3, 5, 5, 1))
	EffectContext.new(eng, me).rummage(1)
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_target")
	eng.apply(Action.resolve_choice({"target_ids": [victim.instance_id]}))
	assert_int(victim.current_damage).is_equal(0)

func test_skunk_only_first_rummage_each_turn() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	seed_discard(eng, me, 6)
	place_on_board(eng, me, raccoon_def(6))
	place_on_board(eng, opp, TestFactory.minion(3, 5, 5, 1))
	var ctx := EffectContext.new(eng, me)
	ctx.rummage(1)
	eng.apply(Action.resolve_choice({"target_ids": []}))
	ctx.rummage(1)
	assert_bool(eng.state.pending_choice == null).is_true()
