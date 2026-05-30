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

func test_discard_panel_requires_exact_count() -> void:
	var p = _inst("res://src/ui/overlays/discard_panel.tscn")
	p.show_hand(_hand(7), 2)
	p.toggle_index(0)
	assert_bool(p.can_confirm()).is_false()
	p.toggle_index(1)
	assert_bool(p.can_confirm()).is_true()

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