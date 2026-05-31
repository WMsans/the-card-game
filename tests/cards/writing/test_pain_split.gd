# tests/cards/writing/test_pain_split.gd
extends WritingTestBase

func test_pain_split_trashes_one_and_damages_another() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var ps := eng.state.players[me]
	var sacrifice := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 1))
	var enemy := place_on_board(eng, opp, TestFactory.minion(1, 1, 9, 2))
	var spell := eng.state.make_instance(writing_def(17))
	ps.hand.append(spell)
	ps.tickets_total = 20
	eng.apply(Action.play_card(spell.instance_id))
	# 1) pick the ally to TRASH
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_target")
	eng.apply(Action.resolve_choice({"target_ids": [sacrifice.instance_id]}))
	# 2) pick the unit to take 4 damage
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_target")
	eng.apply(Action.resolve_choice({"target_ids": [enemy.instance_id]}))
	assert_int(enemy.current_health).is_equal(5)
	assert_bool(ps.discard.has(sacrifice)).is_true()
