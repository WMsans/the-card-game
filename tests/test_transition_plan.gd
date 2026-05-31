extends GdUnitTestSuite

func test_detects_zone_change() -> void:
	var before := {10: {"zone": Enums.Zone.DECK, "player": 0}}
	var after := {10: {"zone": Enums.Zone.HAND, "player": 0}}
	var plan := TransitionPlan.compute(before, after)
	assert_int(plan.size()).is_equal(1)
	assert_int(plan[0]["instance_id"]).is_equal(10)
	assert_int(plan[0]["from"]).is_equal(Enums.Zone.DECK)
	assert_int(plan[0]["to"]).is_equal(Enums.Zone.HAND)
	assert_int(plan[0]["player"]).is_equal(0)

func test_ignores_unchanged_zone() -> void:
	var before := {10: {"zone": Enums.Zone.HAND, "player": 0}}
	var after := {10: {"zone": Enums.Zone.HAND, "player": 0}}
	assert_array(TransitionPlan.compute(before, after)).is_empty()

func test_ignores_cards_absent_before() -> void:
	var before := {}
	var after := {10: {"zone": Enums.Zone.HAND, "player": 0}}
	assert_array(TransitionPlan.compute(before, after)).is_empty()

func test_multiple_changes_preserve_after_order() -> void:
	var before := {10: {"zone": Enums.Zone.DECK, "player": 0},
		20: {"zone": Enums.Zone.DECK, "player": 0}}
	var after := {10: {"zone": Enums.Zone.HAND, "player": 0},
		20: {"zone": Enums.Zone.HAND, "player": 0}}
	var plan := TransitionPlan.compute(before, after)
	assert_int(plan.size()).is_equal(2)
	assert_int(plan[0]["instance_id"]).is_equal(10)
	assert_int(plan[1]["instance_id"]).is_equal(20)
