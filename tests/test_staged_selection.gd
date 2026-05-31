extends GdUnitTestSuite

# source_ids are the instance_ids of the source card list, index-aligned.
# e.g. source list [cardA, cardB, cardC] -> source_ids [10, 20, 30],
# where index 0 == cardA == instance_id 10.

func _sel(min_n: int, max_n: int) -> StagedSelection:
	return StagedSelection.new([10, 20, 30, 40], min_n, max_n)

func test_select_appends_under_max() -> void:
	var s := _sel(0, 2)
	s.toggle(10)
	s.toggle(30)
	assert_array(s.staged).is_equal([10, 30])

func test_toggle_same_id_deselects() -> void:
	var s := _sel(0, 2)
	s.toggle(10)
	s.toggle(10)
	assert_array(s.staged).is_equal([])

func test_at_max_replaces_rightmost() -> void:
	var s := _sel(0, 2)
	s.toggle(10)
	s.toggle(20)        # staged == [10, 20], now at max
	s.toggle(30)        # replaces rightmost (20) with 30
	assert_array(s.staged).is_equal([10, 30])

func test_toggle_returns_change_info() -> void:
	var s := _sel(0, 2)
	var added := s.toggle(10)
	assert_int(added["added"]).is_equal(10)
	assert_int(added["removed"]).is_equal(-1)
	var removed := s.toggle(10)
	assert_int(removed["added"]).is_equal(-1)
	assert_int(removed["removed"]).is_equal(10)

func test_replace_change_info_reports_both() -> void:
	var s := _sel(0, 1)
	s.toggle(10)
	var change := s.toggle(20)   # at max 1 -> replace 10 with 20
	assert_int(change["added"]).is_equal(20)
	assert_int(change["removed"]).is_equal(10)

func test_can_confirm_boundaries() -> void:
	var s := _sel(1, 2)
	assert_bool(s.can_confirm()).is_false()   # 0 < min
	s.toggle(10)
	assert_bool(s.can_confirm()).is_true()     # 1 in [1,2]
	s.toggle(20)
	assert_bool(s.can_confirm()).is_true()     # 2 in [1,2]

func test_min_zero_can_confirm_immediately() -> void:
	var s := _sel(0, 2)
	assert_bool(s.can_confirm()).is_true()

func test_to_indices_maps_staged_to_source_indices() -> void:
	var s := _sel(0, 3)
	s.toggle(30)   # index 2
	s.toggle(10)   # index 0
	assert_array(s.to_indices()).is_equal([2, 0])   # preserves staged order

func test_to_indices_after_replace() -> void:
	var s := _sel(0, 2)
	s.toggle(10)   # index 0
	s.toggle(20)   # index 1
	s.toggle(40)   # replaces 20 -> staged [10, 40] -> indices [0, 3]
	assert_array(s.to_indices()).is_equal([0, 3])
