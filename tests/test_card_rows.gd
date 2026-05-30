extends GdUnitTestSuite

func _strike_defs() -> Array:
	return CardDatabase.load_deck("res://src/data/decks/strike.csv", "Strike")

func _instances(n: int) -> Array[CardInstance]:
	var defs := _strike_defs()
	var out: Array[CardInstance] = []
	for i in range(n):
		out.append(CardInstance.new(i + 1, defs[i % defs.size()]))
	return out

func _row(path: String) -> Node2D:
	var n := Node2D.new()
	n.set_script(load(path))
	add_child(n)
	auto_free(n)
	return n

func test_hand_view_spawns_one_cardview_per_card() -> void:
	var hv := _row("res://src/ui/table/hand_view.gd")
	hv.render(_instances(5), 0)
	assert_int(hv.get_child_count()).is_equal(5)

func test_board_view_spawns_one_cardview_per_unit() -> void:
	var bv := _row("res://src/ui/table/board_view.gd")
	bv.render(_instances(3), 0)
	assert_int(bv.get_child_count()).is_equal(3)
