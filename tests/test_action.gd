extends GdUnitTestSuite

func test_play_card_merges_options() -> void:
	var a := Action.play_card(5, {"pay_by_discard": true})
	assert_int(a.type).is_equal(Enums.ActionType.PLAY_CARD)
	assert_int(a.params["instance_id"]).is_equal(5)
	assert_bool(a.params["pay_by_discard"]).is_true()

func test_declare_attack_deck_target() -> void:
	var a := Action.declare_attack(9, {"deck": true})
	assert_int(a.type).is_equal(Enums.ActionType.DECLARE_ATTACK)
	assert_int(a.params["attacker_id"]).is_equal(9)
	assert_bool(a.params["target"]["deck"]).is_true()

func test_simple_constructors() -> void:
	assert_int(Action.end_turn().type).is_equal(Enums.ActionType.END_TURN)
	assert_int(Action.mulligan([0, 1]).type).is_equal(Enums.ActionType.MULLIGAN)
	assert_int(Action.resolve_choice({"indices": [0]}).type).is_equal(Enums.ActionType.RESOLVE_CHOICE)
