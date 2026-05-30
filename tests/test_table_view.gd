extends GdUnitTestSuite

func test_renders_counts_from_seeded_state() -> void:
	var tv: Node = load("res://src/ui/table/table_view.tscn").instantiate()
	add_child(tv)
	auto_free(tv)
	tv.build(12345)
	var p0: PlayerState = tv.state.players[0]
	var p1: PlayerState = tv.state.players[1]
	assert_int(tv.find_child("PlayerHand").get_child_count()).is_equal(p0.hand.size())
	assert_int(tv.find_child("OppHand").get_child_count()).is_equal(p1.hand.size())
	assert_int(tv.find_child("PlayerBoard").get_child_count()).is_equal(p0.board.size())
	assert_int(tv.find_child("OppBoard").get_child_count()).is_equal(p1.board.size())
	assert_str(tv.find_child("PlayerDeck").find_child("Count").text).is_equal(str(p0.deck.size()))
	assert_str(tv.find_child("PlayerDiscard").find_child("Count").text).is_equal(str(p0.discard.size()))
