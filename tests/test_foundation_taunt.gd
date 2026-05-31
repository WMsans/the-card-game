# tests/test_foundation_taunt.gd
extends CardTestBase

func _attack_targets(eng: GameEngine, attacker_id: int) -> Array:
	var out: Array = []
	for a in eng.get_legal_actions():
		if a.type == Enums.ActionType.DECLARE_ATTACK and a.params["attacker_id"] == attacker_id:
			out.append(a.params["target"])
	return out

func test_taunt_restricts_targets_and_blocks_deck() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var attacker := place_on_board(eng, me, TestFactory.minion(1, 2, 2, 1))
	attacker.tapped = false
	var taunt := place_on_board(eng, opp, TestFactory.minion(1, 1, 5, 2))
	var plain := place_on_board(eng, opp, TestFactory.minion(1, 1, 5, 3))
	taunt.vars["taunt"] = true
	var targets := _attack_targets(eng, attacker.instance_id)
	# only the taunt unit is a legal target; deck attack disallowed
	assert_int(targets.size()).is_equal(1)
	assert_int(targets[0].get("unit", -1)).is_equal(taunt.instance_id)

func test_no_taunt_allows_deck_and_all_units() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var attacker := place_on_board(eng, me, TestFactory.minion(1, 2, 2, 1))
	attacker.tapped = false
	place_on_board(eng, opp, TestFactory.minion(1, 1, 5, 2))
	var targets := _attack_targets(eng, attacker.instance_id)
	var has_deck := targets.any(func(t): return t.get("deck", false))
	assert_bool(has_deck).is_true()
