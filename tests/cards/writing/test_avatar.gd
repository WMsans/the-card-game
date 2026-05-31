# tests/cards/writing/test_avatar.gd
extends WritingTestBase

func test_avatar_trashes_own_then_opponent_trashes_same_count() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var ps := eng.state.players[me]
	var mine := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 1))
	var enemy_a := place_on_board(eng, opp, TestFactory.minion(1, 1, 1, 2))
	place_on_board(eng, opp, TestFactory.minion(1, 1, 1, 3))
	var avatar := eng.state.make_instance(writing_def(6))
	ps.hand.append(avatar)
	ps.tickets_total = 20
	eng.apply(Action.play_card(avatar.instance_id))
	assert_int(eng.state.pending_choice.player).is_equal(me)
	eng.apply(Action.resolve_choice({"target_ids": [mine.instance_id]}))
	assert_int(eng.state.pending_choice.player).is_equal(opp)
	eng.apply(Action.resolve_choice({"target_ids": [enemy_a.instance_id]}))
	assert_bool(ps.discard.has(mine)).is_true()
	assert_bool(eng.state.players[opp].discard.has(enemy_a)).is_true()
