# tests/cards/writing/test_melon_zombie_hulk.gd
extends WritingTestBase

func test_hulk_trashes_a_chosen_ally_on_attack() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var hulk := place_on_board(eng, me, writing_def(2))
	hulk.tapped = false
	var ally := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 1))
	eng.apply(Action.declare_attack(hulk.instance_id, {"deck": true}))
	# Hulk asks which ally to trash
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_target")
	eng.apply(Action.resolve_choice({"target_ids": [ally.instance_id]}))
	assert_bool(eng.state.players[me].discard.has(ally)).is_true()
