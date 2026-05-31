extends GdUnitTestSuite

func _hand_view_with_cards() -> Node:
	var m: Node = load("res://src/ui/match/match.tscn").instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(3, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	return m.hand_view

func test_excluding_a_card_reflows_remaining_to_n_minus_1() -> void:
	var hv := _hand_view_with_cards()
	var order: Array = hv._hand_order
	var n := order.size()
	assert_int(n).is_greater(1)

	hv.set_choice_excluded([order[0]])

	var first_visible_id: int = order[1]
	var cv: CardView = hv.card_views[first_visible_id]
	var expected := BoardLayout.slot(Enums.Zone.HAND, 0, n - 1, 0).origin - BoardLayout.CARD_PIVOT
	assert_vector(cv._rest_position).is_equal_approx(expected, Vector2(0.5, 0.5))

func test_clearing_exclusion_restores_full_layout() -> void:
	var hv := _hand_view_with_cards()
	var order: Array = hv._hand_order
	var n := order.size()
	hv.set_choice_excluded([order[0]])
	hv.set_choice_excluded([])

	var cv: CardView = hv.card_views[order[0]]
	var expected := BoardLayout.slot(Enums.Zone.HAND, 0, n, 0).origin - BoardLayout.CARD_PIVOT
	assert_vector(cv._rest_position).is_equal_approx(expected, Vector2(0.5, 0.5))
