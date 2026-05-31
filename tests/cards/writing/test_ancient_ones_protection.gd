# tests/cards/writing/test_ancient_ones_protection.gd
extends WritingTestBase

func test_protects_unit_by_trashing_another_on_battle_death() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var ps := eng.state.players[me]
	var attacker := place_on_board(eng, opp, TestFactory.minion(1, 5, 5, 1))
	attacker.tapped = false
	var defender := place_on_board(eng, me, TestFactory.minion(1, 1, 2, 2))
	var scapegoat := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 3))
	var trap := eng.state.make_instance(writing_def(19))
	trap.zone = Enums.Zone.TRAP_SET
	ps.set_traps.append(trap)
	eng.state.active_player = opp
	eng.apply(Action.declare_attack(attacker.instance_id, {"unit": defender.instance_id}))
	assert_str(eng.state.pending_choice.kind).is_equal("intercept")
	eng.apply(Action.resolve_choice({"option": 0}))
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_target")
	eng.apply(Action.resolve_choice({"target_ids": [scapegoat.instance_id]}))
	assert_bool(ps.board.has(defender)).is_true()
	assert_bool(ps.discard.has(scapegoat)).is_true()
