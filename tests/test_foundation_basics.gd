# tests/test_foundation_basics.gd
extends GdUnitTestSuite

func test_new_event_types_exist_and_are_distinct() -> void:
	var types := [
		Enums.EventType.CARD_RUMMAGED, Enums.EventType.RUMMAGE_PERFORMED,
		Enums.EventType.HARMONIZE, Enums.EventType.UNIT_TRASHED,
	]
	# all distinct
	assert_int(types.size()).is_equal(4)
	for i in range(types.size()):
		for j in range(i + 1, types.size()):
			assert_bool(types[i] == types[j]).is_false()

func test_rummages_made_counter_starts_zero() -> void:
	var ps := PlayerState.new()
	assert_int(ps.turn_counters["rummages_made"]).is_equal(0)
