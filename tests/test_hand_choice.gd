extends GdUnitTestSuite

func _match() -> Node:
	var m: Node = load("res://src/ui/match/match.tscn").instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(3, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	return m

func test_start_shows_chrome_and_title() -> void:
	var m := _match()
	var hc := m._hand_choice
	hc.start(m.hand_view, m.state.players[0].hand, 1, 1, "Pick 1")
	assert_bool(hc.visible).is_true()
	assert_str(hc.find_child("Title").text).is_equal("Pick 1")
	assert_bool(hc.find_child("Confirm").disabled).is_true()

func test_click_then_confirm_emits_source_index() -> void:
	var m := _match()
	var hc := m._hand_choice
	var hand: Array = m.state.players[0].hand
	hc.start(m.hand_view, hand, 1, 1, "Pick 1")
	var got := {"indices": []}
	hc.confirmed.connect(func(idx): got["indices"] = idx)
	hc._on_card_clicked(hand[2].instance_id)
	assert_bool(hc.find_child("Confirm").disabled).is_false()
	hc._confirm_pressed()
	assert_array(got["indices"]).is_equal([2])

func test_clicking_past_max_replaces_rightmost() -> void:
	var m := _match()
	var hc := m._hand_choice
	var hand: Array = m.state.players[0].hand
	hc.start(m.hand_view, hand, 2, 2, "Pick 2")
	var got := {"indices": []}
	hc.confirmed.connect(func(idx): got["indices"] = idx)
	hc._on_card_clicked(hand[0].instance_id)
	hc._on_card_clicked(hand[1].instance_id)
	hc._on_card_clicked(hand[2].instance_id)
	hc._confirm_pressed()
	assert_array(got["indices"]).is_equal([0, 2])

func test_clicking_staged_card_deselects() -> void:
	var m := _match()
	var hc := m._hand_choice
	var hand: Array = m.state.players[0].hand
	hc.start(m.hand_view, hand, 0, 2, "Up to 2")
	hc._on_card_clicked(hand[0].instance_id)
	hc._on_card_clicked(hand[0].instance_id)
	var got := {"indices": [-99]}
	hc.confirmed.connect(func(idx): got["indices"] = idx)
	hc._confirm_pressed()
	assert_array(got["indices"]).is_equal([])
