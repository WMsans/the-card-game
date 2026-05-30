extends GdUnitTestSuite

func _strike_hand() -> Array[CardInstance]:
	var defs := CardDatabase.load_deck("res://src/data/decks/strike.csv", "S")
	var out: Array[CardInstance] = []
	for i in range(5):
		out.append(CardInstance.new(i + 1, defs[i]))
	return out

func _spawn() -> MulliganPanel:
	var p: MulliganPanel = load("res://src/ui/overlays/mulligan_panel.tscn").instantiate()
	add_child(p)
	auto_free(p)
	return p

func test_confirm_disabled_until_exactly_two_selected() -> void:
	var p := _spawn()
	p.show_hand(_strike_hand())
	assert_bool(p.can_confirm()).is_false()
	p.toggle_index(0)
	assert_bool(p.can_confirm()).is_false()
	p.toggle_index(1)
	assert_bool(p.can_confirm()).is_true()
	p.toggle_index(2)
	assert_bool(p.can_confirm()).is_false()   # 3 selected

func test_confirm_emits_selected_indices() -> void:
	var p := _spawn()
	p.show_hand(_strike_hand())
	p.toggle_index(0)
	p.toggle_index(3)
	var got: Array = []
	p.confirmed.connect(func(idx): got.assign(idx))
	p.confirm()
	assert_array(got).contains_exactly_in_any_order([0, 3])