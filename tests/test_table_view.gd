extends GdUnitTestSuite

func test_renders_counts_from_seeded_state() -> void:
	var tv: Node = load("res://src/ui/table/table_view.tscn").instantiate()
	add_child(tv)
	auto_free(tv)
	tv.build(12345)
	var hand: Node = tv.find_child("PlayerHand")
	assert_int(hand.get_child_count()).is_equal(tv.state.players[0].hand.size())
	var opp: Node = tv.find_child("OppHand")
	assert_int(opp.get_child_count()).is_equal(tv.state.players[1].hand.size())
