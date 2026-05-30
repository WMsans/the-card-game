extends GdUnitTestSuite

func _spawn() -> Node:
	var t: Node = load("res://src/ui/table/ticket_tray.tscn").instantiate()
	add_child(t)
	auto_free(t)
	return t

func test_draws_total_pips_with_tapped_filled() -> void:
	var tray := _spawn()
	tray.set_tickets(3, 5)
	assert_int(tray.get_child_count()).is_equal(5)
	assert_int(tray.filled_count()).is_equal(2)

func test_preview_cost_marks_spent_pips_red() -> void:
	var tray := _spawn()
	tray.set_tickets(0, 5)   # 5 available (indices 0..4 filled)
	tray.preview_cost(2)     # the last 2 available pips (3, 4) turn red
	assert_object((tray.get_child(4) as ColorRect).color).is_equal(UiPalette.PIP_COST)
	assert_object((tray.get_child(3) as ColorRect).color).is_equal(UiPalette.PIP_COST)
	assert_object((tray.get_child(2) as ColorRect).color).is_equal(UiPalette.PIP_FILLED)

func test_clear_preview_restores_filled() -> void:
	var tray := _spawn()
	tray.set_tickets(0, 5)
	tray.preview_cost(2)
	tray.clear_preview()
	assert_object((tray.get_child(4) as ColorRect).color).is_equal(UiPalette.PIP_FILLED)