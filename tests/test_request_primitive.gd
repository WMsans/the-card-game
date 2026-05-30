extends GdUnitTestSuite

func test_flag_defaults_false_and_resets_each_turn() -> void:
	var ps := PlayerState.new()
	assert_bool(ps.all_requests_met_this_turn).is_false()
	ps.all_requests_met_this_turn = true
	ps.reset_turn_counters()
	assert_bool(ps.all_requests_met_this_turn).is_false()
