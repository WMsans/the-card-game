extends GdUnitTestSuite

func _hand(n: int) -> Array[CardInstance]:
	var defs := CardDatabase.load_deck("res://src/data/decks/strike.csv", "S")
	var out: Array[CardInstance] = []
	for i in range(n):
		out.append(CardInstance.new(i + 1, defs[i % defs.size()]))
	return out

func _inst(path: String) -> Node:
	var p = load(path).instantiate()
	add_child(p)
	auto_free(p)
	return p

func test_card_select_requires_min_to_confirm() -> void:
	var p = _inst("res://src/ui/overlays/card_select_panel.tscn")
	p.show_selection(_hand(7), 2, 2, "Pick 2")
	p.toggle_index(0)
	assert_bool(p.can_confirm()).is_false()
	p.toggle_index(1)
	assert_bool(p.can_confirm()).is_true()

func test_card_select_allows_range() -> void:
	var p = _inst("res://src/ui/overlays/card_select_panel.tscn")
	p.show_selection(_hand(7), 0, 3, "Up to 3")
	assert_bool(p.can_confirm()).is_true()        # 0 is allowed
	p.toggle_index(0); p.toggle_index(1); p.toggle_index(2); p.toggle_index(3)
	assert_int(p._selected.size()).is_equal(3)    # capped at max 3

func test_card_select_highlights_card() -> void:
	var p = _inst("res://src/ui/overlays/card_select_panel.tscn")
	p.show_selection(_hand(7), 0, 2, "x")
	p.toggle_index(0)
	var row := p.find_child("CardRow")
	var first_card: CardView = row.get_child(0)
	assert_bool((first_card.find_child("Highlight") as Control).visible).is_true()
	p.toggle_index(0)
	assert_bool((first_card.find_child("Highlight") as Control).visible).is_false()

func test_leader_prompt_emits_payment_choice() -> void:
	var p = _inst("res://src/ui/overlays/leader_cost_prompt.tscn")
	var got := {"called": false, "by_discard": false}
	p.chosen.connect(func(by_discard): got["called"] = true; got["by_discard"] = by_discard)
	p.show_prompt()
	p.choose_discard()
	assert_bool(got["called"]).is_true()
	assert_bool(got["by_discard"]).is_true()

func test_game_over_shows_winner_text() -> void:
	var p = _inst("res://src/ui/overlays/game_over_panel.tscn")
	p.show_result(0, 0)
	assert_str(p.find_child("ResultLabel").text).is_equal("You Win")
	p.show_result(1, 0)
	assert_str(p.find_child("ResultLabel").text).is_equal("You Lose")

func test_card_select_emits_minimize_requested() -> void:
	var p = _inst("res://src/ui/overlays/card_select_panel.tscn")
	p.show_selection(_hand(3), 0, 1, "Pick")
	var btn: Button = p.find_child("MinimizeButton")
	assert_bool(not btn.pressed.get_connections().is_empty()).is_true()
	var got := {"called": false}
	p.minimize_requested.connect(func(): got["called"] = true)
	p.minimize_requested.emit()
	assert_bool(got["called"]).is_true()

func test_card_select_animatable_nodes() -> void:
	var p = _inst("res://src/ui/overlays/card_select_panel.tscn")
	p.show_selection(_hand(3), 0, 1, "Pick")
	var nodes: Array[Node] = p.get_animatable_nodes()
	assert_int(nodes.size()).is_equal(3)

func test_hand_choice_animatable_nodes() -> void:
	var p = _inst("res://src/ui/match/hand_choice.tscn")
	var nodes: Array[Node] = p.get_animatable_nodes()
	assert_int(nodes.size()).is_equal(2)

func test_option_prompt_animatable_nodes() -> void:
	var p = _inst("res://src/ui/overlays/option_prompt.tscn")
	p.show_options(["A", "B"], "Choose", null)
	var nodes: Array[Node] = p.get_animatable_nodes()
	assert_int(nodes.size()).is_equal(2)

func test_trap_reveal_animatable_nodes() -> void:
	var p = _inst("res://src/ui/overlays/trap_reveal_overlay.tscn")
	var nodes: Array[Node] = p.get_animatable_nodes()
	assert_int(nodes.size()).is_equal(3)
